/* ============================================================================
   Module: Data Quality Corrections
   Purpose:
   - Create/maintain correction queue tables by source domain (header/images/etc).
   - Create audit table for correction workflow activity.
   - Build scan stored procedure that repopulates pending issues by scope.
   Notes:
   - Script is idempotent and safe to rerun.
   ============================================================================ */

/* ----------------------------------------------------------------------------
   Section 0: Rename legacy DQ tables to the new split-aligned names
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_instruments', 'U') IS NULL
   AND OBJECT_ID('dbo.corrections_header', 'U') IS NOT NULL
    EXEC sys.sp_rename N'dbo.corrections_header', N'corrections_instruments';

IF OBJECT_ID('dbo.corrections_pages', 'U') IS NULL
   AND OBJECT_ID('dbo.corrections_images', 'U') IS NOT NULL
    EXEC sys.sp_rename N'dbo.corrections_images', N'corrections_pages';

IF OBJECT_ID('dbo.corrections_parties', 'U') IS NULL
   AND OBJECT_ID('dbo.corrections_names', 'U') IS NOT NULL
    EXEC sys.sp_rename N'dbo.corrections_names', N'corrections_parties';

IF OBJECT_ID('dbo.corrections_instrument_references', 'U') IS NULL
   AND OBJECT_ID('dbo.corrections_reference', 'U') IS NOT NULL
    EXEC sys.sp_rename N'dbo.corrections_reference', N'corrections_instrument_references';

/* ----------------------------------------------------------------------------
   Section A: Header correction queue table and legacy column/index backfills
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_instruments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instruments (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_header_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_header_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_header_snapshot DEFAULT '',
        new_col02varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c02 DEFAULT '',
        new_col03varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c03 DEFAULT '',
        new_col04varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c04 DEFAULT '',
        new_col05varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c05 DEFAULT '',
        new_col06varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c06 DEFAULT '',
        new_col07varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c07 DEFAULT '',
        new_col08varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c08 DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_header_fixed DEFAULT (0),
        resolution_action VARCHAR(50) NOT NULL CONSTRAINT DF_corr_header_resolution DEFAULT '',
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_header_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_header_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_header_scope ON dbo.corrections_instruments (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_header_scope_source ON dbo.corrections_instruments (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;

IF COL_LENGTH('dbo.corrections_instruments', 'new_col02varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col02varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c02_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'new_col03varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col03varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c03_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'new_col04varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col04varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c04_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'new_col05varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col05varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c05_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'new_col06varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col06varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c06_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'new_col07varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col07varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c07_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'new_col08varchar') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD new_col08varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_header_new_c08_legacy DEFAULT '';
IF COL_LENGTH('dbo.corrections_instruments', 'resolution_action') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD resolution_action VARCHAR(50) NOT NULL CONSTRAINT DF_corr_header_resolution_legacy DEFAULT '';
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_corr_header_scope_source'
      AND object_id = OBJECT_ID('dbo.corrections_instruments')
)
    CREATE INDEX IX_corr_header_scope_source ON dbo.corrections_instruments (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);

/* ----------------------------------------------------------------------------
   Section B: Images correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_pages', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_pages (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_images_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_images_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_images_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_images_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_images_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_images_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_images_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_images_scope ON dbo.corrections_pages (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_images_scope_source ON dbo.corrections_pages (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_corr_images_scope_source'
      AND object_id = OBJECT_ID('dbo.corrections_pages')
)
    CREATE INDEX IX_corr_images_scope_source ON dbo.corrections_pages (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);

/* ----------------------------------------------------------------------------
   Section C: Legal correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_legal', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_legal (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_legal_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_legal_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_legal_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_legal_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_legal_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_legal_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_legal_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_legal_scope ON dbo.corrections_legal (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_legal_scope_source ON dbo.corrections_legal (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_corr_legal_scope_source'
      AND object_id = OBJECT_ID('dbo.corrections_legal')
)
    CREATE INDEX IX_corr_legal_scope_source ON dbo.corrections_legal (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);

/* ----------------------------------------------------------------------------
   Section D: Names correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_parties', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_parties (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_names_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_names_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_names_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_names_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_names_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_names_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_names_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_names_scope ON dbo.corrections_parties (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_names_scope_source ON dbo.corrections_parties (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_corr_names_scope_source'
      AND object_id = OBJECT_ID('dbo.corrections_parties')
)
    CREATE INDEX IX_corr_names_scope_source ON dbo.corrections_parties (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);

/* ----------------------------------------------------------------------------
   Section E: Reference correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_instrument_references', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instrument_references (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_ref_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_ref_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_ref_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_ref_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_ref_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_ref_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_ref_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_ref_scope ON dbo.corrections_instrument_references (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_ref_scope_source ON dbo.corrections_instrument_references (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_corr_ref_scope_source'
      AND object_id = OBJECT_ID('dbo.corrections_instrument_references')
)
    CREATE INDEX IX_corr_ref_scope_source ON dbo.corrections_instrument_references (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);

/* ----------------------------------------------------------------------------
   Section F: Instrument Types correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_instrument_types_dq', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instrument_types_dq (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_it_dq_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_it_dq_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_it_dq_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_it_dq_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_it_dq_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_it_dq_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it_dq_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_it_dq_scope ON dbo.corrections_instrument_types_dq (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_it_dq_scope_source ON dbo.corrections_instrument_types_dq (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;

/* ----------------------------------------------------------------------------
   Section G: Additions correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_additions_dq', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_additions_dq (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_add_dq_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_add_dq_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add_dq_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_add_dq_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_add_dq_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_add_dq_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add_dq_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_add_dq_scope ON dbo.corrections_additions_dq (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_add_dq_scope_source ON dbo.corrections_additions_dq (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;

/* ----------------------------------------------------------------------------
   Section H: Record Series correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_record_series_dq', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_record_series_dq (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_rs_dq_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_rs_dq_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_rs_dq_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_rs_dq_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_rs_dq_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_rs_dq_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_rs_dq_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_rs_dq_scope ON dbo.corrections_record_series_dq (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_rs_dq_scope_source ON dbo.corrections_record_series_dq (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;

/* ----------------------------------------------------------------------------
   Section I: Township/Range correction queue table
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_township_range_dq', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_township_range_dq (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id INT NULL,
        error_key VARCHAR(100) NOT NULL,
        error_label VARCHAR(200) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_tr_dq_hfk DEFAULT '',
        file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_corr_tr_dq_fk DEFAULT '',
        col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_tr_dq_c01 DEFAULT '',
        snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_corr_tr_dq_snapshot DEFAULT '',
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_tr_dq_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_corr_tr_dq_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_tr_dq_created DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NULL,
        updated_by_user_id INT NULL
    );
    CREATE INDEX IX_corr_tr_dq_scope ON dbo.corrections_township_range_dq (imported_by_user_id, state_fips, county_fips, is_fixed, error_key);
    CREATE INDEX IX_corr_tr_dq_scope_source ON dbo.corrections_township_range_dq (imported_by_user_id, state_fips, county_fips, error_key, source_row_id, is_fixed);
END;

IF COL_LENGTH('dbo.corrections_instruments', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_instruments ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_pages', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_pages ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_legal', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_legal ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_parties', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_parties ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_instrument_references', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_instrument_references ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_instrument_types_dq', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_instrument_types_dq ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_additions_dq', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_additions_dq ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_record_series_dq', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_record_series_dq ADD import_batch_id VARCHAR(36) NULL;
IF COL_LENGTH('dbo.corrections_township_range_dq', 'import_batch_id') IS NULL
    ALTER TABLE dbo.corrections_township_range_dq ADD import_batch_id VARCHAR(36) NULL;

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
      AND ISNULL(h.is_deleted,0)=0;
    CREATE CLUSTERED INDEX IX_scope_header_id ON #scope_header (id);
    CREATE INDEX IX_scope_header_book_page ON #scope_header (book, beginning_page);

    -- -------------------------------------------------------------------------
    -- 4) Header issue detection block
    -- -------------------------------------------------------------------------

    -- 4.1 Duplicate book + beginning page
    ;WITH header_dups AS (
        SELECT
            h.id,
            h.header_file_key,
            h.file_key,
            h.col01varchar,
            h.col02varchar,
            h.col04varchar,
            h.col05varchar,
            h.col06varchar,
            h.book,
            h.beginning_page,
            COUNT(1) OVER (PARTITION BY ISNULL(h.book, ''''), ISNULL(h.beginning_page, '''')) AS dup_count
        FROM #scope_header h
        WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
    )
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerDuplicateBookPageNumber'', ''Duplicate book + beginning page.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''book='', ISNULL(h.book, ''''), ''; beginning_page='', ISNULL(h.beginning_page, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM header_dups h
    WHERE h.dup_count > 1
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerDuplicateBookPageNumber''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.2 Blank instrument number in col02varchar
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerDuplicateInstrumentNumber'', ''Instrument number (col02varchar) is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''col02varchar is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))=''''
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerDuplicateInstrumentNumber''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.3 (moved) record series lookup checks now populate corrections_record_series_dq

    -- 4.4 Non numeric beginning_page
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerNonNumericPageNumber'', ''Page number contains non-numeric characters.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''beginning_page='', ISNULL(h.beginning_page, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))<>''''
      AND (
          (ISNULL(h.is_split_book, 0) = 0
            AND TRY_CONVERT(BIGINT, REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))),''-'',''''),''_'',''''),''.'','''')) IS NULL
          )
          OR
          (ISNULL(h.is_split_book, 0) = 1
            AND NOT (
                (
                    LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 4
                    AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) IS NOT NULL
                )
                OR
                (
                    LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 5
                    AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 4)) IS NOT NULL
                    AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 1) LIKE ''[A-Z]''
                )
            )
          )
      )
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerNonNumericPageNumber''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.5 Invalid book range
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerValidBookRange'', ''Book number outside valid range.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''book='', ISNULL(h.book, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND (TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(h.book,''''))),'''')) IS NULL OR TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(h.book,''''))),'''')) NOT BETWEEN 1 AND 999999)
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerValidBookRange''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.6 Missing beginning_page
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingBeginningPageNumber'', ''Beginning page number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''beginning_page is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingBeginningPageNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.7 Missing book
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingBookNumber'', ''Book number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''book is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.book,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingBookNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.8 Missing instrument number
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingInstrumentNumber'', ''Instrument number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''col02varchar is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingInstrumentNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.9 Non numeric instrument number
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerNonNumericInstrumentNumber'', ''Instrument number is non-numeric.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(h.col02varchar, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))<>''''
      AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) IS NULL
      AND NOT (
          RIGHT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), 1) LIKE ''[A-Z]''
          AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) - 1)) IS NOT NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerNonNumericInstrumentNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.10 Unexpected alpha suffix instrument number format
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerInstrumentNumberSixDigits'', ''Instrument number suffix format is unexpected.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(h.col02varchar, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND RIGHT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), 1) LIKE ''[A-Z]''
      AND (
          LEN(LEFT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) - 1)) <> 6
          OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) - 1)) IS NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerInstrumentNumberSixDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.11 (moved) record series id checks now populate corrections_record_series_dq

    -- 4.12 Missing ending_page
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingEndingPageNumber'', ''Ending page number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''ending_page is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.ending_page,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingEndingPageNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.13 Book is not six-digit numeric
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerBookSixDigits'', ''Book number should be 6 digits.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''book='', ISNULL(h.book, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.book,'''')))<>''''
      AND (
          LEN(LTRIM(RTRIM(ISNULL(h.book,'''')))) <> 6
          OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.book,'''')))) IS NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerBookSixDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.14 Beginning page length/format check
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerBeginningPageFourDigits'', ''Beginning page should be fixed-length numeric by county split-image setting.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''beginning_page='', ISNULL(h.beginning_page, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))<>''''
      AND (
          (ISNULL(h.is_split_book, 0) = 0 AND (
              LEN(LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) <> @page_digits
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) IS NULL
          ))
          OR
          (ISNULL(h.is_split_book, 0) = 1 AND NOT (
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 4
                  AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) IS NOT NULL
              )
              OR
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 5
                  AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 4)) IS NOT NULL
                  AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 1) LIKE ''[A-Z]''
              )
          ))
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerBeginningPageFourDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.15 Ending page length/format check
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerEndingPageFourDigits'', ''Ending page should be fixed-length numeric by county split-image setting.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''ending_page='', ISNULL(h.ending_page, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.ending_page,'''')))<>''''
      AND (
          (ISNULL(h.is_split_book, 0) = 0 AND (
              LEN(LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) <> @page_digits
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) IS NULL
          ))
          OR
          (ISNULL(h.is_split_book, 0) = 1 AND NOT (
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END) = 4
                  AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END) IS NOT NULL
              )
              OR
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END) = 5
                  AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END, 4)) IS NOT NULL
                  AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END, 1) LIKE ''[A-Z]''
              )
          ))
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerEndingPageFourDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- -------------------------------------------------------------------------
    -- 5) Names issue detection block
    -- -------------------------------------------------------------------------
    -- 5.1 Duplicate party rows:
    --     duplicate only when same instrument + same party type + same party name.
    --     Grantor vs Grantee with same name is NOT a duplicate.
    ;WITH normalized_party_rows AS (
        SELECT
            n.id,
            n.header_file_key,
            n.file_key,
            n.col01varchar,
            n.col02varchar,
            n.col03varchar,
            ISNULL(
                NULLIF(LTRIM(RTRIM(ISNULL(n.header_file_key, ''''))), ''''),
                ISNULL(
                    NULLIF(LTRIM(RTRIM(ISNULL(n.file_key, ''''))), ''''),
                    LTRIM(RTRIM(ISNULL(n.fn, '''')))
                )
            ) AS instrument_scope_key,
            UPPER(LTRIM(RTRIM(ISNULL(n.col02varchar, '''')))) AS norm_party_type,
            UPPER(LTRIM(RTRIM(ISNULL(n.col03varchar, '''')))) AS norm_party_name
        FROM dbo.gdi_parties n
        WHERE n.imported_by_user_id=@ImportedByUserId
          AND n.state_fips=@StateFips
          AND n.county_fips=@CountyFips
          AND ISNULL(n.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(n.col01varchar,'''')))<>''''
          AND LTRIM(RTRIM(ISNULL(n.col03varchar,'''')))<>''''
    ),
    name_dups AS (
        SELECT
            n.id,
            n.header_file_key,
            n.file_key,
            n.col01varchar,
            n.col02varchar,
            n.col03varchar,
            COUNT(1) OVER (
                PARTITION BY
                    n.instrument_scope_key,
                    ISNULL(n.col01varchar, ''''),
                    n.norm_party_type,
                    n.norm_party_name
            ) AS dup_count
        FROM normalized_party_rows n
        WHERE n.instrument_scope_key <> ''''
          AND n.norm_party_type <> ''''
          AND n.norm_party_name <> ''''
    )
    INSERT INTO dbo.corrections_parties (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
    SELECT n.id, ''nameDuplicateNames'', ''Duplicate name rows.'', ISNULL(n.header_file_key,''''), ISNULL(n.file_key,''''), ISNULL(n.col01varchar,''''), CONCAT(''type='', ISNULL(n.col02varchar, ''''), ''; name='', ISNULL(n.col03varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
    FROM name_dups n
    WHERE n.dup_count > 1
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_names cn
          WHERE cn.imported_by_user_id=@ImportedByUserId
            AND cn.state_fips=@StateFips
            AND cn.county_fips=@CountyFips
            AND cn.error_key=''nameDuplicateNames''
            AND cn.source_row_id=n.id
            AND ISNULL(cn.is_fixed,0)=1
      );

    -- -------------------------------------------------------------------------
    -- 6) Images issue detection block
    --    Supports either gdi_pages or legacy gdi_pages table name.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''tempdb..#scope_images'', ''U'') IS NOT NULL
        DROP TABLE #scope_images;
    CREATE TABLE #scope_images (
        id INT NOT NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL,
        is_split_book BIT NOT NULL,
        header_file_key NVARCHAR(260) NULL,
        file_key NVARCHAR(260) NULL,
        col01varchar VARCHAR(1000) NULL,
        col02varchar VARCHAR(1000) NULL,
        col03varchar VARCHAR(1000) NULL,
        book VARCHAR(1000) NULL,
        page_number VARCHAR(1000) NULL
    );
    CREATE CLUSTERED INDEX IX_scope_images_id ON #scope_images (id);
    CREATE INDEX IX_scope_images_book_page ON #scope_images (book, page_number);

    IF OBJECT_ID(''dbo.gdi_pages'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_images (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, col02varchar, col03varchar, book, page_number
        )
        SELECT
            i.id,
            i.imported_by_user_id,
            i.state_fips,
            i.county_fips,
            i.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(i.book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(i.book, ''''))), LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(i.book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            i.header_file_key,
            i.file_key,
            i.col01varchar,
            i.col02varchar,
            i.col03varchar,
            i.book,
            i.page_number
        FROM dbo.gdi_pages i
        WHERE i.imported_by_user_id=@ImportedByUserId
          AND i.state_fips=@StateFips
          AND i.county_fips=@CountyFips
          AND ISNULL(i.is_deleted,0)=0;

        -- 6.1 Duplicate image book + page
        ;WITH image_dups AS (
            SELECT
                i.id,
                i.header_file_key,
                i.file_key,
                i.col01varchar,
                i.book,
                i.page_number,
                COUNT(1) OVER (PARTITION BY ISNULL(i.book, ''''), ISNULL(i.page_number, '''')) AS dup_count
            FROM #scope_images i
            WHERE 1=1
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageDuplicateBookPageNumber'', ''Duplicate image book+page combination.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, ''''), ''; page='', ISNULL(i.page_number, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM image_dups i
        WHERE i.dup_count > 1
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageDuplicateBookPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.2 Image path book segment length/format issues
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageIncorrectBookLength'', ''Image path book part is not 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col03varchar='', ISNULL(i.col03varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (
              LEN(LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) <> 6
              OR TRY_CONVERT(INT, LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectBookLength'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.3 Page length profile anomalies
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256) AS page_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256)) AS page_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT page_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY page_len
        ),
        dominant AS (
            SELECT TOP 1 page_len AS dominant_len
            FROM freq
            WHERE page_len > 0
            ORDER BY cnt DESC, page_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE page_len > 0
        ),
        major AS (
            SELECT f.page_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.page_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.page_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.page_value) AS page_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.page_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPageLength'',
            ''Image page_number length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_page_number='', s.page_value,
                ''; page_len='', CAST(s.page_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.page_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.page_len = s.page_len))
            OR (mc.major_groups < 2 AND s.page_len > 0 AND s.page_len <> ISNULL(d.dominant_len, s.page_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPageLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.4 Path length profile anomalies
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512) AS path_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512)) AS path_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT path_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY path_len
        ),
        dominant AS (
            SELECT TOP 1 path_len AS dominant_len
            FROM freq
            WHERE path_len > 0
            ORDER BY cnt DESC, path_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE path_len > 0
        ),
        major AS (
            SELECT f.path_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.path_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.path_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.path_value) AS path_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.path_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPathLength'',
            ''Image path length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_referenced_page='', s.path_value,
                ''; path_len='', CAST(s.path_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.path_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.path_len = s.path_len))
            OR (mc.major_groups < 2 AND s.path_len > 0 AND s.path_len <> ISNULL(d.dominant_len, s.path_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPathLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.5 Non numeric page number values
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericPageNumber'', ''Image page number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(i.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) IS NULL
          AND NOT (
              RIGHT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), 1) LIKE ''[A-Z]''
              AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) - 1)) IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.6 Non numeric book
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericBookNumber'', ''Image book number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.7 Missing book
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingBookNumber'', ''Image book number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.8 Missing page
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingPageNumber'', ''Image page number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''page_number is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.9 Book range
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageValidBookRange'', ''Image book number outside valid range.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) IS NULL OR TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) NOT BETWEEN 1 AND 999999)
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageValidBookRange'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.10 Book should be six digits
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageBookSixDigits'', ''Image book should be 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND (
              LEN(LTRIM(RTRIM(ISNULL(i.book,'''')))) <> 6
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageBookSixDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.11 Page should be fixed-length numeric by split-image setting
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imagePageFourDigits'', ''Image page should be fixed-length numeric by county split-image setting.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''page_number='', ISNULL(i.page_number, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))<>''''
          AND (
              (ISNULL(i.is_split_book, 0) = 0 AND (
                  LEN(LTRIM(RTRIM(ISNULL(i.page_number,'''')))) <> @page_digits
                  OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.page_number,'''')))) IS NULL
              ))
              OR
              (ISNULL(i.is_split_book, 0) = 1 AND NOT (
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 4
                      AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) IS NOT NULL
                  )
                  OR
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 5
                      AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 4)) IS NOT NULL
                      AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 1) LIKE ''[A-Z]''
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imagePageFourDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );
    END;
    ELSE IF OBJECT_ID(''dbo.gdi_pages'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_images (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, col02varchar, col03varchar, book, page_number
        )
        SELECT
            i.id,
            i.imported_by_user_id,
            i.state_fips,
            i.county_fips,
            i.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(i.book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(i.book, ''''))), LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(i.book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            i.header_file_key,
            i.file_key,
            i.col01varchar,
            i.col02varchar,
            i.col03varchar,
            i.book,
            i.page_number
        FROM dbo.gdi_pages i
        WHERE i.imported_by_user_id=@ImportedByUserId
          AND i.state_fips=@StateFips
          AND i.county_fips=@CountyFips
          AND ISNULL(i.is_deleted,0)=0;

        -- 6.1 Duplicate image book + page (legacy table)
        ;WITH image_dups AS (
            SELECT
                i.id,
                i.header_file_key,
                i.file_key,
                i.col01varchar,
                i.book,
                i.page_number,
                COUNT(1) OVER (PARTITION BY ISNULL(i.book, ''''), ISNULL(i.page_number, '''')) AS dup_count
            FROM #scope_images i
            WHERE 1=1
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageDuplicateBookPageNumber'', ''Duplicate image book+page combination.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, ''''), ''; page='', ISNULL(i.page_number, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM image_dups i
        WHERE i.dup_count > 1
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageDuplicateBookPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.2 Image path book segment length/format issues (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageIncorrectBookLength'', ''Image path book part is not 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col03varchar='', ISNULL(i.col03varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (
              LEN(LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) <> 6
              OR TRY_CONVERT(INT, LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectBookLength'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.3 Page length profile anomalies (legacy table)
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256) AS page_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256)) AS page_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT page_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY page_len
        ),
        dominant AS (
            SELECT TOP 1 page_len AS dominant_len
            FROM freq
            WHERE page_len > 0
            ORDER BY cnt DESC, page_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE page_len > 0
        ),
        major AS (
            SELECT f.page_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.page_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.page_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.page_value) AS page_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.page_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPageLength'',
            ''Image page_number length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_page_number='', s.page_value,
                ''; page_len='', CAST(s.page_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.page_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.page_len = s.page_len))
            OR (mc.major_groups < 2 AND s.page_len > 0 AND s.page_len <> ISNULL(d.dominant_len, s.page_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPageLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.4 Path length profile anomalies (legacy table)
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512) AS path_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512)) AS path_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT path_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY path_len
        ),
        dominant AS (
            SELECT TOP 1 path_len AS dominant_len
            FROM freq
            WHERE path_len > 0
            ORDER BY cnt DESC, path_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE path_len > 0
        ),
        major AS (
            SELECT f.path_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.path_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.path_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.path_value) AS path_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.path_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPathLength'',
            ''Image path length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_referenced_page='', s.path_value,
                ''; path_len='', CAST(s.path_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.path_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.path_len = s.path_len))
            OR (mc.major_groups < 2 AND s.path_len > 0 AND s.path_len <> ISNULL(d.dominant_len, s.path_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPathLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.5 Non numeric page number values (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericPageNumber'', ''Image page number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(i.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) IS NULL
          AND NOT (
              RIGHT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), 1) LIKE ''[A-Z]''
              AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) - 1)) IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.6 Non numeric book (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericBookNumber'', ''Image book number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.7 Missing book (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingBookNumber'', ''Image book number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.8 Missing page (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingPageNumber'', ''Image page number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''page_number is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.9 Book range (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageValidBookRange'', ''Image book number outside valid range.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) IS NULL OR TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) NOT BETWEEN 1 AND 999999)
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageValidBookRange'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.10 Book should be six digits (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageBookSixDigits'', ''Image book should be 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND (
              LEN(LTRIM(RTRIM(ISNULL(i.book,'''')))) <> 6
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageBookSixDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.11 Page should be fixed-length numeric by split-image setting (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imagePageFourDigits'', ''Image page should be fixed-length numeric by county split-image setting.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''page_number='', ISNULL(i.page_number, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))<>''''
          AND (
              (ISNULL(i.is_split_book, 0) = 0 AND (
                  LEN(LTRIM(RTRIM(ISNULL(i.page_number,'''')))) <> @page_digits
                  OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.page_number,'''')))) IS NULL
              ))
              OR
              (ISNULL(i.is_split_book, 0) = 1 AND NOT (
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 4
                      AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) IS NOT NULL
                  )
                  OR
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 5
                      AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 4)) IS NOT NULL
                      AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 1) LIKE ''[A-Z]''
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imagePageFourDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );
    END;

    IF OBJECT_ID(''tempdb..#scope_header_books'', ''U'') IS NOT NULL
        DROP TABLE #scope_header_books;
    CREATE TABLE #scope_header_books (
        book6 CHAR(6) NOT NULL PRIMARY KEY
    );
    INSERT INTO #scope_header_books (book6)
    SELECT DISTINCT RIGHT(''000000'' + LTRIM(RTRIM(ISNULL(h.book, ''''))), 6)
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId
      AND h.state_fips=@StateFips
      AND h.county_fips=@CountyFips
      AND ISNULL(h.is_deleted,0)=0;

    -- -------------------------------------------------------------------------
    -- 7) Legal issue detection block
    --    Supports either gdi_legals or legacy gdi_legal table name.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_legals'', ''U'') IS NOT NULL
    BEGIN
        -- 7.1 (moved) township/range lookup checks now populate corrections_township_range_dq

        -- 7.2 Quarter section token outside allowed set
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeQuarterSections'', ''Quarter section value is outside allowed set.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col08='', ISNULL(l.col08varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legals l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))<>''''
          AND UPPER(LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))) NOT IN (''N2'',''S2'',''E2'',''W2'',''NE'',''NW'',''SE'',''SW'',''N'',''S'',''E'',''W'')
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeQuarterSections'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );

        -- 7.3 Section value not numeric or out of 1..36
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeSection'', ''Section value is outside allowed range.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col02='', ISNULL(l.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legals l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))<>''''
          AND (
              LTRIM(RTRIM(ISNULL(l.col02varchar,''''))) = ''?''
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) IS NULL
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) NOT BETWEEN 1 AND 36
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeSection'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );
    END;
    ELSE IF OBJECT_ID(''dbo.gdi_legal'', ''U'') IS NOT NULL
    BEGIN
        -- 7.1 (moved) township/range lookup checks now populate corrections_township_range_dq

        -- 7.2 Quarter section token outside allowed set (legacy table)
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeQuarterSections'', ''Quarter section value is outside allowed set.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col08='', ISNULL(l.col08varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legal l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))<>''''
          AND UPPER(LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))) NOT IN (''N2'',''S2'',''E2'',''W2'',''NE'',''NW'',''SE'',''SW'',''N'',''S'',''E'',''W'')
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeQuarterSections'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );

        -- 7.3 Section value not numeric or out of 1..36 (legacy table)
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeSection'', ''Section value is outside allowed range.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col02='', ISNULL(l.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legal l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))<>''''
          AND (
              LTRIM(RTRIM(ISNULL(l.col02varchar,''''))) = ''?''
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) IS NULL
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) NOT BETWEEN 1 AND 36
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeSection'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 8) Reference issue detection block
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''tempdb..#scope_reference'', ''U'') IS NOT NULL
        DROP TABLE #scope_reference;
    CREATE TABLE #scope_reference (
        id INT NOT NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL,
        is_split_book BIT NOT NULL,
        header_file_key NVARCHAR(260) NULL,
        file_key NVARCHAR(260) NULL,
        col01varchar VARCHAR(1000) NULL,
        referenced_book VARCHAR(1000) NULL,
        referenced_page VARCHAR(1000) NULL
    );
    CREATE CLUSTERED INDEX IX_scope_reference_id ON #scope_reference (id);
    CREATE INDEX IX_scope_reference_book_page ON #scope_reference (referenced_book, referenced_page);

    IF OBJECT_ID(''dbo.gdi_instrument_references'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_reference (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, referenced_book, referenced_page
        )
        SELECT
            r.id,
            r.imported_by_user_id,
            r.state_fips,
            r.county_fips,
            r.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            r.header_file_key,
            r.file_key,
            r.col01varchar,
            r.referenced_book,
            r.referenced_page
        FROM dbo.gdi_instrument_references r
        WHERE r.imported_by_user_id=@ImportedByUserId
          AND r.state_fips=@StateFips
          AND r.county_fips=@CountyFips
          AND ISNULL(r.is_deleted,0)=0;

        -- 8.1 Recorded reference book is outside the books seen in header scope
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refRecordedNotWithinBookRange'', ''Reference recorded book does not match any header book in scope.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, ''''), ''; referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM #scope_header_books hb
              WHERE hb.book6 = RIGHT(''000000'' +
                                     CASE
                                         WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                              AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                             THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                                         ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                                     END, 6)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refRecordedNotWithinBookRange'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.2 Reference book should be six digits with optional one suffix
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refBookSixDigits'', ''Reference book should be 6 digits.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                  AND (
                      LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) <> 6
                      OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL
                  )
              )
              OR (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
                  AND (
                      LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) <> 6
                      OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL
                  )
              )
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refBookSixDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.3 Reference page should be four digits with optional one suffix
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refPageFourDigits'', ''Reference page should be 4 digits (optional one suffix).'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) <> 4
                          OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL
                      )
                  )
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) <> 4
                          OR TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL
                      )
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refPageFourDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.4 Missing reference book
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingBookNumber'', ''Reference book is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.5 Missing reference page
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingPageNumber'', ''Reference page is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_page is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.6 Non numeric reference book
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericBookNumber'', ''Reference book contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL)
              OR
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.7 Non numeric reference page
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericPageNumber'', ''Reference page contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL)
                  OR
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL)
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL)
                  OR
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL)
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );
    END;
    ELSE IF OBJECT_ID(''dbo.gdi_instrument_references'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_reference (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, referenced_book, referenced_page
        )
        SELECT
            r.id,
            r.imported_by_user_id,
            r.state_fips,
            r.county_fips,
            r.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            r.header_file_key,
            r.file_key,
            r.col01varchar,
            r.referenced_book,
            r.referenced_page
        FROM dbo.gdi_instrument_references r
        WHERE r.imported_by_user_id=@ImportedByUserId
          AND r.state_fips=@StateFips
          AND r.county_fips=@CountyFips
          AND ISNULL(r.is_deleted,0)=0;

        -- 8.1 Recorded reference book is outside the books seen in header scope (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refRecordedNotWithinBookRange'', ''Reference recorded book does not match any header book in scope.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, ''''), ''; referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM #scope_header_books hb
              WHERE hb.book6 = RIGHT(''000000'' +
                                     CASE
                                         WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                              AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                             THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                                         ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                                     END, 6)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refRecordedNotWithinBookRange'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.2 Reference book should be six digits with optional one suffix (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refBookSixDigits'', ''Reference book should be 6 digits.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                  AND (
                      LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) <> 6
                      OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL
                  )
              )
              OR (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
                  AND (
                      LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) <> 6
                      OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL
                  )
              )
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refBookSixDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.3 Reference page should be four digits with optional one suffix (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refPageFourDigits'', ''Reference page should be 4 digits (optional one suffix).'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) <> 4
                          OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL
                      )
                  )
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) <> 4
                          OR TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL
                      )
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refPageFourDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.4 Missing reference book (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingBookNumber'', ''Reference book is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.5 Missing reference page (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingPageNumber'', ''Reference page is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_page is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.6 Non numeric reference book (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericBookNumber'', ''Reference book contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL)
              OR
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.7 Non numeric reference page (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericPageNumber'', ''Reference page contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL)
                  OR
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL)
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL)
                  OR
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL)
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 9) Instrument Types issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_instrument_types'', ''U'') IS NOT NULL
       AND OBJECT_ID(''dbo.keli_instrument_types'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_instrument_types_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT it.id, ''instTypeMissingLookup'', ''Instrument type does not match keli lookup.'', ISNULL(it.header_file_key,''''), ISNULL(it.file_key,''''), ISNULL(it.col01varchar,''''), CONCAT(''original='', LTRIM(RTRIM(ISNULL(it.col03varchar, '''')))), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_instrument_types it
        WHERE it.imported_by_user_id=@ImportedByUserId AND it.state_fips=@StateFips AND it.county_fips=@CountyFips AND ISNULL(it.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(it.col03varchar, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.keli_instrument_types k
              WHERE LOWER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(1000)), '''')))) = LOWER(LTRIM(RTRIM(ISNULL(it.col03varchar, ''''))))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_inst_types ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''instTypeMissingLookup'' AND ci.source_row_id=it.id AND ISNULL(ci.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 10) Additions issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_additions'', ''U'') IS NOT NULL
       AND OBJECT_ID(''dbo.keli_additions'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_additions_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT a.id, ''additionMissingLookup'', ''Addition does not match keli lookup.'', ISNULL(a.header_file_key,''''), ISNULL(a.file_key,''''), ISNULL(a.col01varchar,''''), CONCAT(''original='', LTRIM(RTRIM(ISNULL(a.col05varchar, '''')))), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_additions a
        WHERE a.imported_by_user_id=@ImportedByUserId AND a.state_fips=@StateFips AND a.county_fips=@CountyFips AND ISNULL(a.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(a.col05varchar, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.keli_additions k
              WHERE RIGHT(''00'' + LTRIM(RTRIM(ISNULL(CAST(k.state_fips AS VARCHAR(1000)), ''''))), 2) = @StateFips
                AND RIGHT(''00000'' + LTRIM(RTRIM(ISNULL(CAST(k.county_fips AS VARCHAR(1000)), ''''))), 5) = @CountyFips
                AND LOWER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(1000)), '''')))) = LOWER(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_additions ca
              WHERE ca.imported_by_user_id=@ImportedByUserId AND ca.state_fips=@StateFips AND ca.county_fips=@CountyFips
                AND ca.error_key=''additionMissingLookup'' AND ca.source_row_id=a.id AND ISNULL(ca.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 11) Record Series issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_record_series'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_record_series_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT rs.id, ''recordSeriesMissingYear'', ''Record series year is blank.'', ISNULL(rs.header_file_key,''''), ISNULL(rs.file_key,''''), ISNULL(rs.col01varchar,''''), ''year is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_record_series rs
        WHERE rs.imported_by_user_id=@ImportedByUserId AND rs.state_fips=@StateFips AND rs.county_fips=@CountyFips AND ISNULL(rs.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(rs.[year], '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_record_series cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''recordSeriesMissingYear'' AND cr.source_row_id=rs.id AND ISNULL(cr.is_fixed,0)=1
          );

        IF OBJECT_ID(''dbo.keli_record_series'', ''U'') IS NOT NULL
        BEGIN
            INSERT INTO dbo.corrections_record_series_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
            SELECT rs.id, ''recordSeriesMissingLookup'', ''Record series year not found in keli_record_series.'', ISNULL(rs.header_file_key,''''), ISNULL(rs.file_key,''''), ISNULL(rs.col01varchar,''''), CONCAT(''year='', LTRIM(RTRIM(ISNULL(rs.[year], '''')))), @ImportedByUserId, @StateFips, @CountyFips
            FROM dbo.gdi_record_series rs
            WHERE rs.imported_by_user_id=@ImportedByUserId AND rs.state_fips=@StateFips AND rs.county_fips=@CountyFips AND ISNULL(rs.is_deleted,0)=0
              AND LTRIM(RTRIM(ISNULL(rs.[year], '''')))<>''''
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.keli_record_series k
                  WHERE UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(rs.[year], ''''))))
              )
              AND NOT EXISTS (
                  SELECT 1 FROM #fixed_record_series cr
                  WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                    AND cr.error_key=''recordSeriesMissingLookup'' AND cr.source_row_id=rs.id AND ISNULL(cr.is_fixed,0)=1
              );

            INSERT INTO dbo.corrections_record_series_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
            SELECT rs.id, ''recordSeriesIncorrectInternalId'', ''Record series internal id does not match year mapping.'', ISNULL(rs.header_file_key,''''), ISNULL(rs.file_key,''''), ISNULL(rs.col01varchar,''''), CONCAT(''year='', ISNULL(rs.[year], ''''), ''; record_series_internal_id='', ISNULL(rs.record_series_internal_id, '''')), @ImportedByUserId, @StateFips, @CountyFips
            FROM dbo.gdi_record_series rs
            JOIN dbo.keli_record_series k
              ON UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(rs.[year], ''''))))
            WHERE rs.imported_by_user_id=@ImportedByUserId AND rs.state_fips=@StateFips AND rs.county_fips=@CountyFips AND ISNULL(rs.is_deleted,0)=0
              AND LTRIM(RTRIM(ISNULL(rs.[year],'''')))<>''''
              AND ISNULL(rs.record_series_internal_id, '''') <> CAST(k.id AS VARCHAR(1000))
              AND NOT EXISTS (
                  SELECT 1 FROM #fixed_record_series cr
                  WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                    AND cr.error_key=''recordSeriesIncorrectInternalId'' AND cr.source_row_id=rs.id AND ISNULL(cr.is_fixed,0)=1
              );
        END;
    END;

    -- -------------------------------------------------------------------------
    -- 12) Township/Range issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_township_range'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_township_range_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT tr.id, ''townshipRangeMissingValues'', ''Township or range is blank.'', ISNULL(tr.header_file_key,''''), ISNULL(tr.file_key,''''), ISNULL(tr.col01varchar,''''), CONCAT(''township='', ISNULL(tr.col03varchar, ''''), ''; range='', ISNULL(tr.col04varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_township_range tr
        WHERE tr.imported_by_user_id=@ImportedByUserId AND tr.state_fips=@StateFips AND tr.county_fips=@CountyFips AND ISNULL(tr.is_deleted,0)=0
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(tr.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND (LTRIM(RTRIM(ISNULL(tr.col03varchar, '''')))='''' OR LTRIM(RTRIM(ISNULL(tr.col04varchar, '''')))='''')
          AND (
                OBJECT_ID(''dbo.gdi_additions'', ''U'') IS NULL
                OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.gdi_additions a
                    WHERE a.imported_by_user_id = tr.imported_by_user_id
                      AND a.state_fips = tr.state_fips
                      AND a.county_fips = tr.county_fips
                      AND ISNULL(a.is_deleted, 0) = 0
                      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(a.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
                      AND ISNULL(a.header_file_key, '''') = ISNULL(tr.header_file_key, '''')
                      AND ISNULL(a.col01varchar, '''') = ISNULL(tr.col01varchar, '''')
                      AND LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))) <> ''''
                )
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_township_range ct
              WHERE ct.imported_by_user_id=@ImportedByUserId AND ct.state_fips=@StateFips AND ct.county_fips=@CountyFips
                AND ct.error_key=''townshipRangeMissingValues'' AND ct.source_row_id=tr.id AND ISNULL(ct.is_fixed,0)=1
          );

        IF OBJECT_ID(''dbo.keli_township_ranges'', ''U'') IS NOT NULL
        BEGIN
            INSERT INTO dbo.corrections_township_range_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
            SELECT tr.id, ''townshipRangeOutOfCounty'', ''Township/Range not valid for county lookup.'', ISNULL(tr.header_file_key,''''), ISNULL(tr.file_key,''''), ISNULL(tr.col01varchar,''''), CONCAT(''township='', ISNULL(tr.col03varchar, ''''), ''; range='', ISNULL(tr.col04varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
            FROM dbo.gdi_township_range tr
            WHERE tr.imported_by_user_id=@ImportedByUserId AND tr.state_fips=@StateFips AND tr.county_fips=@CountyFips AND ISNULL(tr.is_deleted,0)=0
              AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(tr.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
              AND LTRIM(RTRIM(ISNULL(tr.col03varchar, ''''))) <> ''''
              AND LTRIM(RTRIM(ISNULL(tr.col04varchar, ''''))) <> ''''
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.keli_township_ranges ktr
                  WHERE UPPER(LTRIM(RTRIM(ISNULL(CAST(ktr.township AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(tr.col03varchar, ''''))))
                    AND UPPER(LTRIM(RTRIM(ISNULL(CAST(ktr.[range] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(tr.col04varchar, ''''))))
                    AND ISNULL(ktr.active, 0) = 1
              )
              AND NOT EXISTS (
                  SELECT 1 FROM #fixed_township_range ct
                  WHERE ct.imported_by_user_id=@ImportedByUserId AND ct.state_fips=@StateFips AND ct.county_fips=@CountyFips
                    AND ct.error_key=''townshipRangeOutOfCounty'' AND ct.source_row_id=tr.id AND ISNULL(ct.is_fixed,0)=1
              );
        END;
    END;

    IF ISNULL(@scope_import_batch_id, '''') <> ''''
    BEGIN
        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_instruments c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_pages c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_legal c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_parties c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_instrument_references c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_instrument_types_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_additions_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_record_series_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_township_range_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';
    END;

    -- -------------------------------------------------------------------------
    -- 13) Return pending counts for each correction queue
    -- -------------------------------------------------------------------------
    SELECT
        (SELECT COUNT(1) FROM dbo.corrections_instruments WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS header_count,
        (SELECT COUNT(1) FROM dbo.corrections_pages WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS images_count,
        (SELECT COUNT(1) FROM dbo.corrections_legal WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS legal_count,
        (SELECT COUNT(1) FROM dbo.corrections_parties WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS names_count,
        (SELECT COUNT(1) FROM dbo.corrections_instrument_references WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS reference_count,
        (SELECT COUNT(1) FROM dbo.corrections_instrument_types_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS instrument_types_count,
        (SELECT COUNT(1) FROM dbo.corrections_additions_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS additions_count,
        (SELECT COUNT(1) FROM dbo.corrections_record_series_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS record_series_count,
        (SELECT COUNT(1) FROM dbo.corrections_township_range_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS township_range_count;
END;');
