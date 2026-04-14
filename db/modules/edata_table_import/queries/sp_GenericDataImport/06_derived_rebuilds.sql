/* ============================================================================
   File: 06_derived_rebuilds.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - Rebuilds the derived helper tables that the UI and DQ tooling use for
     record series, instrument types, additions, and township/range review.
   Why this file exists:
   - These tables are derived from the active split scope and are easier to
     reason about separately from the generic split-table rebuild loop.
   Maintenance notes:
   - Deduping rules for additions and township/range live here.
   - Keep the table contracts stable because downstream correction tooling binds
     to these helper tables directly.
   ============================================================================ */
        DROP TABLE IF EXISTS dbo.gdi_record_series;
        CREATE TABLE dbo.gdi_record_series (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            [year] VARCHAR(1000),
            record_series_internal_id VARCHAR(1000),
            record_series_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH scoped_headers AS (
            SELECT
                h.*,
                CASE
                    WHEN LEN(LTRIM(RTRIM(ISNULL(h.col06varchar, '')))) >= 4
                        THEN LEFT(LTRIM(RTRIM(ISNULL(h.col06varchar, ''))), 4)
                    ELSE ''
                END AS [year_value]
            FROM dbo.gdi_instruments h
            WHERE h.imported_by_user_id = @ImportedByUserId
              AND h.state_fips = @state_fips
              AND h.county_fips = @county_fips
        )
        INSERT INTO dbo.gdi_record_series (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, [year], record_series_internal_id, record_series_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(h.fn, ''), ISNULL(h.file_key, ''), ISNULL(h.header_file_key, ''), ISNULL(h.keyOriginalValue, ''), ISNULL(h.OriginalValue, ''),
            ISNULL(h.col01varchar, ''), ISNULL(h.year_value, ''), '', '',
            0,
            h.imported_by_user_id, h.import_batch_id, h.state_fips, h.county_fips, ISNULL(h.is_deleted, 0), h.imported_at
        FROM scoped_headers h;

        DROP TABLE IF EXISTS dbo.gdi_instrument_types;
        CREATE TABLE dbo.gdi_instrument_types (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col03varchar VARCHAR(1000),
            instrument_type_internal_id VARCHAR(1000),
            instrument_type_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH source_rows AS (
            SELECT
                g.id,
                g.fn,
                g.OriginalValue,
                g.col01varchar,
                g.col03varchar,
                g.imported_by_user_id,
                g.import_batch_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.is_deleted, 0) AS is_deleted,
                g.imported_at,
                ISNULL(sp.file_key, '') AS file_key,
                ISNULL(sp.header_file_key, '') AS header_file_key
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport g
              ON g.ID = sp.source_id
            WHERE sp.tag = 'header'
              AND LTRIM(RTRIM(ISNULL(g.col03varchar, ''))) <> ''
        )
        INSERT INTO dbo.gdi_instrument_types (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col03varchar, instrument_type_internal_id, instrument_type_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(s.fn, ''), ISNULL(s.file_key, ''), ISNULL(s.header_file_key, ''),
            ISNULL(s.OriginalValue, ''),
            ISNULL(s.OriginalValue, ''),
            ISNULL(s.col01varchar, ''), ISNULL(s.col03varchar, ''), '', '',
            0,
            s.imported_by_user_id, s.import_batch_id, s.state_fips, s.county_fips, ISNULL(s.is_deleted, 0), s.imported_at
        FROM source_rows s;

        DROP TABLE IF EXISTS dbo.gdi_additions;
        CREATE TABLE dbo.gdi_additions (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col05varchar VARCHAR(1000),
            additions_internal_id VARCHAR(1000),
            additions_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH source_rows AS (
            SELECT
                g.id,
                g.fn,
                g.OriginalValue,
                g.col01varchar,
                g.col05varchar,
                g.imported_by_user_id,
                g.import_batch_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.is_deleted, 0) AS is_deleted,
                g.imported_at,
                CASE
                    WHEN sp.tag = 'legal' THEN 'legals' + ISNULL(sp.file_suffix, '')
                    ELSE ISNULL(sp.file_key, '')
                END AS file_key,
                ISNULL(sp.header_file_key, '') AS header_file_key
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport g
              ON g.ID = sp.source_id
            WHERE sp.tag IN ('legal', 'legals')
              AND LTRIM(RTRIM(ISNULL(g.col05varchar, ''))) <> ''
        ),
        ranked AS (
            SELECT
                s.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        s.import_batch_id,
                        ISNULL(s.header_file_key, ''),
                        ISNULL(s.col01varchar, ''),
                        LTRIM(RTRIM(ISNULL(s.col05varchar, '')))
                    ORDER BY s.id
                ) AS rn
            FROM source_rows s
        )
        INSERT INTO dbo.gdi_additions (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col05varchar, additions_internal_id, additions_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(r.fn, ''), ISNULL(r.file_key, ''), ISNULL(r.header_file_key, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.col01varchar, ''), ISNULL(r.col05varchar, ''), '', '',
            0,
            r.imported_by_user_id, r.import_batch_id, r.state_fips, r.county_fips, ISNULL(r.is_deleted, 0), r.imported_at
        FROM ranked r
        WHERE r.rn = 1;

        DROP TABLE IF EXISTS dbo.gdi_township_range;
        CREATE TABLE dbo.gdi_township_range (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col03varchar VARCHAR(1000),
            col04varchar VARCHAR(1000),
            township_range_internal_id VARCHAR(1000),
            township_range_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH source_rows AS (
            SELECT
                g.id,
                g.fn,
                g.OriginalValue,
                g.col01varchar,
                g.col03varchar,
                g.col04varchar,
                g.imported_by_user_id,
                g.import_batch_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.is_deleted, 0) AS is_deleted,
                g.imported_at,
                CASE
                    WHEN sp.tag = 'legal' THEN 'legals' + ISNULL(sp.file_suffix, '')
                    ELSE ISNULL(sp.file_key, '')
                END AS file_key,
                ISNULL(sp.header_file_key, '') AS header_file_key
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport g
              ON g.ID = sp.source_id
            WHERE sp.tag IN ('legal', 'legals')
        ),
        ranked AS (
            SELECT
                s.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        s.import_batch_id,
                        ISNULL(s.header_file_key, ''),
                        ISNULL(s.col01varchar, ''),
                        LTRIM(RTRIM(ISNULL(s.col03varchar, ''))),
                        LTRIM(RTRIM(ISNULL(s.col04varchar, '')))
                    ORDER BY s.id
                ) AS rn
            FROM source_rows s
        )
        INSERT INTO dbo.gdi_township_range (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col03varchar, col04varchar, township_range_internal_id, township_range_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(r.fn, ''), ISNULL(r.file_key, ''), ISNULL(r.header_file_key, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.col01varchar, ''), ISNULL(r.col03varchar, ''), ISNULL(r.col04varchar, ''), '', '',
            0,
            r.imported_by_user_id, r.import_batch_id, r.state_fips, r.county_fips, ISNULL(r.is_deleted, 0), r.imported_at
        FROM ranked r
        WHERE r.rn = 1;
