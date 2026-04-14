/* ==========================================================================
   Keli Data Quality schema bootstrap
   ========================================================================== */

IF OBJECT_ID('dbo.keli_quality_issues', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.keli_quality_issues (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        table_key VARCHAR(50) NOT NULL,
        error_key VARCHAR(200) NOT NULL,
        error_label VARCHAR(300) NOT NULL,
        row_summary VARCHAR(2000) NOT NULL CONSTRAINT DF_keli_quality_issues_row_summary DEFAULT '',
        row_text NVARCHAR(MAX) NOT NULL CONSTRAINT DF_keli_quality_issues_row_text DEFAULT '',
        row_data NVARCHAR(MAX) NULL,
        is_fixed BIT NOT NULL CONSTRAINT DF_keli_quality_issues_is_fixed DEFAULT (0),
        fixed_note VARCHAR(2000) NOT NULL CONSTRAINT DF_keli_quality_issues_fixed_note DEFAULT '',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_keli_quality_issues_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_keli_quality_issues_updated_at DEFAULT SYSDATETIMEOFFSET(),
        updated_by_user_id INT NULL
    );

    CREATE INDEX IX_keli_quality_issues_scope
        ON dbo.keli_quality_issues (imported_by_user_id, state_fips, county_fips, table_key, is_fixed, error_key);

    CREATE INDEX IX_keli_quality_issues_scope_source
        ON dbo.keli_quality_issues (imported_by_user_id, state_fips, county_fips, error_key, is_fixed, id);
END;

IF OBJECT_ID('dbo.keli_quality_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.keli_quality_audit (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_keli_quality_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        table_key VARCHAR(50) NOT NULL,
        issue_row_id BIGINT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_keli_quality_audit_scope_time
        ON dbo.keli_quality_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;
