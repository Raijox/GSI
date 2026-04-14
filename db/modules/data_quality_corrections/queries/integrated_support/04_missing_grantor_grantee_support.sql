/* ============================================================================
   File: 04_missing_grantor_grantee_support.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Local copy of the missing grantor/grantee correction schema used by the
     integrated data quality corrections tool.
   Why this file exists:
   - The integrated DQ UI can send users through the same name-fix workflow, so
     the required correction tables and audit tables need to be owned locally by
     this tool.
   What lives here:
   - corrections_missing_grantor_grantee_names creation/backfills.
   - supporting indexes and audit storage.
   Maintenance notes:
   - This file should remain behaviorally equivalent to the standalone missing
     names tool unless the integrated workflow intentionally changes.
   ============================================================================ */
IF OBJECT_ID('dbo.corrections_missing_grantor_grantee_names', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_missing_grantor_grantee_names (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        name_row_id INT NOT NULL,
        old_type VARCHAR(50) NOT NULL CONSTRAINT DF_corr_mgn_old_type DEFAULT '',
        new_type VARCHAR(50) NOT NULL CONSTRAINT DF_corr_mgn_new_type DEFAULT '',
        old_name VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_mgn_old_name DEFAULT '',
        new_name VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_mgn_new_name DEFAULT '',
        action_type VARCHAR(50) NOT NULL CONSTRAINT DF_corr_mgn_action_type DEFAULT '',
        imported_by_user_id INT NOT NULL,
        import_batch_id VARCHAR(36) NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_by_user_id INT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_mgn_created_at DEFAULT SYSDATETIMEOFFSET()
    );

    CREATE INDEX IX_mgg_scope_time
        ON dbo.corrections_missing_grantor_grantee_names (imported_by_user_id, state_fips, county_fips, created_at DESC);
END;

IF OBJECT_ID('dbo.corrections_missing_grantor_grantee_names', 'U') IS NOT NULL
   AND COL_LENGTH('dbo.corrections_missing_grantor_grantee_names', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_missing_grantor_grantee_names
        ADD import_batch_id VARCHAR(36) NULL;
END;

IF OBJECT_ID('dbo.corrections_missing_grantor_grantee_names', 'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.corrections_missing_grantor_grantee_names')
          AND name = 'IX_mgg_scope_batch_row_time'
   )
BEGIN
    CREATE INDEX IX_mgg_scope_batch_row_time
        ON dbo.corrections_missing_grantor_grantee_names (
            imported_by_user_id,
            state_fips,
            county_fips,
            import_batch_id,
            name_row_id,
            id DESC
        );
END;

IF OBJECT_ID('dbo.corrections_missing_grantor_grantee_names_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_missing_grantor_grantee_names_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_mgn_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        name_row_id INT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_mgg_audit_scope_time
        ON dbo.corrections_missing_grantor_grantee_names_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;
