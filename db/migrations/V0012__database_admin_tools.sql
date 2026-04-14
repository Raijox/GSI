/*
    Purpose: Add database administration support tables for query logging,
    managed backups, and add-on rollback operations.
    Notes:
      - `database_query_log` captures executed SQL plus request/tool context.
      - `database_backup_catalog` tracks managed backup files created from the UI.
      - `addon_operation_log` and `addon_operation_rollback_steps` store
        reversible add-on actions and their undo payloads.
*/

IF OBJECT_ID('dbo.database_query_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.database_query_log (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        logged_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_database_query_log_logged_at DEFAULT SYSDATETIMEOFFSET(),
        completed_at DATETIMEOFFSET NULL,
        duration_ms INT NOT NULL CONSTRAINT DF_database_query_log_duration_ms DEFAULT 0,
        success BIT NOT NULL CONSTRAINT DF_database_query_log_success DEFAULT 1,
        query_mode VARCHAR(20) NOT NULL CONSTRAINT DF_database_query_log_query_mode DEFAULT 'execute',
        statement_type VARCHAR(32) NOT NULL CONSTRAINT DF_database_query_log_statement_type DEFAULT '',
        row_count INT NULL,
        rows_returned INT NULL,
        database_name NVARCHAR(128) NULL,
        request_id NVARCHAR(64) NULL,
        request_path NVARCHAR(512) NULL,
        request_method NVARCHAR(16) NULL,
        request_endpoint NVARCHAR(255) NULL,
        user_id INT NULL,
        username NVARCHAR(100) NULL,
        user_role NVARCHAR(20) NULL,
        addon_id NVARCHAR(64) NULL,
        addon_type NVARCHAR(64) NULL,
        tool_name NVARCHAR(128) NULL,
        operation_name NVARCHAR(128) NULL,
        process_name NVARCHAR(128) NULL,
        addon_operation_id BIGINT NULL,
        source_module NVARCHAR(255) NULL,
        source_function NVARCHAR(255) NULL,
        source_line INT NULL,
        query_text NVARCHAR(MAX) NOT NULL,
        params_json NVARCHAR(MAX) NULL,
        error_type NVARCHAR(200) NULL,
        error_message NVARCHAR(MAX) NULL
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.database_query_log')
      AND name = 'IX_database_query_log_logged_at'
)
BEGIN
    CREATE INDEX IX_database_query_log_logged_at
        ON dbo.database_query_log (logged_at DESC, id DESC);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.database_query_log')
      AND name = 'IX_database_query_log_user_tool'
)
BEGIN
    CREATE INDEX IX_database_query_log_user_tool
        ON dbo.database_query_log (user_id, addon_id, operation_name, logged_at DESC);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.database_query_log')
      AND name = 'IX_database_query_log_operation'
)
BEGIN
    CREATE INDEX IX_database_query_log_operation
        ON dbo.database_query_log (addon_operation_id, logged_at DESC);
END;

IF OBJECT_ID('dbo.database_backup_catalog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.database_backup_catalog (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        database_name NVARCHAR(128) NOT NULL,
        version_number INT NOT NULL,
        backup_label NVARCHAR(255) NOT NULL,
        file_name NVARCHAR(512) NOT NULL,
        relative_path NVARCHAR(1000) NOT NULL,
        full_path NVARCHAR(2000) NOT NULL,
        folder_root NVARCHAR(2000) NOT NULL,
        folder_subpath NVARCHAR(1000) NOT NULL CONSTRAINT DF_database_backup_catalog_folder_subpath DEFAULT '',
        file_size_bytes BIGINT NULL,
        scope_state_fips CHAR(2) NULL,
        scope_county_fips CHAR(5) NULL,
        created_by_user_id INT NULL,
        created_by_username NVARCHAR(100) NULL,
        backup_started_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_database_backup_catalog_started_at DEFAULT SYSDATETIMEOFFSET(),
        backup_completed_at DATETIMEOFFSET NULL,
        status VARCHAR(30) NOT NULL CONSTRAINT DF_database_backup_catalog_status DEFAULT 'completed',
        details_json NVARCHAR(MAX) NULL
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.database_backup_catalog')
      AND name = 'UX_database_backup_catalog_database_version'
)
BEGIN
    CREATE UNIQUE INDEX UX_database_backup_catalog_database_version
        ON dbo.database_backup_catalog (database_name, version_number);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.database_backup_catalog')
      AND name = 'IX_database_backup_catalog_scope_time'
)
BEGIN
    CREATE INDEX IX_database_backup_catalog_scope_time
        ON dbo.database_backup_catalog (scope_state_fips, scope_county_fips, backup_started_at DESC);
