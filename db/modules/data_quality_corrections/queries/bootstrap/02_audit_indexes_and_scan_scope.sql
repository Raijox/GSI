/* ============================================================================
   File: 02_audit_indexes_and_scan_scope.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Second bootstrap fragment.
   - Creates the shared audit table, adds optional source-table helper indexes,
     and opens the scan procedure definition.
   What lives here:
   - corrections_audit creation.
   - Optional gdi_* helper indexes used to keep scan predicates and queue loads
     seekable in larger county scopes.
   - The opening portion of dbo.sp_DataQualityCorrectionsScan: prerequisite
     checks, pending-row cleanup, fixed-row preservation temp tables, split-book
     range discovery, and the shared scoped header temp table.
   Why this file exists:
   - The tool needs one stable place for its performance scaffolding and the
     common procedure setup that every later scan block depends on.
   Maintenance notes:
   - This fragment intentionally starts the dynamic ALTER PROCEDURE string but
     does not close it. Later fragments continue the exact same definition, so
     ordering inside the directory must not change.
   ============================================================================ */
/* ----------------------------------------------------------------------------
   Section J: Audit table for scan/apply workflow logs
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        table_key VARCHAR(30) NOT NULL CONSTRAINT DF_corr_audit_table_key DEFAULT '',
        correction_row_id BIGINT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        details NVARCHAR(MAX) NULL
    );
    CREATE INDEX IX_corr_audit_scope_time ON dbo.corrections_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;

/* ----------------------------------------------------------------------------
   Section J.1: Optional source-table helper indexes for faster scan predicates
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.gdi_instruments', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_instruments', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_instruments')
         AND [name] = 'IX_gdi_header_dq_scope'
   )
    CREATE INDEX IX_gdi_header_dq_scope
        ON dbo.gdi_instruments (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, col02varchar, col04varchar, col05varchar, col06varchar, book, beginning_page, ending_page);

IF OBJECT_ID('dbo.gdi_parties', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_parties', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_parties')
         AND [name] = 'IX_gdi_names_dq_scope'
   )
    CREATE INDEX IX_gdi_names_dq_scope
        ON dbo.gdi_parties (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, col02varchar, col03varchar);

IF OBJECT_ID('dbo.gdi_pages', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_pages', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_pages')
         AND [name] = 'IX_gdi_images_dq_scope'
   )
    CREATE INDEX IX_gdi_images_dq_scope
        ON dbo.gdi_pages (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, col02varchar, col03varchar, book, page_number);

IF OBJECT_ID('dbo.gdi_pages', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_pages', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_pages')
         AND [name] = 'IX_gdi_image_dq_scope'
   )
    CREATE INDEX IX_gdi_image_dq_scope
        ON dbo.gdi_pages (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, col02varchar, col03varchar, book, page_number);

IF OBJECT_ID('dbo.gdi_instrument_references', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_instrument_references', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_instrument_references')
         AND [name] = 'IX_gdi_reference_dq_scope'
   )
    CREATE INDEX IX_gdi_reference_dq_scope
        ON dbo.gdi_instrument_references (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, referenced_book, referenced_page);

IF OBJECT_ID('dbo.gdi_instrument_references', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_instrument_references', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_instrument_references')
         AND [name] = 'IX_gdi_ref_dq_scope'
   )
    CREATE INDEX IX_gdi_ref_dq_scope
        ON dbo.gdi_instrument_references (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, referenced_book, referenced_page);

IF OBJECT_ID('dbo.gdi_record_series', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_record_series', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_record_series')
         AND [name] = 'IX_gdi_record_series_dq_scope'
   )
    CREATE INDEX IX_gdi_record_series_dq_scope
        ON dbo.gdi_record_series (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, [year], record_series_internal_id);

IF OBJECT_ID('dbo.gdi_legals', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_legals', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_legals')
         AND [name] = 'IX_gdi_legals_dq_scope'
   )
    CREATE INDEX IX_gdi_legals_dq_scope
        ON dbo.gdi_legals (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, col02varchar, col08varchar);

IF OBJECT_ID('dbo.gdi_legal', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_legal', 'is_deleted') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM sys.indexes
       WHERE object_id = OBJECT_ID('dbo.gdi_legal')
         AND [name] = 'IX_gdi_legal_dq_scope'
   )
    CREATE INDEX IX_gdi_legal_dq_scope
        ON dbo.gdi_legal (imported_by_user_id, state_fips, county_fips, is_deleted)
        INCLUDE (id, header_file_key, file_key, col01varchar, col02varchar, col08varchar);

/* ----------------------------------------------------------------------------
   Section K: Recreate scan procedure (single source of truth for issue scans)
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.sp_DataQualityCorrectionsScan', 'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DataQualityCorrectionsScan AS BEGIN SET NOCOUNT ON; END;');

EXEC(N'ALTER PROCEDURE dbo.sp_DataQualityCorrectionsScan
    @ImportedByUserId INT,
    @StateFips CHAR(2),
    @CountyFips CHAR(5)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @scope_import_batch_id VARCHAR(36) = '''';

    -- -------------------------------------------------------------------------
    -- 1) Prerequisite checks
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_instruments'', ''U'') IS NULL
    BEGIN
        RAISERROR(''gdi_instruments table was not found. Import eData first.'', 16, 1);
        RETURN;
    END;
    IF OBJECT_ID(''dbo.gdi_parties'', ''U'') IS NULL
    BEGIN
        RAISERROR(''gdi_parties table was not found. Import eData first.'', 16, 1);
        RETURN;
    END;

    IF COL_LENGTH(''dbo.corrections_instruments'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_instruments c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_pages'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_pages c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_legal'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_legal c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_parties'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_parties c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_instrument_references'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_instrument_references c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_instrument_types_dq'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_instrument_types_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_additions_dq'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_additions_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_record_series_dq'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_record_series_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;
    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.corrections_township_range_dq'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(c.import_batch_id AS VARCHAR(36))
        FROM dbo.corrections_township_range_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND c.import_batch_id IS NOT NULL
        ORDER BY CASE WHEN ISNULL(c.is_fixed, 0) = 0 THEN 0 ELSE 1 END,
                 ISNULL(c.updated_at, c.created_at) DESC,
                 c.id DESC;
    END;

    IF ISNULL(@scope_import_batch_id, '''') = '''' AND COL_LENGTH(''dbo.gdi_instruments'', ''import_batch_id'') IS NOT NULL
    BEGIN
        SELECT TOP 1 @scope_import_batch_id = CAST(h.import_batch_id AS VARCHAR(36))
        FROM dbo.gdi_instruments h
        WHERE h.imported_by_user_id = @ImportedByUserId
          AND h.state_fips = @StateFips
          AND h.county_fips = @CountyFips
          AND h.import_batch_id IS NOT NULL
          AND ISNULL(h.is_deleted, 0) = 0
        ORDER BY h.imported_at DESC, h.id DESC;
    END;

    -- -------------------------------------------------------------------------
    -- 2) Clear only pending (unfixed) rows so fixed audit history is preserved
    -- -------------------------------------------------------------------------
    DELETE FROM dbo.corrections_instruments WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_pages WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_legal WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_parties WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_instrument_references WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_instrument_types_dq WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_additions_dq WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_record_series_dq WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;
    DELETE FROM dbo.corrections_township_range_dq WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 0;

    IF OBJECT_ID(''tempdb..#fixed_header'', ''U'') IS NOT NULL DROP TABLE #fixed_header;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_header
    FROM dbo.corrections_instruments
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_header_key ON #fixed_header (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_images'', ''U'') IS NOT NULL DROP TABLE #fixed_images;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_images
    FROM dbo.corrections_pages
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_images_key ON #fixed_images (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_legal'', ''U'') IS NOT NULL DROP TABLE #fixed_legal;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_legal
    FROM dbo.corrections_legal
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_legal_key ON #fixed_legal (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_names'', ''U'') IS NOT NULL DROP TABLE #fixed_names;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_names
    FROM dbo.corrections_parties
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_names_key ON #fixed_names (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_reference'', ''U'') IS NOT NULL DROP TABLE #fixed_reference;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_reference
    FROM dbo.corrections_instrument_references
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_reference_key ON #fixed_reference (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_inst_types'', ''U'') IS NOT NULL DROP TABLE #fixed_inst_types;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_inst_types
    FROM dbo.corrections_instrument_types_dq
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_inst_types_key ON #fixed_inst_types (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_additions'', ''U'') IS NOT NULL DROP TABLE #fixed_additions;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_additions
    FROM dbo.corrections_additions_dq
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_additions_key ON #fixed_additions (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_record_series'', ''U'') IS NOT NULL DROP TABLE #fixed_record_series;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_record_series
    FROM dbo.corrections_record_series_dq
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_record_series_key ON #fixed_record_series (error_key, source_row_id);

    IF OBJECT_ID(''tempdb..#fixed_township_range'', ''U'') IS NOT NULL DROP TABLE #fixed_township_range;
    SELECT imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed
    INTO #fixed_township_range
    FROM dbo.corrections_township_range_dq
    WHERE imported_by_user_id = @ImportedByUserId AND state_fips = @StateFips AND county_fips = @CountyFips AND ISNULL(is_fixed, 0) = 1
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR ISNULL(import_batch_id, '''') = @scope_import_batch_id);
    CREATE INDEX IX_fixed_township_range_key ON #fixed_township_range (error_key, source_row_id);

    DECLARE @page_digits INT = 4;
    DECLARE @split_book_start INT = NULL;
    DECLARE @split_book_end INT = NULL;
    DECLARE @has_split_book_range BIT = 0;
    IF OBJECT_ID(''dbo.county_work_items'', ''U'') IS NOT NULL
       AND COL_LENGTH(''dbo.county_work_items'', ''split_book_start'') IS NOT NULL
       AND COL_LENGTH(''dbo.county_work_items'', ''split_book_end'') IS NOT NULL
    BEGIN
        SELECT TOP 1
            @split_book_start = TRY_CONVERT(INT, cwi.split_book_start),
            @split_book_end = TRY_CONVERT(INT, cwi.split_book_end)
        FROM dbo.county_work_items cwi
        WHERE cwi.county_fips = @CountyFips
          AND ISNULL(cwi.is_split_job, 0) = 1;
        IF @split_book_start IS NOT NULL
           AND @split_book_end IS NOT NULL
           AND @split_book_start > 0
           AND @split_book_end >= @split_book_start
        BEGIN
            SET @has_split_book_range = 1;
        END;
    END;

    -- -------------------------------------------------------------------------
    -- 3) Header normalization: auto-derive record series internal id from
    --    header year when a keli record series match exists.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_record_series'', ''U'') IS NOT NULL
    BEGIN
        ;WITH rs_match AS (
            SELECT DISTINCT
                LTRIM(RTRIM(ISNULL(rs.[year], ''''))) AS series_prefix,
                CAST(k.id AS VARCHAR(1000)) AS rs_id
            FROM dbo.gdi_record_series rs
            JOIN dbo.keli_record_series k
              ON UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(rs.[year], ''''))))
            WHERE rs.imported_by_user_id = @ImportedByUserId
              AND rs.state_fips = @StateFips
              AND rs.county_fips = @CountyFips
              AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(rs.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
              AND ISNULL(rs.is_deleted, 0) = 0
              AND LTRIM(RTRIM(ISNULL(rs.[year], ''''))) <> ''''
        )
        UPDATE rs
        SET rs.record_series_internal_id = m.rs_id
        FROM dbo.gdi_record_series rs
        JOIN rs_match m
          ON m.series_prefix = LTRIM(RTRIM(ISNULL(rs.[year], '''')))
        WHERE rs.imported_by_user_id = @ImportedByUserId
          AND rs.state_fips = @StateFips
          AND rs.county_fips = @CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(rs.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(rs.is_deleted, 0) = 0;
    END;

    IF OBJECT_ID(''tempdb..#scope_header'', ''U'') IS NOT NULL
        DROP TABLE #scope_header;
    SELECT
        h.id,
        h.imported_by_user_id,
        h.state_fips,
        h.county_fips,
        h.is_deleted,
        h.header_file_key,
        h.file_key,
        h.col01varchar,
        h.col02varchar,
        h.col04varchar,
        h.col05varchar,
        h.col06varchar,
        h.book,
        h.beginning_page,
        h.ending_page,
        CASE
            WHEN @has_split_book_range = 1
                 AND TRY_CONVERT(INT, CASE
                        WHEN RIGHT(LTRIM(RTRIM(ISNULL(h.book, ''''))), 1) LIKE ''[A-Z]''
                             AND LEN(LTRIM(RTRIM(ISNULL(h.book, '''')))) > 1
                            THEN LEFT(LTRIM(RTRIM(ISNULL(h.book, ''''))), LEN(LTRIM(RTRIM(ISNULL(h.book, '''')))) - 1)
                        ELSE LTRIM(RTRIM(ISNULL(h.book, '''')))
                    END) BETWEEN @split_book_start AND @split_book_end
                THEN 1
            ELSE 0
        END AS is_split_book
    INTO #scope_header
    FROM dbo.gdi_instruments h
    WHERE h.imported_by_user_id=@ImportedByUserId
      AND h.state_fips=@StateFips
      AND h.county_fips=@CountyFips
      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(h.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
      AND ISNULL(h.is_deleted,0)=0;
    CREATE CLUSTERED INDEX IX_scope_header_id ON #scope_header (id);
    CREATE INDEX IX_scope_header_book_page ON #scope_header (book, beginning_page);
