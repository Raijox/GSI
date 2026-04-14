/* ============================================================================
   File: 02_reference_normalization.sql
   Procedure: dbo.sp_EdataTableSetup
   Role in assembly:
   - Computes the active import batch context and normalizes referenced_book and
     referenced_page values inside the scoped gdi reference table.
   Why this file exists:
   - Reference normalization has dense business rules and is easier to maintain
     when it is isolated from Keli seeding and legal consolidation.
   Maintenance notes:
   - This fragment establishes scope_import_batch_id for later setup steps.
   - Keep the reference formatting rules centralized here to avoid divergence.
   ============================================================================ */
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
      AND (@scope_import_batch_id IS NULL OR h.import_batch_id = @scope_import_batch_id)
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
              AND (@batch_id IS NULL OR r.import_batch_id = @batch_id)
              AND ISNULL(r.is_deleted, 0) = 0;';
        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @book_min INT, @book_max INT, @batch_id UNIQUEIDENTIFIER',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips,
            @book_min = @job_book_min,
            @book_max = @job_book_max,
            @batch_id = @scope_import_batch_id;
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