END;

IF OBJECT_ID('dbo.addon_operation_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.addon_operation_log (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        addon_id NVARCHAR(64) NOT NULL,
        addon_type NVARCHAR(64) NOT NULL,
        module_key NVARCHAR(128) NULL,
        operation_name NVARCHAR(128) NOT NULL,
        operation_label NVARCHAR(255) NOT NULL,
        request_id NVARCHAR(64) NULL,
        request_path NVARCHAR(512) NULL,
        request_method NVARCHAR(16) NULL,
        user_id INT NULL,
        username NVARCHAR(100) NULL,
        user_role NVARCHAR(20) NULL,
        scope_state_fips CHAR(2) NULL,
        scope_county_fips CHAR(5) NULL,
        job_scope_key NVARCHAR(200) NULL,
        started_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_addon_operation_log_started_at DEFAULT SYSDATETIMEOFFSET(),
        completed_at DATETIMEOFFSET NULL,
        status VARCHAR(30) NOT NULL CONSTRAINT DF_addon_operation_log_status DEFAULT 'started',
        is_reversible BIT NOT NULL CONSTRAINT DF_addon_operation_log_is_reversible DEFAULT 0,
        undo_step_count INT NOT NULL CONSTRAINT DF_addon_operation_log_undo_step_count DEFAULT 0,
        summary NVARCHAR(2000) NULL,
        details_json NVARCHAR(MAX) NULL,
        error_message NVARCHAR(MAX) NULL,
        rolled_back_at DATETIMEOFFSET NULL,
        rolled_back_by_user_id INT NULL,
        rolled_back_in_operation_id BIGINT NULL
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.addon_operation_log')
      AND name = 'IX_addon_operation_log_user_time'
)
BEGIN
    CREATE INDEX IX_addon_operation_log_user_time
        ON dbo.addon_operation_log (user_id, started_at DESC, id DESC);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.addon_operation_log')
      AND name = 'IX_addon_operation_log_status'
)
BEGIN
    CREATE INDEX IX_addon_operation_log_status
        ON dbo.addon_operation_log (status, is_reversible, started_at DESC, id DESC);
END;

IF OBJECT_ID('dbo.addon_operation_rollback_steps', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.addon_operation_rollback_steps (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        operation_id BIGINT NOT NULL,
        step_order INT NOT NULL,
        step_type VARCHAR(40) NOT NULL,
        target_table NVARCHAR(128) NULL,
        step_key_json NVARCHAR(MAX) NULL,
        row_data_json NVARCHAR(MAX) NULL,
        existed_before BIT NOT NULL CONSTRAINT DF_addon_operation_rollback_steps_existed_before DEFAULT 1,
        description NVARCHAR(1000) NULL,
        created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_addon_operation_rollback_steps_created_at DEFAULT SYSDATETIMEOFFSET(),
        CONSTRAINT FK_addon_operation_rollback_steps_operation
            FOREIGN KEY (operation_id) REFERENCES dbo.addon_operation_log(id) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.addon_operation_rollback_steps')
      AND name = 'UX_addon_operation_rollback_steps_operation_order'
)
BEGIN
    CREATE UNIQUE INDEX UX_addon_operation_rollback_steps_operation_order
        ON dbo.addon_operation_rollback_steps (operation_id, step_order);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.addon_operation_rollback_steps')
      AND name = 'IX_addon_operation_rollback_steps_operation'
)
BEGIN
    CREATE INDEX IX_addon_operation_rollback_steps_operation
        ON dbo.addon_operation_rollback_steps (operation_id, step_order DESC, id DESC);
END;
