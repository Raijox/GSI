/* ============================================================================
   File: 02_additions_history_support.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Local copy of the additions correction history schema used by the
     integrated data quality corrections tool.
   Why this file exists:
   - The integrated DQ flow can apply and persist additions history inline, so
     the schema bootstrap needs to live under this tool rather than in a
     separate module dependency.
   What lives here:
   - corrections_additions table creation/backfills.
   - supporting indexes and audit table creation.
   Maintenance notes:
   - Preserve idempotence and keep this aligned with the standalone additions
     correction schema unless a deliberate integrated-only change is required.
   ============================================================================ */
IF OBJECT_ID('dbo.corrections_additions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_additions (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id BIGINT NULL,
        original_addition_value VARCHAR(1000) NOT NULL,
        new_addition_name VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add_new_name DEFAULT '',
        new_addition_id VARCHAR(100) NOT NULL CONSTRAINT DF_corr_add_new_id DEFAULT '',
        new_addition_description VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add_new_description DEFAULT '',
        new_block_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add_new_block DEFAULT '',
        new_lot_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add_new_lot DEFAULT '',
        new_is_active BIT NULL,
        needs_added BIT NOT NULL CONSTRAINT DF_corr_add_needs_added DEFAULT 0,
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_add_is_fixed DEFAULT (0),
        import_batch_id VARCHAR(36) NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add_updated_at DEFAULT SYSDATETIMEOFFSET(),
        updated_by_user_id INT NULL
    );

    CREATE INDEX IX_ac_scope_updated
        ON dbo.corrections_additions (imported_by_user_id, state_fips, county_fips, updated_at DESC);
END;

IF COL_LENGTH('dbo.corrections_additions', 'source_row_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD source_row_id BIGINT NULL;
END;

IF COL_LENGTH('dbo.corrections_additions', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD import_batch_id VARCHAR(36) NULL;
END;

IF COL_LENGTH('dbo.corrections_additions', 'new_block_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD new_block_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add_new_block_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions', 'new_lot_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD new_lot_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add_new_lot_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions', 'needs_added') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD needs_added BIT NOT NULL CONSTRAINT DF_corr_add_needs_added_legacy DEFAULT 0;
END;

IF COL_LENGTH('dbo.corrections_additions', 'is_fixed') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD is_fixed BIT NOT NULL CONSTRAINT DF_corr_add_is_fixed_legacy DEFAULT (0);
END;

IF COL_LENGTH('dbo.corrections_additions', 'needs_added_header_file_key') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD needs_added_header_file_key VARCHAR(260) NOT NULL CONSTRAINT DF_corr_add_needs_added_header_file_key DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions', 'needs_added_instrument_key') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD needs_added_instrument_key VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add_needs_added_instrument_key DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions', 'needs_added_instrument_number') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD needs_added_instrument_number VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add_needs_added_instrument_number DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions', 'needs_added_beginning_page') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD needs_added_beginning_page VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add_needs_added_beginning_page DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions', 'needs_added_ending_page') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions
    ADD needs_added_ending_page VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add_needs_added_ending_page DEFAULT '';
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_additions')
      AND name = 'UX_ac_scope_original'
)
BEGIN
    DROP INDEX UX_ac_scope_original ON dbo.corrections_additions;
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('dbo.corrections_additions')
      AND i.name = 'UX_ac_scope_source_row'
      AND NOT EXISTS (
          SELECT 1
          WHERE
              (SELECT COUNT(1)
               FROM sys.index_columns ic
               WHERE ic.object_id = i.object_id
                 AND ic.index_id = i.index_id
                 AND ic.key_ordinal > 0) = 5
              AND EXISTS (
                  SELECT 1
                  FROM sys.index_columns ic
                  JOIN sys.columns c
                    ON c.object_id = ic.object_id
                   AND c.column_id = ic.column_id
                  WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.key_ordinal = 1
                    AND c.name = 'imported_by_user_id'
              )
              AND EXISTS (
                  SELECT 1
                  FROM sys.index_columns ic
                  JOIN sys.columns c
                    ON c.object_id = ic.object_id
                   AND c.column_id = ic.column_id
                  WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.key_ordinal = 2
                    AND c.name = 'state_fips'
              )
              AND EXISTS (
                  SELECT 1
                  FROM sys.index_columns ic
                  JOIN sys.columns c
                    ON c.object_id = ic.object_id
                   AND c.column_id = ic.column_id
                  WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.key_ordinal = 3
                    AND c.name = 'county_fips'
              )
              AND EXISTS (
                  SELECT 1
                  FROM sys.index_columns ic
                  JOIN sys.columns c
                    ON c.object_id = ic.object_id
                   AND c.column_id = ic.column_id
                  WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.key_ordinal = 4
                    AND c.name = 'import_batch_id'
              )
              AND EXISTS (
                  SELECT 1
                  FROM sys.index_columns ic
                  JOIN sys.columns c
                    ON c.object_id = ic.object_id
                   AND c.column_id = ic.column_id
                  WHERE ic.object_id = i.object_id
                    AND ic.index_id = i.index_id
                    AND ic.key_ordinal = 5
                    AND c.name = 'source_row_id'
              )
      )
)
BEGIN
    DROP INDEX UX_ac_scope_source_row ON dbo.corrections_additions;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_additions')
      AND name = 'UX_ac_scope_source_row'
)
BEGIN
    IF COL_LENGTH('dbo.corrections_additions', 'source_row_id') IS NOT NULL
    BEGIN
        EXEC(N'
            CREATE UNIQUE INDEX UX_ac_scope_source_row
                ON dbo.corrections_additions (imported_by_user_id, state_fips, county_fips, import_batch_id, source_row_id)
                WHERE source_row_id IS NOT NULL;
        ');
    END;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_additions')
      AND name = 'IX_ac_scope_original_value'
)
BEGIN
    CREATE INDEX IX_ac_scope_original_value
        ON dbo.corrections_additions (imported_by_user_id, state_fips, county_fips, original_addition_value);
