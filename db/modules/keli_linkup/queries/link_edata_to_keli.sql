CREATE OR ALTER PROCEDURE dbo.sp_LinkEdataToKeli
    @ImportedByUserId INT,
    @StateFips CHAR(2),
    @CountyFips CHAR(5)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ImportedByUserId IS NULL OR @ImportedByUserId <= 0
        THROW 50001, 'ImportedByUserId is required.', 1;
    IF @StateFips IS NULL OR LEN(LTRIM(RTRIM(@StateFips))) <> 2
        THROW 50002, 'StateFips must be 2 characters.', 1;
    IF @CountyFips IS NULL OR LEN(LTRIM(RTRIM(@CountyFips))) <> 5
        THROW 50003, 'CountyFips must be 5 characters.', 1;

    SET @StateFips = RIGHT('00' + LTRIM(RTRIM(@StateFips)), 2);
    SET @CountyFips = RIGHT('00000' + LTRIM(RTRIM(@CountyFips)), 5);

    IF OBJECT_ID(N'dbo.gdi_instruments', N'U') IS NULL
        THROW 50004, 'gdi_instruments table was not found.', 1;

    -- Header year is no longer used for linkup; record-series year is sourced
    -- from dbo.gdi_record_series.[year]. Keep linkup independent of any
    -- legacy dbo.gdi_instruments.[year] column.

    DECLARE @legal_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.gdi_legals', N'U') IS NOT NULL
        SET @legal_table = N'gdi_legals';
    ELSE IF OBJECT_ID(N'dbo.gdi_legal', N'U') IS NOT NULL
        SET @legal_table = N'gdi_legal';
    IF @legal_table IS NULL
        THROW 50005, 'gdi_legals/gdi_legal table was not found.', 1;

    DECLARE @names_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.gdi_parties', N'U') IS NOT NULL
        SET @names_table = N'gdi_parties';

    DECLARE @reference_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
        SET @reference_table = N'gdi_instrument_references';

    DECLARE @keli_instrument_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.keli_instrument', N'U') IS NOT NULL
        SET @keli_instrument_table = N'keli_instrument';
    ELSE IF OBJECT_ID(N'dbo.keli_instruments', N'U') IS NOT NULL
        SET @keli_instrument_table = N'keli_instruments';

    DECLARE @keli_parties_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.keli_parties', N'U') IS NOT NULL
        SET @keli_parties_table = N'keli_parties';
    ELSE IF OBJECT_ID(N'dbo.keli_party', N'U') IS NOT NULL
        SET @keli_parties_table = N'keli_party';

    DECLARE @keli_legals_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.keli_legals', N'U') IS NOT NULL
        SET @keli_legals_table = N'keli_legals';
    ELSE IF OBJECT_ID(N'dbo.keli_legal', N'U') IS NOT NULL
        SET @keli_legals_table = N'keli_legal';

    DECLARE @keli_refs_table SYSNAME = NULL;
    DECLARE @keli_ref_book_col SYSNAME = NULL;
    DECLARE @keli_ref_page_col SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.keli_instrument_references', N'U') IS NOT NULL
        SET @keli_refs_table = N'keli_instrument_references';
    ELSE IF OBJECT_ID(N'dbo.keli_instrument_reference', N'U') IS NOT NULL
        SET @keli_refs_table = N'keli_instrument_reference';

    IF @keli_refs_table IS NOT NULL
    BEGIN
        IF COL_LENGTH(N'dbo.' + @keli_refs_table, 'referenced_book') IS NOT NULL
            SET @keli_ref_book_col = N'referenced_book';
        ELSE IF COL_LENGTH(N'dbo.' + @keli_refs_table, 'reference_book') IS NOT NULL
            SET @keli_ref_book_col = N'reference_book';

        IF COL_LENGTH(N'dbo.' + @keli_refs_table, 'referenced_page') IS NOT NULL
            SET @keli_ref_page_col = N'referenced_page';
        ELSE IF COL_LENGTH(N'dbo.' + @keli_refs_table, 'reference_page') IS NOT NULL
            SET @keli_ref_page_col = N'reference_page';
    END;

    DECLARE @job_book_min INT = NULL;
    DECLARE @job_book_max INT = NULL;
    SELECT
        @job_book_min = MIN(TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(h.book)), ''))),
        @job_book_max = MAX(TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(h.book)), '')))
    FROM dbo.gdi_instruments h
    WHERE h.imported_by_user_id = @ImportedByUserId
      AND h.state_fips = @StateFips
      AND h.county_fips = @CountyFips
      AND ISNULL(h.is_deleted, 0) = 0;

    DECLARE @sql NVARCHAR(MAX);

    IF OBJECT_ID(N'dbo.keli_record_series', N'U') IS NULL
        THROW 50006, 'keli_record_series table was not found.', 1;
    IF OBJECT_ID(N'dbo.keli_additions', N'U') IS NULL
        THROW 50007, 'keli_additions table was not found.', 1;
    IF OBJECT_ID(N'dbo.keli_township_ranges', N'U') IS NULL
        THROW 50008, 'keli_township_ranges table was not found.', 1;

    IF OBJECT_ID(N'dbo.gdi_record_series', N'U') IS NOT NULL
    BEGIN
        ;WITH rs AS (
            SELECT
                grs.id,
                LTRIM(RTRIM(ISNULL(grs.[year], ''))) AS series_year
            FROM dbo.gdi_record_series grs
            WHERE grs.imported_by_user_id = @ImportedByUserId
              AND grs.state_fips = @StateFips
              AND grs.county_fips = @CountyFips
              AND ISNULL(grs.is_deleted, 0) = 0
        ),
        matched AS (
            SELECT
                rs.id,
                CAST(k.id AS VARCHAR(1000)) AS keli_series_id
            FROM rs
            JOIN dbo.keli_record_series k
              ON UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '')))) = UPPER(rs.series_year)
             AND k.state_fips = @StateFips
             AND k.county_fips = @CountyFips
            WHERE rs.series_year <> ''
        )
        UPDATE grs
        SET
            grs.record_series_internal_id = m.keli_series_id,
            grs.record_series_external_id = ''
        FROM dbo.gdi_record_series grs
        JOIN matched m ON m.id = grs.id;

        ;WITH missing_prefix AS (
            SELECT
                LTRIM(RTRIM(ISNULL(grs.[year], ''))) AS series_prefix,
                MIN(grs.id) AS first_id
            FROM dbo.gdi_record_series grs
            WHERE grs.imported_by_user_id = @ImportedByUserId
              AND grs.state_fips = @StateFips
              AND grs.county_fips = @CountyFips
              AND ISNULL(grs.is_deleted, 0) = 0
              AND LTRIM(RTRIM(ISNULL(grs.[year], ''))) <> ''
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.keli_record_series k
                  WHERE UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '')))) =
                        UPPER(LTRIM(RTRIM(ISNULL(grs.[year], ''))))
                    AND k.state_fips = @StateFips
                    AND k.county_fips = @CountyFips
              )
            GROUP BY LTRIM(RTRIM(ISNULL(grs.[year], '')))
        ),
        ranked AS (
            SELECT
                mp.series_prefix,
                DENSE_RANK() OVER (
                    ORDER BY mp.first_id, mp.series_prefix
                ) AS seq_id
            FROM missing_prefix mp
        )
        UPDATE grs
        SET
            grs.record_series_internal_id = '',
            grs.record_series_external_id = CAST(r.seq_id AS VARCHAR(1000))
        FROM dbo.gdi_record_series grs
        JOIN ranked r
          ON r.series_prefix = LTRIM(RTRIM(ISNULL(grs.[year], '')))
        WHERE grs.imported_by_user_id = @ImportedByUserId
          AND grs.state_fips = @StateFips
          AND grs.county_fips = @CountyFips
          AND ISNULL(grs.is_deleted, 0) = 0;

        UPDATE grs
        SET
            grs.record_series_internal_id = '',
            grs.record_series_external_id = ''
        FROM dbo.gdi_record_series grs
        WHERE grs.imported_by_user_id = @ImportedByUserId
          AND grs.state_fips = @StateFips
          AND grs.county_fips = @CountyFips
          AND ISNULL(grs.is_deleted, 0) = 0
          AND LTRIM(RTRIM(ISNULL(grs.[year], ''))) = '';
    END;

    -- Build a normalized keli instrument map once and reuse throughout linkup.
    DROP TABLE IF EXISTS #keli_instrument_scope;
    IF @keli_instrument_table IS NOT NULL
    BEGIN
        CREATE TABLE #keli_instrument_scope (
            norm_book VARCHAR(64) NOT NULL,
            norm_page VARCHAR(64) NOT NULL,
            keli_inst_id VARCHAR(1000) NOT NULL
        );

        SET @sql = N'
            INSERT INTO #keli_instrument_scope (norm_book, norm_page, keli_inst_id)
            SELECT
                LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(ki.book AS VARCHAR(1000)), '''')))), 64) AS norm_book,
                LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(ki.beginning_page AS VARCHAR(1000)), '''')))), 64) AS norm_page,
                MIN(CAST(ki.id AS VARCHAR(1000))) AS keli_inst_id
            FROM dbo.' + QUOTENAME(@keli_instrument_table) + N' ki
            WHERE ki.state_fips = @sf
              AND ki.county_fips = @cf
            GROUP BY
                LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(ki.book AS VARCHAR(1000)), '''')))), 64),
                LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(ki.beginning_page AS VARCHAR(1000)), '''')))), 64);';
        EXEC sys.sp_executesql @sql, N'@sf CHAR(2), @cf CHAR(5)', @sf=@StateFips, @cf=@CountyFips;
        CREATE INDEX IX_keli_instrument_scope_book_page
            ON #keli_instrument_scope (norm_book, norm_page);
    END;

    DROP TABLE IF EXISTS #keli_instrument_number_scope;
    IF @keli_instrument_table IS NOT NULL
    BEGIN
        CREATE TABLE #keli_instrument_number_scope (
            norm_instrument_number VARCHAR(1000) NOT NULL,
            keli_inst_id VARCHAR(1000) NOT NULL
        );

        SET @sql = N'
            INSERT INTO #keli_instrument_number_scope (norm_instrument_number, keli_inst_id)
            SELECT
                src.norm_instrument_number,
                MIN(src.keli_inst_id) AS keli_inst_id
            FROM (
                SELECT
                    UPPER(LTRIM(RTRIM(ISNULL(CAST(ki.instrument_number AS VARCHAR(1000)), '''')))) AS norm_instrument_number,
                    CAST(ki.id AS VARCHAR(1000)) AS keli_inst_id
                FROM dbo.' + QUOTENAME(@keli_instrument_table) + N' ki
                WHERE ki.state_fips = @sf
                  AND ki.county_fips = @cf
                  AND LTRIM(RTRIM(ISNULL(CAST(ki.instrument_number AS VARCHAR(1000)), ''''))) <> ''''
            ) src
            GROUP BY src.norm_instrument_number
            HAVING COUNT(*) = 1;';
        EXEC sys.sp_executesql @sql, N'@sf CHAR(2), @cf CHAR(5)', @sf=@StateFips, @cf=@CountyFips;
        CREATE INDEX IX_keli_instrument_number_scope_inst_no
            ON #keli_instrument_number_scope (norm_instrument_number);
    END;

    DROP TABLE IF EXISTS #keli_instrument_num_scope;
    IF @keli_instrument_table IS NOT NULL
    BEGIN
        CREATE TABLE #keli_instrument_num_scope (
            num_book BIGINT NOT NULL,
            num_page BIGINT NOT NULL,
            keli_inst_id VARCHAR(1000) NOT NULL
        );

        SET @sql = N'
            INSERT INTO #keli_instrument_num_scope (num_book, num_page, keli_inst_id)
            SELECT
                TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(CAST(ki.book AS VARCHAR(1000)))), '''')) AS num_book,
                TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(CAST(ki.beginning_page AS VARCHAR(1000)))), '''')) AS num_page,
                MIN(CAST(ki.id AS VARCHAR(1000))) AS keli_inst_id
            FROM dbo.' + QUOTENAME(@keli_instrument_table) + N' ki
            WHERE TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(CAST(ki.book AS VARCHAR(1000)))), '''')) IS NOT NULL
              AND TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(CAST(ki.beginning_page AS VARCHAR(1000)))), '''')) IS NOT NULL
              AND ki.state_fips = @sf
              AND ki.county_fips = @cf
            GROUP BY
                TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(CAST(ki.book AS VARCHAR(1000)))), '''')),
                TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(CAST(ki.beginning_page AS VARCHAR(1000)))), ''''));';
        EXEC sys.sp_executesql @sql, N'@sf CHAR(2), @cf CHAR(5)', @sf=@StateFips, @cf=@CountyFips;
        CREATE INDEX IX_keli_instrument_num_scope_book_page
            ON #keli_instrument_num_scope (num_book, num_page);
    END;

    DROP TABLE IF EXISTS #header_keli_match;
    CREATE TABLE #header_keli_match (
        header_id INT NOT NULL PRIMARY KEY,
        keli_inst_id VARCHAR(1000) NULL
    );

    IF @keli_instrument_table IS NOT NULL
    BEGIN
        INSERT INTO #header_keli_match (header_id, keli_inst_id)
        SELECT
            h.id,
            COALESCE(kis_raw.keli_inst_id, kis_num.keli_inst_id, kis_inst.keli_inst_id) AS keli_inst_id
        FROM dbo.gdi_instruments h
        LEFT JOIN #keli_instrument_scope kis_raw
          ON kis_raw.norm_book = LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), 64)
         AND kis_raw.norm_page = LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.beginning_page, '')))), 64)
        LEFT JOIN #keli_instrument_num_scope kis_num
          ON kis_num.num_book = TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(h.book, ''))), ''))
         AND kis_num.num_page = TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(h.beginning_page, ''))), ''))
        LEFT JOIN #keli_instrument_number_scope kis_inst
          ON kis_inst.norm_instrument_number = UPPER(LTRIM(RTRIM(ISNULL(h.instrument_number, ''))))
        WHERE h.imported_by_user_id = @ImportedByUserId
          AND h.state_fips = @StateFips
          AND h.county_fips = @CountyFips
          AND ISNULL(h.is_deleted, 0) = 0;
    END;

    -- Header linkup:
    -- internal_id = keli instrument id (match by book + beginning_page)
    -- external_id = per-job sequence (1..N) ordered by header id within each import_batch_id
    IF @keli_instrument_table IS NOT NULL
    BEGIN
        SET @sql = N'
            ;WITH header_seq AS (
                SELECT
                    hs.id,
                    ROW_NUMBER() OVER (
                        PARTITION BY hs.import_batch_id
                        ORDER BY hs.id
                    ) AS seq_id
                FROM dbo.gdi_instruments hs
                WHERE hs.imported_by_user_id = @uid
                  AND hs.state_fips = @sf
                  AND hs.county_fips = @cf
                  AND ISNULL(hs.is_deleted, 0) = 0
            )
            UPDATE h
            SET
                h.internal_id = ISNULL(hkm.keli_inst_id, ''''),
                h.external_id = CAST(s.seq_id AS VARCHAR(1000))
            FROM dbo.gdi_instruments h
            JOIN header_seq s
              ON s.id = h.id
            LEFT JOIN #header_keli_match hkm
              ON hkm.header_id = h.id
            WHERE h.imported_by_user_id = @uid
              AND h.state_fips = @sf
              AND h.county_fips = @cf
              AND ISNULL(h.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END
    ELSE
    BEGIN
        ;WITH header_seq AS (
            SELECT
                hs.id,
                ROW_NUMBER() OVER (
                    PARTITION BY hs.import_batch_id
                    ORDER BY hs.id
                ) AS seq_id
            FROM dbo.gdi_instruments hs
            WHERE hs.imported_by_user_id = @ImportedByUserId
              AND hs.state_fips = @StateFips
              AND hs.county_fips = @CountyFips
              AND ISNULL(hs.is_deleted, 0) = 0
        )
        UPDATE h
        SET
            h.internal_id = '',
            h.external_id = CAST(s.seq_id AS VARCHAR(1000))
        FROM dbo.gdi_instruments h
        JOIN header_seq s
          ON s.id = h.id
        WHERE h.imported_by_user_id = @ImportedByUserId
          AND h.state_fips = @StateFips
          AND h.county_fips = @CountyFips
          AND ISNULL(h.is_deleted, 0) = 0;
    END;

    DROP TABLE IF EXISTS #header_keli_inst_map;
    CREATE TABLE #header_keli_inst_map (
        header_id INT NOT NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL,
        col01varchar VARCHAR(1000) NOT NULL,
        keli_inst_id VARCHAR(1000) NULL
    );
    CREATE INDEX IX_header_keli_inst_map_scope_key
        ON #header_keli_inst_map (imported_by_user_id, state_fips, county_fips, header_file_key, col01varchar);

    IF @keli_instrument_table IS NOT NULL
    BEGIN
        SET @sql = N'
            INSERT INTO #header_keli_inst_map (
                header_id, imported_by_user_id, state_fips, county_fips, header_file_key, col01varchar, keli_inst_id
            )
            SELECT
                h.id,
                h.imported_by_user_id,
                h.state_fips,
                h.county_fips,
                ISNULL(h.header_file_key, ''''),
                ISNULL(h.col01varchar, ''''),
                MIN(hkm.keli_inst_id) AS keli_inst_id
            FROM dbo.gdi_instruments h
            LEFT JOIN #header_keli_match hkm
              ON hkm.header_id = h.id
            WHERE h.imported_by_user_id = @uid
              AND h.state_fips = @sf
              AND h.county_fips = @cf
              AND ISNULL(h.is_deleted, 0) = 0
            GROUP BY
                h.id, h.imported_by_user_id, h.state_fips, h.county_fips, ISNULL(h.header_file_key, ''''), ISNULL(h.col01varchar, '''');';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END
    ELSE
    BEGIN
        INSERT INTO #header_keli_inst_map (
            header_id, imported_by_user_id, state_fips, county_fips, header_file_key, col01varchar, keli_inst_id
        )
        SELECT
            h.id, h.imported_by_user_id, h.state_fips, h.county_fips,
            ISNULL(h.header_file_key, ''), ISNULL(h.col01varchar, ''), NULL
        FROM dbo.gdi_instruments h
        WHERE h.imported_by_user_id = @ImportedByUserId
          AND h.state_fips = @StateFips
          AND h.county_fips = @CountyFips
          AND ISNULL(h.is_deleted, 0) = 0;
    END;

    DROP TABLE IF EXISTS #header_book_page_map;
    CREATE TABLE #header_book_page_map (
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        book VARCHAR(64) NOT NULL,
        beginning_page VARCHAR(64) NOT NULL,
        target_header_id VARCHAR(1000) NOT NULL,
        target_header_external_id VARCHAR(1000) NOT NULL
    );

    INSERT INTO #header_book_page_map (
        imported_by_user_id, state_fips, county_fips, book, beginning_page, target_header_id, target_header_external_id
    )
    SELECT
        x.imported_by_user_id,
        x.state_fips,
        x.county_fips,
        x.book,
        x.beginning_page,
        x.target_header_id,
        x.target_header_external_id
    FROM (
        SELECT
            h.imported_by_user_id,
            h.state_fips,
            h.county_fips,
            LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), 64) AS book,
            LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.beginning_page, '')))), 64) AS beginning_page,
            CAST(h.id AS VARCHAR(1000)) AS target_header_id,
            ISNULL(CAST(h.external_id AS VARCHAR(1000)), '') AS target_header_external_id,
            ROW_NUMBER() OVER (
                PARTITION BY h.imported_by_user_id, h.state_fips, h.county_fips,
                             LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), 64),
                             LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.beginning_page, '')))), 64)
                ORDER BY h.id
            ) AS rn
        FROM dbo.gdi_instruments h
        WHERE h.imported_by_user_id = @ImportedByUserId
          AND h.state_fips = @StateFips
          AND h.county_fips = @CountyFips
          AND ISNULL(h.is_deleted, 0) = 0
    ) x
    WHERE x.rn = 1;
    CREATE INDEX IX_header_book_page_map_scope_book_page
        ON #header_book_page_map (imported_by_user_id, state_fips, county_fips, book, beginning_page);

    DROP TABLE IF EXISTS #keli_additions_scope;
    CREATE TABLE #keli_additions_scope (
        norm_addition_name VARCHAR(1000) NOT NULL,
        keli_add_id VARCHAR(1000) NOT NULL
    );
    INSERT INTO #keli_additions_scope (norm_addition_name, keli_add_id)
    SELECT
        UPPER(REPLACE(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(1000)), ''))), ',', '')) AS norm_addition_name,
        MIN(CAST(k.id AS VARCHAR(1000))) AS keli_add_id
    FROM dbo.keli_additions k
    WHERE k.state_fips = @StateFips
      AND k.county_fips = @CountyFips
    GROUP BY UPPER(REPLACE(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(1000)), ''))), ',', ''));
    CREATE INDEX IX_keli_additions_scope_name
        ON #keli_additions_scope (norm_addition_name);

    DROP TABLE IF EXISTS #keli_township_scope;
    CREATE TABLE #keli_township_scope (
        norm_township VARCHAR(100) NOT NULL,
        norm_range VARCHAR(100) NOT NULL,
        keli_tr_id VARCHAR(1000) NOT NULL
    );
    INSERT INTO #keli_township_scope (norm_township, norm_range, keli_tr_id)
    SELECT
        UPPER(LTRIM(RTRIM(ISNULL(CAST(k.township AS VARCHAR(100)), '')))) AS norm_township,
        UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[range] AS VARCHAR(100)), '')))) AS norm_range,
        MIN(CAST(k.id AS VARCHAR(1000))) AS keli_tr_id
    FROM dbo.keli_township_ranges k
    WHERE ISNULL(k.active, 0) = 1
      AND k.state_fips = @StateFips
      AND k.county_fips = @CountyFips
    GROUP BY
        UPPER(LTRIM(RTRIM(ISNULL(CAST(k.township AS VARCHAR(100)), '')))),
        UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[range] AS VARCHAR(100)), ''))));
    CREATE INDEX IX_keli_township_scope_tr
        ON #keli_township_scope (norm_township, norm_range);

    DROP TABLE IF EXISTS #keli_refs_scope;
    IF @keli_refs_table IS NOT NULL
       AND @keli_ref_book_col IS NOT NULL
       AND @keli_ref_page_col IS NOT NULL
    BEGIN
        CREATE TABLE #keli_refs_scope (
            norm_ref_book VARCHAR(64) NOT NULL,
            norm_ref_page VARCHAR(64) NOT NULL,
            keli_ref_id VARCHAR(1000) NOT NULL
        );

        SET @sql = N'
            INSERT INTO #keli_refs_scope (norm_ref_book, norm_ref_page, keli_ref_id)
            SELECT
                src.norm_ref_book,
                src.norm_ref_page,
                MIN(src.keli_ref_id) AS keli_ref_id
            FROM (
                SELECT
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), '''')))), 64) AS norm_ref_book,
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_page_col) + N' AS VARCHAR(1000)), '''')))), 64) AS norm_ref_page,
                    CAST(kir.id AS VARCHAR(1000)) AS keli_ref_id
                FROM dbo.' + QUOTENAME(@keli_refs_table) + N' kir
                WHERE kir.state_fips = @sf
                  AND kir.county_fips = @cf
            ) src
            JOIN #header_book_page_map hbm
              ON hbm.book = src.norm_ref_book
             AND hbm.beginning_page = src.norm_ref_page
            GROUP BY src.norm_ref_book, src.norm_ref_page;';
        EXEC sys.sp_executesql @sql, N'@sf CHAR(2), @cf CHAR(5)', @sf=@StateFips, @cf=@CountyFips;

        CREATE INDEX IX_keli_refs_scope_book_page
            ON #keli_refs_scope (norm_ref_book, norm_ref_page);
    END;


    IF OBJECT_ID(N'dbo.gdi_instrument_types', N'U') IS NOT NULL
    BEGIN
        DECLARE @inst_type_table SYSNAME = NULL;
        IF OBJECT_ID(N'dbo.keli_instrument_types', N'U') IS NOT NULL
            SET @inst_type_table = N'keli_instrument_types';
        ELSE IF OBJECT_ID(N'dbo.keli_instrument_type', N'U') IS NOT NULL
            SET @inst_type_table = N'keli_instrument_type';

        IF @inst_type_table IS NOT NULL
        BEGIN
            SET @sql = N'
                ;WITH matched AS (
                    SELECT
                        git.id,
                        CAST(kit.id AS VARCHAR(1000)) AS keli_inst_type_id
                    FROM dbo.gdi_instrument_types git
                    JOIN dbo.' + QUOTENAME(@inst_type_table) + N' kit
                      ON UPPER(LTRIM(RTRIM(ISNULL(CAST(kit.[name] AS VARCHAR(1000)), '''')))) =
                         UPPER(LTRIM(RTRIM(ISNULL(git.col03varchar, ''''))))
                    WHERE git.imported_by_user_id = @uid
                      AND git.state_fips = @sf
                      AND git.county_fips = @cf
                      AND kit.state_fips = @sf
                      AND kit.county_fips = @cf
                      AND ISNULL(git.is_deleted, 0) = 0
                      AND LTRIM(RTRIM(ISNULL(git.col03varchar, ''''))) <> ''''
                )
                UPDATE git
                SET
                    git.instrument_type_internal_id = m.keli_inst_type_id,
                    git.instrument_type_external_id = ''''
                FROM dbo.gdi_instrument_types git
                JOIN matched m ON m.id = git.id;

                ;WITH missing AS (
                    SELECT
                        git.id
                    FROM dbo.gdi_instrument_types git
                    WHERE git.imported_by_user_id = @uid
                      AND git.state_fips = @sf
                      AND git.county_fips = @cf
                      AND ISNULL(git.is_deleted, 0) = 0
                      AND LTRIM(RTRIM(ISNULL(git.col03varchar, ''''))) <> ''''
                      AND NOT EXISTS (
                          SELECT 1
                          FROM dbo.' + QUOTENAME(@inst_type_table) + N' kit
                          WHERE UPPER(LTRIM(RTRIM(ISNULL(CAST(kit.[name] AS VARCHAR(1000)), '''')))) =
                                UPPER(LTRIM(RTRIM(ISNULL(git.col03varchar, ''''))))
                            AND kit.state_fips = @sf
                            AND kit.county_fips = @cf
                      )
                ),
                ranked AS (
                    SELECT
                        m.id,
                        DENSE_RANK() OVER (ORDER BY m.id) AS seq_id
                    FROM missing m
                )
                UPDATE git
                SET
                    git.instrument_type_internal_id = '''',
                    git.instrument_type_external_id = CAST(r.seq_id AS VARCHAR(1000))
                FROM dbo.gdi_instrument_types git
                JOIN ranked r ON r.id = git.id;

                UPDATE git
                SET
                    git.instrument_type_internal_id = '''',
                    git.instrument_type_external_id = ''''
                FROM dbo.gdi_instrument_types git
                WHERE git.imported_by_user_id = @uid
                  AND git.state_fips = @sf
                  AND git.county_fips = @cf
                  AND ISNULL(git.is_deleted, 0) = 0
                  AND LTRIM(RTRIM(ISNULL(git.col03varchar, ''''))) = '''';';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END;
    END;

    DECLARE @party_suffix_table SYSNAME = NULL;
    DECLARE @party_suffix_id_col SYSNAME = NULL;
    DECLARE @party_suffix_name_col SYSNAME = NULL;
    DECLARE @et_al_internal_id VARCHAR(1000) = '';
    DECLARE @image_table SYSNAME = NULL;
    DECLARE @image_deleted_filter NVARCHAR(80) = N'';
    DECLARE @keli_pages_table SYSNAME = NULL;

    IF OBJECT_ID(N'dbo.keli_party_suffix', N'U') IS NOT NULL
        SET @party_suffix_table = N'keli_party_suffix';
    ELSE IF OBJECT_ID(N'dbo.keli_party_suffixes', N'U') IS NOT NULL
        SET @party_suffix_table = N'keli_party_suffixes';

    IF @party_suffix_table IS NOT NULL
    BEGIN
        SELECT TOP 1 @party_suffix_id_col = c.name
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID(N'dbo.' + @party_suffix_table)
          AND c.name IN ('id', 'party_suffix_id')
        ORDER BY CASE c.name WHEN 'id' THEN 0 ELSE 1 END;

        SELECT TOP 1 @party_suffix_name_col = c.name
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID(N'dbo.' + @party_suffix_table)
          AND c.name IN ('name', 'suffix', 'party_suffix', 'description', 'col01varchar')
        ORDER BY CASE c.name WHEN 'name' THEN 0 WHEN 'suffix' THEN 1 WHEN 'party_suffix' THEN 2 WHEN 'description' THEN 3 ELSE 4 END;
    END;

    IF @party_suffix_table IS NOT NULL AND @party_suffix_id_col IS NOT NULL AND @party_suffix_name_col IS NOT NULL
    BEGIN
        SET @sql = N'
            SELECT TOP 1
                @out_et_al = LTRIM(RTRIM(ISNULL(CAST(ps.' + QUOTENAME(@party_suffix_id_col) + N' AS VARCHAR(1000)), '''')))
            FROM dbo.' + QUOTENAME(@party_suffix_table) + N' ps
            WHERE (
                    UPPER(LTRIM(RTRIM(ISNULL(CAST(ps.' + QUOTENAME(@party_suffix_name_col) + N' AS VARCHAR(300)), '''')))) IN (''ET AL'', ''ET AL.'')
                    OR UPPER(LTRIM(RTRIM(ISNULL(CAST(ps.' + QUOTENAME(@party_suffix_name_col) + N' AS VARCHAR(300)), '''')))) LIKE ''ET AL%''
                  )
              AND (
                    COL_LENGTH(N''dbo.' + @party_suffix_table + N''', ''state_fips'') IS NULL
                    OR (
                        ps.state_fips = @sf
                        AND ps.county_fips = @cf
                    )
                  )
            ORDER BY
                CASE WHEN TRY_CONVERT(INT, ps.' + QUOTENAME(@party_suffix_id_col) + N') IS NULL THEN 1 ELSE 0 END,
                TRY_CONVERT(INT, ps.' + QUOTENAME(@party_suffix_id_col) + N'),
                CAST(ps.' + QUOTENAME(@party_suffix_id_col) + N' AS VARCHAR(1000));
        ';
        EXEC sys.sp_executesql
            @sql,
            N'@out_et_al VARCHAR(1000) OUTPUT, @sf CHAR(2), @cf CHAR(5)',
            @sf = @StateFips,
            @cf = @CountyFips,
            @out_et_al = @et_al_internal_id OUTPUT;
    END;

    IF OBJECT_ID(N'dbo.gdi_parties', N'U') IS NOT NULL
    BEGIN
        ;WITH name_counts AS (
            SELECT
                n.header_file_key,
                n.col01varchar,
                SUM(CASE WHEN UPPER(LTRIM(RTRIM(ISNULL(n.col02varchar, '')))) = 'GRANTOR' THEN 1 ELSE 0 END) AS grantor_count,
                SUM(CASE WHEN UPPER(LTRIM(RTRIM(ISNULL(n.col02varchar, '')))) = 'GRANTEE' THEN 1 ELSE 0 END) AS grantee_count
            FROM dbo.gdi_parties n
            WHERE n.imported_by_user_id = @ImportedByUserId
              AND n.state_fips = @StateFips
              AND n.county_fips = @CountyFips
              AND (COL_LENGTH('dbo.gdi_parties', 'is_deleted') IS NULL OR ISNULL(n.is_deleted, 0) = 0)
            GROUP BY n.header_file_key, n.col01varchar
        )
        UPDATE h
        SET
            h.grantor_suffix_internal_id = CASE
                WHEN ISNULL(nc.grantor_count, 0) > 1 AND @et_al_internal_id <> '' THEN @et_al_internal_id
                ELSE ''
            END,
            h.grantee_suffix_internal_id = CASE
                WHEN ISNULL(nc.grantee_count, 0) > 1 AND @et_al_internal_id <> '' THEN @et_al_internal_id
                ELSE ''
            END
        FROM dbo.gdi_instruments h
        LEFT JOIN name_counts nc
          ON nc.header_file_key = h.header_file_key
         AND nc.col01varchar = h.col01varchar
        WHERE h.imported_by_user_id = @ImportedByUserId
          AND h.state_fips = @StateFips
          AND h.county_fips = @CountyFips
          AND ISNULL(h.is_deleted, 0) = 0;
    END;

    IF OBJECT_ID(N'dbo.gdi_pages', N'U') IS NOT NULL
        SET @image_table = N'gdi_pages';

    IF OBJECT_ID(N'dbo.keli_pages', N'U') IS NOT NULL
        SET @keli_pages_table = N'keli_pages';
    ELSE IF OBJECT_ID(N'dbo.keli_page', N'U') IS NOT NULL
        SET @keli_pages_table = N'keli_page';

    IF @image_table IS NOT NULL
    BEGIN
        IF COL_LENGTH(N'dbo.' + @image_table, 'is_deleted') IS NOT NULL
            SET @image_deleted_filter = N' AND ISNULL(i.is_deleted, 0) = 0 ';

        IF COL_LENGTH(N'dbo.' + @image_table, 'original_page_number') IS NULL
        BEGIN
            SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@image_table) + N' ADD original_page_number VARCHAR(1000) NULL;';
            EXEC sys.sp_executesql @sql;
        END;

        SET @sql = N'
            UPDATE i
            SET
                i.original_page_number = src.original_page_number,
                i.image_path = path_src.source_image_path
            FROM dbo.' + QUOTENAME(@image_table) + N' i
            CROSS APPLY (
                SELECT
                    LTRIM(RTRIM(ISNULL(CAST(i.col03varchar AS VARCHAR(2000)), ''''))) AS source_image_path,
                    REPLACE(
                        REPLACE(
                            LTRIM(RTRIM(ISNULL(CAST(i.col03varchar AS VARCHAR(2000)), ''''))),
                            ''/'',
                            CHAR(92)
                        ),
                        ''"'',
                        ''''
                    ) AS normalized_path
            ) path_src
            CROSS APPLY (
                SELECT
                    CASE
                        WHEN CHARINDEX(CHAR(92), path_src.normalized_path) > 0
                            THEN RIGHT(
                                path_src.normalized_path,
                                CHARINDEX(CHAR(92), REVERSE(path_src.normalized_path)) - 1
                            )
                        ELSE path_src.normalized_path
                    END AS file_name
            ) file_src
            CROSS APPLY (
                SELECT
                    LTRIM(RTRIM(
                        CASE
                            WHEN CHARINDEX(''.'', file_src.file_name) > 0
                                THEN LEFT(
                                    file_src.file_name,
                                    LEN(file_src.file_name) - CHARINDEX(''.'', REVERSE(file_src.file_name))
                                )
                            ELSE file_src.file_name
                        END
                    )) AS original_page_number
            ) src
            WHERE i.imported_by_user_id = @uid
              AND i.state_fips = @sf
              AND i.county_fips = @cf
              AND ISNULL(i.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        SET @sql = N'
            ;WITH image_counts AS (
                SELECT
                    i.header_file_key,
                    i.col01varchar,
                    COUNT(1) AS page_count
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                WHERE i.imported_by_user_id = @uid
                  AND i.state_fips = @sf
                  AND i.county_fips = @cf
                  ' + @image_deleted_filter + N'
                GROUP BY i.header_file_key, i.col01varchar
            )
            UPDATE h
            SET h.manual_page_count = CAST(ISNULL(ic.page_count, 0) AS VARCHAR(1000))
            FROM dbo.gdi_instruments h
            LEFT JOIN image_counts ic
              ON ic.header_file_key = h.header_file_key
             AND ic.col01varchar = h.col01varchar
            WHERE h.imported_by_user_id = @uid
              AND h.state_fips = @sf
              AND h.county_fips = @cf
              AND ISNULL(h.is_deleted, 0) = 0;
        ';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        -- ---------------------------------------------------------------------
        -- Image linkup:
        -- 1) If book + original_page_number matches a Keli page, use the Keli page id.
        -- 2) Otherwise, if image_path matches keli assumed_image_path, use the
        --    Keli page id.
        -- 3) Otherwise use the image instrument external id so output treats it
        --    as a new image row.
        -- 4) Images renamed by the duplicate-page tool are always forced into
        --    the new-image path even if the original image_path still matches.
        -- ---------------------------------------------------------------------
        DROP TABLE IF EXISTS #forced_new_image_scope;
        CREATE TABLE #forced_new_image_scope (
            image_id INT NOT NULL PRIMARY KEY
        );

        IF OBJECT_ID(N'dbo.gdi_page_linkup_audit', N'U') IS NOT NULL
        BEGIN
            INSERT INTO #forced_new_image_scope (image_id)
            SELECT DISTINCT i.id
            FROM dbo.gdi_pages i
            JOIN (
                SELECT
                    a.source_row_id,
                    MAX(a.id) AS latest_audit_id
                FROM dbo.gdi_page_linkup_audit a
                WHERE a.source_table = 'gdi_pages'
                  AND a.column_name = 'page_number'
                  AND a.action_key = 'update_duplicate_pages'
                  AND ISNULL(a.force_new_image, 0) = 1
                  AND a.imported_by_user_id = @ImportedByUserId
                  AND a.state_fips = @StateFips
                  AND a.county_fips = @CountyFips
                GROUP BY a.source_row_id
            ) latest
              ON latest.source_row_id = i.id
            JOIN dbo.gdi_page_linkup_audit a
              ON a.id = latest.latest_audit_id
            WHERE i.imported_by_user_id = @ImportedByUserId
              AND i.state_fips = @StateFips
              AND i.county_fips = @CountyFips
              AND ISNULL(i.is_deleted, 0) = 0
              AND LTRIM(RTRIM(ISNULL(i.page_number, ''))) = LTRIM(RTRIM(ISNULL(a.new_page_value, '')));
        END;

        DROP TABLE IF EXISTS #matched_pages;
        CREATE TABLE #matched_pages (
            image_id INT NOT NULL PRIMARY KEY,
            keli_page_id VARCHAR(1000) NOT NULL
        );

        IF @keli_pages_table IS NOT NULL
        BEGIN
            DECLARE @keli_assumed_path_expr NVARCHAR(MAX);
            DROP TABLE IF EXISTS #keli_pages_book_page_scope;
            CREATE TABLE #keli_pages_book_page_scope (
                norm_book VARCHAR(64) NOT NULL,
                norm_page VARCHAR(64) NOT NULL,
                keli_page_id VARCHAR(1000) NOT NULL
            );

            SET @sql = N'
                INSERT INTO #keli_pages_book_page_scope (norm_book, norm_page, keli_page_id)
                SELECT
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), '''')))), 64) AS norm_book,
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), '''')))), 64) AS norm_page,
                    MIN(CAST(kp.id AS VARCHAR(1000))) AS keli_page_id
                FROM dbo.' + QUOTENAME(@keli_pages_table) + N' kp
                WHERE kp.state_fips = @sf
                  AND kp.county_fips = @cf
                  AND LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), ''''))) <> ''''
                  AND LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), ''''))) <> ''''
                GROUP BY
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), '''')))), 64),
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), '''')))), 64);';
            EXEC sys.sp_executesql @sql, N'@sf CHAR(2), @cf CHAR(5)', @sf=@StateFips, @cf=@CountyFips;
            CREATE INDEX IX_keli_pages_book_page_scope
                ON #keli_pages_book_page_scope (norm_book, norm_page);

            SET @sql = N'
                INSERT INTO #matched_pages (image_id, keli_page_id)
                SELECT
                    i.id AS image_id,
                    MIN(kp.keli_page_id) AS keli_page_id
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                JOIN #keli_pages_book_page_scope kp
                 ON kp.norm_book = LEFT(UPPER(LTRIM(RTRIM(ISNULL(CAST(i.book AS VARCHAR(1000)), '''')))), 64)
                 AND kp.norm_page = LEFT(
                        UPPER(
                            LTRIM(
                                RTRIM(
                                    ISNULL(
                                        CAST(i.original_page_number AS VARCHAR(1000)),
                                        ''''
                                    )
                                )
                            )
                        ),
                        64
                     )
                LEFT JOIN #forced_new_image_scope fni
                  ON fni.image_id = i.id
                WHERE i.imported_by_user_id = @uid
                  AND i.state_fips = @sf
                  AND i.county_fips = @cf
                  AND ISNULL(i.is_deleted, 0) = 0
                  AND fni.image_id IS NULL
                  AND LTRIM(RTRIM(ISNULL(CAST(i.book AS VARCHAR(1000)), ''''))) <> ''''
                  AND LTRIM(RTRIM(ISNULL(
                        CAST(i.original_page_number AS VARCHAR(1000)),
                        ''''
                  ))) <> ''''
                GROUP BY i.id;';
            EXEC sys.sp_executesql
                @sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @uid = @ImportedByUserId,
                @sf = @StateFips,
                @cf = @CountyFips;

            DROP TABLE IF EXISTS #keli_pages_scope;
            CREATE TABLE #keli_pages_scope (
                norm_assumed_image_path VARCHAR(512) NOT NULL,
                keli_page_id VARCHAR(1000) NOT NULL
            );

            IF COL_LENGTH(N'dbo.' + @keli_pages_table, 'assumed_image_path') IS NOT NULL
                SET @keli_assumed_path_expr = N'
                    COALESCE(
                        NULLIF(
                            LOWER(LTRIM(RTRIM(ISNULL(CAST(kp.assumed_image_path AS VARCHAR(1000)), '''')))),
                            ''''
                        ),
                        CASE
                            WHEN LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), ''''))) <> ''''
                             AND LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), ''''))) <> ''''
                                THEN LOWER(
                                    LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), '''')))
                                    + ''/''
                                    + LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), '''')))
                                    + ''.tif''
                                )
                            ELSE ''''
                        END
                    )';
            ELSE
                SET @keli_assumed_path_expr = N'
                    CASE
                        WHEN LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), ''''))) <> ''''
                         AND LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), ''''))) <> ''''
                            THEN LOWER(
                                LTRIM(RTRIM(ISNULL(CAST(kp.book AS VARCHAR(1000)), '''')))
                                + ''/''
                                + LTRIM(RTRIM(ISNULL(CAST(kp.page_number AS VARCHAR(1000)), '''')))
                                + ''.tif''
                            )
                        ELSE ''''
                    END';

            SET @sql = N'
                INSERT INTO #keli_pages_scope (norm_assumed_image_path, keli_page_id)
                SELECT
                    LEFT(UPPER(LTRIM(RTRIM(ISNULL(src.assumed_image_path, '''')))), 512) AS norm_assumed_image_path,
                    MIN(CAST(kp.id AS VARCHAR(1000))) AS keli_page_id
                FROM dbo.' + QUOTENAME(@keli_pages_table) + N' kp
                CROSS APPLY (
                    SELECT ' + @keli_assumed_path_expr + N' AS assumed_image_path
                ) src
                WHERE kp.state_fips = @sf
                  AND kp.county_fips = @cf
                  AND LTRIM(RTRIM(ISNULL(src.assumed_image_path, ''''))) <> ''''
                GROUP BY LEFT(UPPER(LTRIM(RTRIM(ISNULL(src.assumed_image_path, '''')))), 512);';
            EXEC sys.sp_executesql @sql, N'@sf CHAR(2), @cf CHAR(5)', @sf=@StateFips, @cf=@CountyFips;
            CREATE INDEX IX_keli_pages_scope_assumed_path
                ON #keli_pages_scope (norm_assumed_image_path);

            SET @sql = N'
                INSERT INTO #matched_pages (image_id, keli_page_id)
                SELECT i.id AS image_id, MIN(kp.keli_page_id) AS keli_page_id
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                JOIN #keli_pages_scope kp
                  ON kp.norm_assumed_image_path = LEFT(
                        UPPER(
                            REPLACE(
                                LTRIM(RTRIM(ISNULL(CAST(i.image_path AS VARCHAR(1000)), ''''))),
                                CHAR(92),
                                ''/''
                            )
                        ),
                        512
                     )
                LEFT JOIN #forced_new_image_scope fni
                  ON fni.image_id = i.id
                LEFT JOIN #matched_pages mp_existing
                  ON mp_existing.image_id = i.id
                WHERE i.imported_by_user_id = @uid
                  AND i.state_fips = @sf
                  AND i.county_fips = @cf
                  AND ISNULL(i.is_deleted, 0) = 0
                  AND fni.image_id IS NULL
                  AND mp_existing.image_id IS NULL
                  AND ISNULL(LTRIM(RTRIM(CAST(i.image_path AS VARCHAR(1000)))), '''') <> ''''
                GROUP BY i.id;';
            EXEC sys.sp_executesql
                @sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @uid = @ImportedByUserId,
                @sf = @StateFips,
                @cf = @CountyFips;
        END;

        SET @sql = N'
            UPDATE i
            SET i.internal_id = mp.keli_page_id
            FROM dbo.' + QUOTENAME(@image_table) + N' i
            JOIN #matched_pages mp
              ON mp.image_id = i.id
            WHERE i.imported_by_user_id = @uid
              AND i.state_fips = @sf
              AND i.county_fips = @cf
              AND ISNULL(i.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        SET @sql = N'
            UPDATE i
            SET i.internal_id = COALESCE(
                NULLIF(LTRIM(RTRIM(ISNULL(CAST(i.instrument_external_id AS VARCHAR(1000)), ''''))), ''''),
                NULLIF(LTRIM(RTRIM(ISNULL(CAST(h.external_id AS VARCHAR(1000)), ''''))), ''''),
                ''''
            )
            FROM dbo.' + QUOTENAME(@image_table) + N' i
            LEFT JOIN #matched_pages mp
              ON mp.image_id = i.id
            LEFT JOIN dbo.gdi_instruments h
              ON h.imported_by_user_id = i.imported_by_user_id
             AND h.state_fips = i.state_fips
             AND h.county_fips = i.county_fips
             AND ISNULL(h.header_file_key, '''') = ISNULL(i.header_file_key, '''')
             AND ISNULL(h.col01varchar, '''') = ISNULL(i.col01varchar, '''')
             AND ISNULL(h.is_deleted, 0) = 0
            WHERE i.imported_by_user_id = @uid
              AND i.state_fips = @sf
              AND i.county_fips = @cf
              AND ISNULL(i.is_deleted, 0) = 0
              AND mp.image_id IS NULL;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        SET @sql = N'
            UPDATE i
            SET i.image_path = CASE
                WHEN mp.image_id IS NOT NULL THEN ''''
                ELSE ISNULL(LTRIM(RTRIM(CAST(i.col03varchar AS VARCHAR(2000)))), '''')
            END
            FROM dbo.' + QUOTENAME(@image_table) + N' i
            LEFT JOIN #matched_pages mp
              ON mp.image_id = i.id
            WHERE i.imported_by_user_id = @uid
              AND i.state_fips = @sf
              AND i.county_fips = @cf
              AND ISNULL(i.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;
    END;

    -- Image instrument linkup:
    -- instrument_external_id = linked header external_id
    -- instrument_internal_id = keli instrument id by image book+page_number
    IF @image_table IS NOT NULL
    BEGIN
        IF @keli_instrument_table IS NOT NULL
        BEGIN
            SET @sql = N'
                UPDATE i
                SET
                    i.instrument_internal_id = ISNULL(hm.keli_inst_id, ''''),
                    i.instrument_external_id = ISNULL(CAST(h.external_id AS VARCHAR(1000)), '''')
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                LEFT JOIN dbo.gdi_instruments h
                  ON h.imported_by_user_id = i.imported_by_user_id
                 AND h.state_fips = i.state_fips
                 AND h.county_fips = i.county_fips
                 AND ISNULL(h.header_file_key, '''') = ISNULL(i.header_file_key, '''')
                 AND ISNULL(h.col01varchar, '''') = ISNULL(i.col01varchar, '''')
                 AND ISNULL(h.is_deleted, 0) = 0
                LEFT JOIN #header_keli_inst_map hm
                  ON hm.imported_by_user_id = i.imported_by_user_id
                 AND hm.state_fips = i.state_fips
                 AND hm.county_fips = i.county_fips
                 AND hm.header_file_key = ISNULL(i.header_file_key, '''')
                 AND hm.col01varchar = ISNULL(i.col01varchar, '''')
                WHERE i.imported_by_user_id = @uid
                  AND i.state_fips = @sf
                  AND i.county_fips = @cf
                  AND ISNULL(i.is_deleted, 0) = 0;';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END
        ELSE
        BEGIN
            SET @sql = N'
                UPDATE i
                SET
                    i.instrument_internal_id = '''',
                    i.instrument_external_id = ISNULL(CAST(h.external_id AS VARCHAR(1000)), '''')
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                LEFT JOIN dbo.gdi_instruments h
                  ON h.imported_by_user_id = i.imported_by_user_id
                 AND h.state_fips = i.state_fips
                 AND h.county_fips = i.county_fips
                 AND ISNULL(h.header_file_key, '''') = ISNULL(i.header_file_key, '''')
                 AND ISNULL(h.col01varchar, '''') = ISNULL(i.col01varchar, '''')
                 AND ISNULL(h.is_deleted, 0) = 0
                WHERE i.imported_by_user_id = @uid
                  AND i.state_fips = @sf
                  AND i.county_fips = @cf
                  AND ISNULL(i.is_deleted, 0) = 0;';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END
    END;


    IF OBJECT_ID(N'dbo.gdi_additions', N'U') IS NOT NULL
    BEGIN
        SET @sql = N'
            UPDATE l
            SET l.legal_type = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM dbo.gdi_additions a
                    WHERE a.imported_by_user_id = l.imported_by_user_id
                      AND a.state_fips = l.state_fips
                      AND a.county_fips = l.county_fips
                      AND ISNULL(a.is_deleted, 0) = 0
                      AND ISNULL(a.header_file_key, '''') = ISNULL(l.header_file_key, '''')
                      AND ISNULL(a.col01varchar, '''') = ISNULL(l.col01varchar, '''')
                ) THEN ''Platted''
                WHEN EXISTS (
                    SELECT 1
                    FROM dbo.gdi_township_range t
                    WHERE t.imported_by_user_id = l.imported_by_user_id
                      AND t.state_fips = l.state_fips
                      AND t.county_fips = l.county_fips
                      AND ISNULL(t.is_deleted, 0) = 0
                      AND ISNULL(t.header_file_key, '''') = ISNULL(l.header_file_key, '''')
                      AND ISNULL(t.col01varchar, '''') = ISNULL(l.col01varchar, '''')
                ) THEN ''Unplatted''
                ELSE ''Other''
            END
            FROM dbo.' + QUOTENAME(@legal_table) + N' l
            WHERE l.imported_by_user_id = @uid
              AND l.state_fips = @sf
              AND l.county_fips = @cf
              AND ISNULL(l.is_deleted, 0) = 0;
        ';
    END
    ELSE
    BEGIN
        SET @sql = N'
            UPDATE l
            SET l.legal_type = CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM dbo.gdi_township_range t
                    WHERE t.imported_by_user_id = l.imported_by_user_id
                      AND t.state_fips = l.state_fips
                      AND t.county_fips = l.county_fips
                      AND ISNULL(t.is_deleted, 0) = 0
                      AND ISNULL(t.header_file_key, '''') = ISNULL(l.header_file_key, '''')
                      AND ISNULL(t.col01varchar, '''') = ISNULL(l.col01varchar, '''')
                ) THEN ''Unplatted''
                ELSE ''Other''
            END
            FROM dbo.' + QUOTENAME(@legal_table) + N' l
            WHERE l.imported_by_user_id = @uid
              AND l.state_fips = @sf
              AND l.county_fips = @cf
              AND ISNULL(l.is_deleted, 0) = 0;
        ';
    END;
    EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;

    IF OBJECT_ID(N'dbo.gdi_additions', N'U') IS NOT NULL
    BEGIN
        SET @sql = N'
            ;WITH matched_add AS (
                SELECT
                    a.id AS add_id,
                    kas.keli_add_id
                FROM dbo.gdi_additions a
                JOIN #keli_additions_scope kas
                  ON kas.norm_addition_name = UPPER(REPLACE(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))), '','', ''''))
                WHERE a.imported_by_user_id = @uid
                  AND a.state_fips = @sf
                  AND a.county_fips = @cf
                  AND ISNULL(a.is_deleted, 0) = 0
                  AND LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))) <> ''''
            )
            UPDATE a
            SET a.additions_internal_id = m.keli_add_id,
                a.additions_external_id = ''''
            FROM dbo.gdi_additions a
            JOIN matched_add m ON m.add_id = a.id;

            ;WITH missing_add_seed AS (
                SELECT
                    UPPER(REPLACE(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))), '','', '''')) AS norm_addition_name,
                    MIN(a.id) AS first_add_id
                FROM dbo.gdi_additions a
                WHERE a.imported_by_user_id = @uid
                  AND a.state_fips = @sf
                  AND a.county_fips = @cf
                  AND ISNULL(a.is_deleted, 0) = 0
                  AND LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))) <> ''''
                  AND NOT EXISTS (
                      SELECT 1
                      FROM #keli_additions_scope kas
                      WHERE kas.norm_addition_name =
                            UPPER(REPLACE(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))), '','', ''''))
                  )
                GROUP BY UPPER(REPLACE(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))), '','', ''''))
            ),
            missing_add AS (
                SELECT
                    mas.norm_addition_name,
                    DENSE_RANK() OVER (ORDER BY mas.first_add_id, mas.norm_addition_name) AS seq_id
                FROM missing_add_seed mas
            )
            UPDATE a
            SET a.additions_internal_id = '''',
                a.additions_external_id = CAST(m.seq_id AS VARCHAR(1000))
            FROM dbo.gdi_additions a
            JOIN missing_add m
              ON m.norm_addition_name = UPPER(REPLACE(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))), '','', ''''))
            WHERE a.imported_by_user_id = @uid
              AND a.state_fips = @sf
              AND a.county_fips = @cf
              AND ISNULL(a.is_deleted, 0) = 0
              AND LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))) <> ''''
              AND NOT EXISTS (
                  SELECT 1
                  FROM #keli_additions_scope kas
                  WHERE kas.norm_addition_name =
                        UPPER(REPLACE(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))), '','', ''''))
              );

            UPDATE a
            SET a.additions_internal_id = '''',
                a.additions_external_id = ''''
            FROM dbo.gdi_additions a
            WHERE a.imported_by_user_id = @uid
              AND a.state_fips = @sf
              AND a.county_fips = @cf
              AND ISNULL(a.is_deleted, 0) = 0
              AND LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))) = '''';';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END;

    IF OBJECT_ID(N'dbo.gdi_township_range', N'U') IS NOT NULL
    BEGIN
        SET @sql = N'
            ;WITH matched_tr AS (
                SELECT
                    t.id AS tr_id,
                    kts.keli_tr_id
                FROM dbo.gdi_township_range t
                JOIN #keli_township_scope kts
                  ON kts.norm_township = UPPER(LTRIM(RTRIM(ISNULL(t.col03varchar, ''''))))
                 AND kts.norm_range = UPPER(LTRIM(RTRIM(ISNULL(t.col04varchar, ''''))))
                WHERE t.imported_by_user_id = @uid
                  AND t.state_fips = @sf
                  AND t.county_fips = @cf
                  AND ISNULL(t.is_deleted, 0) = 0
            )
            UPDATE t
            SET t.township_range_internal_id = m.keli_tr_id,
                t.township_range_external_id = ''''
            FROM dbo.gdi_township_range t
            JOIN matched_tr m ON m.tr_id = t.id;

            ;WITH missing_tr AS (
                SELECT
                    t.id,
                    DENSE_RANK() OVER (ORDER BY t.id) AS seq_id
                FROM dbo.gdi_township_range t
                WHERE t.imported_by_user_id = @uid
                  AND t.state_fips = @sf
                  AND t.county_fips = @cf
                  AND ISNULL(t.is_deleted, 0) = 0
                  AND LTRIM(RTRIM(ISNULL(t.col03varchar, ''''))) <> ''''
                  AND LTRIM(RTRIM(ISNULL(t.col04varchar, ''''))) <> ''''
                  AND NOT EXISTS (
                      SELECT 1
                      FROM #keli_township_scope kts
                      WHERE kts.norm_township = UPPER(LTRIM(RTRIM(ISNULL(t.col03varchar, ''''))))
                        AND kts.norm_range = UPPER(LTRIM(RTRIM(ISNULL(t.col04varchar, ''''))))
                  )
            )
            UPDATE t
            SET t.township_range_internal_id = '''',
                t.township_range_external_id = CAST(m.seq_id AS VARCHAR(1000))
            FROM dbo.gdi_township_range t
            JOIN missing_tr m ON m.id = t.id;

            UPDATE t
            SET t.township_range_internal_id = '''',
                t.township_range_external_id = ''''
            FROM dbo.gdi_township_range t
            WHERE t.imported_by_user_id = @uid
              AND t.state_fips = @sf
              AND t.county_fips = @cf
              AND ISNULL(t.is_deleted, 0) = 0
              AND (
                  LTRIM(RTRIM(ISNULL(t.col03varchar, ''''))) = ''''
                  OR LTRIM(RTRIM(ISNULL(t.col04varchar, ''''))) = ''''
              );';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END;

    -- Names linkup:
    -- instrument_external_id = linked header id
    -- instrument_internal_id = keli instrument id by linked header book+beginning_page
    -- line = row_number by header ordered by names row id
    -- internal_id = keli party id when matched by instrument + party_type + line
    IF @names_table IS NOT NULL
    BEGIN
        IF @keli_instrument_table IS NOT NULL
        BEGIN
            SET @sql = N'
                ;WITH nsrc AS (
                    SELECT
                        n.id,
                        hm.header_id,
                        ROW_NUMBER() OVER (
                            PARTITION BY hm.header_id
                            ORDER BY n.id
                        ) AS new_line,
                        hm.keli_inst_id
                    FROM dbo.' + QUOTENAME(@names_table) + N' n
                    JOIN #header_keli_inst_map hm
                      ON hm.imported_by_user_id = n.imported_by_user_id
                     AND hm.state_fips = n.state_fips
                     AND hm.county_fips = n.county_fips
                     AND hm.header_file_key = ISNULL(n.header_file_key, '''')
                     AND hm.col01varchar = ISNULL(n.col01varchar, '''')
                    WHERE n.imported_by_user_id = @uid
                      AND n.state_fips = @sf
                      AND n.county_fips = @cf
                      AND ISNULL(n.is_deleted, 0) = 0
                )
                UPDATE n
                SET
                    n.instrument_external_id = CAST(s.header_id AS VARCHAR(1000)),
                    n.instrument_internal_id = ISNULL(s.keli_inst_id, ''''),
                    n.line = CAST(s.new_line AS VARCHAR(1000))
                FROM dbo.' + QUOTENAME(@names_table) + N' n
                JOIN nsrc s ON s.id = n.id;
            ';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END
        ELSE
        BEGIN
            SET @sql = N'
                ;WITH nsrc AS (
                    SELECT
                        n.id,
                        hm.header_id,
                        ROW_NUMBER() OVER (
                            PARTITION BY hm.header_id
                            ORDER BY n.id
                        ) AS new_line
                    FROM dbo.' + QUOTENAME(@names_table) + N' n
                    JOIN #header_keli_inst_map hm
                      ON hm.imported_by_user_id = n.imported_by_user_id
                     AND hm.state_fips = n.state_fips
                     AND hm.county_fips = n.county_fips
                     AND hm.header_file_key = ISNULL(n.header_file_key, '''')
                     AND hm.col01varchar = ISNULL(n.col01varchar, '''')
                    WHERE n.imported_by_user_id = @uid
                      AND n.state_fips = @sf
                      AND n.county_fips = @cf
                      AND ISNULL(n.is_deleted, 0) = 0
                )
                UPDATE n
                SET
                    n.instrument_external_id = CAST(s.header_id AS VARCHAR(1000)),
                    n.instrument_internal_id = '''',
                    n.line = CAST(s.new_line AS VARCHAR(1000))
                FROM dbo.' + QUOTENAME(@names_table) + N' n
                JOIN nsrc s ON s.id = n.id;
            ';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END;

        IF @keli_parties_table IS NOT NULL
        BEGIN
            SET @sql = N'
                ;WITH n_rank AS (
                    SELECT
                        n.id,
                        ISNULL(LTRIM(RTRIM(n.instrument_internal_id)), '''') AS inst_id,
                        LOWER(LTRIM(RTRIM(ISNULL(n.party_type, '''')))) AS party_type,
                        ROW_NUMBER() OVER (
                            PARTITION BY ISNULL(LTRIM(RTRIM(n.instrument_internal_id)), ''''), LOWER(LTRIM(RTRIM(ISNULL(n.party_type, ''''))))
                            ORDER BY TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(n.line)), '''')), n.id
                        ) AS line_rank
                    FROM dbo.' + QUOTENAME(@names_table) + N' n
                    WHERE n.imported_by_user_id = @uid
                      AND n.state_fips = @sf
                      AND n.county_fips = @cf
                      AND ISNULL(n.is_deleted, 0) = 0
                      AND ISNULL(LTRIM(RTRIM(n.instrument_internal_id)), '''') <> ''''
                ),
                scoped_inst AS (
                    SELECT DISTINCT
                        nr.inst_id,
                        nr.party_type
                    FROM n_rank nr
                ),
                kp_rank AS (
                    SELECT
                        CAST(kp.id AS VARCHAR(1000)) AS kp_id,
                        CAST(kp.instrument AS VARCHAR(1000)) AS inst_id,
                        LOWER(LTRIM(RTRIM(ISNULL(CAST(kp.party_type AS VARCHAR(1000)), '''')))) AS party_type,
                        ROW_NUMBER() OVER (
                            PARTITION BY CAST(kp.instrument AS VARCHAR(1000)), LOWER(LTRIM(RTRIM(ISNULL(CAST(kp.party_type AS VARCHAR(1000)), ''''))))
                            ORDER BY kp.id
                        ) AS line_rank
                    FROM dbo.' + QUOTENAME(@keli_parties_table) + N' kp
                    JOIN scoped_inst si
                      ON si.inst_id = CAST(kp.instrument AS VARCHAR(1000))
                     AND si.party_type = LOWER(LTRIM(RTRIM(ISNULL(CAST(kp.party_type AS VARCHAR(1000)), ''''))))
                    WHERE kp.state_fips = @sf
                      AND kp.county_fips = @cf
                )
                UPDATE n
                SET n.internal_id = ISNULL(kp.kp_id, '''')
                FROM dbo.' + QUOTENAME(@names_table) + N' n
                LEFT JOIN n_rank nr ON nr.id = n.id
                LEFT JOIN kp_rank kp
                  ON kp.inst_id = nr.inst_id
                 AND kp.party_type = nr.party_type
                 AND kp.line_rank = nr.line_rank
                WHERE n.imported_by_user_id = @uid
                  AND n.state_fips = @sf
                  AND n.county_fips = @cf
                  AND ISNULL(n.is_deleted, 0) = 0;
            ';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END
        ELSE
        BEGIN
            SET @sql = N'
                UPDATE n
                SET n.internal_id = ''''
                FROM dbo.' + QUOTENAME(@names_table) + N' n
                WHERE n.imported_by_user_id = @uid
                  AND n.state_fips = @sf
                  AND n.county_fips = @cf
                  AND ISNULL(n.is_deleted, 0) = 0;';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
        END;
    END;


    -- Legal linkup:
    -- instrument_external_id = linked header id
    -- instrument_internal_id = keli instrument id by linked header book+beginning_page
    -- line = row_number by header ordered by legal row id
    -- internal_id = keli legal id when matched by instrument + line
    IF @keli_instrument_table IS NOT NULL
    BEGIN
        SET @sql = N'
            ;WITH lsrc AS (
                SELECT
                    l.id,
                    hm.header_id,
                    ROW_NUMBER() OVER (
                        PARTITION BY hm.header_id
                        ORDER BY l.id
                    ) AS new_line,
                    hm.keli_inst_id
                FROM dbo.' + QUOTENAME(@legal_table) + N' l
                JOIN #header_keli_inst_map hm
                  ON hm.imported_by_user_id = l.imported_by_user_id
                 AND hm.state_fips = l.state_fips
                 AND hm.county_fips = l.county_fips
                 AND hm.header_file_key = ISNULL(l.header_file_key, '''')
                 AND hm.col01varchar = ISNULL(l.col01varchar, '''')
                WHERE l.imported_by_user_id = @uid
                  AND l.state_fips = @sf
                  AND l.county_fips = @cf
                  AND ISNULL(l.is_deleted, 0) = 0
            )
            UPDATE l
            SET
                l.instrument_external_id = CAST(s.header_id AS VARCHAR(1000)),
                l.instrument_internal_id = ISNULL(s.keli_inst_id, ''''),
                l.line = CAST(s.new_line AS VARCHAR(1000))
            FROM dbo.' + QUOTENAME(@legal_table) + N' l
            JOIN lsrc s ON s.id = l.id;
        ';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END
    ELSE
    BEGIN
        SET @sql = N'
            ;WITH lsrc AS (
                SELECT
                    l.id,
                    hm.header_id,
                    ROW_NUMBER() OVER (
                        PARTITION BY hm.header_id
                        ORDER BY l.id
                    ) AS new_line
                FROM dbo.' + QUOTENAME(@legal_table) + N' l
                JOIN #header_keli_inst_map hm
                  ON hm.imported_by_user_id = l.imported_by_user_id
                 AND hm.state_fips = l.state_fips
                 AND hm.county_fips = l.county_fips
                 AND hm.header_file_key = ISNULL(l.header_file_key, '''')
                 AND hm.col01varchar = ISNULL(l.col01varchar, '''')
                WHERE l.imported_by_user_id = @uid
                  AND l.state_fips = @sf
                  AND l.county_fips = @cf
                  AND ISNULL(l.is_deleted, 0) = 0
            )
            UPDATE l
            SET
                l.instrument_external_id = CAST(s.header_id AS VARCHAR(1000)),
                l.instrument_internal_id = '''',
                l.line = CAST(s.new_line AS VARCHAR(1000))
            FROM dbo.' + QUOTENAME(@legal_table) + N' l
            JOIN lsrc s ON s.id = l.id;
        ';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END;

    IF @keli_legals_table IS NOT NULL
    BEGIN
        SET @sql = N'
            ;WITH l_rank AS (
                SELECT
                    l.id,
                    ISNULL(LTRIM(RTRIM(l.instrument_internal_id)), '''') AS inst_id,
                    ROW_NUMBER() OVER (
                        PARTITION BY ISNULL(LTRIM(RTRIM(l.instrument_internal_id)), '''')
                        ORDER BY TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(l.line)), '''')), l.id
                    ) AS line_rank
                FROM dbo.' + QUOTENAME(@legal_table) + N' l
                WHERE l.imported_by_user_id = @uid
                  AND l.state_fips = @sf
                  AND l.county_fips = @cf
                  AND ISNULL(l.is_deleted, 0) = 0
                  AND ISNULL(LTRIM(RTRIM(l.instrument_internal_id)), '''') <> ''''
            ),
            scoped_inst AS (
                SELECT DISTINCT lr.inst_id
                FROM l_rank lr
            ),
                kl_rank AS (
                    SELECT
                        CAST(kl.id AS VARCHAR(1000)) AS kl_id,
                        CAST(kl.instrument AS VARCHAR(1000)) AS inst_id,
                        ROW_NUMBER() OVER (
                        PARTITION BY CAST(kl.instrument AS VARCHAR(1000))
                        ORDER BY kl.id
                    ) AS line_rank
                    FROM dbo.' + QUOTENAME(@keli_legals_table) + N' kl
                    JOIN scoped_inst si
                      ON si.inst_id = CAST(kl.instrument AS VARCHAR(1000))
                    WHERE kl.state_fips = @sf
                      AND kl.county_fips = @cf
                )
            UPDATE l
            SET l.internal_id = ISNULL(kl.kl_id, '''')
            FROM dbo.' + QUOTENAME(@legal_table) + N' l
            LEFT JOIN l_rank lr ON lr.id = l.id
            LEFT JOIN kl_rank kl
              ON kl.inst_id = lr.inst_id
             AND kl.line_rank = lr.line_rank
            WHERE l.imported_by_user_id = @uid
              AND l.state_fips = @sf
              AND l.county_fips = @cf
              AND ISNULL(l.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END
    ELSE
    BEGIN
        SET @sql = N'
            UPDATE l
            SET l.internal_id = ''''
            FROM dbo.' + QUOTENAME(@legal_table) + N' l
            WHERE l.imported_by_user_id = @uid
              AND l.state_fips = @sf
              AND l.county_fips = @cf
              AND ISNULL(l.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @uid=@ImportedByUserId, @sf=@StateFips, @cf=@CountyFips;
    END;

    IF @reference_table IS NOT NULL
    BEGIN
        -- Temporary backfill for in-flight jobs:
        -- seed missing in-scope existing Keli references into gdi_instrument_references(s)
        -- so they can be linked/edited in DQ and exported consistently.
        IF @keli_refs_table IS NOT NULL
           AND @keli_ref_book_col IS NOT NULL
           AND @keli_ref_page_col IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'fn') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'file_key') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'header_file_key') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'keyOriginalValue') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'OriginalValue') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'col01varchar') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'col02varchar') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'col03varchar') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'book') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'page_number') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'internal_id') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'instrument_external_id') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'referenced_instrument_internal_id') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'referenced_instrument_external_id') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'referenced_book') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'referenced_page') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'imported_by_user_id') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'import_batch_id') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'state_fips') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'county_fips') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'is_deleted') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_instrument_references', 'imported_at') IS NOT NULL
        BEGIN
            DROP TABLE IF EXISTS #keli_ref_seed;
            CREATE TABLE #keli_ref_seed (
                keli_ref_id VARCHAR(1000) NOT NULL,
                header_file_key NVARCHAR(260) NOT NULL,
                col01varchar VARCHAR(1000) NOT NULL,
                file_key NVARCHAR(260) NOT NULL,
                fn VARCHAR(1000) NOT NULL,
                import_batch_id UNIQUEIDENTIFIER NOT NULL,
                raw_referenced_book VARCHAR(1000) NOT NULL,
                raw_referenced_page VARCHAR(1000) NOT NULL,
                norm_referenced_book VARCHAR(64) NOT NULL,
                norm_referenced_page VARCHAR(64) NOT NULL,
                referenced_header_external_id VARCHAR(1000) NOT NULL
            );

            IF @keli_refs_table = N'keli_instrument_references'
               AND @keli_ref_book_col = N'referenced_book'
               AND @keli_ref_page_col = N'referenced_page'
            BEGIN
                ;WITH keli_src AS (
                    SELECT
                        ISNULL(LTRIM(RTRIM(CAST(kir.id AS VARCHAR(1000)))), '') AS keli_ref_id,
                        ISNULL(LTRIM(RTRIM(CAST(kir.referenced_book AS VARCHAR(1000)))), '') AS raw_referenced_book,
                        ISNULL(LTRIM(RTRIM(CAST(kir.referenced_page AS VARCHAR(1000)))), '') AS raw_referenced_page
                    FROM dbo.keli_instrument_references kir
                    WHERE kir.state_fips = @StateFips
                      AND kir.county_fips = @CountyFips
                ),
                norm AS (
                    SELECT
                        ks.keli_ref_id,
                        ks.raw_referenced_book,
                        ks.raw_referenced_page,
                        LEFT(UPPER(ks.raw_referenced_book), 64) AS norm_referenced_book,
                        LEFT(UPPER(ks.raw_referenced_page), 64) AS norm_referenced_page
                    FROM keli_src ks
                ),
                matched AS (
                    SELECT
                        n.keli_ref_id,
                        n.raw_referenced_book,
                        n.raw_referenced_page,
                        LEFT(n.norm_referenced_book, 64) AS norm_referenced_book,
                        LEFT(n.norm_referenced_page, 64) AS norm_referenced_page,
                        ISNULL(hm_exact.target_header_external_id, '') AS target_header_external_id,
                        hctx.header_file_key,
                        hctx.col01varchar,
                        hctx.file_key,
                        hctx.fn,
                        hctx.import_batch_id,
                        ROW_NUMBER() OVER (
                            PARTITION BY n.keli_ref_id
                            ORDER BY hctx.id
                        ) AS rn
                    FROM norm n
                    OUTER APPLY (
                        SELECT TOP 1
                            hm.target_header_id,
                            hm.target_header_external_id
                        FROM #header_book_page_map hm
                        WHERE hm.book = LEFT(n.norm_referenced_book, 64)
                          AND hm.beginning_page = LEFT(n.norm_referenced_page, 64)
                        ORDER BY hm.target_header_id
                    ) hm_exact
                    OUTER APPLY (
                        SELECT TOP 1
                            h.id,
                            h.header_file_key,
                            h.col01varchar,
                            h.file_key,
                            h.fn,
                            h.import_batch_id
                        FROM dbo.gdi_instruments h
                        WHERE h.imported_by_user_id = @ImportedByUserId
                          AND h.state_fips = @StateFips
                          AND h.county_fips = @CountyFips
                          AND ISNULL(h.is_deleted, 0) = 0
                          AND (
                                (hm_exact.target_header_id IS NOT NULL AND CAST(h.id AS VARCHAR(1000)) = hm_exact.target_header_id)
                                OR hm_exact.target_header_id IS NULL
                              )
                        ORDER BY
                            CASE WHEN hm_exact.target_header_id IS NOT NULL AND CAST(h.id AS VARCHAR(1000)) = hm_exact.target_header_id THEN 0 ELSE 1 END,
                            h.id
                    ) hctx
                    WHERE hm_exact.target_header_id IS NOT NULL
                )
                INSERT INTO #keli_ref_seed (
                    keli_ref_id, header_file_key, col01varchar, file_key, fn, import_batch_id,
                    raw_referenced_book, raw_referenced_page, norm_referenced_book, norm_referenced_page, referenced_header_external_id
                )
                SELECT
                    m.keli_ref_id,
                    ISNULL(m.header_file_key, ''),
                    ISNULL(m.col01varchar, ''),
                    ISNULL(m.file_key, ''),
                    ISNULL(m.fn, ''),
                    m.import_batch_id,
                    ISNULL(m.raw_referenced_book, ''),
                    ISNULL(m.raw_referenced_page, ''),
                    ISNULL(m.norm_referenced_book, ''),
                    ISNULL(m.norm_referenced_page, ''),
                    ISNULL(m.target_header_external_id, '')
                FROM matched m
                WHERE m.rn = 1;
            END;

            IF @reference_table = N'gdi_instrument_references'
            BEGIN
                INSERT INTO dbo.gdi_instrument_references (
                    fn, file_key, header_file_key, keyOriginalValue, OriginalValue,
                    col01varchar, col02varchar, col03varchar, book, page_number,
                    internal_id, instrument_external_id, referenced_instrument_internal_id, referenced_instrument_external_id,
                    referenced_book, referenced_page,
                    imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
                )
                SELECT
                    REPLACE(REPLACE(ISNULL(s.fn, ''), 'HEADER', 'Reference'), 'header', 'reference'),
                    CASE WHEN LOWER(ISNULL(s.file_key, '')) LIKE 'header%' THEN STUFF(s.file_key, 1, 6, 'references') ELSE 'references_' + ISNULL(s.file_key, '') END,
                    ISNULL(s.header_file_key, ''),
                    ISNULL(s.col01varchar, '') + '|' + ISNULL(s.raw_referenced_book, '') + '|' + ISNULL(s.raw_referenced_page, ''),
                    ISNULL(s.col01varchar, '') + '|' + ISNULL(s.raw_referenced_book, '') + '|' + ISNULL(s.raw_referenced_page, ''),
                    ISNULL(s.col01varchar, ''), ISNULL(s.raw_referenced_book, ''), ISNULL(s.raw_referenced_page, ''),
                    ISNULL(s.raw_referenced_book, ''), ISNULL(s.raw_referenced_page, ''),
                    ISNULL(s.keli_ref_id, ''), '', '', ISNULL(s.referenced_header_external_id, ''),
                    ISNULL(s.raw_referenced_book, ''), ISNULL(s.raw_referenced_page, ''),
                    @ImportedByUserId, s.import_batch_id, @StateFips, @CountyFips, 0, SYSDATETIMEOFFSET()
                FROM #keli_ref_seed s
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.gdi_instrument_references r
                    WHERE r.imported_by_user_id = @ImportedByUserId
                      AND r.state_fips = @StateFips
                      AND r.county_fips = @CountyFips
                      AND ISNULL(r.is_deleted, 0) = 0
                      AND ISNULL(LTRIM(RTRIM(r.internal_id)), '') = ISNULL(s.keli_ref_id, '')
                );
            END;
        END;
        -- Stage 0:
        -- Normalize and align referenced_book/referenced_page.
        -- If col02varchar is inside the scoped header book range, source values
        -- come from reference row book/page_number; otherwise col02/col03.
        -- Book: 6 digits + optional one alpha suffix.
        -- Page: 4 digits + optional one alpha suffix.
        SET @sql = N'
            UPDATE r
            SET
                r.referenced_book =
                    CASE
                        WHEN LTRIM(RTRIM(ISNULL(src.source_book, ''''))) = '''' THEN ''''
                        ELSE
                            CASE
                                WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(src.source_book, '''')))), 1) LIKE ''[A-Z]''
                                     AND LEN(LTRIM(RTRIM(ISNULL(src.source_book, '''')))) > 1
                                     AND TRY_CONVERT(BIGINT, LEFT(UPPER(LTRIM(RTRIM(ISNULL(src.source_book, '''')))), LEN(LTRIM(RTRIM(ISNULL(src.source_book, '''')))) - 1)) IS NOT NULL
                                    THEN RIGHT(''000000'' + LEFT(UPPER(LTRIM(RTRIM(ISNULL(src.source_book, '''')))), LEN(LTRIM(RTRIM(ISNULL(src.source_book, '''')))) - 1), 6)
                                         + RIGHT(UPPER(LTRIM(RTRIM(ISNULL(src.source_book, '''')))), 1)
                                WHEN TRY_CONVERT(BIGINT, UPPER(LTRIM(RTRIM(ISNULL(src.source_book, ''''))))) IS NOT NULL
                                    THEN RIGHT(''000000'' + UPPER(LTRIM(RTRIM(ISNULL(src.source_book, '''')))), 6)
                                ELSE UPPER(LTRIM(RTRIM(ISNULL(src.source_book, ''''))))
                            END
                    END,
                r.referenced_page =
                    CASE
                        WHEN LTRIM(RTRIM(ISNULL(src.source_page, ''''))) = '''' THEN ''''
                        ELSE
                            CASE
                                WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(src.source_page, '''')))), 1) LIKE ''[A-Z]''
                                     AND LEN(LTRIM(RTRIM(ISNULL(src.source_page, '''')))) > 1
                                     AND TRY_CONVERT(BIGINT, LEFT(UPPER(LTRIM(RTRIM(ISNULL(src.source_page, '''')))), LEN(LTRIM(RTRIM(ISNULL(src.source_page, '''')))) - 1)) IS NOT NULL
                                    THEN RIGHT(''0000'' + LEFT(UPPER(LTRIM(RTRIM(ISNULL(src.source_page, '''')))), LEN(LTRIM(RTRIM(ISNULL(src.source_page, '''')))) - 1), 4)
                                         + RIGHT(UPPER(LTRIM(RTRIM(ISNULL(src.source_page, '''')))), 1)
                                WHEN TRY_CONVERT(BIGINT, UPPER(LTRIM(RTRIM(ISNULL(src.source_page, ''''))))) IS NOT NULL
                                    THEN RIGHT(''0000'' + UPPER(LTRIM(RTRIM(ISNULL(src.source_page, '''')))), 4)
                                ELSE UPPER(LTRIM(RTRIM(ISNULL(src.source_page, ''''))))
                            END
                    END
            FROM dbo.' + QUOTENAME(@reference_table) + N' r
            CROSS APPLY (
                SELECT
                    CASE
                        WHEN @book_min IS NOT NULL
                         AND @book_max IS NOT NULL
                         AND TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(r.col02varchar, ''''))), '''')) BETWEEN @book_min AND @book_max
                            THEN ISNULL(r.book, '''')
                        ELSE ISNULL(r.col02varchar, '''')
                    END AS source_book,
                    CASE
                        WHEN @book_min IS NOT NULL
                         AND @book_max IS NOT NULL
                         AND TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(r.col02varchar, ''''))), '''')) BETWEEN @book_min AND @book_max
                            THEN ISNULL(r.page_number, '''')
                        ELSE ISNULL(r.col03varchar, '''')
                    END AS source_page
            ) src
            WHERE r.imported_by_user_id = @uid
              AND r.state_fips = @sf
              AND r.county_fips = @cf
              AND ISNULL(r.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @book_min INT, @book_max INT',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips,
            @book_min = @job_book_min,
            @book_max = @job_book_max;

        SET @sql = N'
            UPDATE r
            SET r.instrument_external_id = ISNULL(CAST(h.external_id AS VARCHAR(1000)), '''')
            FROM dbo.' + QUOTENAME(@reference_table) + N' r
            LEFT JOIN dbo.gdi_instruments h
              ON h.imported_by_user_id = r.imported_by_user_id
             AND h.state_fips = r.state_fips
             AND h.county_fips = r.county_fips
             AND ISNULL(h.header_file_key, '''') = ISNULL(r.header_file_key, '''')
             AND ISNULL(h.col01varchar, '''') = ISNULL(r.col01varchar, '''')
             AND ISNULL(h.is_deleted, 0) = 0
            WHERE r.imported_by_user_id = @uid
              AND r.state_fips = @sf
              AND r.county_fips = @cf
              AND ISNULL(r.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        SET @sql = N'
            UPDATE r
            SET
                r.referenced_instrument_internal_id = '''',
                r.referenced_instrument_external_id = ''''
            FROM dbo.' + QUOTENAME(@reference_table) + N' r
            WHERE r.imported_by_user_id = @uid
              AND r.state_fips = @sf
              AND r.county_fips = @cf
              AND ISNULL(r.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        -- internal_id = keli reference id when referenced_book/referenced_page
        -- match an existing keli instrument reference row.
        IF @keli_refs_table IS NOT NULL
           AND @keli_ref_book_col IS NOT NULL
           AND @keli_ref_page_col IS NOT NULL
        BEGIN
            SET @sql = N'
                ;WITH matched_ref AS (
                    SELECT
                        r.id AS ref_id,
                        krs.keli_ref_id
                    FROM dbo.' + QUOTENAME(@reference_table) + N' r
                    JOIN #keli_refs_scope krs
                      ON krs.norm_ref_book = LEFT(UPPER(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))), 64)
                     AND krs.norm_ref_page = LEFT(UPPER(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))), 64)
                    WHERE r.imported_by_user_id = @uid
                      AND r.state_fips = @sf
                      AND r.county_fips = @cf
                      AND ISNULL(r.is_deleted, 0) = 0
                )
                UPDATE r
                SET r.internal_id = ISNULL(mr.keli_ref_id, '''')
                FROM dbo.' + QUOTENAME(@reference_table) + N' r
                LEFT JOIN matched_ref mr ON mr.ref_id = r.id
                WHERE r.imported_by_user_id = @uid
                  AND r.state_fips = @sf
                  AND r.county_fips = @cf
                  AND ISNULL(r.is_deleted, 0) = 0;';
            EXEC sys.sp_executesql
                @sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @uid = @ImportedByUserId,
                @sf = @StateFips,
                @cf = @CountyFips;
        END
        ELSE
        BEGIN
            SET @sql = N'
                UPDATE r
                SET r.internal_id = ''''
                FROM dbo.' + QUOTENAME(@reference_table) + N' r
                WHERE r.imported_by_user_id = @uid
                  AND r.state_fips = @sf
                  AND r.county_fips = @cf
                  AND ISNULL(r.is_deleted, 0) = 0;';
            EXEC sys.sp_executesql
                @sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @uid = @ImportedByUserId,
                @sf = @StateFips,
                @cf = @CountyFips;
        END;

        -- Enforce exclusivity:
        -- if internal_id exists, this is an existing keli reference and must not
        -- carry an instrument_external_id.
        SET @sql = N'
            UPDATE r
            SET r.instrument_external_id = ''''
            FROM dbo.' + QUOTENAME(@reference_table) + N' r
            WHERE r.imported_by_user_id = @uid
              AND r.state_fips = @sf
              AND r.county_fips = @cf
              AND ISNULL(r.is_deleted, 0) = 0
              AND ISNULL(LTRIM(RTRIM(r.internal_id)), '''') <> '''';';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        -- If no matching reference row exists, but a keli instrument exists for
        -- referenced_book/referenced_page, set referenced_instrument_internal_id.
        IF @keli_instrument_table IS NOT NULL
        BEGIN
            SET @sql = N'
                UPDATE r
                SET r.referenced_instrument_internal_id = kin.keli_inst_id
                FROM dbo.' + QUOTENAME(@reference_table) + N' r
                JOIN #keli_instrument_num_scope kin
                  ON kin.num_book = TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(r.referenced_book)), ''''))
                 AND kin.num_page = TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(r.referenced_page)), ''''))
                WHERE r.imported_by_user_id = @uid
                  AND r.state_fips = @sf
                  AND r.county_fips = @cf
                  AND ISNULL(r.is_deleted, 0) = 0
                  AND ISNULL(LTRIM(RTRIM(r.internal_id)), '''') = ''''
                  AND ISNULL(LTRIM(RTRIM(r.referenced_instrument_internal_id)), '''') = '''';';
            EXEC sys.sp_executesql
                @sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @uid = @ImportedByUserId,
                @sf = @StateFips,
                @cf = @CountyFips;
        END;

        -- referenced_instrument_external_id = header external_id for matching
        -- referenced_book/referenced_page when found in this job scope.
        SET @sql = N'
            UPDATE r
            SET r.referenced_instrument_external_id =
                CASE
                    WHEN ISNULL(LTRIM(RTRIM(r.referenced_instrument_internal_id)), '''') <> ''''
                        THEN ''''
                    ELSE ISNULL(hm.target_header_external_id, '''')
                END
            FROM dbo.' + QUOTENAME(@reference_table) + N' r
            LEFT JOIN #header_book_page_map hm
              ON hm.imported_by_user_id = r.imported_by_user_id
             AND hm.state_fips = r.state_fips
             AND hm.county_fips = r.county_fips
             AND hm.book = LEFT(UPPER(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))), 64)
             AND hm.beginning_page = LEFT(UPPER(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))), 64)
            WHERE r.imported_by_user_id = @uid
              AND r.state_fips = @sf
              AND r.county_fips = @cf
              AND ISNULL(r.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;
    END;

END;
