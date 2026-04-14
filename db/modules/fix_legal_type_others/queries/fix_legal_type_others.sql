/* ============================================================================
   Module: Fix Legal Type Others
   Purpose: Persistent storage for legal type "Other" user fixes and audit logs.
   Notes:
   - This script is idempotent.
   - Each block below is independent and safe to rerun.
   ============================================================================ */

/* ----------------------------------------------------------------------------
   Block 1: Main fix table
   Stores the edited legal fields for a single legal row in a scoped county/job.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_other_type_legals', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_other_type_legals (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        legal_row_id INT NOT NULL,
        section_value VARCHAR(10) NOT NULL CONSTRAINT DF_corr_otl_section DEFAULT '',
        township_value VARCHAR(100) NOT NULL CONSTRAINT DF_corr_otl_township DEFAULT '',
        range_value VARCHAR(100) NOT NULL CONSTRAINT DF_corr_otl_range DEFAULT '',
        addition_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_otl_addition DEFAULT '',
        block_value VARCHAR(200) NOT NULL CONSTRAINT DF_corr_otl_block DEFAULT '',
        lot_value VARCHAR(200) NOT NULL CONSTRAINT DF_corr_otl_lot DEFAULT '',
        quarter_value VARCHAR(200) NOT NULL CONSTRAINT DF_corr_otl_quarter DEFAULT '',
        imported_by_user_id INT NOT NULL,
        import_batch_id VARCHAR(36) NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        fixed_by_user_id INT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_otl_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_otl_updated_at DEFAULT SYSDATETIMEOFFSET()
    );

    CREATE UNIQUE INDEX UX_ltof_scope_batch_legal_row
        ON dbo.corrections_other_type_legals (imported_by_user_id, state_fips, county_fips, import_batch_id, legal_row_id);

    CREATE INDEX IX_ltof_scope_updated
        ON dbo.corrections_other_type_legals (imported_by_user_id, state_fips, county_fips, updated_at DESC);
END;

IF OBJECT_ID('dbo.corrections_other_type_legals', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.corrections_other_type_legals', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_other_type_legals
        ADD import_batch_id VARCHAR(36) NULL;
END;

IF OBJECT_ID('dbo.corrections_other_type_legals', 'U') IS NOT NULL
   AND EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.corrections_other_type_legals')
          AND name = 'UX_ltof_scope_legal_row'
   )
BEGIN
    DROP INDEX UX_ltof_scope_legal_row ON dbo.corrections_other_type_legals;
END;

IF OBJECT_ID('dbo.corrections_other_type_legals', 'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.corrections_other_type_legals')
          AND name = 'UX_ltof_scope_batch_legal_row'
   )
BEGIN
    CREATE UNIQUE INDEX UX_ltof_scope_batch_legal_row
        ON dbo.corrections_other_type_legals (
            imported_by_user_id,
            state_fips,
            county_fips,
            import_batch_id,
            legal_row_id
        );
END;

IF OBJECT_ID('dbo.corrections_other_type_legals', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.corrections_other_type_legals', 'free_form_legal_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_other_type_legals
        ADD free_form_legal_value VARCHAR(300) NOT NULL
        CONSTRAINT DF_corr_otl_free_form_legal DEFAULT '';
END;

IF OBJECT_ID('dbo.gdi_additions', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_additions', 'legal_row_id') IS NULL
BEGIN
    ALTER TABLE dbo.gdi_additions
        ADD legal_row_id INT NULL;
END;

IF OBJECT_ID('dbo.gdi_township_range', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.gdi_township_range', 'legal_row_id') IS NULL
BEGIN
    ALTER TABLE dbo.gdi_township_range
        ADD legal_row_id INT NULL;
END;

/* ----------------------------------------------------------------------------
   Block 2: Audit table
   Stores event logs for queue loads, apply actions, and error traces.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.corrections_other_type_legals_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_other_type_legals_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_otl_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        legal_row_id INT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_ltof_audit_scope_time
        ON dbo.corrections_other_type_legals_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;
