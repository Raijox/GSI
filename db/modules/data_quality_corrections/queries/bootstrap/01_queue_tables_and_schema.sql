/* ============================================================================
   File: 01_queue_tables_and_schema.sql
   Module: Data Quality Corrections
   Role in assembly:
   - First bootstrap fragment for the data quality corrections schema.
   - Creates or backfills the per-domain correction queue tables used by the
     integrated review UI.
   - Preserves legacy rename behavior so older installs still land on the split
     queue table names expected by the current application.
   What lives here:
   - Legacy table renames from old queue names to the current split-aligned
     queue names.
   - Queue table creation for instruments, pages, legal, parties, reference,
     instrument-types DQ, additions DQ, record-series DQ, and township-range DQ.
   - Import-batch backfill columns so pending/fixed rows can stay tied to a
     specific working import batch.
   Why this file exists:
   - These objects form the persistent storage contract for the tool, and they
     change much less often than the scan logic. Keeping them separate makes it
     easier to evolve queue structure without digging through the scan procedure.
   Maintenance notes:
   - Preserve idempotence. Every CREATE/ALTER block here must remain safe to run
     repeatedly on active databases.
   - If a new correction domain is added to the integrated DQ UI, its queue
     table should be introduced in this file before the scan procedure starts
     writing rows into it.
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
