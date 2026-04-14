/* ============================================================================
   File: sp_SeedScopedKeliReferences.sql
   Procedure: dbo.sp_SeedScopedKeliReferences
   Purpose:
   - Seed scoped Keli instrument-reference rows into
     dbo.gdi_instrument_references for the active eData working batch.
   Why this file exists:
   - The Keli import owns Keli table creation and column-shape discovery, so the
     Keli-to-eData handoff should live with the Keli module instead of being
     embedded directly inside the eData setup procedure.
   What this procedure does:
   - Validates and normalizes the user/county scope.
   - Resolves the active eData import batch from dbo.gdi_instruments with a
     dbo.GenericDataImport fallback so inserted reference rows line up with the
     current working eData batch.
   - Computes the active eData book range from non-deleted dbo.gdi_instruments
     rows so only Keli references that belong to the current job range are
     copied into the working reference table.
   - Discovers the available Keli reference table shape
     (keli_instrument_references or keli_instrument_reference) and the correct
     referenced-book/page columns without assuming one exact legacy schema.
   - Ensures the scoped dedupe index used by the NOT EXISTS check is present.
   - Inserts only missing active-scope Keli references, keyed by the Keli row id.
   Safety rules:
   - This procedure returns without error when the Keli source table does not
     exist yet or when dbo.gdi_instrument_references has not been created yet.
     That keeps both import orders safe: eData-first or Keli-first.
   Maintenance notes:
   - Keep future Keli-to-eData reference seeding rules centralized here.
   - Call this procedure after Keli import completes, and optionally from eData
     setup as a guarded follow-up when Keli tables already exist.
   ============================================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_SeedScopedKeliReferences
    @ImportedByUserId INT,
    @StateFips CHAR(2),
    @CountyFips CHAR(5)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ImportedByUserId IS NULL OR @ImportedByUserId <= 0
        THROW 61000, 'ImportedByUserId is required.', 1;
    IF @StateFips IS NULL OR LEN(LTRIM(RTRIM(@StateFips))) <> 2
        THROW 61001, 'StateFips must be 2 characters.', 1;
    IF @CountyFips IS NULL OR LEN(LTRIM(RTRIM(@CountyFips))) <> 5
        THROW 61002, 'CountyFips must be 5 characters.', 1;

    SET @StateFips = RIGHT('00' + LTRIM(RTRIM(@StateFips)), 2);
    SET @CountyFips = RIGHT('00000' + LTRIM(RTRIM(@CountyFips)), 5);

    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NULL
        RETURN;

    IF COL_LENGTH(N'dbo.gdi_instrument_references', 'referenced_book') IS NULL
       OR COL_LENGTH(N'dbo.gdi_instrument_references', 'referenced_page') IS NULL
       OR COL_LENGTH(N'dbo.gdi_instrument_references', 'internal_id') IS NULL
       OR COL_LENGTH(N'dbo.gdi_instrument_references', 'import_batch_id') IS NULL
    BEGIN
        RETURN;
    END;

    DECLARE @scope_import_batch_id UNIQUEIDENTIFIER = NULL;
    DECLARE @job_book_min INT = NULL;
    DECLARE @job_book_max INT = NULL;
    DECLARE @keli_reference_table SYSNAME = NULL;
    DECLARE @keli_ref_scope_filter NVARCHAR(500) = N'';
    DECLARE @keli_ref_book_col SYSNAME = NULL;
    DECLARE @keli_ref_page_col SYSNAME = NULL;
    DECLARE @sql NVARCHAR(MAX);

    IF OBJECT_ID(N'dbo.gdi_instruments', N'U') IS NOT NULL
    BEGIN
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
    END;

    IF @scope_import_batch_id IS NULL
       AND OBJECT_ID(N'dbo.GenericDataImport', N'U') IS NOT NULL
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
       OR @job_book_min IS NULL
       OR @job_book_max IS NULL
    BEGIN
        RETURN;
    END;

    IF OBJECT_ID(N'dbo.keli_instrument_references', N'U') IS NOT NULL
        SET @keli_reference_table = N'keli_instrument_references';
    ELSE IF OBJECT_ID(N'dbo.keli_instrument_reference', N'U') IS NOT NULL
        SET @keli_reference_table = N'keli_instrument_reference';

    IF @keli_reference_table IS NULL
        RETURN;

    IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'id') IS NULL
        RETURN;

    IF @keli_reference_table = N'keli_instrument_references'
    BEGIN
        IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'referenced_book') IS NOT NULL
            SET @keli_ref_book_col = N'referenced_book';
        IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'referenced_page') IS NOT NULL
            SET @keli_ref_page_col = N'referenced_page';
    END;

    IF @keli_ref_book_col IS NULL
    BEGIN
        IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'referenced_book') IS NOT NULL
            SET @keli_ref_book_col = N'referenced_book';
        ELSE IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'reference_book') IS NOT NULL
            SET @keli_ref_book_col = N'reference_book';
    END;

    IF @keli_ref_page_col IS NULL
    BEGIN
        IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'referenced_page') IS NOT NULL
            SET @keli_ref_page_col = N'referenced_page';
        ELSE IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'reference_page') IS NOT NULL
            SET @keli_ref_page_col = N'reference_page';
    END;

    IF @keli_ref_book_col IS NULL OR @keli_ref_page_col IS NULL
        RETURN;

    IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'state_fips') IS NOT NULL
       AND COL_LENGTH(N'dbo.' + @keli_reference_table, 'county_fips') IS NOT NULL
    BEGIN
        SET @keli_ref_scope_filter = @keli_ref_scope_filter + N'
              AND RIGHT(''00'' + LTRIM(RTRIM(ISNULL(CAST(kir.state_fips AS VARCHAR(1000)), ''''))), 2) = @sf
              AND RIGHT(''00000'' + LTRIM(RTRIM(ISNULL(CAST(kir.county_fips AS VARCHAR(1000)), ''''))), 5) = @cf';
    END;

    IF COL_LENGTH(N'dbo.' + @keli_reference_table, 'is_deleted') IS NOT NULL
    BEGIN
        SET @keli_ref_scope_filter = @keli_ref_scope_filter + N'
              AND ISNULL(kir.is_deleted, 0) = 0';
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_gdi_instrument_references_scope_internal'
          AND object_id = OBJECT_ID(N'dbo.gdi_instrument_references')
    )
    BEGIN
        CREATE INDEX IX_gdi_instrument_references_scope_internal
            ON dbo.gdi_instrument_references (state_fips, county_fips, imported_by_user_id, is_deleted, internal_id);
    END;

    SET @sql = N'
        INSERT INTO dbo.gdi_instrument_references (
            fn, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col02varchar, col03varchar, book, page_number,
            internal_id, instrument_external_id, referenced_instrument_internal_id, referenced_instrument_external_id,
            referenced_book, referenced_page,
            imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            '''', '''', '''', '''', '''',
            '''', '''', '''', '''', '''',
            ISNULL(LTRIM(RTRIM(CAST(kir.id AS VARCHAR(1000)))), ''''),
            '''', '''', '''',
            ISNULL(LTRIM(RTRIM(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)))), ''''),
            ISNULL(LTRIM(RTRIM(CAST(kir.' + QUOTENAME(@keli_ref_page_col) + N' AS VARCHAR(1000)))), ''''),
            @uid, @batch_id, @sf, @cf, 0, SYSDATETIMEOFFSET()
        FROM dbo.' + QUOTENAME(@keli_reference_table) + N' kir
        WHERE LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), ''''))) <> ''''
          AND TRY_CONVERT(
                BIGINT,
                NULLIF(
                    CASE
                        WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), '''')))), 1) LIKE ''[A-Z]''
                             AND LEN(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), '''')))) > 1
                            THEN LEFT(
                                UPPER(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), '''')))),
                                LEN(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), '''')))) - 1
                            )
                        ELSE UPPER(LTRIM(RTRIM(ISNULL(CAST(kir.' + QUOTENAME(@keli_ref_book_col) + N' AS VARCHAR(1000)), ''''))))
                    END,
                    ''''
                )
              ) BETWEEN @book_min AND @book_max
' + @keli_ref_scope_filter + N'
          AND ISNULL(LTRIM(RTRIM(CAST(kir.id AS VARCHAR(1000)))), '''') <> ''''
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.gdi_instrument_references r
                WHERE r.imported_by_user_id = @uid
                  AND r.state_fips = @sf
                  AND r.county_fips = @cf
                  AND ISNULL(r.is_deleted, 0) = 0
                  AND ISNULL(LTRIM(RTRIM(r.internal_id)), '''') = ISNULL(LTRIM(RTRIM(CAST(kir.id AS VARCHAR(1000)))), '''')
          );';

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
