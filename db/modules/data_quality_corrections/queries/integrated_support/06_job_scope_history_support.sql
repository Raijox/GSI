/* ============================================================================
   File: 06_job_scope_history_support.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Provides persistent job-scope correction history for the integrated DQ
     workflow.
   Why this file exists:
   - Additions and instrument types intentionally keep county-wide history, but
     the rest of the DQ tool now needs a narrower replay model that only
     reuses corrections when the user is scanning the same import job scope.
   What lives here:
   - dbo.dq_job_scope_correction_history
   - indexes for scope lookup and per-row upsert
   Data model notes:
   - job_scope_key is a stable scope identifier derived from the current active
     job range for the county.
   - match_key is a deterministic hash of the queue row identity fields
     (error_key + header/file/col01/snapshot) so a fresh import of the same
     scope can find the same issue again even though source_row_id changes.
   - action_key + payload_json capture the latest reusable correction to replay.
   Maintenance notes:
   - This table is DQ-only. Do not use it for county-wide history targets like
     additions or instrument types.
   ============================================================================ */
IF OBJECT_ID('dbo.dq_job_scope_correction_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.dq_job_scope_correction_history (
        id BIGINT NOT NULL IDENTITY(1,1) PRIMARY KEY,
        job_scope_key VARCHAR(200) NOT NULL,
        job_scope_label VARCHAR(200) NOT NULL CONSTRAINT DF_dqjsh_scope_label DEFAULT '',
        table_key VARCHAR(50) NOT NULL,
        error_key VARCHAR(120) NOT NULL CONSTRAINT DF_dqjsh_error_key DEFAULT '',
        action_key VARCHAR(80) NOT NULL,
        source_table VARCHAR(128) NOT NULL CONSTRAINT DF_dqjsh_source_table DEFAULT '',
        match_key CHAR(64) NOT NULL,
        match_header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_dqjsh_hfk DEFAULT '',
        match_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_dqjsh_fk DEFAULT '',
        match_col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_dqjsh_c01 DEFAULT '',
        match_snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_dqjsh_snapshot DEFAULT '',
        payload_json NVARCHAR(MAX) NOT NULL CONSTRAINT DF_dqjsh_payload DEFAULT '{}',
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_dqjsh_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_dqjsh_updated_at DEFAULT SYSDATETIMEOFFSET(),
        updated_by_user_id INT NULL
    );

    CREATE UNIQUE INDEX UX_dqjsh_scope_match
        ON dbo.dq_job_scope_correction_history (
            imported_by_user_id,
            state_fips,
            county_fips,
            job_scope_key,
            table_key,
            match_key
        );

    CREATE INDEX IX_dqjsh_scope_table_updated
        ON dbo.dq_job_scope_correction_history (
            imported_by_user_id,
            state_fips,
            county_fips,
            job_scope_key,
            table_key,
            updated_at DESC
        );
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'job_scope_label') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD job_scope_label VARCHAR(200) NOT NULL CONSTRAINT DF_dqjsh_scope_label_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'source_table') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD source_table VARCHAR(128) NOT NULL CONSTRAINT DF_dqjsh_source_table_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'match_key') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD match_key CHAR(64) NOT NULL CONSTRAINT DF_dqjsh_match_key_legacy DEFAULT REPLICATE('0', 64);
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'match_header_file_key') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD match_header_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_dqjsh_hfk_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'match_file_key') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD match_file_key NVARCHAR(260) NOT NULL CONSTRAINT DF_dqjsh_fk_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'match_col01varchar') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD match_col01varchar VARCHAR(1000) NOT NULL CONSTRAINT DF_dqjsh_c01_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.dq_job_scope_correction_history', 'match_snapshot') IS NULL
BEGIN
    ALTER TABLE dbo.dq_job_scope_correction_history
    ADD match_snapshot NVARCHAR(MAX) NOT NULL CONSTRAINT DF_dqjsh_snapshot_legacy DEFAULT '';
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.dq_job_scope_correction_history')
      AND name = 'UX_dqjsh_scope_match'
)
AND NOT EXISTS (
    SELECT 1
    FROM sys.index_columns ic
    JOIN sys.columns c
      ON c.object_id = ic.object_id
     AND c.column_id = ic.column_id
    WHERE ic.object_id = OBJECT_ID('dbo.dq_job_scope_correction_history')
      AND ic.index_id = INDEXPROPERTY(OBJECT_ID('dbo.dq_job_scope_correction_history'), 'UX_dqjsh_scope_match', 'IndexID')
      AND c.name = 'match_key'
)
BEGIN
    DROP INDEX UX_dqjsh_scope_match ON dbo.dq_job_scope_correction_history;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.dq_job_scope_correction_history')
      AND name = 'UX_dqjsh_scope_match'
)
BEGIN
    CREATE UNIQUE INDEX UX_dqjsh_scope_match
        ON dbo.dq_job_scope_correction_history (
            imported_by_user_id,
            state_fips,
            county_fips,
            job_scope_key,
            table_key,
            match_key
        );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.dq_job_scope_correction_history')
      AND name = 'IX_dqjsh_scope_table_updated'
)
BEGIN
    CREATE INDEX IX_dqjsh_scope_table_updated
        ON dbo.dq_job_scope_correction_history (
            imported_by_user_id,
            state_fips,
            county_fips,
            job_scope_key,
            table_key,
            updated_at DESC
        );
END;
