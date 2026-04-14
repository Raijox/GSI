/* ============================================================================
   Procedure: dbo.sp_EdataTableSetup
   Purpose:
   - Normalize imported eData row values after import/split.
   - Ensure supporting indexes exist.
   - Seed default legal rows where needed.
   - Force nullable text fields to empty strings for consistent UI behavior.
   ============================================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_EdataTableSetup
    @ImportedByUserId INT,
    @StateFips CHAR(2),
    @CountyFips CHAR(5)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- -------------------------------------------------------------------------
    -- Section 1: Input validation and scope normalization
    -- -------------------------------------------------------------------------
    IF @ImportedByUserId IS NULL OR @ImportedByUserId <= 0
        THROW 50001, 'ImportedByUserId is required.', 1;
    IF @StateFips IS NULL OR LEN(LTRIM(RTRIM(@StateFips))) <> 2
        THROW 50002, 'StateFips must be 2 characters.', 1;
    IF @CountyFips IS NULL OR LEN(LTRIM(RTRIM(@CountyFips))) <> 5
        THROW 50003, 'CountyFips must be 5 characters.', 1;

    SET @StateFips = RIGHT('00' + LTRIM(RTRIM(@StateFips)), 2);
    SET @CountyFips = RIGHT('00000' + LTRIM(RTRIM(@CountyFips)), 5);

    IF OBJECT_ID(N'dbo.GenericDataImport', N'U') IS NULL
        THROW 50004, 'GenericDataImport table does not exist.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.GenericDataImport g
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @StateFips
          AND g.county_fips = @CountyFips
    )
        RETURN;

    -- -------------------------------------------------------------------------
    -- Section 2: Normalize base imported values (GenericDataImport)
    -- -------------------------------------------------------------------------
	    UPDATE g
	    SET g.fn = REPLACE(REPLACE(REPLACE(ISNULL(g.fn, ''), 'Images', 'Image'), 'Legals', 'Legal'), 'Names', 'Name')
	    FROM dbo.GenericDataImport g
	    WHERE g.imported_by_user_id = @ImportedByUserId
	      AND g.state_fips = @StateFips
	      AND g.county_fips = @CountyFips
	      AND (
	            ISNULL(g.fn, '') LIKE '%Images%'
	         OR ISNULL(g.fn, '') LIKE '%Legals%'
	         OR ISNULL(g.fn, '') LIKE '%Names%'
	      );

    UPDATE g
    SET g.col03varchar = REPLACE(
            ISNULL(g.col03varchar, ''),
            SUBSTRING(ISNULL(g.col03varchar, ''), CHARINDEX('_', ISNULL(g.col03varchar, '')), CHARINDEX('.', ISNULL(g.col03varchar, '')) - CHARINDEX('_', ISNULL(g.col03varchar, ''))),
            ''
        )
    FROM dbo.GenericDataImport g
    WHERE g.imported_by_user_id = @ImportedByUserId
      AND g.state_fips = @StateFips
      AND g.county_fips = @CountyFips
      AND LOWER(ISNULL(g.fn, '')) LIKE '%image%'
      AND CHARINDEX('_', ISNULL(g.col03varchar, '')) > 0
      AND CHARINDEX('.', ISNULL(g.col03varchar, '')) > CHARINDEX('_', ISNULL(g.col03varchar, ''));

    -- -------------------------------------------------------------------------
    -- Section 3: Apply the same normalization to all split gdi_* tables
    -- -------------------------------------------------------------------------
    DECLARE @fix_tbl SYSNAME;
    DECLARE @fix_sql NVARCHAR(MAX);
    DECLARE @sql NVARCHAR(MAX);

    DECLARE fix_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name
        FROM sys.tables t
        WHERE t.name LIKE 'gdi[_]%'
          AND EXISTS (
              SELECT 1
              FROM sys.columns c
              WHERE c.object_id = t.object_id
                AND c.name = 'fn'
          );

    OPEN fix_cur;
    FETCH NEXT FROM fix_cur INTO @fix_tbl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
	        SET @fix_sql = N'
	            UPDATE t
	            SET t.fn = REPLACE(REPLACE(REPLACE(ISNULL(t.fn, ''''), ''Images'', ''Image''), ''Legals'', ''Legal''), ''Names'', ''Name'')
	            FROM dbo.' + QUOTENAME(@fix_tbl) + N' t
	            WHERE t.imported_by_user_id = @uid
	              AND t.state_fips = @sf
	              AND t.county_fips = @cf
	              AND (
	                    ISNULL(t.fn, '''') LIKE ''%Images%''
	                 OR ISNULL(t.fn, '''') LIKE ''%Legals%''
	                 OR ISNULL(t.fn, '''') LIKE ''%Names%''
	              );';
        EXEC sys.sp_executesql
            @fix_sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;

        IF COL_LENGTH(N'dbo.' + @fix_tbl, 'col03varchar') IS NOT NULL
        BEGIN
            SET @fix_sql = N'
                UPDATE t
                SET t.col03varchar = REPLACE(
                        ISNULL(t.col03varchar, ''''),
                        SUBSTRING(ISNULL(t.col03varchar, ''''), CHARINDEX(''_'', ISNULL(t.col03varchar, '''')), CHARINDEX(''.'', ISNULL(t.col03varchar, '''')) - CHARINDEX(''_'', ISNULL(t.col03varchar, ''''))),
                        ''''
                    )
                FROM dbo.' + QUOTENAME(@fix_tbl) + N' t
                WHERE t.imported_by_user_id = @uid
                  AND t.state_fips = @sf
                  AND t.county_fips = @cf
                  AND LOWER(ISNULL(t.fn, '''')) LIKE ''%image%''
                  AND CHARINDEX(''_'', ISNULL(t.col03varchar, '''')) > 0
                  AND CHARINDEX(''.'', ISNULL(t.col03varchar, '''')) > CHARINDEX(''_'', ISNULL(t.col03varchar, ''''));';
            EXEC sys.sp_executesql
                @fix_sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @uid = @ImportedByUserId,
                @sf = @StateFips,
                @cf = @CountyFips;
        END;

        FETCH NEXT FROM fix_cur INTO @fix_tbl;
    END
    CLOSE fix_cur;
    DEALLOCATE fix_cur;

    -- -------------------------------------------------------------------------
    -- Section 4: Normalize referenced_book/referenced_page from source cols
    -- Source selection rule:
    -- - If col02varchar numeric value is within the scoped header book range,
    --   use reference row book/page_number as source.
    -- - Otherwise use col02varchar/col03varchar as source.
    -- Rules:
    -- - referenced_book: 6 digits + optional one alpha suffix.
    -- - referenced_page: 4 digits + optional one alpha suffix.
    -- Examples:
    --   0000600  -> 000600
    --   000600A  -> 000600A
    --   000700   -> 0700
    --   000700A  -> 0700A
    -- -------------------------------------------------------------------------
    DECLARE @gdi_reference_table SYSNAME = NULL;
    DECLARE @gdi_ref_book_col SYSNAME = NULL;
    DECLARE @gdi_ref_page_col SYSNAME = NULL;
    DECLARE @gdi_ref_id_col SYSNAME = NULL;
    DECLARE @gdi_ref_insert_cols NVARCHAR(MAX) = N'';
    DECLARE @gdi_ref_select_cols NVARCHAR(MAX) = N'';
    DECLARE @job_book_min INT = NULL;
    DECLARE @job_book_max INT = NULL;
    DECLARE @scope_import_batch_id UNIQUEIDENTIFIER = NULL;

    SELECT
        @job_book_min = MIN(
            TRY_CONVERT(
                INT,
                NULLIF(
                    CASE
                        WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), 1) LIKE '[A-Z]'
                             AND LEN(LTRIM(RTRIM(ISNULL(h.book, '')))) > 1
                            THEN LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), LEN(LTRIM(RTRIM(ISNULL(h.book, '')))) - 1)
                        ELSE UPPER(LTRIM(RTRIM(ISNULL(h.book, ''))))
                    END,
                    ''
                )
            )
        ),
        @job_book_max = MAX(
            TRY_CONVERT(
                INT,
                NULLIF(
                    CASE
                        WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), 1) LIKE '[A-Z]'
                             AND LEN(LTRIM(RTRIM(ISNULL(h.book, '')))) > 1
                            THEN LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '')))), LEN(LTRIM(RTRIM(ISNULL(h.book, '')))) - 1)
                        ELSE UPPER(LTRIM(RTRIM(ISNULL(h.book, ''))))
                    END,
                    ''
                )
            )
        ),
        @scope_import_batch_id = MAX(h.import_batch_id)
    FROM dbo.gdi_instruments h
    WHERE h.imported_by_user_id = @ImportedByUserId
      AND h.state_fips = @StateFips
      AND h.county_fips = @CountyFips
      AND ISNULL(h.is_deleted, 0) = 0;

    IF @scope_import_batch_id IS NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = g.import_batch_id
        FROM dbo.GenericDataImport g
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @StateFips
          AND g.county_fips = @CountyFips
          AND g.import_batch_id IS NOT NULL
        ORDER BY g.ID DESC;
    END;
    IF @scope_import_batch_id IS NULL
        SET @scope_import_batch_id = NEWID();

    -- Retire unresolved additions/township-range DQ rows from prior batches so
    -- the current import does not inherit stale queue state.
    IF OBJECT_ID(N'dbo.corrections_additions_dq', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.corrections_additions_dq', 'import_batch_id') IS NOT NULL
    BEGIN
        UPDATE c
        SET c.is_fixed = 1,
            c.fixed_note = 'superseded_by_new_import_batch',
            c.updated_at = SYSDATETIMEOFFSET()
        FROM dbo.corrections_additions_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '') <> CAST(@scope_import_batch_id AS VARCHAR(36));
    END;

    IF OBJECT_ID(N'dbo.corrections_township_range_dq', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.corrections_township_range_dq', 'import_batch_id') IS NOT NULL
    BEGIN
        UPDATE c
        SET c.is_fixed = 1,
            c.fixed_note = 'superseded_by_new_import_batch',
            c.updated_at = SYSDATETIMEOFFSET()
        FROM dbo.corrections_township_range_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '') <> CAST(@scope_import_batch_id AS VARCHAR(36));
    END;

    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
        SET @gdi_reference_table = N'gdi_instrument_references';

    IF @gdi_reference_table IS NOT NULL
    BEGIN
        IF COL_LENGTH(N'dbo.' + @gdi_reference_table, 'referenced_book') IS NOT NULL
            SET @gdi_ref_book_col = N'referenced_book';

        IF COL_LENGTH(N'dbo.' + @gdi_reference_table, 'referenced_page') IS NOT NULL
            SET @gdi_ref_page_col = N'referenced_page';

        IF COL_LENGTH(N'dbo.' + @gdi_reference_table, 'internal_id') IS NOT NULL
            SET @gdi_ref_id_col = N'internal_id';
    END;

    IF @gdi_reference_table IS NOT NULL
       AND @gdi_ref_book_col IS NOT NULL
       AND @gdi_ref_page_col IS NOT NULL
    BEGIN
        SET @sql = N'
            UPDATE r
            SET
                r.' + QUOTENAME(@gdi_ref_book_col) + N' =
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
                r.' + QUOTENAME(@gdi_ref_page_col) + N' =
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
            FROM dbo.' + QUOTENAME(@gdi_reference_table) + N' r
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
    END;

    -- Build the dedupe index before Keli reference seeding so NOT EXISTS stays seekable.
    IF @gdi_reference_table = N'gdi_instrument_references'
       AND @gdi_ref_id_col IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE name = 'IX_gdi_instrument_references_scope_internal'
              AND object_id = OBJECT_ID('dbo.gdi_instrument_references')
       )
    BEGIN
        SET @sql = N'CREATE INDEX IX_gdi_instrument_references_scope_internal
            ON dbo.gdi_instrument_references (state_fips, county_fips, imported_by_user_id, is_deleted, ' + QUOTENAME(@gdi_ref_id_col) + N');';
        EXEC sys.sp_executesql @sql;
    END;

    -- -------------------------------------------------------------------------
    -- Section 5: Delegate Keli reference seeding to the shared helper proc
    -- The helper owns Keli table discovery, scope resolution, and insert rules.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(N'dbo.sp_SeedScopedKeliReferences', N'P') IS NOT NULL
    BEGIN
        EXEC dbo.sp_SeedScopedKeliReferences
            @ImportedByUserId = @ImportedByUserId,
            @StateFips = @StateFips,
            @CountyFips = @CountyFips;
    END;

    -- -------------------------------------------------------------------------
    -- Section 6: Consolidate legacy singular legal rows into dbo.gdi_legals
    -- for the active scope so the app only needs one legal table contract.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(N'dbo.gdi_legal', N'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID(N'dbo.gdi_legals', N'U') IS NULL
            SELECT TOP (0) * INTO dbo.gdi_legals FROM dbo.gdi_legal;

        DROP TABLE IF EXISTS #legal_row_map;
        CREATE TABLE #legal_row_map (
            old_id INT NOT NULL PRIMARY KEY,
            new_id INT NOT NULL
        );

        ;WITH src AS (
            SELECT
                l.id AS old_id,
                ISNULL(l.fn, '') AS fn,
                CASE
                    WHEN LOWER(ISNULL(l.file_key, '')) LIKE 'legal%' THEN 'legals' + SUBSTRING(ISNULL(l.file_key, ''), 6, 260)
                    ELSE ISNULL(l.file_key, '')
                END AS file_key,
                ISNULL(l.header_file_key, '') AS header_file_key,
                ISNULL(l.keyOriginalValue, '') AS keyOriginalValue,
                ISNULL(l.OriginalValue, '') AS OriginalValue,
                ISNULL(l.col01varchar, '') AS col01varchar,
                ISNULL(l.col02varchar, '') AS col02varchar,
                ISNULL(l.col06varchar, '') AS col06varchar,
                ISNULL(l.col07varchar, '') AS col07varchar,
                ISNULL(l.col08varchar, '') AS col08varchar,
                ISNULL(l.book, '') AS book,
                ISNULL(l.page_number, '') AS page_number,
                ISNULL(l.internal_id, '') AS internal_id,
                ISNULL(l.instrument_internal_id, '') AS instrument_internal_id,
                ISNULL(l.instrument_external_id, '') AS instrument_external_id,
                ISNULL(l.line, '') AS line,
                ISNULL(l.legal_type, '') AS legal_type,
                ISNULL(l.block, '') AS block,
                ISNULL(l.lot, '') AS lot,
                ISNULL(l.section, '') AS section,
                ISNULL(l.location, '') AS location,
                ISNULL(l.free_form_legal, '') AS free_form_legal,
                ISNULL(l.is_split_book, 0) AS is_split_book,
                l.imported_by_user_id,
                l.import_batch_id,
                l.state_fips,
                l.county_fips,
                ISNULL(l.is_deleted, 0) AS is_deleted,
                l.imported_at,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ISNULL(l.fn, ''),
                        CASE
                            WHEN LOWER(ISNULL(l.file_key, '')) LIKE 'legal%' THEN 'legals' + SUBSTRING(ISNULL(l.file_key, ''), 6, 260)
                            ELSE ISNULL(l.file_key, '')
                        END,
                        ISNULL(l.header_file_key, ''),
                        ISNULL(l.keyOriginalValue, ''),
                        ISNULL(l.OriginalValue, ''),
                        ISNULL(l.col01varchar, ''),
                        ISNULL(l.col02varchar, ''),
                        ISNULL(l.col06varchar, ''),
                        ISNULL(l.col07varchar, ''),
                        ISNULL(l.col08varchar, ''),
                        ISNULL(l.book, ''),
                        ISNULL(l.page_number, ''),
                        ISNULL(l.internal_id, ''),
                        ISNULL(l.instrument_internal_id, ''),
                        ISNULL(l.instrument_external_id, ''),
                        ISNULL(l.line, ''),
                        ISNULL(l.legal_type, ''),
                        ISNULL(l.block, ''),
                        ISNULL(l.lot, ''),
                        ISNULL(l.section, ''),
                        ISNULL(l.location, ''),
                        ISNULL(l.free_form_legal, ''),
                        ISNULL(l.is_split_book, 0),
                        l.imported_by_user_id,
                        l.import_batch_id,
                        l.state_fips,
                        l.county_fips,
                        ISNULL(l.is_deleted, 0)
                    ORDER BY l.id
                ) AS rn
            FROM dbo.gdi_legal l
            WHERE l.imported_by_user_id = @ImportedByUserId
              AND l.state_fips = @StateFips
              AND l.county_fips = @CountyFips
        ),
        dest AS (
            SELECT
                gl.id AS new_id,
                ISNULL(gl.fn, '') AS fn,
                ISNULL(gl.file_key, '') AS file_key,
                ISNULL(gl.header_file_key, '') AS header_file_key,
                ISNULL(gl.keyOriginalValue, '') AS keyOriginalValue,
                ISNULL(gl.OriginalValue, '') AS OriginalValue,
                ISNULL(gl.col01varchar, '') AS col01varchar,
                ISNULL(gl.col02varchar, '') AS col02varchar,
                ISNULL(gl.col06varchar, '') AS col06varchar,
                ISNULL(gl.col07varchar, '') AS col07varchar,
                ISNULL(gl.col08varchar, '') AS col08varchar,
                ISNULL(gl.book, '') AS book,
                ISNULL(gl.page_number, '') AS page_number,
                ISNULL(gl.internal_id, '') AS internal_id,
                ISNULL(gl.instrument_internal_id, '') AS instrument_internal_id,
                ISNULL(gl.instrument_external_id, '') AS instrument_external_id,
                ISNULL(gl.line, '') AS line,
                ISNULL(gl.legal_type, '') AS legal_type,
                ISNULL(gl.block, '') AS block,
                ISNULL(gl.lot, '') AS lot,
                ISNULL(gl.section, '') AS section,
                ISNULL(gl.location, '') AS location,
                ISNULL(gl.free_form_legal, '') AS free_form_legal,
                ISNULL(gl.is_split_book, 0) AS is_split_book,
                gl.imported_by_user_id,
                gl.import_batch_id,
                gl.state_fips,
                gl.county_fips,
                ISNULL(gl.is_deleted, 0) AS is_deleted,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ISNULL(gl.fn, ''),
                        ISNULL(gl.file_key, ''),
                        ISNULL(gl.header_file_key, ''),
                        ISNULL(gl.keyOriginalValue, ''),
                        ISNULL(gl.OriginalValue, ''),
                        ISNULL(gl.col01varchar, ''),
                        ISNULL(gl.col02varchar, ''),
                        ISNULL(gl.col06varchar, ''),
                        ISNULL(gl.col07varchar, ''),
                        ISNULL(gl.col08varchar, ''),
                        ISNULL(gl.book, ''),
                        ISNULL(gl.page_number, ''),
                        ISNULL(gl.internal_id, ''),
                        ISNULL(gl.instrument_internal_id, ''),
                        ISNULL(gl.instrument_external_id, ''),
                        ISNULL(gl.line, ''),
                        ISNULL(gl.legal_type, ''),
                        ISNULL(gl.block, ''),
                        ISNULL(gl.lot, ''),
                        ISNULL(gl.section, ''),
                        ISNULL(gl.location, ''),
                        ISNULL(gl.free_form_legal, ''),
                        ISNULL(gl.is_split_book, 0),
                        gl.imported_by_user_id,
                        gl.import_batch_id,
                        gl.state_fips,
                        gl.county_fips,
                        ISNULL(gl.is_deleted, 0)
                    ORDER BY gl.id
                ) AS rn
            FROM dbo.gdi_legals gl
            WHERE gl.imported_by_user_id = @ImportedByUserId
              AND gl.state_fips = @StateFips
              AND gl.county_fips = @CountyFips
        )
        INSERT INTO dbo.gdi_legals (
            fn, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col02varchar, col06varchar, col07varchar, col08varchar,
            book, page_number, internal_id, instrument_internal_id, instrument_external_id, line, legal_type,
            block, lot, section, location, free_form_legal,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            s.fn, s.file_key, s.header_file_key, s.keyOriginalValue, s.OriginalValue,
            s.col01varchar, s.col02varchar, s.col06varchar, s.col07varchar, s.col08varchar,
            s.book, s.page_number, s.internal_id, s.instrument_internal_id, s.instrument_external_id, s.line, s.legal_type,
            s.block, s.lot, s.section, s.location, s.free_form_legal,
            s.is_split_book, s.imported_by_user_id, s.import_batch_id, s.state_fips, s.county_fips, s.is_deleted, s.imported_at
        FROM src s
        LEFT JOIN dest d
          ON d.fn = s.fn
         AND d.file_key = s.file_key
         AND d.header_file_key = s.header_file_key
         AND d.keyOriginalValue = s.keyOriginalValue
         AND d.OriginalValue = s.OriginalValue
         AND d.col01varchar = s.col01varchar
         AND d.col02varchar = s.col02varchar
         AND d.col06varchar = s.col06varchar
         AND d.col07varchar = s.col07varchar
         AND d.col08varchar = s.col08varchar
         AND d.book = s.book
         AND d.page_number = s.page_number
         AND d.internal_id = s.internal_id
         AND d.instrument_internal_id = s.instrument_internal_id
         AND d.instrument_external_id = s.instrument_external_id
         AND d.line = s.line
         AND d.legal_type = s.legal_type
         AND d.block = s.block
         AND d.lot = s.lot
         AND d.section = s.section
         AND d.location = s.location
         AND d.free_form_legal = s.free_form_legal
         AND d.is_split_book = s.is_split_book
         AND d.imported_by_user_id = s.imported_by_user_id
         AND d.import_batch_id = s.import_batch_id
         AND d.state_fips = s.state_fips
         AND d.county_fips = s.county_fips
         AND d.is_deleted = s.is_deleted
         AND d.rn = s.rn
        WHERE d.new_id IS NULL;

        ;WITH src AS (
            SELECT
                l.id AS old_id,
                ISNULL(l.fn, '') AS fn,
                CASE
                    WHEN LOWER(ISNULL(l.file_key, '')) LIKE 'legal%' THEN 'legals' + SUBSTRING(ISNULL(l.file_key, ''), 6, 260)
                    ELSE ISNULL(l.file_key, '')
                END AS file_key,
                ISNULL(l.header_file_key, '') AS header_file_key,
                ISNULL(l.keyOriginalValue, '') AS keyOriginalValue,
                ISNULL(l.OriginalValue, '') AS OriginalValue,
                ISNULL(l.col01varchar, '') AS col01varchar,
                ISNULL(l.col02varchar, '') AS col02varchar,
                ISNULL(l.col06varchar, '') AS col06varchar,
                ISNULL(l.col07varchar, '') AS col07varchar,
                ISNULL(l.col08varchar, '') AS col08varchar,
                ISNULL(l.book, '') AS book,
                ISNULL(l.page_number, '') AS page_number,
                ISNULL(l.internal_id, '') AS internal_id,
                ISNULL(l.instrument_internal_id, '') AS instrument_internal_id,
                ISNULL(l.instrument_external_id, '') AS instrument_external_id,
                ISNULL(l.line, '') AS line,
                ISNULL(l.legal_type, '') AS legal_type,
                ISNULL(l.block, '') AS block,
                ISNULL(l.lot, '') AS lot,
                ISNULL(l.section, '') AS section,
                ISNULL(l.location, '') AS location,
                ISNULL(l.free_form_legal, '') AS free_form_legal,
                ISNULL(l.is_split_book, 0) AS is_split_book,
                l.imported_by_user_id,
                l.import_batch_id,
                l.state_fips,
                l.county_fips,
                ISNULL(l.is_deleted, 0) AS is_deleted,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ISNULL(l.fn, ''),
                        CASE
                            WHEN LOWER(ISNULL(l.file_key, '')) LIKE 'legal%' THEN 'legals' + SUBSTRING(ISNULL(l.file_key, ''), 6, 260)
                            ELSE ISNULL(l.file_key, '')
                        END,
                        ISNULL(l.header_file_key, ''),
                        ISNULL(l.keyOriginalValue, ''),
                        ISNULL(l.OriginalValue, ''),
                        ISNULL(l.col01varchar, ''),
                        ISNULL(l.col02varchar, ''),
                        ISNULL(l.col06varchar, ''),
                        ISNULL(l.col07varchar, ''),
                        ISNULL(l.col08varchar, ''),
                        ISNULL(l.book, ''),
                        ISNULL(l.page_number, ''),
                        ISNULL(l.internal_id, ''),
                        ISNULL(l.instrument_internal_id, ''),
                        ISNULL(l.instrument_external_id, ''),
                        ISNULL(l.line, ''),
                        ISNULL(l.legal_type, ''),
                        ISNULL(l.block, ''),
                        ISNULL(l.lot, ''),
                        ISNULL(l.section, ''),
                        ISNULL(l.location, ''),
                        ISNULL(l.free_form_legal, ''),
                        ISNULL(l.is_split_book, 0),
                        l.imported_by_user_id,
                        l.import_batch_id,
                        l.state_fips,
                        l.county_fips,
                        ISNULL(l.is_deleted, 0)
                    ORDER BY l.id
                ) AS rn
            FROM dbo.gdi_legal l
            WHERE l.imported_by_user_id = @ImportedByUserId
              AND l.state_fips = @StateFips
              AND l.county_fips = @CountyFips
        ),
        dest AS (
            SELECT
                gl.id AS new_id,
                ISNULL(gl.fn, '') AS fn,
                ISNULL(gl.file_key, '') AS file_key,
                ISNULL(gl.header_file_key, '') AS header_file_key,
                ISNULL(gl.keyOriginalValue, '') AS keyOriginalValue,
                ISNULL(gl.OriginalValue, '') AS OriginalValue,
                ISNULL(gl.col01varchar, '') AS col01varchar,
                ISNULL(gl.col02varchar, '') AS col02varchar,
                ISNULL(gl.col06varchar, '') AS col06varchar,
                ISNULL(gl.col07varchar, '') AS col07varchar,
                ISNULL(gl.col08varchar, '') AS col08varchar,
                ISNULL(gl.book, '') AS book,
                ISNULL(gl.page_number, '') AS page_number,
                ISNULL(gl.internal_id, '') AS internal_id,
                ISNULL(gl.instrument_internal_id, '') AS instrument_internal_id,
                ISNULL(gl.instrument_external_id, '') AS instrument_external_id,
                ISNULL(gl.line, '') AS line,
                ISNULL(gl.legal_type, '') AS legal_type,
                ISNULL(gl.block, '') AS block,
                ISNULL(gl.lot, '') AS lot,
                ISNULL(gl.section, '') AS section,
                ISNULL(gl.location, '') AS location,
                ISNULL(gl.free_form_legal, '') AS free_form_legal,
                ISNULL(gl.is_split_book, 0) AS is_split_book,
                gl.imported_by_user_id,
                gl.import_batch_id,
                gl.state_fips,
                gl.county_fips,
                ISNULL(gl.is_deleted, 0) AS is_deleted,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ISNULL(gl.fn, ''),
                        ISNULL(gl.file_key, ''),
                        ISNULL(gl.header_file_key, ''),
                        ISNULL(gl.keyOriginalValue, ''),
                        ISNULL(gl.OriginalValue, ''),
                        ISNULL(gl.col01varchar, ''),
                        ISNULL(gl.col02varchar, ''),
                        ISNULL(gl.col06varchar, ''),
                        ISNULL(gl.col07varchar, ''),
                        ISNULL(gl.col08varchar, ''),
                        ISNULL(gl.book, ''),
                        ISNULL(gl.page_number, ''),
                        ISNULL(gl.internal_id, ''),
                        ISNULL(gl.instrument_internal_id, ''),
                        ISNULL(gl.instrument_external_id, ''),
                        ISNULL(gl.line, ''),
                        ISNULL(gl.legal_type, ''),
                        ISNULL(gl.block, ''),
                        ISNULL(gl.lot, ''),
                        ISNULL(gl.section, ''),
                        ISNULL(gl.location, ''),
                        ISNULL(gl.free_form_legal, ''),
                        ISNULL(gl.is_split_book, 0),
                        gl.imported_by_user_id,
                        gl.import_batch_id,
                        gl.state_fips,
                        gl.county_fips,
                        ISNULL(gl.is_deleted, 0)
                    ORDER BY gl.id
                ) AS rn
            FROM dbo.gdi_legals gl
            WHERE gl.imported_by_user_id = @ImportedByUserId
              AND gl.state_fips = @StateFips
              AND gl.county_fips = @CountyFips
        )
        INSERT INTO #legal_row_map (old_id, new_id)
        SELECT s.old_id, d.new_id
        FROM src s
        JOIN dest d
          ON d.fn = s.fn
         AND d.file_key = s.file_key
         AND d.header_file_key = s.header_file_key
         AND d.keyOriginalValue = s.keyOriginalValue
         AND d.OriginalValue = s.OriginalValue
         AND d.col01varchar = s.col01varchar
         AND d.col02varchar = s.col02varchar
         AND d.col06varchar = s.col06varchar
         AND d.col07varchar = s.col07varchar
         AND d.col08varchar = s.col08varchar
         AND d.book = s.book
         AND d.page_number = s.page_number
         AND d.internal_id = s.internal_id
         AND d.instrument_internal_id = s.instrument_internal_id
         AND d.instrument_external_id = s.instrument_external_id
         AND d.line = s.line
         AND d.legal_type = s.legal_type
         AND d.block = s.block
         AND d.lot = s.lot
         AND d.section = s.section
         AND d.location = s.location
         AND d.free_form_legal = s.free_form_legal
         AND d.is_split_book = s.is_split_book
         AND d.imported_by_user_id = s.imported_by_user_id
         AND d.import_batch_id = s.import_batch_id
         AND d.state_fips = s.state_fips
         AND d.county_fips = s.county_fips
         AND d.is_deleted = s.is_deleted
         AND d.rn = s.rn;

        UPDATE c
        SET c.source_row_id = m.new_id
        FROM dbo.corrections_legal c
        JOIN #legal_row_map m
          ON m.old_id = c.source_row_id
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips;

        IF OBJECT_ID(N'dbo.corrections_other_type_legals', N'U') IS NOT NULL
        BEGIN
            UPDATE c
            SET c.legal_row_id = m.new_id
            FROM dbo.corrections_other_type_legals c
            JOIN #legal_row_map m
              ON m.old_id = c.legal_row_id
            WHERE c.imported_by_user_id = @ImportedByUserId
              AND c.state_fips = @StateFips
              AND c.county_fips = @CountyFips;
        END;

        IF OBJECT_ID(N'dbo.corrections_other_type_legals_audit', N'U') IS NOT NULL
        BEGIN
            UPDATE c
            SET c.legal_row_id = m.new_id
            FROM dbo.corrections_other_type_legals_audit c
            JOIN #legal_row_map m
              ON m.old_id = c.legal_row_id
            WHERE c.imported_by_user_id = @ImportedByUserId
              AND c.state_fips = @StateFips
              AND c.county_fips = @CountyFips;
        END;

        IF OBJECT_ID(N'dbo.gdi_additions', N'U') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_additions', 'legal_row_id') IS NOT NULL
        BEGIN
            UPDATE a
            SET a.legal_row_id = m.new_id
            FROM dbo.gdi_additions a
            JOIN #legal_row_map m
              ON m.old_id = a.legal_row_id
            WHERE a.imported_by_user_id = @ImportedByUserId
              AND a.state_fips = @StateFips
              AND a.county_fips = @CountyFips;
        END;

        IF OBJECT_ID(N'dbo.gdi_township_range', N'U') IS NOT NULL
           AND COL_LENGTH(N'dbo.gdi_township_range', 'legal_row_id') IS NOT NULL
        BEGIN
            UPDATE t
            SET t.legal_row_id = m.new_id
            FROM dbo.gdi_township_range t
            JOIN #legal_row_map m
              ON m.old_id = t.legal_row_id
            WHERE t.imported_by_user_id = @ImportedByUserId
              AND t.state_fips = @StateFips
              AND t.county_fips = @CountyFips;
        END;

        DELETE l
        FROM dbo.gdi_legal l
        JOIN #legal_row_map m
          ON m.old_id = l.id;

        IF NOT EXISTS (SELECT 1 FROM dbo.gdi_legal)
            DROP TABLE dbo.gdi_legal;
    END;

    DECLARE @legacy_cleanup TABLE (table_name SYSNAME NOT NULL);
    INSERT INTO @legacy_cleanup (table_name)
    VALUES
        (N'gdi_header'),
        (N'gdi_headers'),
        (N'gdi_image'),
        (N'gdi_images'),
        (N'gdi_name'),
        (N'gdi_names'),
        (N'gdi_reference'),
        (N'gdi_references');

    DECLARE @legacy_table SYSNAME;
    DECLARE legacy_cleanup_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT lc.table_name
        FROM @legacy_cleanup lc;

    OPEN legacy_cleanup_cursor;
    FETCH NEXT FROM legacy_cleanup_cursor INTO @legacy_table;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF OBJECT_ID(N'dbo.' + @legacy_table, N'U') IS NOT NULL
        BEGIN
            SET @sql = N'
                IF NOT EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@legacy_table) + N')
                    DROP TABLE dbo.' + QUOTENAME(@legacy_table) + N';';
            EXEC sys.sp_executesql @sql;
        END;

        FETCH NEXT FROM legacy_cleanup_cursor INTO @legacy_table;
    END;
    CLOSE legacy_cleanup_cursor;
    DEALLOCATE legacy_cleanup_cursor;

    -- -------------------------------------------------------------------------
    -- Section 7: Ensure scope indexes exist for key working tables
    -- -------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope_fn_col01'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope_fn_col01
            ON dbo.GenericDataImport (state_fips, county_fips, imported_by_user_id, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_instruments', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_header_scope_file_col01'
          AND object_id = OBJECT_ID('dbo.gdi_instruments')
    )
        CREATE INDEX IX_gdi_header_scope_file_col01
            ON dbo.gdi_instruments (state_fips, county_fips, imported_by_user_id, file_key, col01varchar);

    DECLARE @gdi_legal_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.gdi_legals', N'U') IS NOT NULL
        SET @gdi_legal_table = N'gdi_legals';
    ELSE IF OBJECT_ID(N'dbo.gdi_legal', N'U') IS NOT NULL
        SET @gdi_legal_table = N'gdi_legal';

    IF @gdi_legal_table IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_legal_scope_header_col01'
          AND object_id = OBJECT_ID(N'dbo.' + @gdi_legal_table)
    )
    BEGIN
        SET @sql = N'CREATE INDEX IX_gdi_legal_scope_header_col01
            ON dbo.' + QUOTENAME(@gdi_legal_table) + N' (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);';
        EXEC sys.sp_executesql @sql;
    END;

    IF OBJECT_ID(N'dbo.gdi_parties', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_names_scope_header_col01'
          AND object_id = OBJECT_ID('dbo.gdi_parties')
    )
        CREATE INDEX IX_gdi_names_scope_header_col01
            ON dbo.gdi_parties (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_pages', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_pages_scope_header_col01'
          AND object_id = OBJECT_ID('dbo.gdi_pages')
    )
        CREATE INDEX IX_gdi_pages_scope_header_col01
            ON dbo.gdi_pages (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE name = 'IX_gdi_instrument_references_scope_header_col01'
              AND object_id = OBJECT_ID('dbo.gdi_instrument_references')
       )
        CREATE INDEX IX_gdi_instrument_references_scope_header_col01
            ON dbo.gdi_instrument_references (state_fips, county_fips, imported_by_user_id, is_deleted, header_file_key, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
       AND @gdi_ref_id_col IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE name = 'IX_gdi_instrument_references_scope_internal'
              AND object_id = OBJECT_ID('dbo.gdi_instrument_references')
       )
    BEGIN
        SET @sql = N'CREATE INDEX IX_gdi_instrument_references_scope_internal
            ON dbo.gdi_instrument_references (state_fips, county_fips, imported_by_user_id, is_deleted, ' + QUOTENAME(@gdi_ref_id_col) + N');';
        EXEC sys.sp_executesql @sql;
    END;

    -- -------------------------------------------------------------------------
    -- Section 7: Seed default legal rows for headers missing legal records
    -- -------------------------------------------------------------------------
    IF @gdi_legal_table IS NOT NULL
    BEGIN
        SET @sql = N'
        INSERT INTO dbo.' + QUOTENAME(@gdi_legal_table) + N' (
            fn, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col02varchar,
            col06varchar, col07varchar, col08varchar,
            book, page_number, internal_id, instrument_internal_id, instrument_external_id, line, legal_type,
            block, lot, section, location, free_form_legal,
            imported_by_user_id, import_batch_id, state_fips, county_fips, imported_at
        )
        SELECT
            REPLACE(REPLACE(ISNULL(h.fn, ''''), ''HEADER'', ''Legal''), ''header'', ''legal'') AS fn,
            CASE
                WHEN LOWER(ISNULL(h.file_key, '''')) LIKE ''header%'' THEN STUFF(h.file_key, 1, 6, ''legals'')
                ELSE ''legals_'' + ISNULL(h.file_key, '''')
            END AS file_key,
            ISNULL(h.header_file_key, ''''),
            ISNULL(h.keyOriginalValue, ISNULL(h.OriginalValue, '''')),
            '''',
            ISNULL(h.col01varchar, ''''), '''',
            '''', '''', '''',
            ISNULL(h.book, ''''), ISNULL(h.beginning_page, ''''), '''', '''', '''', '''', ''Other'',
            '''', '''', '''', '''', ''No Legal Description'',
            h.imported_by_user_id, h.import_batch_id, h.state_fips, h.county_fips, SYSDATETIMEOFFSET()
        FROM dbo.gdi_instruments h
        LEFT JOIN dbo.' + QUOTENAME(@gdi_legal_table) + N' l
            ON l.imported_by_user_id = h.imported_by_user_id
           AND l.state_fips = h.state_fips
           AND l.county_fips = h.county_fips
           AND l.header_file_key = h.header_file_key
           AND l.col01varchar = h.col01varchar
        WHERE h.imported_by_user_id = @uid
          AND h.state_fips = @sf
          AND h.county_fips = @cf
          AND l.ID IS NULL;';

        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips;
    END;

	    -- -------------------------------------------------------------------------
	    -- Section 8: Final data hygiene pass
	    -- Convert all nullable text columns to empty string by scope.
	    -- -------------------------------------------------------------------------
	    DECLARE @table_name SYSNAME;
	    DECLARE @set_clause NVARCHAR(MAX);
	    DECLARE @null_predicate NVARCHAR(MAX);

    DECLARE tcur CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name
        FROM sys.tables t
        WHERE (t.name = 'GenericDataImport' OR t.name LIKE 'gdi[_]%')
          AND EXISTS (
              SELECT 1
              FROM sys.columns s
              WHERE s.object_id = t.object_id
                AND s.name IN ('imported_by_user_id', 'state_fips', 'county_fips')
              GROUP BY s.object_id
              HAVING COUNT(DISTINCT s.name) = 3
          )
          AND EXISTS (
              SELECT 1
              FROM sys.columns c
              JOIN sys.types ty ON c.user_type_id = ty.user_type_id
              WHERE c.object_id = t.object_id
                AND c.is_computed = 0
                AND ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
          );

    OPEN tcur;
    FETCH NEXT FROM tcur INTO @table_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
	        SELECT
	            @set_clause = STUFF((
	                SELECT
	                    N', ' + QUOTENAME(c.name) + N' = ISNULL(' + QUOTENAME(c.name) + N', '''')'
	                FROM sys.columns c
	                JOIN sys.types ty ON c.user_type_id = ty.user_type_id
	                WHERE c.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@table_name))
	                  AND c.is_computed = 0
	                  AND c.is_nullable = 1
	                  AND ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
	                FOR XML PATH(''), TYPE
	            ).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
	            @null_predicate = STUFF((
	                SELECT
	                    N' OR t.' + QUOTENAME(c.name) + N' IS NULL'
	                FROM sys.columns c
	                JOIN sys.types ty ON c.user_type_id = ty.user_type_id
	                WHERE c.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@table_name))
	                  AND c.is_computed = 0
	                  AND c.is_nullable = 1
	                  AND ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
	                FOR XML PATH(''), TYPE
	            ).value('.', 'NVARCHAR(MAX)'), 1, 4, N'');

	        IF ISNULL(@set_clause, N'') <> N'' AND ISNULL(@null_predicate, N'') <> N''
	        BEGIN
	            SET @sql = N'UPDATE t SET ' + @set_clause
	                + N' FROM dbo.' + QUOTENAME(@table_name) + N' t'
	                + N' WHERE t.imported_by_user_id = @uid AND t.state_fips = @sf AND t.county_fips = @cf'
	                + N' AND (' + @null_predicate + N')';
	            EXEC sys.sp_executesql
	                @sql,
	                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
	                @uid = @ImportedByUserId,
	                @sf = @StateFips,
                @cf = @CountyFips;
        END;

        FETCH NEXT FROM tcur INTO @table_name;
    END
    CLOSE tcur;
    DEALLOCATE tcur;
END;