END;

IF OBJECT_ID('dbo.corrections_additions_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_additions_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        original_addition_value VARCHAR(1000) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_ac_audit_scope_time
        ON dbo.corrections_additions_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;

IF OBJECT_ID('dbo.corrections_additions_second_pass', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_additions_second_pass (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id BIGINT NULL,
        original_addition_value VARCHAR(1000) NOT NULL,
        new_addition_name VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add2_new_name DEFAULT '',
        new_addition_id VARCHAR(100) NOT NULL CONSTRAINT DF_corr_add2_new_id DEFAULT '',
        new_addition_description VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add2_new_description DEFAULT '',
        new_block_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add2_new_block DEFAULT '',
        new_lot_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add2_new_lot DEFAULT '',
        new_is_active BIT NULL,
        needs_added BIT NOT NULL CONSTRAINT DF_corr_add2_needs_added DEFAULT 0,
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_add2_is_fixed DEFAULT (0),
        initial_addition_value VARCHAR(1000) NULL,
        primary_pass_addition_value VARCHAR(1000) NULL,
        import_batch_id VARCHAR(36) NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add2_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add2_updated_at DEFAULT SYSDATETIMEOFFSET(),
        updated_by_user_id INT NULL
    );

    CREATE INDEX IX_ac2_scope_updated
        ON dbo.corrections_additions_second_pass (imported_by_user_id, state_fips, county_fips, updated_at DESC);
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'source_row_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD source_row_id BIGINT NULL;
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD import_batch_id VARCHAR(36) NULL;
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'initial_addition_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD initial_addition_value VARCHAR(1000) NULL;
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'primary_pass_addition_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD primary_pass_addition_value VARCHAR(1000) NULL;
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'new_block_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD new_block_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add2_new_block_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'new_lot_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD new_lot_value VARCHAR(300) NOT NULL CONSTRAINT DF_corr_add2_new_lot_legacy DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'needs_added') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD needs_added BIT NOT NULL CONSTRAINT DF_corr_add2_needs_added_legacy DEFAULT 0;
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'is_fixed') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD is_fixed BIT NOT NULL CONSTRAINT DF_corr_add2_is_fixed_legacy DEFAULT (0);
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'needs_added_header_file_key') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD needs_added_header_file_key VARCHAR(260) NOT NULL CONSTRAINT DF_corr_add2_needs_added_header_file_key DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'needs_added_instrument_key') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD needs_added_instrument_key VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add2_needs_added_instrument_key DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'needs_added_instrument_number') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD needs_added_instrument_number VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add2_needs_added_instrument_number DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'needs_added_beginning_page') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD needs_added_beginning_page VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add2_needs_added_beginning_page DEFAULT '';
END;

IF COL_LENGTH('dbo.corrections_additions_second_pass', 'needs_added_ending_page') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_additions_second_pass
    ADD needs_added_ending_page VARCHAR(1000) NOT NULL CONSTRAINT DF_corr_add2_needs_added_ending_page DEFAULT '';
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_additions_second_pass')
      AND name = 'UX_ac2_scope_source_row'
)
BEGIN
    DROP INDEX UX_ac2_scope_source_row ON dbo.corrections_additions_second_pass;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_additions_second_pass')
      AND name = 'UX_ac2_scope_source_row'
)
BEGIN
    IF COL_LENGTH('dbo.corrections_additions_second_pass', 'source_row_id') IS NOT NULL
    BEGIN
        EXEC(N'
            CREATE UNIQUE INDEX UX_ac2_scope_source_row
                ON dbo.corrections_additions_second_pass (imported_by_user_id, state_fips, county_fips, import_batch_id, source_row_id)
                WHERE source_row_id IS NOT NULL;
        ');
    END;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_additions_second_pass')
      AND name = 'IX_ac2_scope_original_value'
)
BEGIN
    CREATE INDEX IX_ac2_scope_original_value
        ON dbo.corrections_additions_second_pass (imported_by_user_id, state_fips, county_fips, original_addition_value);
END;

IF OBJECT_ID('dbo.corrections_additions_second_pass_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_additions_second_pass_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_add2_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        original_addition_value VARCHAR(1000) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_ac2_audit_scope_time
        ON dbo.corrections_additions_second_pass_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;
