IF OBJECT_ID('dbo.corrections_missed_indexing_images', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_missed_indexing_images (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_key VARCHAR(120) NOT NULL,
        root_path VARCHAR(1000) NOT NULL,
        relative_path VARCHAR(2000) NOT NULL,
        file_name VARCHAR(260) NOT NULL,
        review_status VARCHAR(20) NOT NULL CONSTRAINT DF_corr_mii_review_status DEFAULT 'pending',
        is_present BIT NOT NULL CONSTRAINT DF_corr_mii_is_present DEFAULT 1,
        first_seen_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_mii_first_seen_at DEFAULT SYSDATETIMEOFFSET(),
        last_seen_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_mii_last_seen_at DEFAULT SYSDATETIMEOFFSET(),
        reviewed_at DATETIMEOFFSET NULL,
        reviewed_by_user_id INT NULL,
        import_batch_id UNIQUEIDENTIFIER NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL
    );
    CREATE UNIQUE INDEX UX_mii_scope_source_path
        ON dbo.corrections_missed_indexing_images (imported_by_user_id, state_fips, county_fips, source_key, relative_path);
    CREATE INDEX IX_mii_scope_status
        ON dbo.corrections_missed_indexing_images (imported_by_user_id, state_fips, county_fips, source_key, review_status, is_present);
END;

IF OBJECT_ID('dbo.corrections_missed_indexing_images_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_missed_indexing_images_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_mii_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        import_batch_id UNIQUEIDENTIFIER NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        source_key VARCHAR(120) NULL,
        details NVARCHAR(MAX) NULL
    );
    CREATE INDEX IX_mii_audit_scope_time
        ON dbo.corrections_missed_indexing_images_audit (imported_by_user_id, state_fips, county_fips, source_key, audit_time DESC);
END;
