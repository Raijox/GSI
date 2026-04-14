/* ============================================================================
   File: 01_proc_header_and_bootstrap.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - First fragment of the ordered sp_GenericDataImport procedure definition.
   - Owns procedure signature, input normalization, file/tag derivation, schema
     compatibility guards, and bootstrap index creation.
   Why this file exists:
   - Every later fragment assumes the scope variables, target table names, and
     compatibility columns are already established here.
   Maintenance notes:
   - Keep the procedure declaration and bootstrap contracts in this fragment.
   - If downstream fragments need new columns or indexes to exist before import
     work begins, add those guards here instead of scattering them later.
   ============================================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_GenericDataImport
    @ImportFileName VARCHAR(1000),
    @DropOrAppend VARCHAR(1),
    @ImportedByUserId INT = NULL,
    @StateFips CHAR(2) = NULL,
    @CountyFips CHAR(5) = NULL,
    @ImportBatchId UNIQUEIDENTIFIER = NULL,
    @SkipSplitRebuild BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @mode CHAR(1) = UPPER(LTRIM(RTRIM(ISNULL(@DropOrAppend, ''))));
    DECLARE @state_fips CHAR(2) = RIGHT('00' + LTRIM(RTRIM(ISNULL(@StateFips, ''))), 2);
    DECLARE @county_fips CHAR(5) = RIGHT('00000' + LTRIM(RTRIM(ISNULL(@CountyFips, ''))), 5);
    DECLARE @batch_id UNIQUEIDENTIFIER = ISNULL(@ImportBatchId, NEWID());

    IF @mode NOT IN ('D', 'A')
    BEGIN
        THROW 50000, 'DropOrAppend must be D or A.', 1;
    END;

    IF ISNULL(@ImportedByUserId, 0) <= 0
       OR LEN(LTRIM(RTRIM(ISNULL(@StateFips, '')))) <> 2
       OR LEN(LTRIM(RTRIM(ISNULL(@CountyFips, '')))) <> 5
    BEGIN
        THROW 50002, 'Scoped import requires ImportedByUserId, StateFips, and CountyFips.', 1;
    END;

    DECLARE @normalized_path NVARCHAR(1000) = REPLACE(REPLACE(LTRIM(RTRIM(@ImportFileName)), '/', '\'), '"', '');
    DECLARE @file_name NVARCHAR(260) = @normalized_path;
    DECLARE @slash_pos INT = CHARINDEX('\', REVERSE(@normalized_path));
    IF @slash_pos > 0
        SET @file_name = RIGHT(@normalized_path, @slash_pos - 1);

    DECLARE @dot_pos INT = CHARINDEX('.', REVERSE(@file_name));
    DECLARE @file_stem NVARCHAR(260) = CASE WHEN @dot_pos > 0 THEN LEFT(@file_name, LEN(@file_name) - @dot_pos) ELSE @file_name END;
    DECLARE @file_key NVARCHAR(260) = LOWER(@file_stem);

    DECLARE @digit_pos INT = PATINDEX('%[0-9]%', @file_key);
    DECLARE @raw_tag NVARCHAR(120);
    DECLARE @tag NVARCHAR(120);
    DECLARE @file_suffix NVARCHAR(220);

    IF @digit_pos > 1
    BEGIN
        SET @raw_tag = LEFT(@file_key, @digit_pos - 1);
        SET @file_suffix = SUBSTRING(@file_key, @digit_pos, LEN(@file_key));
    END
    ELSE
    BEGIN
        SET @raw_tag = @file_key;
        SET @file_suffix = '';
    END;

    SET @tag = @raw_tag;
    IF @tag IS NULL OR LTRIM(RTRIM(@tag)) = '' OR PATINDEX('%[^a-z0-9_]%', @tag) > 0
        SET @tag = 'misc';
    ELSE IF @tag IN ('image', 'images')
        SET @tag = 'images';
    ELSE IF @tag IN ('name', 'names')
        SET @tag = 'names';
    ELSE IF @tag IN ('reference', 'references', 'ref')
        SET @tag = 'references';
    ELSE IF @tag IN ('legal', 'legals')
        SET @tag = 'legals';
    ELSE IF @tag IN ('header', 'headers')
        SET @tag = 'header';

    DECLARE @header_file_key NVARCHAR(260) = CASE
        WHEN @tag = 'header' THEN @file_key
        WHEN @file_suffix <> '' THEN 'header' + @file_suffix
        ELSE 'header_' + @file_key
    END;

    IF OBJECT_ID(N'dbo.GenericDataImport', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.GenericDataImport (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col02varchar VARCHAR(1000),
            col03varchar VARCHAR(1000),
            col04varchar VARCHAR(1000),
            col05varchar VARCHAR(1000),
            col06varchar VARCHAR(1000),
            col07varchar VARCHAR(1000),
            col08varchar VARCHAR(1000),
            col09varchar VARCHAR(1000),
            col10varchar VARCHAR(1000),
            key_id VARCHAR(1000),
            book VARCHAR(1000),
            page_number VARCHAR(1000),
            keli_image_path VARCHAR(1000),
            beginning_page VARCHAR(1000),
            ending_page VARCHAR(1000),
            record_series_internal_id VARCHAR(1000),
            record_series_external_id VARCHAR(1000),
            instrument_type_internal_id VARCHAR(1000),
            instrument_type_external_id VARCHAR(1000),
            grantor_suffix_internal_id VARCHAR(1000),
            grantee_suffix_internal_id VARCHAR(1000),
            manual_page_count VARCHAR(1000),
            legal_type VARCHAR(1000),
            additions_internal_id VARCHAR(1000),
            additions_external_id VARCHAR(1000),
            township_range_internal_id VARCHAR(1000),
            township_range_external_id VARCHAR(1000),
            free_form_legal VARCHAR(1000),
            referenced_instrument VARCHAR(1000),
            referenced_book VARCHAR(1000),
            referenced_page VARCHAR(1000),
            col20other VARCHAR(1000),
            uf1 VARCHAR(1000),
            uf2 VARCHAR(1000),
            uf3 VARCHAR(1000),
            leftovers VARCHAR(1000),
            imported_by_user_id INT NULL,
            import_batch_id UNIQUEIDENTIFIER NULL,
            state_fips CHAR(2) NULL,
            county_fips CHAR(5) NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );
    END;

    IF COL_LENGTH('dbo.GenericDataImport', 'imported_by_user_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD imported_by_user_id INT NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'import_batch_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD import_batch_id UNIQUEIDENTIFIER NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'state_fips') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD state_fips CHAR(2) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'county_fips') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD county_fips CHAR(5) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'is_deleted') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD is_deleted BIT NOT NULL DEFAULT (0);
    IF COL_LENGTH('dbo.GenericDataImport', 'imported_at') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET();

    IF COL_LENGTH('dbo.GenericDataImport', 'key_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD key_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'book') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD book VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'page_number') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD page_number VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'keli_image_path') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD keli_image_path VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'beginning_page') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD beginning_page VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'ending_page') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD ending_page VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'record_series_internal_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD record_series_internal_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'record_series_external_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD record_series_external_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'instrument_type_internal_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD instrument_type_internal_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'instrument_type_external_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD instrument_type_external_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'grantor_suffix_internal_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD grantor_suffix_internal_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'grantee_suffix_internal_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD grantee_suffix_internal_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'manual_page_count') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD manual_page_count VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'legal_type') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD legal_type VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'additions_internal_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD additions_internal_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'additions_external_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD additions_external_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'township_range_internal_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD township_range_internal_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'township_range_external_id') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD township_range_external_id VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'free_form_legal') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD free_form_legal VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'referenced_instrument') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD referenced_instrument VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'referenced_book') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD referenced_book VARCHAR(1000) NULL;
    IF COL_LENGTH('dbo.GenericDataImport', 'referenced_page') IS NULL
        ALTER TABLE dbo.GenericDataImport ADD referenced_page VARCHAR(1000) NULL;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope ON dbo.GenericDataImport (state_fips, county_fips, imported_by_user_id);

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_import_batch'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_import_batch ON dbo.GenericDataImport (import_batch_id);

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope_fn'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope_fn ON dbo.GenericDataImport (imported_by_user_id, state_fips, county_fips, FN);

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope_book'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope_book ON dbo.GenericDataImport (imported_by_user_id, state_fips, county_fips, book);

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope_active'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope_active
            ON dbo.GenericDataImport (imported_by_user_id, state_fips, county_fips, is_deleted, ID)
            INCLUDE (fn, col01varchar, OriginalValue, key_id, book, page_number, col03varchar, col04varchar, col05varchar, beginning_page, ending_page, import_batch_id, imported_at);

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope_batch_active'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope_batch_active
            ON dbo.GenericDataImport (imported_by_user_id, state_fips, county_fips, import_batch_id, is_deleted, ID)
            INCLUDE (fn, col01varchar, OriginalValue, book);

    IF OBJECT_ID(N'dbo.gdi_instruments', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_gdi_header_scope_header_col01'
          AND object_id = OBJECT_ID('dbo.gdi_instruments')
    )
        CREATE INDEX IX_gdi_header_scope_header_col01
            ON dbo.gdi_instruments (imported_by_user_id, state_fips, county_fips, header_file_key, col01varchar)
            INCLUDE (file_key, OriginalValue, book, beginning_page, ending_page);

    IF OBJECT_ID(N'dbo.gdi_audit', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.gdi_audit (
            id BIGINT NOT NULL IDENTITY PRIMARY KEY,
            audit_time DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
            severity VARCHAR(20) NOT NULL,
            event_type VARCHAR(100) NOT NULL,
            message NVARCHAR(2000) NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NULL,
            imported_by_user_id INT NULL,
            state_fips CHAR(2) NULL,
            county_fips CHAR(5) NULL,
            import_file_name VARCHAR(1000) NULL,
            file_key NVARCHAR(260) NULL,
            tag NVARCHAR(120) NULL,
            file_suffix NVARCHAR(220) NULL,
            details NVARCHAR(MAX) NULL
        );
        CREATE INDEX IX_gdi_audit_scope_time ON dbo.gdi_audit (imported_by_user_id, state_fips, county_fips, audit_time DESC);
        CREATE INDEX IX_gdi_audit_batch_time ON dbo.gdi_audit (import_batch_id, audit_time DESC);
    END;

    DECLARE @header_table SYSNAME = N'gdi_instruments';
    DECLARE @target_table SYSNAME = CASE
        WHEN @tag = N'header' THEN N'gdi_instruments'
        WHEN @tag = N'images' THEN N'gdi_pages'
        WHEN @tag = N'names' THEN N'gdi_parties'
        WHEN @tag = N'references' THEN N'gdi_instrument_references'
        WHEN @tag = N'legals' THEN N'gdi_legals'
        ELSE N'gdi_' + @tag
    END;
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @q_header NVARCHAR(300) = N'dbo.' + QUOTENAME(@header_table);
    DECLARE @q_target NVARCHAR(300) = N'dbo.' + QUOTENAME(@target_table);

    SET @sql = N'
IF OBJECT_ID(''' + @q_header + ''',''U'') IS NULL
BEGIN
    CREATE TABLE ' + @q_header + ' (
        ID INT NOT NULL IDENTITY PRIMARY KEY,
        FN VARCHAR(1000),
        file_key NVARCHAR(260) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL,
        keyOriginalValue VARCHAR(MAX) NULL,
        OriginalValue VARCHAR(MAX),
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col03varchar VARCHAR(1000),
        col04varchar VARCHAR(1000),
        col05varchar VARCHAR(1000),
        col06varchar VARCHAR(1000),
        col07varchar VARCHAR(1000),
        col08varchar VARCHAR(1000),
        col09varchar VARCHAR(1000),
        col10varchar VARCHAR(1000),
        key_id VARCHAR(1000),
        book VARCHAR(1000),
        page_number VARCHAR(1000),
        keli_image_path VARCHAR(1000),
        beginning_page VARCHAR(1000),
        ending_page VARCHAR(1000),
        record_series_internal_id VARCHAR(1000),
        record_series_external_id VARCHAR(1000),
        instrument_type_internal_id VARCHAR(1000),
        instrument_type_external_id VARCHAR(1000),
        grantor_suffix_internal_id VARCHAR(1000),
        grantee_suffix_internal_id VARCHAR(1000),
        manual_page_count VARCHAR(1000),
        legal_type VARCHAR(1000),
        additions_internal_id VARCHAR(1000),
        additions_external_id VARCHAR(1000),
        township_range_internal_id VARCHAR(1000),
        township_range_external_id VARCHAR(1000),
        free_form_legal VARCHAR(1000),
        referenced_instrument VARCHAR(1000),
        referenced_book VARCHAR(1000),
        referenced_page VARCHAR(1000),
        col20other VARCHAR(1000),
        uf1 VARCHAR(1000),
        uf2 VARCHAR(1000),
        uf3 VARCHAR(1000),
        leftovers VARCHAR(1000),
        imported_by_user_id INT NOT NULL,
        import_batch_id UNIQUEIDENTIFIER NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL DEFAULT (0),
        imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
    );
END;

IF COL_LENGTH(''' + @q_header + ''', ''file_key'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD file_key NVARCHAR(260) NOT NULL DEFAULT ('''');
IF COL_LENGTH(''' + @q_header + ''', ''header_file_key'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD header_file_key NVARCHAR(260) NOT NULL DEFAULT ('''');
IF COL_LENGTH(''' + @q_header + ''', ''keyOriginalValue'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD keyOriginalValue VARCHAR(MAX) NULL;
IF COL_LENGTH(''' + @q_header + ''', ''free_form_legal'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD free_form_legal VARCHAR(1000) NULL;
IF COL_LENGTH(''' + @q_header + ''', ''referenced_instrument'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD referenced_instrument VARCHAR(1000) NULL;
IF COL_LENGTH(''' + @q_header + ''', ''referenced_book'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD referenced_book VARCHAR(1000) NULL;
IF COL_LENGTH(''' + @q_header + ''', ''referenced_page'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD referenced_page VARCHAR(1000) NULL;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = ''IX_' + @header_table + '_scope_key''
      AND object_id = OBJECT_ID(''' + @q_header + ''')
)
    CREATE INDEX IX_' + @header_table + '_scope_key ON ' + @q_header + ' (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

IF COL_LENGTH(''' + @q_header + ''', ''is_deleted'') IS NULL
    ALTER TABLE ' + @q_header + ' ADD is_deleted BIT NOT NULL DEFAULT (0);
';
    EXEC sys.sp_executesql @sql;

    ;WITH header_dedupe AS (
        SELECT
            h.ID,
            ROW_NUMBER() OVER (
                PARTITION BY h.state_fips, h.county_fips, h.imported_by_user_id, h.file_key, h.col01varchar
                ORDER BY h.ID DESC
            ) AS rn
        FROM dbo.gdi_instruments h
        WHERE h.col01varchar IS NOT NULL
    )
    DELETE h
    FROM dbo.gdi_instruments h
    JOIN header_dedupe d
      ON d.ID = h.ID
    WHERE d.rn > 1;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'UQ_gdi_header_fn_col01'
          AND object_id = OBJECT_ID('dbo.gdi_instruments')
    )
        CREATE UNIQUE INDEX UQ_gdi_header_fn_col01
            ON dbo.gdi_instruments (state_fips, county_fips, imported_by_user_id, file_key, col01varchar)
            WHERE col01varchar IS NOT NULL AND is_deleted = 0;

    SET @sql = N'
IF OBJECT_ID(''' + @q_target + ''',''U'') IS NULL
BEGIN
    CREATE TABLE ' + @q_target + ' (
        ID INT NOT NULL IDENTITY PRIMARY KEY,
        FN VARCHAR(1000),
        file_key NVARCHAR(260) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL,
        keyOriginalValue VARCHAR(MAX) NULL,
        OriginalValue VARCHAR(MAX),
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col03varchar VARCHAR(1000),
        col04varchar VARCHAR(1000),
        col05varchar VARCHAR(1000),
        col06varchar VARCHAR(1000),
        col07varchar VARCHAR(1000),
        col08varchar VARCHAR(1000),
        col09varchar VARCHAR(1000),
        col10varchar VARCHAR(1000),
        key_id VARCHAR(1000),
        book VARCHAR(1000),
        page_number VARCHAR(1000),
        keli_image_path VARCHAR(1000),
        beginning_page VARCHAR(1000),
        ending_page VARCHAR(1000),
        record_series_internal_id VARCHAR(1000),
        record_series_external_id VARCHAR(1000),
        instrument_type_internal_id VARCHAR(1000),
        instrument_type_external_id VARCHAR(1000),
        grantor_suffix_internal_id VARCHAR(1000),
        grantee_suffix_internal_id VARCHAR(1000),
        manual_page_count VARCHAR(1000),
        legal_type VARCHAR(1000),
        additions_internal_id VARCHAR(1000),
        additions_external_id VARCHAR(1000),
        township_range_internal_id VARCHAR(1000),
        township_range_external_id VARCHAR(1000),
        free_form_legal VARCHAR(1000),
        referenced_instrument VARCHAR(1000),
        referenced_book VARCHAR(1000),
        referenced_page VARCHAR(1000),
        col20other VARCHAR(1000),
        uf1 VARCHAR(1000),
        uf2 VARCHAR(1000),
        uf3 VARCHAR(1000),
        leftovers VARCHAR(1000),
        imported_by_user_id INT NOT NULL,
        import_batch_id UNIQUEIDENTIFIER NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL DEFAULT (0),
        imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
    );
END;

IF COL_LENGTH(''' + @q_target + ''', ''file_key'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD file_key NVARCHAR(260) NOT NULL DEFAULT ('''');
IF COL_LENGTH(''' + @q_target + ''', ''header_file_key'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD header_file_key NVARCHAR(260) NOT NULL DEFAULT ('''');
IF COL_LENGTH(''' + @q_target + ''', ''keyOriginalValue'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD keyOriginalValue VARCHAR(MAX) NULL;
IF COL_LENGTH(''' + @q_target + ''', ''free_form_legal'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD free_form_legal VARCHAR(1000) NULL;
IF COL_LENGTH(''' + @q_target + ''', ''referenced_instrument'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD referenced_instrument VARCHAR(1000) NULL;
IF COL_LENGTH(''' + @q_target + ''', ''referenced_book'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD referenced_book VARCHAR(1000) NULL;
IF COL_LENGTH(''' + @q_target + ''', ''referenced_page'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD referenced_page VARCHAR(1000) NULL;
IF ''' + @target_table + ''' = ''gdi_pages'' AND COL_LENGTH(''' + @q_target + ''', ''original_page_number'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD original_page_number VARCHAR(1000) NULL;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = ''IX_' + @target_table + '_scope_key''
      AND object_id = OBJECT_ID(''' + @q_target + ''')
)
    CREATE INDEX IX_' + @target_table + '_scope_key ON ' + @q_target + ' (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

IF COL_LENGTH(''' + @q_target + ''', ''is_deleted'') IS NULL
    ALTER TABLE ' + @q_target + ' ADD is_deleted BIT NOT NULL DEFAULT (0);
';
    EXEC sys.sp_executesql @sql;
