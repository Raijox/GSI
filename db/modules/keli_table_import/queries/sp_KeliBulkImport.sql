/* ============================================================================
   File: sp_KeliBulkImport.sql
   Procedure: dbo.sp_KeliBulkImport
   Purpose:
   - Bulk load one Keli CSV file at a time into a dynamically managed dbo.keli_*
     table whose name is derived from the source file name.
   Why this file exists:
   - Keli imports do not arrive as one rigid schema. Each CSV file can map to a
     different destination table and can gain columns over time, so the import
     procedure has to discover headers at runtime, create or widen target tables,
     and then load rows without requiring a new migration for every feed change.
   What this procedure does:
   - Validates import mode, scope, file path, and supplied header metadata.
   - Normalizes the CSV file name into a stable dbo.keli_* table name.
   - Parses header JSON into an ordered column contract and deduplicates header
     names so duplicate or blank source columns still import safely.
   - Creates the target Keli table on first use and adds newly discovered
     columns on later imports while preserving prior data.
   - In drop mode, clears the scoped rows for this user/county from the target
     Keli table before loading the current file.
   - In append mode, upserts by source id when an id column exists; otherwise it
     appends raw rows and records an audit warning that no stable key existed.
   - Uses BULK INSERT into a temp staging table so file parsing happens inside
     SQL Server using the same path visibility rules as production imports.
   - Writes detailed audit rows for success, mismatches, duplicate ids, blank ids,
     schema drift, and hard failures.
   What this procedure does not do:
   - It does not own the Keli-to-eData reference handoff. That follow-up is kept
     in dbo.sp_SeedScopedKeliReferences so it can run once after the full folder
     import finishes instead of once per file.
   Maintenance notes:
   - Keep file-to-table name normalization stable so re-imports land in the same
     target table.
   - Keep audit payloads descriptive; they are the main debugging surface for
     import operators when a county feed changes shape.
   ============================================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_KeliBulkImport
    @ImportFileName VARCHAR(1000),
    @DropOrAppend VARCHAR(1),
    @ImportedByUserId INT = NULL,
    @StateFips CHAR(2) = NULL,
    @CountyFips CHAR(5) = NULL,
    @ImportBatchId UNIQUEIDENTIFIER = NULL,
    @HeaderJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @mode CHAR(1) = UPPER(LTRIM(RTRIM(ISNULL(@DropOrAppend, ''))));
    DECLARE @state_fips CHAR(2) = RIGHT('00' + LTRIM(RTRIM(ISNULL(@StateFips, ''))), 2);
    DECLARE @county_fips CHAR(5) = RIGHT('00000' + LTRIM(RTRIM(ISNULL(@CountyFips, ''))), 5);
    DECLARE @batch_id UNIQUEIDENTIFIER = ISNULL(@ImportBatchId, NEWID());

    IF @mode NOT IN ('D', 'A')
        THROW 60000, 'DropOrAppend must be D or A.', 1;

    IF ISNULL(@ImportedByUserId, 0) <= 0
       OR LEN(LTRIM(RTRIM(ISNULL(@StateFips, '')))) <> 2
       OR LEN(LTRIM(RTRIM(ISNULL(@CountyFips, '')))) <> 5
       OR LTRIM(RTRIM(ISNULL(@ImportFileName, ''))) = ''
    BEGIN
        THROW 60001, 'Import requires file path, ImportedByUserId, StateFips, and CountyFips.', 1;
    END;

    IF ISNULL(LTRIM(RTRIM(@HeaderJson)), '') = ''
        THROW 60002, 'HeaderJson is required and must contain the CSV header values.', 1;

    IF OBJECT_ID(N'dbo.keli_audit', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.keli_audit (
            id BIGINT NOT NULL IDENTITY PRIMARY KEY,
            audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_keli_audit_time DEFAULT SYSDATETIMEOFFSET(),
            severity VARCHAR(20) NOT NULL,
            event_type VARCHAR(100) NOT NULL,
            message NVARCHAR(2000) NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NULL,
            imported_by_user_id INT NULL,
            state_fips CHAR(2) NULL,
            county_fips CHAR(5) NULL,
            import_file_name VARCHAR(1000) NULL,
            details NVARCHAR(MAX) NULL
        );
        CREATE INDEX IX_keli_audit_scope_time ON dbo.keli_audit(imported_by_user_id, state_fips, county_fips, audit_time DESC);
        CREATE INDEX IX_keli_audit_batch_time ON dbo.keli_audit(import_batch_id, audit_time DESC);
    END;

    DECLARE @normalized_path NVARCHAR(1000) = REPLACE(REPLACE(LTRIM(RTRIM(@ImportFileName)), '/', '\'), '"', '');
    DECLARE @file_name NVARCHAR(260) = @normalized_path;
    DECLARE @slash_pos INT = CHARINDEX('\', REVERSE(@normalized_path));
    IF @slash_pos > 0
        SET @file_name = RIGHT(@normalized_path, @slash_pos - 1);
    DECLARE @dot_pos INT = CHARINDEX('.', REVERSE(@file_name));
    DECLARE @file_stem NVARCHAR(260) = CASE WHEN @dot_pos > 0 THEN LEFT(@file_name, LEN(@file_name) - @dot_pos) ELSE @file_name END;

    DECLARE @table_name SYSNAME = LOWER(ISNULL(@file_stem, 'keli_data'));
    SET @table_name = REPLACE(@table_name, ' ', '_');
    SET @table_name = REPLACE(@table_name, '-', '_');
    SET @table_name = REPLACE(@table_name, '.', '_');
    SET @table_name = REPLACE(@table_name, '(', '_');
    SET @table_name = REPLACE(@table_name, ')', '_');
    SET @table_name = REPLACE(@table_name, '[', '_');
    SET @table_name = REPLACE(@table_name, ']', '_');
    SET @table_name = REPLACE(@table_name, '/', '_');
    SET @table_name = REPLACE(@table_name, '\', '_');
    SET @table_name = REPLACE(@table_name, ':', '_');
    SET @table_name = REPLACE(@table_name, ';', '_');
    SET @table_name = REPLACE(@table_name, ',', '_');
    SET @table_name = REPLACE(@table_name, '"', '_');
    SET @table_name = REPLACE(@table_name, '''', '_');
    WHILE CHARINDEX('__', @table_name) > 0
        SET @table_name = REPLACE(@table_name, '__', '_');
    SET @table_name = LTRIM(RTRIM(@table_name));
    IF LEFT(@table_name, 1) = '_'
        SET @table_name = STUFF(@table_name, 1, 1, '');
    IF RIGHT(@table_name, 1) = '_'
        SET @table_name = LEFT(@table_name, LEN(@table_name) - 1);
    IF @table_name = '' SET @table_name = 'data';
    IF @table_name LIKE '[0-9]%' SET @table_name = 't_' + @table_name;
    IF LEN(@table_name) > 110 SET @table_name = LEFT(@table_name, 110);
    SET @table_name = 'keli_' + @table_name;

    DROP TABLE IF EXISTS #keli_headers_raw;
    SELECT
        CAST([key] AS INT) + 1 AS ordinal,
        LTRIM(RTRIM(CAST(value AS NVARCHAR(512)))) AS raw_name
    INTO #keli_headers_raw
    FROM OPENJSON(@HeaderJson)
    WHERE [type] IN (1, 2, 3);

    IF NOT EXISTS (SELECT 1 FROM #keli_headers_raw)
        THROW 60003, 'HeaderJson did not provide any usable columns.', 1;

    DROP TABLE IF EXISTS #keli_headers;
    ;WITH base AS (
        SELECT
            hr.ordinal,
            CASE
                WHEN ISNULL(hr.raw_name, '') = '' THEN CONCAT('column_', hr.ordinal)
                ELSE REPLACE(REPLACE(REPLACE(hr.raw_name, CHAR(13), ''), CHAR(10), ''), CHAR(9), ' ')
            END AS base_name
        FROM #keli_headers_raw hr
    ),
    dedup AS (
        SELECT
            b.ordinal,
            b.base_name,
            ROW_NUMBER() OVER (PARTITION BY LOWER(b.base_name) ORDER BY b.ordinal) AS rn
        FROM base b
    )
    SELECT
        d.ordinal,
        CASE
            WHEN d.rn = 1 THEN LEFT(d.base_name, 128)
            ELSE LEFT(
                    d.base_name,
                    CASE
                        WHEN 128 - LEN(CONCAT('_', d.rn)) > 1 THEN 128 - LEN(CONCAT('_', d.rn))
                        ELSE 1
                    END
                ) + CONCAT('_', d.rn)
        END AS column_name
    INTO #keli_headers
    FROM dedup d;

    UPDATE #keli_headers
    SET column_name = CASE
        WHEN LOWER(column_name) IN ('imported_by_user_id', 'import_batch_id', 'state_fips', 'county_fips', 'imported_at')
            THEN LEFT(column_name, 123) + '_file'
        ELSE column_name
    END;

    DECLARE @is_keli_pages_table BIT = CASE WHEN @table_name IN ('keli_pages', 'keli_page') THEN 1 ELSE 0 END;
    DECLARE @has_book_column BIT = CASE
        WHEN EXISTS (SELECT 1 FROM #keli_headers WHERE LOWER(column_name) = 'book')
            THEN 1
        ELSE 0
    END;
    DECLARE @has_page_number_column BIT = CASE
        WHEN EXISTS (SELECT 1 FROM #keli_headers WHERE LOWER(column_name) = 'page_number')
            THEN 1
        ELSE 0
    END;
    DECLARE @manage_assumed_image_path BIT = CASE
        WHEN @is_keli_pages_table = 1 AND @has_book_column = 1 AND @has_page_number_column = 1
            THEN 1
        ELSE 0
    END;

    DECLARE @column_count INT = (SELECT COUNT(1) FROM #keli_headers);

    DECLARE @col_defs NVARCHAR(MAX) = (
        SELECT STRING_AGG(QUOTENAME(column_name) + ' NVARCHAR(MAX) NULL', ',') WITHIN GROUP (ORDER BY ordinal)
        FROM #keli_headers
    );
    DECLARE @page_number_ordinal INT = (
        SELECT TOP 1 ordinal
        FROM #keli_headers
        WHERE LOWER(column_name) = 'page_number'
        ORDER BY ordinal
    );
    DECLARE @create_col_defs NVARCHAR(MAX) = @col_defs;
    IF @manage_assumed_image_path = 1 AND @page_number_ordinal IS NOT NULL
    BEGIN
        SELECT @create_col_defs = STRING_AGG(src.col_def, ',') WITHIN GROUP (ORDER BY src.sort_ordinal)
        FROM (
            SELECT
                CAST(h.ordinal * 10 AS INT) AS sort_ordinal,
                QUOTENAME(h.column_name) + ' NVARCHAR(MAX) NULL' AS col_def
            FROM #keli_headers h
            UNION ALL
            SELECT
                CAST(@page_number_ordinal * 10 + 1 AS INT) AS sort_ordinal,
                '[assumed_image_path] VARCHAR(1000) NULL' AS col_def
        ) src;
    END;
    DECLARE @target_cols NVARCHAR(MAX) = (
        SELECT STRING_AGG(QUOTENAME(column_name), ',') WITHIN GROUP (ORDER BY ordinal)
        FROM #keli_headers
    );
    DECLARE @stage_defs NVARCHAR(MAX) = (
        SELECT STRING_AGG(QUOTENAME(CONCAT('c', ordinal)) + ' NVARCHAR(MAX) NULL', ',') WITHIN GROUP (ORDER BY ordinal)
        FROM #keli_headers
    );
    DECLARE @stage_select NVARCHAR(MAX) = (
        SELECT STRING_AGG('ISNULL(s.' + QUOTENAME(CONCAT('c', ordinal)) + ', '''')', ',') WITHIN GROUP (ORDER BY ordinal)
        FROM #keli_headers
    );
    DECLARE @stage_select_named NVARCHAR(MAX) = (
        SELECT STRING_AGG(
            'ISNULL(s.' + QUOTENAME(CONCAT('c', ordinal)) + ', '''') AS ' + QUOTENAME(column_name),
            ','
        ) WITHIN GROUP (ORDER BY ordinal)
        FROM #keli_headers
    );
    DECLARE @id_col_name SYSNAME = (
        SELECT TOP 1 column_name
        FROM #keli_headers
        WHERE LOWER(column_name) = 'id'
        ORDER BY ordinal
    );
    DECLARE @merge_update_set NVARCHAR(MAX) = (
        SELECT STRING_AGG('t.' + QUOTENAME(column_name) + ' = src.' + QUOTENAME(column_name), ',')
        FROM #keli_headers
        WHERE LOWER(column_name) <> 'id'
    );
    DECLARE @is_upsert_mode BIT = CASE WHEN @mode = 'A' AND @id_col_name IS NOT NULL THEN 1 ELSE 0 END;
    DECLARE @append_without_id BIT = CASE WHEN @mode = 'A' AND @id_col_name IS NULL THEN 1 ELSE 0 END;

    DECLARE @q_target NVARCHAR(300) = N'dbo.' + QUOTENAME(@table_name);
    DECLARE @sql NVARCHAR(MAX);

    SET @sql = N'
IF OBJECT_ID(''' + @q_target + ''',''U'') IS NULL
BEGIN
    CREATE TABLE ' + @q_target + ' (
        ' + @create_col_defs + ',
        imported_by_user_id INT NOT NULL,
        import_batch_id UNIQUEIDENTIFIER NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        imported_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_' + @table_name + '_imported_at DEFAULT SYSDATETIMEOFFSET()
    );
END;
';
    EXEC sys.sp_executesql @sql;

    DECLARE @column_name SYSNAME;
    DECLARE add_col_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT column_name FROM #keli_headers ORDER BY ordinal;
    OPEN add_col_cursor;
    FETCH NEXT FROM add_col_cursor INTO @column_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF COL_LENGTH('dbo.' + @table_name, @column_name) IS NULL
        BEGIN
            SET @sql = N'ALTER TABLE ' + @q_target + N' ADD ' + QUOTENAME(@column_name) + N' NVARCHAR(MAX) NULL;';
            EXEC sys.sp_executesql @sql;
            INSERT INTO dbo.keli_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'warn',
                'keli_table_column_added',
                N'Added missing column to existing Keli target table.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(N'{"tableName":"', @table_name, N'","columnName":"', REPLACE(@column_name, '"', '\"'), N'"}')
            );
        END;
        FETCH NEXT FROM add_col_cursor INTO @column_name;
    END;
    CLOSE add_col_cursor;
    DEALLOCATE add_col_cursor;

    IF @manage_assumed_image_path = 1
       AND COL_LENGTH('dbo.' + @table_name, 'assumed_image_path') IS NULL
    BEGIN
        SET @sql = N'ALTER TABLE ' + @q_target + N' ADD [assumed_image_path] VARCHAR(1000) NULL;';
        EXEC sys.sp_executesql @sql;
    END;

    IF @mode = 'D'
    BEGIN
        SET @sql = N'
            DELETE FROM ' + @q_target + N'
            WHERE imported_by_user_id = @uid
              AND state_fips = @sf
              AND county_fips = @cf;';
        EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @ImportedByUserId, @state_fips, @county_fips;
    END;

    DECLARE @stage_row_count INT = 0;
    DECLARE @inserted_row_count INT = 0;
    DECLARE @updated_row_count INT = 0;
    DECLARE @duplicate_key_row_count INT = 0;
    DECLARE @blank_key_row_count INT = 0;
    SET @sql = N'
        DROP TABLE IF EXISTS #keli_stage;
        CREATE TABLE #keli_stage (' + @stage_defs + N');

        BULK INSERT #keli_stage
        FROM ' + QUOTENAME(REPLACE(@ImportFileName, '''', ''''''), '''') + N'
        WITH (
            FIRSTROW = 2,
            FORMAT = ''CSV'',
            FIELDQUOTE = ''"'',
            FIELDTERMINATOR = '','',
            ROWTERMINATOR = ''0x0a'',
            KEEPNULLS,
            TABLOCK
        );

        SELECT @out_stage = COUNT(1) FROM #keli_stage;
    ';

    IF @is_upsert_mode = 1
    BEGIN
        SET @sql = @sql + N'
        DECLARE @merge_actions TABLE (action NVARCHAR(10) NOT NULL);
        DECLARE @inserted_unkeyed INT = 0;
        DROP TABLE IF EXISTS #keli_source_rows;
        SELECT ' + @stage_select_named + N'
        INTO #keli_source_rows
        FROM #keli_stage s;

        DROP TABLE IF EXISTS #keli_keyed_ranked;
        ;WITH keyed_ranked AS (
            SELECT
                src.*,
                ROW_NUMBER() OVER (PARTITION BY src.' + QUOTENAME(@id_col_name) + N' ORDER BY (SELECT NULL)) AS rn
            FROM #keli_source_rows src
            WHERE ISNULL(LTRIM(RTRIM(src.' + QUOTENAME(@id_col_name) + N')), '''') <> ''''
        )
        SELECT *
        INTO #keli_keyed_ranked
        FROM keyed_ranked;

        SELECT @out_dup = COUNT(1) FROM #keli_keyed_ranked WHERE rn > 1;

        SELECT @out_blank = COUNT(1)
        FROM #keli_source_rows
        WHERE ISNULL(LTRIM(RTRIM(' + QUOTENAME(@id_col_name) + N')), '''') = '''';

        DROP TABLE IF EXISTS #keli_merge_source;
        SELECT *
        INTO #keli_merge_source
        FROM #keli_keyed_ranked
        WHERE rn = 1;

        ;MERGE ' + @q_target + N' AS t
        USING #keli_merge_source AS src
            ON t.' + QUOTENAME(@id_col_name) + N' = src.' + QUOTENAME(@id_col_name) + N'
           AND t.imported_by_user_id = @uid
           AND t.state_fips = @sf
           AND t.county_fips = @cf
        WHEN MATCHED THEN
            UPDATE SET
                ' + CASE
                        WHEN ISNULL(@merge_update_set, '') = ''
                            THEN N''
                        ELSE @merge_update_set + N','
                    END + N'
                t.import_batch_id = @batch,
                t.imported_at = SYSDATETIMEOFFSET()
        WHEN NOT MATCHED THEN
            INSERT (
                ' + @target_cols + N',
                imported_by_user_id, import_batch_id, state_fips, county_fips, imported_at
            )
            VALUES (
                ' + REPLACE(@target_cols, '[', 'src.[') + N',
                @uid, @batch, @sf, @cf, SYSDATETIMEOFFSET()
            )
        OUTPUT $action INTO @merge_actions(action);

        INSERT INTO ' + @q_target + N' (
            ' + @target_cols + N',
            imported_by_user_id, import_batch_id, state_fips, county_fips, imported_at
        )
        SELECT
            ' + REPLACE(@target_cols, '[', 'src.[') + N',
            @uid, @batch, @sf, @cf, SYSDATETIMEOFFSET()
        FROM #keli_source_rows src
        WHERE ISNULL(LTRIM(RTRIM(src.' + QUOTENAME(@id_col_name) + N')), '''') = '''';

        SET @inserted_unkeyed = @@ROWCOUNT;

        SELECT
            @out_inserted = ISNULL(SUM(CASE WHEN action = ''INSERT'' THEN 1 ELSE 0 END), 0) + ISNULL(@inserted_unkeyed, 0),
            @out_updated = ISNULL(SUM(CASE WHEN action = ''UPDATE'' THEN 1 ELSE 0 END), 0)
        FROM @merge_actions;
        ';
    END
    ELSE
    BEGIN
        SET @sql = @sql + N'
        INSERT INTO ' + @q_target + N' (
            ' + @target_cols + N',
            imported_by_user_id, import_batch_id, state_fips, county_fips, imported_at
        )
        SELECT
            ' + @stage_select + N',
            @uid, @batch, @sf, @cf, SYSDATETIMEOFFSET()
        FROM #keli_stage s;

        SELECT
            @out_inserted = @@ROWCOUNT,
            @out_updated = 0,
            @out_dup = 0,
            @out_blank = 0;
        ';
    END;

    BEGIN TRY
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @batch UNIQUEIDENTIFIER, @out_stage INT OUTPUT, @out_inserted INT OUTPUT, @out_updated INT OUTPUT, @out_dup INT OUTPUT, @out_blank INT OUTPUT',
            @ImportedByUserId, @state_fips, @county_fips, @batch_id, @stage_row_count OUTPUT, @inserted_row_count OUTPUT, @updated_row_count OUTPUT, @duplicate_key_row_count OUTPUT, @blank_key_row_count OUTPUT;
    END TRY
    BEGIN CATCH
        DECLARE @err_num INT = ERROR_NUMBER();
        DECLARE @err_line INT = ERROR_LINE();
        DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        BEGIN TRY
            IF OBJECT_ID(N'dbo.keli_audit', N'U') IS NULL
            BEGIN
                CREATE TABLE dbo.keli_audit (
                    id BIGINT NOT NULL IDENTITY PRIMARY KEY,
                    audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_keli_audit_time DEFAULT SYSDATETIMEOFFSET(),
                    severity VARCHAR(20) NOT NULL,
                    event_type VARCHAR(100) NOT NULL,
                    message NVARCHAR(2000) NOT NULL,
                    import_batch_id UNIQUEIDENTIFIER NULL,
                    imported_by_user_id INT NULL,
                    state_fips CHAR(2) NULL,
                    county_fips CHAR(5) NULL,
                    import_file_name VARCHAR(1000) NULL,
                    details NVARCHAR(MAX) NULL
                );
                CREATE INDEX IX_keli_audit_scope_time ON dbo.keli_audit(imported_by_user_id, state_fips, county_fips, audit_time DESC);
                CREATE INDEX IX_keli_audit_batch_time ON dbo.keli_audit(import_batch_id, audit_time DESC);
            END;

            INSERT INTO dbo.keli_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'error',
                'keli_file_import_failed',
                N'Bulk import failed for Keli CSV file.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(
                    N'{"tableName":"', @table_name,
                    N'","errorNumber":', @err_num,
                    N',"errorLine":', @err_line,
                    N',"errorMessage":"', REPLACE(ISNULL(@err_msg, ''), '"', '\"'), N'"}'
                )
            );
        END TRY
        BEGIN CATCH
            -- Do not mask original import failure if audit write also fails.
        END CATCH;

        THROW;
    END CATCH;

    IF @manage_assumed_image_path = 1
    BEGIN
        SET @sql = N'
            UPDATE t
            SET t.assumed_image_path = CASE
                WHEN LTRIM(RTRIM(ISNULL(CAST(t.book AS VARCHAR(1000)), ''''))) <> ''''
                 AND LTRIM(RTRIM(ISNULL(CAST(t.page_number AS VARCHAR(1000)), ''''))) <> ''''
                    THEN LOWER(
                        LTRIM(RTRIM(ISNULL(CAST(t.book AS VARCHAR(1000)), '''')))
                        + ''/''
                        + LTRIM(RTRIM(ISNULL(CAST(t.page_number AS VARCHAR(1000)), '''')))
                        + ''.tif''
                    )
                ELSE ''''
            END
            FROM ' + @q_target + N' t
            WHERE t.imported_by_user_id = @uid
              AND t.state_fips = @sf
              AND t.county_fips = @cf
              AND t.import_batch_id = @batch;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @batch UNIQUEIDENTIFIER',
            @uid = @ImportedByUserId,
            @sf = @state_fips,
            @cf = @county_fips,
            @batch = @batch_id;
    END;

    IF @append_without_id = 1
    BEGIN
        INSERT INTO dbo.keli_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
        )
        VALUES (
            'warn',
            'keli_upsert_key_missing',
            N'Append mode requested upsert, but file is missing "id" column. Rows were appended.',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            CONCAT(N'{"tableName":"', @table_name, N'","requiredKey":"id"}')
        );
    END;

    IF @is_upsert_mode = 1 AND ISNULL(@duplicate_key_row_count, 0) > 0
    BEGIN
        INSERT INTO dbo.keli_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
        )
        VALUES (
            'warn',
            'keli_upsert_duplicate_id_rows',
            N'Duplicate id rows were found in source file. First row per id was used for upsert.',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            CONCAT(
                N'{"tableName":"', @table_name,
                N'","duplicateRowCount":', CAST(@duplicate_key_row_count AS NVARCHAR(40)),
                N',"keyColumn":"id"}'
            )
        );
    END;

    IF @is_upsert_mode = 1 AND ISNULL(@blank_key_row_count, 0) > 0
    BEGIN
        INSERT INTO dbo.keli_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
        )
        VALUES (
            'warn',
            'keli_upsert_blank_id_rows',
            N'Rows with blank id were appended (not upserted).',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            CONCAT(
                N'{"tableName":"', @table_name,
                N'","blankIdRowCount":', CAST(@blank_key_row_count AS NVARCHAR(40)),
                N',"keyColumn":"id"}'
            )
        );
    END;

    DECLARE @processed_row_count INT = CASE WHEN @is_upsert_mode = 1 THEN ISNULL(@inserted_row_count, 0) + ISNULL(@updated_row_count, 0) ELSE ISNULL(@inserted_row_count, 0) END;
    DECLARE @delta INT = ISNULL(@stage_row_count, 0) - ISNULL(@processed_row_count, 0);
    INSERT INTO dbo.keli_audit (
        severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
    )
    VALUES (
        CASE WHEN ISNULL(@delta, 0) = 0 THEN 'info' ELSE 'warn' END,
        CASE WHEN @is_upsert_mode = 1 THEN 'keli_file_upserted' ELSE 'keli_file_imported' END,
        CASE
            WHEN @is_upsert_mode = 1 AND ISNULL(@delta, 0) = 0 THEN N'Keli CSV file upserted successfully using id key.'
            WHEN @is_upsert_mode = 1 THEN N'Keli CSV upsert completed with row count mismatch.'
            WHEN ISNULL(@delta, 0) = 0 THEN N'Keli CSV file imported successfully.'
            ELSE N'Keli CSV imported with row count mismatch between staged and inserted rows.'
        END,
        @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
        CONCAT(
            N'{"tableName":"', @table_name,
            N'","fileName":"', REPLACE(ISNULL(@file_name, ''), '"', '\"'),
            N'","headerColumnCount":', CAST(ISNULL(@column_count, 0) AS NVARCHAR(40)),
            N',"stageRowCount":', CAST(ISNULL(@stage_row_count, 0) AS NVARCHAR(40)),
            N',"insertedRowCount":', CAST(ISNULL(@inserted_row_count, 0) AS NVARCHAR(40)),
            N',"updatedRowCount":', CAST(ISNULL(@updated_row_count, 0) AS NVARCHAR(40)),
            N',"processedRowCount":', CAST(ISNULL(@processed_row_count, 0) AS NVARCHAR(40)),
            N',"upsertMode":', CASE WHEN @is_upsert_mode = 1 THEN N'true' ELSE N'false' END,
            N',"delta":', CAST(ISNULL(@delta, 0) AS NVARCHAR(40)), N'}'
        )
    );
END;
