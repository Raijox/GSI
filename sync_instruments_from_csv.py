#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import sys
from dataclasses import dataclass
from typing import Iterable

import pyodbc


@dataclass
class CsvRow:
    external_id: str
    instrument_type_internal_id: str


def _norm(value: object) -> str:
    return str(value or "").strip()


def _load_env_file(path: str = ".env") -> None:
    if not os.path.exists(path):
        return
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if key and key not in os.environ:
                    os.environ[key] = value
    except Exception:
        pass


def _read_csv_rows(csv_path: str) -> list[CsvRow]:
    rows: list[CsvRow] = []
    with open(csv_path, "r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        headers = {str(h or "").strip().lower(): h for h in (reader.fieldnames or [])}
        ext_col = headers.get("external_id")
        int_col = headers.get("instrument_type_internal_id")
        if not ext_col or not int_col:
            raise RuntimeError(
                "CSV must include columns external_id and instrument_type_internal_id."
            )
        for row in reader:
            external_id = _norm(row.get(ext_col))
            internal_id = _norm(row.get(int_col))
            if not external_id or not internal_id:
                continue
            rows.append(CsvRow(external_id=external_id, instrument_type_internal_id=internal_id))
    if not rows:
        raise RuntimeError("No usable CSV rows found.")
    return rows


def _fetch_columns(cur: pyodbc.Cursor, table_name: str) -> set[str]:
    cur.execute(
        """
        SELECT [name]
        FROM sys.columns
        WHERE object_id = OBJECT_ID(?)
        """,
        (f"dbo.{table_name}",),
    )
    out: set[str] = set()
    for row in cur.fetchall():
        out.add(str(row[0]).strip().lower())
    return out


def _table_exists(cur: pyodbc.Cursor, table_name: str) -> bool:
    cur.execute("SELECT OBJECT_ID(?, 'U')", (f"dbo.{table_name}",))
    row = cur.fetchone()
    return bool(row and row[0] is not None)


def _pick_first(available: set[str], candidates: Iterable[str]) -> str | None:
    for c in candidates:
        if c.lower() in available:
            return c.lower()
    return None


def _quoted(col: str) -> str:
    return f"[{col.replace(']', ']]')}]"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Map instruments.csv instrument_type_internal_id to keli_instrument_types name and "
            "update gdi_instrument_types + corrections_instrument_types."
        )
    )
    parser.add_argument("--csv", default="instruments.csv", help="Path to instruments.csv")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute and print counts without committing changes.",
    )
    args = parser.parse_args()

    _load_env_file()
    conn_str = _norm(os.getenv("GSI_MSSQL_CONNECTION_STRING"))
    if not conn_str:
        print("ERROR: GSI_MSSQL_CONNECTION_STRING is not configured.", file=sys.stderr)
        return 2

    csv_rows = _read_csv_rows(args.csv)

    conn = pyodbc.connect(conn_str)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        if not _table_exists(cur, "gdi_instrument_types"):
            raise RuntimeError("gdi_instrument_types table was not found.")
        if not _table_exists(cur, "keli_instrument_types"):
            raise RuntimeError("keli_instrument_types table was not found.")

        gdi_cols = _fetch_columns(cur, "gdi_instrument_types")
        keli_cols = _fetch_columns(cur, "keli_instrument_types")

        gdi_match_col = _pick_first(gdi_cols, ["col01varchar", "key_id", "external_id", "instrument_external_id"])
        if not gdi_match_col:
            raise RuntimeError("Could not find a match column on gdi_instrument_types (expected col01varchar/key_id/external_id/instrument_external_id).")

        keli_id_col = _pick_first(keli_cols, ["id", "internal_id", "instrument_type_internal_id"])
        keli_name_col = _pick_first(keli_cols, ["name", "instrument_type", "instrument_name"])
        if not keli_id_col or not keli_name_col:
            raise RuntimeError("Could not resolve id/name columns on keli_instrument_types.")

        keli_record_type_col = _pick_first(keli_cols, ["record_type"])
        keli_active_col = _pick_first(keli_cols, ["active", "is_active"])

        has_corr = _table_exists(cur, "corrections_instrument_types")
        corr_cols = _fetch_columns(cur, "corrections_instrument_types") if has_corr else set()

        cur.execute(
            """
            IF OBJECT_ID('tempdb..#csv_inst') IS NOT NULL DROP TABLE #csv_inst;
            CREATE TABLE #csv_inst (
                external_id VARCHAR(1000) NOT NULL,
                instrument_type_internal_id VARCHAR(1000) NOT NULL
            );
            """
        )

        cur.fast_executemany = True
        cur.executemany(
            "INSERT INTO #csv_inst (external_id, instrument_type_internal_id) VALUES (?, ?)",
            [(r.external_id, r.instrument_type_internal_id) for r in csv_rows],
        )

        rec_type_expr = "CAST('' AS VARCHAR(200))"
        if keli_record_type_col:
            rec_type_expr = f"ISNULL(CAST(kit.{_quoted(keli_record_type_col)} AS VARCHAR(200)), '')"
        is_active_expr = "CAST(1 AS INT)"
        if keli_active_col:
            is_active_expr = f"CAST(ISNULL(kit.{_quoted(keli_active_col)}, 0) AS INT)"

        cur.execute(
            f"""
            IF OBJECT_ID('tempdb..#matched_inst') IS NOT NULL DROP TABLE #matched_inst;
            SELECT
                g.id AS source_row_id,
                g.imported_by_user_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.col03varchar, '') AS old_instrument_type_name,
                ISNULL(CAST(kit.{_quoted(keli_name_col)} AS VARCHAR(300)), '') AS new_instrument_type_name,
                ISNULL(CAST(kit.{_quoted(keli_id_col)} AS VARCHAR(1000)), '') AS new_instrument_type_id,
                {rec_type_expr} AS new_record_type,
                {is_active_expr} AS new_is_active
            INTO #matched_inst
            FROM dbo.gdi_instrument_types g
            JOIN #csv_inst c
              ON LOWER(LTRIM(RTRIM(ISNULL(CAST(g.{_quoted(gdi_match_col)} AS VARCHAR(1000)), ''))))
               = LOWER(LTRIM(RTRIM(ISNULL(c.external_id, ''))))
            JOIN dbo.keli_instrument_types kit
              ON LOWER(LTRIM(RTRIM(ISNULL(CAST(kit.{_quoted(keli_id_col)} AS VARCHAR(1000)), ''))))
               = LOWER(LTRIM(RTRIM(ISNULL(c.instrument_type_internal_id, ''))));
            """
        )

        cur.execute("SELECT COUNT(1) FROM #matched_inst")
        matched_count = int(cur.fetchone()[0] or 0)
        if matched_count == 0:
            raise RuntimeError("No matched rows found between CSV external_id and gdi_instrument_types.")

        cur.execute(
            """
            SELECT COUNT(1)
            FROM #matched_inst
            WHERE LOWER(LTRIM(RTRIM(ISNULL(old_instrument_type_name, ''))))
                <> LOWER(LTRIM(RTRIM(ISNULL(new_instrument_type_name, ''))))
            """
        )
        gdi_change_count = int(cur.fetchone()[0] or 0)

        cur.execute(
            """
            UPDATE g
            SET g.col03varchar = m.new_instrument_type_name,
                g.instrument_type_internal_id = m.new_instrument_type_id,
                g.instrument_type_external_id = m.new_instrument_type_id
            FROM dbo.gdi_instrument_types g
            JOIN #matched_inst m
              ON m.source_row_id = g.id
             AND m.imported_by_user_id = g.imported_by_user_id
             AND m.state_fips = g.state_fips
             AND m.county_fips = g.county_fips
            """
        )
        gdi_updated = int(cur.rowcount or 0)

        corr_updated = 0
        corr_inserted = 0
        if has_corr:
            set_parts = [
                "target.original_instrument_type = src.old_instrument_type_name",
                "target.new_instrument_type_name = src.new_instrument_type_name",
                "target.new_instrument_type_id = src.new_instrument_type_id",
                "target.updated_at = SYSDATETIMEOFFSET()",
            ]
            if "new_record_type" in corr_cols:
                set_parts.append("target.new_record_type = src.new_record_type")
            if "new_is_active" in corr_cols:
                set_parts.append("target.new_is_active = src.new_is_active")
            if "updated_by_user_id" in corr_cols:
                set_parts.append("target.updated_by_user_id = src.imported_by_user_id")
            if "is_fixed" in corr_cols:
                set_parts.append("target.is_fixed = 1")

            insert_cols = [
                "source_row_id",
                "original_instrument_type",
                "new_instrument_type_name",
                "new_instrument_type_id",
                "imported_by_user_id",
                "state_fips",
                "county_fips",
            ]
            insert_vals = [
                "src.source_row_id",
                "src.old_instrument_type_name",
                "src.new_instrument_type_name",
                "src.new_instrument_type_id",
                "src.imported_by_user_id",
                "src.state_fips",
                "src.county_fips",
            ]
            if "new_record_type" in corr_cols:
                insert_cols.append("new_record_type")
                insert_vals.append("src.new_record_type")
            if "new_is_active" in corr_cols:
                insert_cols.append("new_is_active")
                insert_vals.append("src.new_is_active")
            if "updated_by_user_id" in corr_cols:
                insert_cols.append("updated_by_user_id")
                insert_vals.append("src.imported_by_user_id")
            if "is_fixed" in corr_cols:
                insert_cols.append("is_fixed")
                insert_vals.append("1")

            cur.execute(
                f"""
                IF OBJECT_ID('tempdb..#corr_merge_action') IS NOT NULL DROP TABLE #corr_merge_action;
                CREATE TABLE #corr_merge_action ([action] NVARCHAR(10) NOT NULL);

                MERGE dbo.corrections_instrument_types AS target
                USING #matched_inst AS src
                ON target.source_row_id = src.source_row_id
               AND target.imported_by_user_id = src.imported_by_user_id
               AND target.state_fips = src.state_fips
               AND target.county_fips = src.county_fips
                WHEN MATCHED THEN
                    UPDATE SET {', '.join(set_parts)}
                WHEN NOT MATCHED THEN
                    INSERT ({', '.join(insert_cols)})
                    VALUES ({', '.join(insert_vals)})
                OUTPUT $action INTO #corr_merge_action([action]);

                SELECT
                    SUM(CASE WHEN [action] = 'UPDATE' THEN 1 ELSE 0 END) AS updated_count,
                    SUM(CASE WHEN [action] = 'INSERT' THEN 1 ELSE 0 END) AS inserted_count
                FROM #corr_merge_action;
                """
            )
            row = cur.fetchone()
            if row:
                corr_updated = int(row[0] or 0)
                corr_inserted = int(row[1] or 0)

        if args.dry_run:
            conn.rollback()
            print("DRY RUN complete (no changes committed).")
        else:
            conn.commit()
            print("Committed updates.")

        print(f"CSV rows loaded: {len(csv_rows)}")
        print(f"Matched gdi rows: {matched_count}")
        print(f"gdi rows requiring name change: {gdi_change_count}")
        print(f"gdi rows updated: {gdi_updated}")
        if has_corr:
            print(f"corrections rows updated: {corr_updated}")
            print(f"corrections rows inserted: {corr_inserted}")
        else:
            print("corrections_instrument_types table not found; skipped corrections updates.")

        return 0
    except Exception as exc:
        conn.rollback()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        try:
            cur.close()
        except Exception:
            pass
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
