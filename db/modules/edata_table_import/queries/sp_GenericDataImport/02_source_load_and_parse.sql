/* ============================================================================
   File: 02_source_load_and_parse.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - Loads the current CSV into temp storage and expands each source row into the
     parsed column set consumed by the import pipeline.
   Why this file exists:
   - It isolates the raw-file handling and parsing rules from the insert, retire,
     and rebuild stages so import format changes can be made in one place.
   Maintenance notes:
   - This fragment must stay after bootstrap and before any insert logic.
   - Be careful with row-width handling and string parsing here because the rest
     of the procedure trusts #ParsedData as the canonical per-file staging set.
   ============================================================================ */
    -- Replace mode is overlap-based and handled after parsing this incoming file.

    DROP TABLE IF EXISTS #TempDataCollector;
    -- Store raw source lines without width truncation. Some county files have very wide rows.
    CREATE TABLE #TempDataCollector (Field1 VARCHAR(MAX));

    SET @sql =
        N'BULK INSERT #TempDataCollector
          FROM ' + QUOTENAME(REPLACE(@ImportFileName, '''', ''''''), '''') + N'
          WITH
          (
              FIRSTROW = 1,
              FIELDTERMINATOR = ''~'',
              ROWTERMINATOR = ''0x0a'',
              TABLOCK
          );';
    EXEC sys.sp_executesql @sql;

    UPDATE #TempDataCollector
    SET Field1 = LTRIM(RTRIM(Field1));
    DECLARE @source_row_count INT = (SELECT COUNT(1) FROM #TempDataCollector);

    DROP TABLE IF EXISTS #ParsedData;
    ;WITH seeded AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS row_id,
            CAST(Field1 AS VARCHAR(MAX)) AS original_value
        FROM #TempDataCollector
    ),
    quote_parse AS (
        SELECT
            s.row_id,
            s.original_value,
            CAST(0 AS INT) AS n,
            CAST(s.original_value AS VARCHAR(MAX)) AS rem,
            CAST('' AS VARCHAR(1000)) AS token
        FROM seeded s

        UNION ALL

        SELECT
            q.row_id,
            q.original_value,
            q.n + 1 AS n,
            CASE
                WHEN a.first_quote_pos > 0 AND a.second_quote_pos > 0
                    THEN STUFF(q.rem, a.first_quote_pos, a.second_quote_pos + 1, '')
                ELSE q.rem
            END AS rem,
            CASE
                WHEN a.first_quote_pos > 0 AND a.second_quote_pos > 0
                    THEN CAST(SUBSTRING(a.after_first_quote, 1, a.second_quote_pos - 1) AS VARCHAR(1000))
                ELSE CAST('' AS VARCHAR(1000))
            END AS token
        FROM quote_parse q
        CROSS APPLY (
            SELECT
                CHARINDEX('"', q.rem) AS first_quote_pos,
                CASE
                    WHEN CHARINDEX('"', q.rem) > 0
                        THEN SUBSTRING(q.rem, CHARINDEX('"', q.rem) + 1, LEN(q.rem))
                    ELSE ''
                END AS after_first_quote
        ) p
        CROSS APPLY (
            SELECT
                p.first_quote_pos,
                p.after_first_quote,
                CHARINDEX('"', p.after_first_quote) AS second_quote_pos
        ) a
        WHERE q.n < 10
    ),
    quote_pivot AS (
        SELECT
            q.row_id,
            q.original_value,
            MAX(CASE WHEN q.n = 1 THEN q.token END) AS col01varchar,
            MAX(CASE WHEN q.n = 2 THEN q.token END) AS col02varchar,
            MAX(CASE WHEN q.n = 3 THEN q.token END) AS col03varchar,
            MAX(CASE WHEN q.n = 4 THEN q.token END) AS col04varchar,
            MAX(CASE WHEN q.n = 5 THEN q.token END) AS col05varchar,
            MAX(CASE WHEN q.n = 6 THEN q.token END) AS col06varchar,
            MAX(CASE WHEN q.n = 7 THEN q.token END) AS col07varchar,
            MAX(CASE WHEN q.n = 8 THEN q.token END) AS col08varchar,
            MAX(CASE WHEN q.n = 9 THEN q.token END) AS col09varchar,
            MAX(CASE WHEN q.n = 10 THEN q.token END) AS col10varchar,
            MAX(CASE WHEN q.n = 10 THEN q.rem END) AS leftovers
        FROM quote_parse q
        GROUP BY q.row_id, q.original_value
    )
    SELECT
        CAST(@ImportFileName AS VARCHAR(1000)) AS fn,
        CAST(@file_key AS NVARCHAR(260)) AS file_key,
        CAST(@header_file_key AS NVARCHAR(260)) AS header_file_key,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(p.original_value, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '') AS OriginalValue,
        ISNULL(p.col01varchar, '') AS col01varchar,
        ISNULL(p.col02varchar, '') AS col02varchar,
        ISNULL(p.col03varchar, '') AS col03varchar,
        ISNULL(p.col04varchar, '') AS col04varchar,
        ISNULL(p.col05varchar, '') AS col05varchar,
        ISNULL(p.col06varchar, '') AS col06varchar,
        ISNULL(p.col07varchar, '') AS col07varchar,
        ISNULL(p.col08varchar, '') AS col08varchar,
        ISNULL(p.col09varchar, '') AS col09varchar,
        ISNULL(p.col10varchar, '') AS col10varchar,
        MAX(CASE WHEN j.[key] = 0 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS key_id,
        MAX(CASE WHEN j.[key] = 1 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS book,
        MAX(CASE WHEN j.[key] = 2 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS page_number,
        MAX(CASE WHEN j.[key] = 3 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS keli_image_path,
        MAX(CASE WHEN j.[key] = 4 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS beginning_page,
        MAX(CASE WHEN j.[key] = 5 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS ending_page,
        MAX(CASE WHEN j.[key] = 6 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS record_series_internal_id,
        MAX(CASE WHEN j.[key] = 7 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS record_series_external_id,
        MAX(CASE WHEN j.[key] = 8 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS instrument_type_internal_id,
        MAX(CASE WHEN j.[key] = 9 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS instrument_type_external_id,
        MAX(CASE WHEN j.[key] = 10 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS grantor_suffix_internal_id,
        MAX(CASE WHEN j.[key] = 11 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS grantee_suffix_internal_id,
        MAX(CASE WHEN j.[key] = 12 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS manual_page_count,
        MAX(CASE WHEN j.[key] = 13 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS legal_type,
        MAX(CASE WHEN j.[key] = 14 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS additions_internal_id,
        MAX(CASE WHEN j.[key] = 15 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS additions_external_id,
        MAX(CASE WHEN j.[key] = 16 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS township_range_internal_id,
        MAX(CASE WHEN j.[key] = 17 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS township_range_external_id,
        MAX(CASE WHEN j.[key] = 18 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS free_form_legal,
        MAX(CASE WHEN j.[key] = 19 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS referenced_instrument,
        MAX(CASE WHEN j.[key] = 20 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS referenced_book,
        MAX(CASE WHEN j.[key] = 21 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS referenced_page,
        MAX(CASE WHEN j.[key] = 22 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS col20other,
        CAST('' AS VARCHAR(1000)) AS uf1,
        CAST('' AS VARCHAR(1000)) AS uf2,
        CAST('' AS VARCHAR(1000)) AS uf3,
        ISNULL(p.leftovers, '') AS leftovers,
        CAST(@ImportedByUserId AS INT) AS imported_by_user_id,
        CAST(@batch_id AS UNIQUEIDENTIFIER) AS import_batch_id,
        CAST(@state_fips AS CHAR(2)) AS state_fips,
        CAST(@county_fips AS CHAR(5)) AS county_fips,
        CAST(0 AS BIT) AS is_deleted,
        SYSDATETIMEOFFSET() AS imported_at
    INTO #ParsedData
    FROM quote_pivot p
    OUTER APPLY (
        SELECT
            CASE
                WHEN ISNULL(p.leftovers, '') = ''
                    THEN N'[]'
                ELSE N'["' + REPLACE(STRING_ESCAPE(CAST(p.leftovers AS NVARCHAR(MAX)), 'json'), ',', '","') + N'"]'
            END AS leftovers_json
    ) js
    OUTER APPLY OPENJSON(js.leftovers_json) j
    GROUP BY
        p.row_id,
        p.original_value,
        p.col01varchar, p.col02varchar, p.col03varchar, p.col04varchar, p.col05varchar,
        p.col06varchar, p.col07varchar, p.col08varchar, p.col09varchar, p.col10varchar,
        p.leftovers;

    DECLARE @parsed_row_count INT = (SELECT COUNT(1) FROM #ParsedData);
    DECLARE @append_existing_match_count INT = 0;
