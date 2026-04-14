IF OBJECT_ID('dbo.corrections_instrument_types', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instrument_types (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id BIGINT NULL,
        original_instrument_type VARCHAR(1000) NOT NULL,
        new_instrument_type_name VARCHAR(300) NOT NULL CONSTRAINT DF_corr_it_new_name DEFAULT '',
        new_instrument_type_id VARCHAR(100) NOT NULL CONSTRAINT DF_corr_it_new_id DEFAULT '',
        new_record_type VARCHAR(120) NOT NULL CONSTRAINT DF_corr_it_new_record_type DEFAULT '',
        new_is_active BIT NULL,
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_it_is_fixed DEFAULT (0),
        import_batch_id VARCHAR(36) NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it_updated_at DEFAULT SYSDATETIMEOFFSET(),
        updated_by_user_id INT NULL
    );

    CREATE INDEX IX_itc_scope_updated
        ON dbo.corrections_instrument_types (imported_by_user_id, state_fips, county_fips, updated_at DESC);
END;

IF COL_LENGTH('dbo.corrections_instrument_types', 'source_row_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types
    ADD source_row_id BIGINT NULL;
END;

IF COL_LENGTH('dbo.corrections_instrument_types', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types
    ADD import_batch_id VARCHAR(36) NULL;
END;

IF COL_LENGTH('dbo.corrections_instrument_types', 'is_fixed') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types
    ADD is_fixed BIT NOT NULL CONSTRAINT DF_corr_it_is_fixed_legacy DEFAULT (0);
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_instrument_types')
      AND name = 'UX_itc_scope_original'
)
BEGIN
    DROP INDEX UX_itc_scope_original ON dbo.corrections_instrument_types;
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('dbo.corrections_instrument_types')
      AND i.name = 'UX_itc_scope_source_row'
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
    DROP INDEX UX_itc_scope_source_row ON dbo.corrections_instrument_types;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_instrument_types')
      AND name = 'UX_itc_scope_source_row'
)
BEGIN
    IF COL_LENGTH('dbo.corrections_instrument_types', 'source_row_id') IS NOT NULL
    BEGIN
        EXEC(N'
            CREATE UNIQUE INDEX UX_itc_scope_source_row
                ON dbo.corrections_instrument_types (imported_by_user_id, state_fips, county_fips, import_batch_id, source_row_id)
                WHERE source_row_id IS NOT NULL;
        ');
    END;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_instrument_types')
      AND name = 'IX_itc_scope_original_value'
)
BEGIN
    CREATE INDEX IX_itc_scope_original_value
        ON dbo.corrections_instrument_types (imported_by_user_id, state_fips, county_fips, original_instrument_type);
END;

IF OBJECT_ID('dbo.corrections_instrument_types_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instrument_types_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        original_instrument_type VARCHAR(1000) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_itc_audit_scope_time
        ON dbo.corrections_instrument_types_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;

IF OBJECT_ID('dbo.corrections_instrument_types_second_pass', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instrument_types_second_pass (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        source_row_id BIGINT NULL,
        original_instrument_type VARCHAR(1000) NOT NULL,
        new_instrument_type_name VARCHAR(300) NOT NULL CONSTRAINT DF_corr_it2_new_name DEFAULT '',
        new_instrument_type_id VARCHAR(100) NOT NULL CONSTRAINT DF_corr_it2_new_id DEFAULT '',
        new_record_type VARCHAR(120) NOT NULL CONSTRAINT DF_corr_it2_new_record_type DEFAULT '',
        new_is_active BIT NULL,
        is_fixed BIT NOT NULL CONSTRAINT DF_corr_it2_is_fixed DEFAULT (0),
        initial_instrument_type_value VARCHAR(1000) NULL,
        primary_pass_instrument_type_value VARCHAR(1000) NULL,
        import_batch_id VARCHAR(36) NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it2_created_at DEFAULT SYSDATETIMEOFFSET(),
        updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it2_updated_at DEFAULT SYSDATETIMEOFFSET(),
        updated_by_user_id INT NULL
    );

    CREATE INDEX IX_itc2_scope_updated
        ON dbo.corrections_instrument_types_second_pass (imported_by_user_id, state_fips, county_fips, updated_at DESC);
END;

IF COL_LENGTH('dbo.corrections_instrument_types_second_pass', 'source_row_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types_second_pass
    ADD source_row_id BIGINT NULL;
END;

IF COL_LENGTH('dbo.corrections_instrument_types_second_pass', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types_second_pass
    ADD import_batch_id VARCHAR(36) NULL;
END;

IF COL_LENGTH('dbo.corrections_instrument_types_second_pass', 'is_fixed') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types_second_pass
    ADD is_fixed BIT NOT NULL CONSTRAINT DF_corr_it2_is_fixed_legacy DEFAULT (0);
END;

IF COL_LENGTH('dbo.corrections_instrument_types_second_pass', 'initial_instrument_type_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types_second_pass
    ADD initial_instrument_type_value VARCHAR(1000) NULL;
END;

IF COL_LENGTH('dbo.corrections_instrument_types_second_pass', 'primary_pass_instrument_type_value') IS NULL
BEGIN
    ALTER TABLE dbo.corrections_instrument_types_second_pass
    ADD primary_pass_instrument_type_value VARCHAR(1000) NULL;
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_instrument_types_second_pass')
      AND name = 'UX_itc2_scope_source_row'
)
BEGIN
    DROP INDEX UX_itc2_scope_source_row ON dbo.corrections_instrument_types_second_pass;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_instrument_types_second_pass')
      AND name = 'UX_itc2_scope_source_row'
)
BEGIN
    IF COL_LENGTH('dbo.corrections_instrument_types_second_pass', 'source_row_id') IS NOT NULL
    BEGIN
        EXEC(N'
            CREATE UNIQUE INDEX UX_itc2_scope_source_row
                ON dbo.corrections_instrument_types_second_pass (imported_by_user_id, state_fips, county_fips, import_batch_id, source_row_id)
                WHERE source_row_id IS NOT NULL;
        ');
    END;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.corrections_instrument_types_second_pass')
      AND name = 'IX_itc2_scope_original_value'
)
BEGIN
    CREATE INDEX IX_itc2_scope_original_value
        ON dbo.corrections_instrument_types_second_pass (imported_by_user_id, state_fips, county_fips, original_instrument_type);
END;

IF OBJECT_ID('dbo.corrections_instrument_types_second_pass_audit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.corrections_instrument_types_second_pass_audit (
        id BIGINT NOT NULL IDENTITY PRIMARY KEY,
        audit_time DATETIMEOFFSET NOT NULL CONSTRAINT DF_corr_it2_audit_time DEFAULT SYSDATETIMEOFFSET(),
        severity VARCHAR(20) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        imported_by_user_id INT NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        original_instrument_type VARCHAR(1000) NULL,
        details NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_itc2_audit_scope_time
        ON dbo.corrections_instrument_types_second_pass_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
END;
