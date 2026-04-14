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

    -- Replace mode is overlap-based and handled after parsing this incoming file.

    DROP TABLE IF EXISTS #TempDataCollector;
    -- Store raw source lines without width truncation. Some county files have very wide rows.
    CREATE TABLE #TempDataCollector (Field1 VARCHAR(MAX));

    SET @sql =
        N'BULK INSERT #TempDataCollector
          FROM ' + QUOTENAME(REPLACE(@ImportFileName, '''', ''''''), '''') + N'
          WITH
          (
              FIRSTROW = 1,
              FIELDTERMINATOR = ''~'',
              ROWTERMINATOR = ''0x0a'',
              TABLOCK
          );';
    EXEC sys.sp_executesql @sql;

    UPDATE #TempDataCollector
    SET Field1 = LTRIM(RTRIM(Field1));
    DECLARE @source_row_count INT = (SELECT COUNT(1) FROM #TempDataCollector);

    DROP TABLE IF EXISTS #ParsedData;
    ;WITH seeded AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS row_id,
            CAST(Field1 AS VARCHAR(MAX)) AS original_value
        FROM #TempDataCollector
    ),
    quote_parse AS (
        SELECT
            s.row_id,
            s.original_value,
            CAST(0 AS INT) AS n,
            CAST(s.original_value AS VARCHAR(MAX)) AS rem,
            CAST('' AS VARCHAR(1000)) AS token
        FROM seeded s

        UNION ALL

        SELECT
            q.row_id,
            q.original_value,
            q.n + 1 AS n,
            CASE
                WHEN a.first_quote_pos > 0 AND a.second_quote_pos > 0
                    THEN STUFF(q.rem, a.first_quote_pos, a.second_quote_pos + 1, '')
                ELSE q.rem
            END AS rem,
            CASE
                WHEN a.first_quote_pos > 0 AND a.second_quote_pos > 0
                    THEN CAST(SUBSTRING(a.after_first_quote, 1, a.second_quote_pos - 1) AS VARCHAR(1000))
                ELSE CAST('' AS VARCHAR(1000))
            END AS token
        FROM quote_parse q
        CROSS APPLY (
            SELECT
                CHARINDEX('"', q.rem) AS first_quote_pos,
                CASE
                    WHEN CHARINDEX('"', q.rem) > 0
                        THEN SUBSTRING(q.rem, CHARINDEX('"', q.rem) + 1, LEN(q.rem))
                    ELSE ''
                END AS after_first_quote
        ) p
        CROSS APPLY (
            SELECT
                p.first_quote_pos,
                p.after_first_quote,
                CHARINDEX('"', p.after_first_quote) AS second_quote_pos
        ) a
        WHERE q.n < 10
    ),
    quote_pivot AS (
        SELECT
            q.row_id,
            q.original_value,
            MAX(CASE WHEN q.n = 1 THEN q.token END) AS col01varchar,
            MAX(CASE WHEN q.n = 2 THEN q.token END) AS col02varchar,
            MAX(CASE WHEN q.n = 3 THEN q.token END) AS col03varchar,
            MAX(CASE WHEN q.n = 4 THEN q.token END) AS col04varchar,
            MAX(CASE WHEN q.n = 5 THEN q.token END) AS col05varchar,
            MAX(CASE WHEN q.n = 6 THEN q.token END) AS col06varchar,
            MAX(CASE WHEN q.n = 7 THEN q.token END) AS col07varchar,
            MAX(CASE WHEN q.n = 8 THEN q.token END) AS col08varchar,
            MAX(CASE WHEN q.n = 9 THEN q.token END) AS col09varchar,
            MAX(CASE WHEN q.n = 10 THEN q.token END) AS col10varchar,
            MAX(CASE WHEN q.n = 10 THEN q.rem END) AS leftovers
        FROM quote_parse q
        GROUP BY q.row_id, q.original_value
    )
    SELECT
        CAST(@ImportFileName AS VARCHAR(1000)) AS fn,
        CAST(@file_key AS NVARCHAR(260)) AS file_key,
        CAST(@header_file_key AS NVARCHAR(260)) AS header_file_key,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(p.original_value, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '') AS OriginalValue,
        ISNULL(p.col01varchar, '') AS col01varchar,
        ISNULL(p.col02varchar, '') AS col02varchar,
        ISNULL(p.col03varchar, '') AS col03varchar,
        ISNULL(p.col04varchar, '') AS col04varchar,
        ISNULL(p.col05varchar, '') AS col05varchar,
        ISNULL(p.col06varchar, '') AS col06varchar,
        ISNULL(p.col07varchar, '') AS col07varchar,
        ISNULL(p.col08varchar, '') AS col08varchar,
        ISNULL(p.col09varchar, '') AS col09varchar,
        ISNULL(p.col10varchar, '') AS col10varchar,
        MAX(CASE WHEN j.[key] = 0 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS key_id,
        MAX(CASE WHEN j.[key] = 1 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS book,
        MAX(CASE WHEN j.[key] = 2 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS page_number,
        MAX(CASE WHEN j.[key] = 3 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS keli_image_path,
        MAX(CASE WHEN j.[key] = 4 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS beginning_page,
        MAX(CASE WHEN j.[key] = 5 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS ending_page,
        MAX(CASE WHEN j.[key] = 6 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS record_series_internal_id,
        MAX(CASE WHEN j.[key] = 7 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS record_series_external_id,
        MAX(CASE WHEN j.[key] = 8 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS instrument_type_internal_id,
        MAX(CASE WHEN j.[key] = 9 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS instrument_type_external_id,
        MAX(CASE WHEN j.[key] = 10 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS grantor_suffix_internal_id,
        MAX(CASE WHEN j.[key] = 11 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS grantee_suffix_internal_id,
        MAX(CASE WHEN j.[key] = 12 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS manual_page_count,
        MAX(CASE WHEN j.[key] = 13 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS legal_type,
        MAX(CASE WHEN j.[key] = 14 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS additions_internal_id,
        MAX(CASE WHEN j.[key] = 15 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS additions_external_id,
        MAX(CASE WHEN j.[key] = 16 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS township_range_internal_id,
        MAX(CASE WHEN j.[key] = 17 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS township_range_external_id,
        MAX(CASE WHEN j.[key] = 18 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS free_form_legal,
        MAX(CASE WHEN j.[key] = 19 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS referenced_instrument,
        MAX(CASE WHEN j.[key] = 20 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS referenced_book,
        MAX(CASE WHEN j.[key] = 21 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS referenced_page,
        MAX(CASE WHEN j.[key] = 22 THEN LTRIM(RTRIM(CAST(j.value AS VARCHAR(1000)))) ELSE '' END) AS col20other,
        CAST('' AS VARCHAR(1000)) AS uf1,
        CAST('' AS VARCHAR(1000)) AS uf2,
        CAST('' AS VARCHAR(1000)) AS uf3,
        ISNULL(p.leftovers, '') AS leftovers,
        CAST(@ImportedByUserId AS INT) AS imported_by_user_id,
        CAST(@batch_id AS UNIQUEIDENTIFIER) AS import_batch_id,
        CAST(@state_fips AS CHAR(2)) AS state_fips,
        CAST(@county_fips AS CHAR(5)) AS county_fips,
        CAST(0 AS BIT) AS is_deleted,
        SYSDATETIMEOFFSET() AS imported_at
    INTO #ParsedData
    FROM quote_pivot p
    OUTER APPLY (
        SELECT
            CASE
                WHEN ISNULL(p.leftovers, '') = ''
                    THEN N'[]'
                ELSE N'["' + REPLACE(STRING_ESCAPE(CAST(p.leftovers AS NVARCHAR(MAX)), 'json'), ',', '","') + N'"]'
            END AS leftovers_json
    ) js
    OUTER APPLY OPENJSON(js.leftovers_json) j
    GROUP BY
        p.row_id,
        p.original_value,
        p.col01varchar, p.col02varchar, p.col03varchar, p.col04varchar, p.col05varchar,
        p.col06varchar, p.col07varchar, p.col08varchar, p.col09varchar, p.col10varchar,
        p.leftovers;

    DECLARE @parsed_row_count INT = (SELECT COUNT(1) FROM #ParsedData);
    DECLARE @append_existing_match_count INT = 0;

    IF @mode = 'A'
    BEGIN
        DROP TABLE IF EXISTS #gdi_scope_existing_rows;
        CREATE TABLE #gdi_scope_existing_rows (
            fn VARCHAR(1000) NOT NULL,
            col01varchar VARCHAR(1000) NOT NULL,
            original_value VARCHAR(MAX) NOT NULL
        );
        CREATE INDEX IX_gdi_scope_existing_rows_fn ON #gdi_scope_existing_rows (fn);

        INSERT INTO #gdi_scope_existing_rows (fn, col01varchar, original_value)
        SELECT
            ISNULL(g.fn, ''),
            ISNULL(g.col01varchar, ''),
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(g.OriginalValue, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '')
        FROM dbo.GenericDataImport g
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @state_fips
          AND g.county_fips = @county_fips
          AND ISNULL(g.is_deleted, 0) = 0;

        SELECT @append_existing_match_count = COUNT(1)
        FROM #ParsedData p
        JOIN #gdi_scope_existing_rows e
          ON e.fn = ISNULL(p.fn, '')
         AND e.col01varchar = ISNULL(p.col01varchar, '')
         AND e.original_value = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(p.OriginalValue, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '');
    END;

    IF @mode = 'A'
    BEGIN
        INSERT INTO dbo.GenericDataImport (
            fn, OriginalValue,
            col01varchar, col02varchar, col03varchar, col04varchar, col05varchar,
            col06varchar, col07varchar, col08varchar, col09varchar, col10varchar,
            key_id, book, page_number, keli_image_path,
            beginning_page, ending_page, record_series_internal_id, record_series_external_id, instrument_type_internal_id,
            instrument_type_external_id, grantor_suffix_internal_id, grantee_suffix_internal_id, manual_page_count, legal_type,
            additions_internal_id, additions_external_id, township_range_internal_id, township_range_external_id, free_form_legal,
            referenced_instrument, referenced_book, referenced_page, col20other,
            uf1, uf2, uf3, leftovers,
            imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            p.fn, p.OriginalValue,
            p.col01varchar, p.col02varchar, p.col03varchar, p.col04varchar, p.col05varchar,
            p.col06varchar, p.col07varchar, p.col08varchar, p.col09varchar, p.col10varchar,
            p.key_id, p.book, p.page_number, p.keli_image_path,
            p.beginning_page, p.ending_page, p.record_series_internal_id, p.record_series_external_id, p.instrument_type_internal_id,
            p.instrument_type_external_id, p.grantor_suffix_internal_id, p.grantee_suffix_internal_id, p.manual_page_count, p.legal_type,
            p.additions_internal_id, p.additions_external_id, p.township_range_internal_id, p.township_range_external_id, p.free_form_legal,
            p.referenced_instrument, p.referenced_book, p.referenced_page, p.col20other,
            p.uf1, p.uf2, p.uf3, p.leftovers,
            p.imported_by_user_id, p.import_batch_id, p.state_fips, p.county_fips, p.is_deleted, p.imported_at
        FROM #ParsedData p
        LEFT JOIN #gdi_scope_existing_rows e
          ON e.fn = ISNULL(p.fn, '')
         AND e.col01varchar = ISNULL(p.col01varchar, '')
         AND e.original_value = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(p.OriginalValue, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '')
        WHERE e.fn IS NULL;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.GenericDataImport (
            fn, OriginalValue,
            col01varchar, col02varchar, col03varchar, col04varchar, col05varchar,
            col06varchar, col07varchar, col08varchar, col09varchar, col10varchar,
            key_id, book, page_number, keli_image_path,
            beginning_page, ending_page, record_series_internal_id, record_series_external_id, instrument_type_internal_id,
            instrument_type_external_id, grantor_suffix_internal_id, grantee_suffix_internal_id, manual_page_count, legal_type,
            additions_internal_id, additions_external_id, township_range_internal_id, township_range_external_id, free_form_legal,
            referenced_instrument, referenced_book, referenced_page, col20other,
            uf1, uf2, uf3, leftovers,
            imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            p.fn, p.OriginalValue,
            p.col01varchar, p.col02varchar, p.col03varchar, p.col04varchar, p.col05varchar,
            p.col06varchar, p.col07varchar, p.col08varchar, p.col09varchar, p.col10varchar,
            p.key_id, p.book, p.page_number, p.keli_image_path,
            p.beginning_page, p.ending_page, p.record_series_internal_id, p.record_series_external_id, p.instrument_type_internal_id,
            p.instrument_type_external_id, p.grantor_suffix_internal_id, p.grantee_suffix_internal_id, p.manual_page_count, p.legal_type,
            p.additions_internal_id, p.additions_external_id, p.township_range_internal_id, p.township_range_external_id, p.free_form_legal,
            p.referenced_instrument, p.referenced_book, p.referenced_page, p.col20other,
            p.uf1, p.uf2, p.uf3, p.leftovers,
            p.imported_by_user_id, p.import_batch_id, p.state_fips, p.county_fips, p.is_deleted, p.imported_at
        FROM #ParsedData p;
    END;

    IF @mode = 'A' AND ISNULL(@append_existing_match_count, 0) > 0
    BEGIN
        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, file_key, tag, file_suffix, details
        )
        VALUES (
            'info',
            'append_existing_rows_skipped',
            N'Append mode skipped rows that already existed in scoped import data.',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName, @file_key, @tag, @file_suffix,
            CONCAT(N'{"skippedExistingRows":', CAST(@append_existing_match_count AS NVARCHAR(40)), N'}')
        );
    END;

    IF @mode = 'D' AND ISNULL(@SkipSplitRebuild, 0) = 0
    BEGIN
        DROP TABLE IF EXISTS #gdi_ranked_batches;
        ;WITH ranked_batches AS (
            SELECT
                g.import_batch_id,
                ROW_NUMBER() OVER (
                    ORDER BY MAX(g.imported_at) DESC, MAX(g.ID) DESC
                ) AS rn
            FROM dbo.GenericDataImport g
            WHERE g.imported_by_user_id = @ImportedByUserId
              AND g.state_fips = @state_fips
              AND g.county_fips = @county_fips
              AND g.import_batch_id IS NOT NULL
            GROUP BY g.import_batch_id
        )
        SELECT
            rb.import_batch_id,
            rb.rn
        INTO #gdi_ranked_batches
        FROM ranked_batches rb;
        CREATE UNIQUE CLUSTERED INDEX IX_gdi_ranked_batches_batch ON #gdi_ranked_batches (import_batch_id);
        CREATE INDEX IX_gdi_ranked_batches_rn ON #gdi_ranked_batches (rn, import_batch_id);

        -- Replace mode is batch-driven: keep the current batch active, retain the
        -- immediately previous batch as soft-deleted history, and purge anything
        -- older after that.
        UPDATE g
        SET g.is_deleted = 1
        FROM dbo.GenericDataImport g
        JOIN #gdi_ranked_batches rb
          ON rb.import_batch_id = g.import_batch_id
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @state_fips
          AND g.county_fips = @county_fips
          AND rb.rn >= 2
          AND ISNULL(g.is_deleted, 0) = 0;

        DELETE g
        FROM dbo.GenericDataImport g
        LEFT JOIN #gdi_ranked_batches rb
          ON rb.import_batch_id = g.import_batch_id
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @state_fips
          AND g.county_fips = @county_fips
          AND (
                g.import_batch_id IS NULL
                OR ISNULL(rb.rn, 999999) > 2
          );
    END;

    IF ISNULL(@SkipSplitRebuild, 0) = 0
    BEGIN
        UPDATE g
        SET g.OriginalValue = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(g.OriginalValue, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '')
        FROM dbo.GenericDataImport g
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @state_fips
          AND g.county_fips = @county_fips
          AND (
                g.OriginalValue IS NULL
             OR CHARINDEX('"', ISNULL(g.OriginalValue, '')) > 0
             OR CHARINDEX(',', ISNULL(g.OriginalValue, '')) > 0
             OR CHARINDEX(CHAR(9), ISNULL(g.OriginalValue, '')) > 0
             OR CHARINDEX(CHAR(10), ISNULL(g.OriginalValue, '')) > 0
             OR CHARINDEX(CHAR(13), ISNULL(g.OriginalValue, '')) > 0
             OR CHARINDEX(' ', ISNULL(g.OriginalValue, '')) > 0
          );
    END;

    IF ISNULL(@SkipSplitRebuild, 0) = 0
    BEGIN
        DECLARE @is_split_job BIT = 0;
        DECLARE @split_book_start_raw VARCHAR(1000) = '';
        DECLARE @split_book_end_raw VARCHAR(1000) = '';
        DECLARE @split_book_start_key VARCHAR(7) = '';
        DECLARE @split_book_end_key VARCHAR(7) = '';
        DECLARE @has_split_book_range BIT = 0;
        IF OBJECT_ID(N'dbo.county_work_items', N'U') IS NOT NULL
           AND COL_LENGTH('dbo.county_work_items', 'split_book_start') IS NOT NULL
           AND COL_LENGTH('dbo.county_work_items', 'split_book_end') IS NOT NULL
        BEGIN
            SELECT TOP 1
                @is_split_job = ISNULL(cwi.is_split_job, 0),
                @split_book_start_raw = LTRIM(RTRIM(ISNULL(CAST(cwi.split_book_start AS VARCHAR(1000)), ''))),
                @split_book_end_raw = LTRIM(RTRIM(ISNULL(CAST(cwi.split_book_end AS VARCHAR(1000)), '')))
            FROM dbo.county_work_items cwi
            WHERE cwi.county_fips = @county_fips;
            SET @split_book_start_key = CASE
                WHEN @split_book_start_raw = '' THEN ''
                WHEN RIGHT(UPPER(@split_book_start_raw), 1) LIKE '[A-Z]' AND LEN(@split_book_start_raw) > 1
                    THEN RIGHT('000000' + LEFT(UPPER(@split_book_start_raw), LEN(@split_book_start_raw) - 1), 6)
                       + RIGHT(UPPER(@split_book_start_raw), 1)
                ELSE RIGHT('000000' + UPPER(@split_book_start_raw), 6)
            END;
            SET @split_book_end_key = CASE
                WHEN @split_book_end_raw = '' THEN ''
                WHEN RIGHT(UPPER(@split_book_end_raw), 1) LIKE '[A-Z]' AND LEN(@split_book_end_raw) > 1
                    THEN RIGHT('000000' + LEFT(UPPER(@split_book_end_raw), LEN(@split_book_end_raw) - 1), 6)
                       + RIGHT(UPPER(@split_book_end_raw), 1)
                ELSE RIGHT('000000' + UPPER(@split_book_end_raw), 6)
            END;
            IF @is_split_job = 1
               AND @split_book_start_key <> ''
               AND @split_book_end_key <> ''
               AND @split_book_end_key >= @split_book_start_key
            BEGIN
                SET @has_split_book_range = 1;
            END;
        END;

        DECLARE @current_tag NVARCHAR(120);
        DECLARE @current_table SYSNAME;
        DECLARE @q_current NVARCHAR(300);
        DECLARE @split_table_cols NVARCHAR(MAX);
        DECLARE @split_insert_cols NVARCHAR(MAX);
        DECLARE @split_select_cols NVARCHAR(MAX);

        DROP TABLE IF EXISTS #gdi_scope_parts_fast;
        SELECT
            g.ID AS source_id,
            g.fn,
            g.col01varchar,
            g.OriginalValue,
            g.import_batch_id,
            k.file_key,
            CASE
                WHEN t.tag IS NULL OR LTRIM(RTRIM(t.tag)) = '' OR PATINDEX('%[^a-z0-9_]%', t.tag) > 0 THEN 'misc'
                WHEN t.tag IN ('image', 'images') THEN 'images'
                WHEN t.tag IN ('name', 'names') THEN 'names'
                WHEN t.tag IN ('reference', 'references', 'ref') THEN 'references'
                WHEN t.tag IN ('legal', 'legals') THEN 'legals'
                WHEN t.tag IN ('header', 'headers') THEN 'header'
                ELSE t.tag
            END AS tag,
            CASE WHEN d.digit_pos > 1 THEN SUBSTRING(k.file_key, d.digit_pos, LEN(k.file_key)) ELSE '' END AS file_suffix,
            CASE
                WHEN t.tag IN ('header', 'headers') THEN k.file_key
                WHEN CASE WHEN d.digit_pos > 1 THEN SUBSTRING(k.file_key, d.digit_pos, LEN(k.file_key)) ELSE '' END <> '' THEN 'header' + CASE WHEN d.digit_pos > 1 THEN SUBSTRING(k.file_key, d.digit_pos, LEN(k.file_key)) ELSE '' END
                ELSE 'header_' + k.file_key
            END AS header_file_key
        INTO #gdi_scope_parts_fast
        FROM dbo.GenericDataImport g
        CROSS APPLY (
            SELECT
                LOWER(
                    CASE
                        WHEN CHARINDEX('\', REVERSE(g.fn)) > 0 THEN RIGHT(g.fn, CHARINDEX('\', REVERSE(g.fn)) - 1)
                        ELSE g.fn
                    END
                ) AS file_name
        ) n
        CROSS APPLY (
            SELECT
                CASE
                    WHEN CHARINDEX('.', REVERSE(n.file_name)) > 0 THEN LEFT(n.file_name, LEN(n.file_name) - CHARINDEX('.', REVERSE(n.file_name)))
                    ELSE n.file_name
                END AS file_key
        ) k
        CROSS APPLY (
            SELECT
                PATINDEX('%[0-9]%', k.file_key) AS digit_pos
        ) d
        CROSS APPLY (
            SELECT
                CASE WHEN d.digit_pos > 1 THEN LEFT(k.file_key, d.digit_pos - 1) ELSE k.file_key END AS tag
        ) t
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @state_fips
          AND g.county_fips = @county_fips
          -- Rebuild scoped gdi_* tables from the active import only so DQ scans
          -- do not pick older batch rows with the same county/user scope.
          AND g.import_batch_id = @batch_id
          AND ISNULL(g.is_deleted, 0) = 0;

        CREATE INDEX IX_gdi_scope_parts_fast_tag ON #gdi_scope_parts_fast (tag);
        CREATE INDEX IX_gdi_scope_parts_fast_batch ON #gdi_scope_parts_fast (import_batch_id);
        CREATE INDEX IX_gdi_scope_parts_fast_source ON #gdi_scope_parts_fast (source_id);

        DROP TABLE IF EXISTS #gdi_scope_headers_fast;
        SELECT
            h.imported_by_user_id,
            h.state_fips,
            h.county_fips,
            h.col01varchar,
            h.OriginalValue,
            sp.file_key AS hdr_file_key
        INTO #gdi_scope_headers_fast
        FROM #gdi_scope_parts_fast sp
        JOIN dbo.GenericDataImport h
          ON h.ID = sp.source_id
        WHERE sp.tag = 'header';
        CREATE INDEX IX_gdi_scope_headers_fast_col01 ON #gdi_scope_headers_fast (imported_by_user_id, state_fips, county_fips, col01varchar) INCLUDE (hdr_file_key, OriginalValue);
        CREATE INDEX IX_gdi_scope_headers_fast_hdr ON #gdi_scope_headers_fast (imported_by_user_id, state_fips, county_fips, hdr_file_key) INCLUDE (col01varchar, OriginalValue);

        -- Ensure scoped names rows are fully refreshed even when the current import
        -- does not include a names file/tag.
        IF OBJECT_ID(N'dbo.gdi_parties', N'U') IS NOT NULL
        BEGIN
            DELETE FROM dbo.gdi_parties
            WHERE imported_by_user_id = @ImportedByUserId
              AND state_fips = @state_fips
              AND county_fips = @county_fips;
        END;

        DECLARE tag_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT sp.tag
            FROM #gdi_scope_parts_fast sp;

        OPEN tag_cursor;
        FETCH NEXT FROM tag_cursor INTO @current_tag;
        WHILE @@FETCH_STATUS = 0
        BEGIN
        SET @current_table = CASE
            WHEN @current_tag = N'header' THEN N'gdi_instruments'
            WHEN @current_tag = N'images' THEN N'gdi_pages'
            WHEN @current_tag = N'names' THEN N'gdi_parties'
            WHEN @current_tag = N'references' THEN N'gdi_instrument_references'
            WHEN @current_tag = N'legals' THEN N'gdi_legals'
            ELSE N'gdi_' + @current_tag
        END;
        SET @q_current = N'dbo.' + QUOTENAME(@current_table);
        SET @split_table_cols = N'';
        SET @split_insert_cols = N'';
        SET @split_select_cols = N'';

        IF @current_tag = N'header'
        BEGIN
            SET @split_table_cols = N'
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col04varchar VARCHAR(1000),
        col05varchar VARCHAR(1000),
        col06varchar VARCHAR(1000),
        internal_id VARCHAR(1000),
        external_id VARCHAR(1000),
        instrument_number VARCHAR(1000),
        recorded_date VARCHAR(1000),
        manual_page_count VARCHAR(1000),
        book VARCHAR(1000),
        beginning_page VARCHAR(1000),
        ending_page VARCHAR(1000),
        grantor_suffix_internal_id VARCHAR(1000),
        grantee_suffix_internal_id VARCHAR(1000),';

            SET @split_insert_cols = N'
                col01varchar, col02varchar, col04varchar, col05varchar, col06varchar,
                internal_id, external_id,
                instrument_number, recorded_date,
                manual_page_count, book, beginning_page, ending_page, grantor_suffix_internal_id, grantee_suffix_internal_id,';

            SET @split_select_cols = N'
                ISNULL(src.col01varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col04varchar, ''''), ISNULL(src.col05varchar, ''''), ISNULL(src.col06varchar, ''''),
                ISNULL(src.key_id, ''''), ISNULL(src.col01varchar, ''''),
                ISNULL(src.col02varchar, ''''), ISNULL(src.col06varchar, ''''),
                ISNULL(src.manual_page_count, ''''), ISNULL(src.book, ''''), ISNULL(src.beginning_page, ''''), ISNULL(src.ending_page, ''''), ISNULL(src.grantor_suffix_internal_id, ''''), ISNULL(src.grantee_suffix_internal_id, ''''),';
        END
        ELSE IF @current_tag = N'images'
        BEGIN
            SET @split_table_cols = N'
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col03varchar VARCHAR(1000),
        col04varchar VARCHAR(1000),
        internal_id VARCHAR(1000),
        instrument_internal_id VARCHAR(1000),
        instrument_external_id VARCHAR(1000),
        book VARCHAR(1000),
        original_page_number VARCHAR(1000),
        page_number VARCHAR(1000),
        image_path VARCHAR(1000),
        key_id VARCHAR(1000),';

            SET @split_insert_cols = N'
                col01varchar, col02varchar, col03varchar, col04varchar,
                internal_id, instrument_internal_id, instrument_external_id,
                book, original_page_number, page_number, image_path,
                key_id,';

            SET @split_select_cols = N'
                ISNULL(src.col01varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col03varchar, ''''), ISNULL(src.col04varchar, ''''),
                ISNULL(src.key_id, ''''), '''', '''',
                ISNULL(src.book, ''''), '''', ISNULL(src.page_number, ''''),
                ISNULL(src.col03varchar, ''''),
                ISNULL(src.key_id, ''''),';
        END
        ELSE IF @current_tag = N'legals'
        BEGIN
            SET @split_table_cols = N'
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col06varchar VARCHAR(1000),
        col07varchar VARCHAR(1000),
        col08varchar VARCHAR(1000),
        book VARCHAR(1000),
        page_number VARCHAR(1000),
        internal_id VARCHAR(1000),
        instrument_internal_id VARCHAR(1000),
        instrument_external_id VARCHAR(1000),
        line VARCHAR(1000),
        legal_type VARCHAR(1000),
        block VARCHAR(1000),
        lot VARCHAR(1000),
        section VARCHAR(1000),
        location VARCHAR(1000),
        free_form_legal VARCHAR(1000),';

            SET @split_insert_cols = N'
                col01varchar, col02varchar, col06varchar, col07varchar, col08varchar,
                book, page_number, internal_id, instrument_internal_id, instrument_external_id, line, legal_type,
                block, lot, section, location, free_form_legal,
                ';

            SET @split_select_cols = N'
                ISNULL(src.col01varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col06varchar, ''''), ISNULL(src.col07varchar, ''''), ISNULL(src.col08varchar, ''''),
                ISNULL(src.book, ''''), ISNULL(src.page_number, ''''), ISNULL(src.key_id, ''''), '''', '''', '''', ISNULL(src.legal_type, ''''),
                ISNULL(src.col06varchar, ''''), ISNULL(src.col07varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col08varchar, ''''), ISNULL(src.free_form_legal, ''''),
                ';
        END
        ELSE IF @current_tag = N'names'
        BEGIN
            SET @split_table_cols = N'
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col03varchar VARCHAR(1000),
        book VARCHAR(1000),
        page_number VARCHAR(1000),
        internal_id VARCHAR(1000),
        instrument_internal_id VARCHAR(1000),
        instrument_external_id VARCHAR(1000),
        party_type VARCHAR(1000),
        line VARCHAR(1000),
        name VARCHAR(1000),';

            SET @split_insert_cols = N'
                col01varchar, col02varchar, col03varchar, book, page_number,
                internal_id, instrument_internal_id, instrument_external_id, party_type, line, name,';

            SET @split_select_cols = N'
                ISNULL(src.col01varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col03varchar, ''''), ISNULL(src.book, ''''), ISNULL(src.page_number, ''''),
                ISNULL(src.key_id, ''''), '''', '''', ISNULL(src.col02varchar, ''''), '''', ISNULL(src.col03varchar, ''''),
                ';
        END
        ELSE IF @current_tag = N'references'
        BEGIN
            SET @split_table_cols = N'
        col01varchar VARCHAR(1000),
        col02varchar VARCHAR(1000),
        col03varchar VARCHAR(1000),
        book VARCHAR(1000),
        page_number VARCHAR(1000),
        internal_id VARCHAR(1000),
        instrument_external_id VARCHAR(1000),
        referenced_instrument_internal_id VARCHAR(1000),
        referenced_instrument_external_id VARCHAR(1000),
        referenced_book VARCHAR(1000),
        referenced_page VARCHAR(1000),';

            SET @split_insert_cols = N'
                col01varchar, col02varchar, col03varchar, book, page_number,
                internal_id, instrument_external_id, referenced_instrument_internal_id, referenced_instrument_external_id, referenced_book, referenced_page,
                ';

            SET @split_select_cols = N'
                ISNULL(src.col01varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col03varchar, ''''), ISNULL(src.book, ''''), ISNULL(src.page_number, ''''),
                ISNULL(src.key_id, ''''), '''', '''', '''', ISNULL(src.referenced_book, ''''), ISNULL(src.referenced_page, ''''),
                ';
        END
        ELSE
        BEGIN
            SET @split_table_cols = N'
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
        beginning_page VARCHAR(1000),
        ending_page VARCHAR(1000),
        leftovers VARCHAR(1000),';

            SET @split_insert_cols = N'
                col01varchar, col02varchar, col03varchar, col04varchar, col05varchar, col06varchar, col07varchar, col08varchar, col09varchar, col10varchar,
                key_id, book, page_number, beginning_page, ending_page, leftovers,';

            SET @split_select_cols = N'
                ISNULL(src.col01varchar, ''''), ISNULL(src.col02varchar, ''''), ISNULL(src.col03varchar, ''''), ISNULL(src.col04varchar, ''''), ISNULL(src.col05varchar, ''''), ISNULL(src.col06varchar, ''''), ISNULL(src.col07varchar, ''''), ISNULL(src.col08varchar, ''''), ISNULL(src.col09varchar, ''''), ISNULL(src.col10varchar, ''''),
                ISNULL(src.key_id, ''''), ISNULL(src.book, ''''), ISNULL(src.page_number, ''''), ISNULL(src.beginning_page, ''''), ISNULL(src.ending_page, ''''), ISNULL(src.leftovers, ''''),';
        END;

        SET @sql = N'
DROP TABLE IF EXISTS ' + @q_current + N';
CREATE TABLE ' + @q_current + ' (
        ID INT NOT NULL IDENTITY PRIMARY KEY,
        FN VARCHAR(1000),
        file_key NVARCHAR(260) NOT NULL,
        header_file_key NVARCHAR(260) NOT NULL,
        keyOriginalValue VARCHAR(MAX) NULL,
        OriginalValue VARCHAR(MAX),
        ' + @split_table_cols + N'
        is_split_book BIT NOT NULL DEFAULT (0),
        imported_by_user_id INT NOT NULL,
        import_batch_id UNIQUEIDENTIFIER NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL DEFAULT (0),
        imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
    );

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = ''IX_' + @current_table + '_scope_key''
      AND object_id = OBJECT_ID(''' + @q_current + ''')
)
    CREATE INDEX IX_' + @current_table + '_scope_key ON ' + @q_current + ' (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

IF COL_LENGTH(''' + @q_current + ''', ''is_deleted'') IS NULL
    ALTER TABLE ' + @q_current + ' ADD is_deleted BIT NOT NULL DEFAULT (0);
';
        EXEC sys.sp_executesql @sql;

        SET @sql = N'
            INSERT INTO ' + @q_current + N' (
                fn, file_key, header_file_key, keyOriginalValue, OriginalValue,
                ' + @split_insert_cols + N'
                is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
            )
            SELECT
                ISNULL(src.fn, ''''),
                sp.file_key,
                sp.header_file_key,
                CASE
                    WHEN sp.tag = ''header'' THEN ISNULL(src.OriginalValue, '''')
                    ELSE ISNULL(hdr.OriginalValue, '''')
                END AS keyOriginalValue,
                ISNULL(src.OriginalValue, ''''),
                ' + @split_select_cols + N'
                0,
                src.imported_by_user_id, src.import_batch_id, src.state_fips, src.county_fips, ISNULL(src.is_deleted, 0), src.imported_at
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport src
              ON src.ID = sp.source_id
            LEFT JOIN #gdi_scope_headers_fast hdr
                ON hdr.imported_by_user_id = src.imported_by_user_id
               AND hdr.state_fips = src.state_fips
               AND hdr.county_fips = src.county_fips
               AND hdr.col01varchar = src.col01varchar
               AND hdr.hdr_file_key = sp.header_file_key
            WHERE src.imported_by_user_id = @uid
              AND src.state_fips = @sf
              AND src.county_fips = @cf
              AND sp.tag = @tag
            ORDER BY
                sp.header_file_key,
                CASE
                    WHEN TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(src.col01varchar, ''''))), '''')) IS NULL THEN 1
                    ELSE 0
                END,
                TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(src.col01varchar, ''''))), '''')),
                LTRIM(RTRIM(ISNULL(src.col01varchar, ''''))),
                src.ID
            ;';
        EXEC sys.sp_executesql @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @tag NVARCHAR(120)',
            @ImportedByUserId, @state_fips, @county_fips, @current_tag;

            FETCH NEXT FROM tag_cursor INTO @current_tag;
        END;
        CLOSE tag_cursor;
        DEALLOCATE tag_cursor;

        DECLARE @image_table SYSNAME = CASE
            WHEN OBJECT_ID(N'dbo.gdi_pages', N'U') IS NOT NULL THEN N'gdi_pages'
            ELSE NULL
        END;

        IF @image_table IS NOT NULL
        BEGIN
            SET @sql = N'
IF COL_LENGTH(''dbo.' + QUOTENAME(@image_table) + ''', ''header_file_key'') IS NULL
    ALTER TABLE dbo.' + QUOTENAME(@image_table) + ' ADD header_file_key NVARCHAR(260) NOT NULL DEFAULT ('''');
	IF COL_LENGTH(''dbo.' + QUOTENAME(@image_table) + ''', ''file_key'') IS NULL
	    ALTER TABLE dbo.' + QUOTENAME(@image_table) + ' ADD file_key NVARCHAR(260) NOT NULL DEFAULT ('''');
	IF COL_LENGTH(''dbo.' + QUOTENAME(@image_table) + ''', ''keyOriginalValue'') IS NULL
	    ALTER TABLE dbo.' + QUOTENAME(@image_table) + ' ADD keyOriginalValue VARCHAR(MAX) NULL;
	IF NOT EXISTS (
	    SELECT 1
	    FROM sys.indexes
	    WHERE name = ''IX_' + @image_table + '_scope_active''
	      AND object_id = OBJECT_ID(''dbo.' + QUOTENAME(@image_table) + ''')
	)
	    CREATE INDEX IX_' + @image_table + '_scope_active
	        ON dbo.' + QUOTENAME(@image_table) + ' (imported_by_user_id, state_fips, county_fips, is_deleted, id)
	        INCLUDE (header_file_key, col01varchar, col03varchar);';
            EXEC sys.sp_executesql @sql;

            DROP TABLE IF EXISTS #gdi_image_page_values;
            CREATE TABLE #gdi_image_page_values (
                image_id INT NOT NULL,
                book_value VARCHAR(1000) NOT NULL,
                page_value VARCHAR(1000) NOT NULL
            );

            DROP TABLE IF EXISTS #gdi_image_page_bounds;
            CREATE TABLE #gdi_image_page_bounds (
                header_file_key NVARCHAR(260) NOT NULL,
                col01varchar VARCHAR(1000) NOT NULL,
                book_value VARCHAR(1000) NOT NULL,
                begin_value VARCHAR(1000) NOT NULL,
                end_value VARCHAR(1000) NOT NULL
            );

            SET @sql = N'
                ;WITH raw_paths AS (
                    SELECT
                        i.id,
                        ISNULL(i.col01varchar, '''') AS col01varchar,
                        REPLACE(REPLACE(LTRIM(RTRIM(COALESCE(
                            NULLIF(CAST(i.col03varchar AS VARCHAR(2000)), ''''),
                            ''''
                        ))), ''/'', CHAR(92)), ''"'', '''') AS normalized_path
                    FROM dbo.' + QUOTENAME(@image_table) + N' i
                    WHERE i.imported_by_user_id = @uid
                      AND i.state_fips = @sf
                      AND i.county_fips = @cf
                      AND ISNULL(i.is_deleted, 0) = 0
                ),
                parsed AS (
                    SELECT
                        r.id,
                        r.col01varchar,
                        CASE
                            WHEN CHARINDEX(CHAR(92), r.normalized_path) > 0
                                THEN LEFT(r.normalized_path, CHARINDEX(CHAR(92), r.normalized_path) - 1)
                            ELSE ''''
                        END AS book_value,
                        CASE
                            WHEN CHARINDEX(CHAR(92), r.normalized_path) > 0
                                THEN RIGHT(r.normalized_path, CHARINDEX(CHAR(92), REVERSE(r.normalized_path)) - 1)
                            ELSE r.normalized_path
                        END AS tail_name
                    FROM raw_paths r
                ),
                page_parts AS (
                    SELECT
                        p.id,
                        p.col01varchar,
                        ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(p.book_value, ''''))), ''''), '''') AS book_value,
                        LTRIM(RTRIM(
                            CASE
                                WHEN CHARINDEX(''.'', p.tail_name) > 0 THEN LEFT(p.tail_name, LEN(p.tail_name) - CHARINDEX(''.'', REVERSE(p.tail_name)))
                                ELSE p.tail_name
                            END
                        )) AS page_raw
                    FROM parsed p
                ),
                scoped AS (
                    SELECT
                        x.id,
                        x.col01varchar,
                        x.book_value,
                        x.page_raw,
                        CASE
                            WHEN @is_split_job = 1
                                 AND (
                                     @has_range = 0
                                     OR CASE
                                         WHEN RIGHT(UPPER(ISNULL(x.book_value, '''')), 1) LIKE ''[A-Z]''
                                              AND LEN(ISNULL(x.book_value, '''')) > 1
                                             THEN RIGHT(''000000'' + LEFT(UPPER(ISNULL(x.book_value, '''')), LEN(ISNULL(x.book_value, '''')) - 1), 6)
                                                  + RIGHT(UPPER(ISNULL(x.book_value, '''')), 1)
                                         ELSE RIGHT(''000000'' + UPPER(ISNULL(x.book_value, '''')), 6)
                                     END BETWEEN @split_start_key AND @split_end_key
                                 )
                                THEN 1
                            ELSE 0
                        END AS in_split_scope
                    FROM page_parts x
                ),
                normalized AS (
                    SELECT
                        s.id,
                        s.col01varchar,
                        ISNULL(s.book_value, '''') AS book_value,
                        ISNULL(NULLIF(s.page_raw, ''''), '''') AS page_raw,
                        CASE
                            WHEN s.in_split_scope = 1
                                 AND CHARINDEX(''-'', ISNULL(s.page_raw, '''')) > 0
                                 AND TRY_CONVERT(
                                     INT,
                                     RIGHT(
                                         ISNULL(s.page_raw, ''''),
                                         CASE
                                             WHEN CHARINDEX(''-'', REVERSE(ISNULL(s.page_raw, ''''))) > 1
                                                 THEN CHARINDEX(''-'', REVERSE(ISNULL(s.page_raw, ''''))) - 1
                                             ELSE 0
                                         END
                                     )
                                 ) IS NOT NULL
                                THEN LEFT(
                                    ISNULL(s.page_raw, ''''),
                                    LEN(ISNULL(s.page_raw, '''')) - CHARINDEX(''-'', REVERSE(ISNULL(s.page_raw, '''')))
                                )
                            ELSE ISNULL(s.page_raw, '''')
                        END AS page_base,
                        CASE
                            WHEN s.in_split_scope = 1
                                 AND CHARINDEX(''-'', ISNULL(s.page_raw, '''')) > 0
                                 AND TRY_CONVERT(
                                     INT,
                                     RIGHT(
                                         ISNULL(s.page_raw, ''''),
                                         CASE
                                             WHEN CHARINDEX(''-'', REVERSE(ISNULL(s.page_raw, ''''))) > 1
                                                 THEN CHARINDEX(''-'', REVERSE(ISNULL(s.page_raw, ''''))) - 1
                                             ELSE 0
                                         END
                                     )
                                 ) IS NOT NULL
                                THEN 1
                            ELSE 0
                        END AS should_dedupe
                    FROM scoped s
                ),
                deduped AS (
                    SELECT
                        n.id,
                        n.book_value,
                        n.page_raw,
                        n.page_base,
                        n.should_dedupe,
                        ROW_NUMBER() OVER (
                            PARTITION BY n.book_value, n.page_base, n.should_dedupe
                            ORDER BY
                                CASE
                                    WHEN TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(n.col01varchar, ''''))), '''')) IS NULL THEN 1
                                    ELSE 0
                                END,
                                TRY_CONVERT(BIGINT, NULLIF(LTRIM(RTRIM(ISNULL(n.col01varchar, ''''))), '''')),
                                LTRIM(RTRIM(ISNULL(n.col01varchar, ''''))),
                                n.id
                        ) AS dup_ordinal
                    FROM normalized n
                )
                INSERT INTO #gdi_image_page_values (image_id, book_value, page_value)
                SELECT
                    d.id,
                    ISNULL(d.book_value, '''') AS book_value,
                    CASE
                        WHEN d.should_dedupe = 1 THEN ISNULL(d.page_base, '''')
                        ELSE ISNULL(d.page_raw, '''')
                    END AS page_value
                FROM deduped d;';
            EXEC sys.sp_executesql @sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5), @is_split_job BIT, @has_range BIT, @split_start_key VARCHAR(7), @split_end_key VARCHAR(7)',
                @ImportedByUserId, @state_fips, @county_fips, @is_split_job, @has_split_book_range, @split_book_start_key, @split_book_end_key;

            SET @sql = N'
                ;WITH ranked AS (
                    SELECT
                        i.header_file_key,
                        ISNULL(i.col01varchar, '''') AS col01varchar,
                        ISNULL(v.book_value, '''') AS book_value,
                        ISNULL(v.page_value, '''') AS page_value,
                        TRY_CONVERT(INT,
                            CASE
                                WHEN LTRIM(RTRIM(ISNULL(v.page_value, ''''))) = '''' THEN NULL
                                ELSE LEFT(
                                    LTRIM(RTRIM(ISNULL(v.page_value, ''''))),
                                    PATINDEX(''%[^0-9]%'', LTRIM(RTRIM(ISNULL(v.page_value, ''''))) + ''X'') - 1
                                )
                            END
                        ) AS page_num,
                        v.image_id
                    FROM #gdi_image_page_values v
                    JOIN dbo.' + QUOTENAME(@image_table) + N' i
                      ON i.id = v.image_id
                    WHERE i.imported_by_user_id = @uid
                      AND i.state_fips = @sf
                      AND i.county_fips = @cf
                      AND ISNULL(i.is_deleted, 0) = 0
                ),
                ordered AS (
                    SELECT
                        r.header_file_key,
                        r.col01varchar,
                        r.book_value,
                        r.page_value,
                        ROW_NUMBER() OVER (
                            PARTITION BY r.header_file_key, r.col01varchar
                            ORDER BY CASE WHEN r.page_num IS NULL THEN 1 ELSE 0 END, r.page_num, r.page_value, r.image_id
                        ) AS rn_asc,
                        ROW_NUMBER() OVER (
                            PARTITION BY r.header_file_key, r.col01varchar
                            ORDER BY CASE WHEN r.page_num IS NULL THEN 1 ELSE 0 END, r.page_num DESC, r.page_value DESC, r.image_id DESC
                        ) AS rn_desc
                    FROM ranked r
                )
                INSERT INTO #gdi_image_page_bounds (header_file_key, col01varchar, book_value, begin_value, end_value)
                SELECT
                    o.header_file_key,
                    o.col01varchar,
                    MAX(CASE WHEN o.book_value <> '''' THEN o.book_value ELSE '''' END) AS book_value,
                    MAX(CASE WHEN o.rn_asc = 1 THEN ISNULL(o.page_value, '''') ELSE '''' END) AS begin_value,
                    MAX(CASE WHEN o.rn_desc = 1 THEN ISNULL(o.page_value, '''') ELSE '''' END) AS end_value
                FROM ordered o
                GROUP BY o.header_file_key, o.col01varchar;';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @ImportedByUserId, @state_fips, @county_fips;

            SET @sql = N'
                UPDATE i
                SET
                    i.book = ISNULL(v.book_value, ''''),
                    i.page_number = ISNULL(v.page_value, '''')
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                JOIN #gdi_image_page_values v
                  ON v.image_id = i.id
                WHERE i.imported_by_user_id = @uid
                  AND i.state_fips = @sf
                  AND i.county_fips = @cf;';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @ImportedByUserId, @state_fips, @county_fips;

            UPDATE h
            SET
                h.book = ISNULL(NULLIF(b.book_value, ''), ISNULL(h.book, '')),
                h.beginning_page = ISNULL(NULLIF(b.begin_value, ''), ISNULL(h.beginning_page, '')),
                h.ending_page = ISNULL(NULLIF(b.end_value, ''), ISNULL(h.ending_page, ''))
            FROM dbo.gdi_instruments h
            JOIN #gdi_image_page_bounds b
              ON b.header_file_key = h.header_file_key
             AND b.col01varchar = h.col01varchar
            WHERE h.imported_by_user_id = @ImportedByUserId
              AND h.state_fips = @state_fips
              AND h.county_fips = @county_fips;

            DECLARE @sync_table SYSNAME;
            DECLARE @sync_sql NVARCHAR(MAX);
            DECLARE sync_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT t.[name]
                FROM sys.tables t
                WHERE t.[name] LIKE 'gdi[_]%'
                  AND t.[name] NOT IN ('gdi_instruments', 'gdi_audit')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'imported_by_user_id')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'state_fips')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'county_fips')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'header_file_key')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'col01varchar')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'book')
                  AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'page_number');

            OPEN sync_cursor;
            FETCH NEXT FROM sync_cursor INTO @sync_table;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF @sync_table <> @image_table
                BEGIN
                    SET @sync_sql = N'
                        UPDATE tgt
                        SET
                            tgt.book = ISNULL(src.book, ''''),
                            tgt.page_number = ISNULL(src.beginning_page, '''')
                        FROM dbo.' + QUOTENAME(@sync_table) + N' tgt
                        JOIN dbo.gdi_instruments src
                          ON src.imported_by_user_id = tgt.imported_by_user_id
                         AND src.state_fips = tgt.state_fips
                         AND src.county_fips = tgt.county_fips
                         AND src.header_file_key = tgt.header_file_key
                         AND src.col01varchar = tgt.col01varchar
                        WHERE tgt.imported_by_user_id = @uid
                          AND tgt.state_fips = @sf
                          AND tgt.county_fips = @cf;';
                    EXEC sys.sp_executesql @sync_sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @ImportedByUserId, @state_fips, @county_fips;
                END
                FETCH NEXT FROM sync_cursor INTO @sync_table;
            END;
            CLOSE sync_cursor;
            DEALLOCATE sync_cursor;
        END;

        DROP TABLE IF EXISTS dbo.gdi_record_series;
        CREATE TABLE dbo.gdi_record_series (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            [year] VARCHAR(1000),
            record_series_internal_id VARCHAR(1000),
            record_series_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH scoped_headers AS (
            SELECT
                h.*,
                CASE
                    WHEN LEN(LTRIM(RTRIM(ISNULL(h.col06varchar, '')))) >= 4
                        THEN LEFT(LTRIM(RTRIM(ISNULL(h.col06varchar, ''))), 4)
                    ELSE ''
                END AS [year_value]
            FROM dbo.gdi_instruments h
            WHERE h.imported_by_user_id = @ImportedByUserId
              AND h.state_fips = @state_fips
              AND h.county_fips = @county_fips
              AND ISNULL(h.is_deleted, 0) = 0
        )
        INSERT INTO dbo.gdi_record_series (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, [year], record_series_internal_id, record_series_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(h.fn, ''), ISNULL(h.file_key, ''), ISNULL(h.header_file_key, ''), ISNULL(h.keyOriginalValue, ''), ISNULL(h.OriginalValue, ''),
            ISNULL(h.col01varchar, ''), ISNULL(h.year_value, ''), '', '',
            0,
            h.imported_by_user_id, h.import_batch_id, h.state_fips, h.county_fips, ISNULL(h.is_deleted, 0), h.imported_at
        FROM scoped_headers h;

        DROP TABLE IF EXISTS dbo.gdi_instrument_types;
        CREATE TABLE dbo.gdi_instrument_types (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col03varchar VARCHAR(1000),
            instrument_type_internal_id VARCHAR(1000),
            instrument_type_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH source_rows AS (
            SELECT
                g.id,
                g.fn,
                g.OriginalValue,
                g.col01varchar,
                g.col03varchar,
                g.imported_by_user_id,
                g.import_batch_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.is_deleted, 0) AS is_deleted,
                g.imported_at,
                ISNULL(sp.file_key, '') AS file_key,
                ISNULL(sp.header_file_key, '') AS header_file_key
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport g
              ON g.ID = sp.source_id
            WHERE sp.tag = 'header'
              AND LTRIM(RTRIM(ISNULL(g.col03varchar, ''))) <> ''
        )
        INSERT INTO dbo.gdi_instrument_types (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col03varchar, instrument_type_internal_id, instrument_type_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(s.fn, ''), ISNULL(s.file_key, ''), ISNULL(s.header_file_key, ''),
            ISNULL(s.OriginalValue, ''),
            ISNULL(s.OriginalValue, ''),
            ISNULL(s.col01varchar, ''), ISNULL(s.col03varchar, ''), '', '',
            0,
            s.imported_by_user_id, s.import_batch_id, s.state_fips, s.county_fips, ISNULL(s.is_deleted, 0), s.imported_at
        FROM source_rows s;

        DROP TABLE IF EXISTS dbo.gdi_additions;
        CREATE TABLE dbo.gdi_additions (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col05varchar VARCHAR(1000),
            additions_internal_id VARCHAR(1000),
            additions_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH source_rows AS (
            SELECT
                g.id,
                g.fn,
                g.OriginalValue,
                g.col01varchar,
                g.col05varchar,
                g.imported_by_user_id,
                g.import_batch_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.is_deleted, 0) AS is_deleted,
                g.imported_at,
                CASE
                    WHEN sp.tag = 'legal' THEN 'legals' + ISNULL(sp.file_suffix, '')
                    ELSE ISNULL(sp.file_key, '')
                END AS file_key,
                ISNULL(sp.header_file_key, '') AS header_file_key
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport g
              ON g.ID = sp.source_id
            WHERE sp.tag IN ('legal', 'legals')
              AND LTRIM(RTRIM(ISNULL(g.col05varchar, ''))) <> ''
        ),
        ranked AS (
            SELECT
                s.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ISNULL(s.header_file_key, ''),
                        ISNULL(s.col01varchar, ''),
                        LTRIM(RTRIM(ISNULL(s.col05varchar, '')))
                    ORDER BY s.id
                ) AS rn
            FROM source_rows s
        )
        INSERT INTO dbo.gdi_additions (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col05varchar, additions_internal_id, additions_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(r.fn, ''), ISNULL(r.file_key, ''), ISNULL(r.header_file_key, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.col01varchar, ''), ISNULL(r.col05varchar, ''), '', '',
            0,
            r.imported_by_user_id, r.import_batch_id, r.state_fips, r.county_fips, ISNULL(r.is_deleted, 0), r.imported_at
        FROM ranked r
        WHERE r.rn = 1;

        DROP TABLE IF EXISTS dbo.gdi_township_range;
        CREATE TABLE dbo.gdi_township_range (
            ID INT NOT NULL IDENTITY PRIMARY KEY,
            FN VARCHAR(1000),
            file_key NVARCHAR(260) NOT NULL,
            header_file_key NVARCHAR(260) NOT NULL,
            keyOriginalValue VARCHAR(MAX) NULL,
            OriginalValue VARCHAR(MAX),
            col01varchar VARCHAR(1000),
            col03varchar VARCHAR(1000),
            col04varchar VARCHAR(1000),
            township_range_internal_id VARCHAR(1000),
            township_range_external_id VARCHAR(1000),
            is_split_book BIT NOT NULL DEFAULT (0),
            imported_by_user_id INT NOT NULL,
            import_batch_id UNIQUEIDENTIFIER NOT NULL,
            state_fips CHAR(2) NOT NULL,
            county_fips CHAR(5) NOT NULL,
            is_deleted BIT NOT NULL DEFAULT (0),
            imported_at DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
        );

        ;WITH source_rows AS (
            SELECT
                g.id,
                g.fn,
                g.OriginalValue,
                g.col01varchar,
                g.col03varchar,
                g.col04varchar,
                g.imported_by_user_id,
                g.import_batch_id,
                g.state_fips,
                g.county_fips,
                ISNULL(g.is_deleted, 0) AS is_deleted,
                g.imported_at,
                CASE
                    WHEN sp.tag = 'legal' THEN 'legals' + ISNULL(sp.file_suffix, '')
                    ELSE ISNULL(sp.file_key, '')
                END AS file_key,
                ISNULL(sp.header_file_key, '') AS header_file_key
            FROM #gdi_scope_parts_fast sp
            JOIN dbo.GenericDataImport g
              ON g.ID = sp.source_id
            WHERE sp.tag IN ('legal', 'legals')
        ),
        ranked AS (
            SELECT
                s.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ISNULL(s.header_file_key, ''),
                        ISNULL(s.col01varchar, ''),
                        LTRIM(RTRIM(ISNULL(s.col03varchar, ''))),
                        LTRIM(RTRIM(ISNULL(s.col04varchar, '')))
                    ORDER BY s.id
                ) AS rn
            FROM source_rows s
        )
        INSERT INTO dbo.gdi_township_range (
            FN, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col03varchar, col04varchar, township_range_internal_id, township_range_external_id,
            is_split_book, imported_by_user_id, import_batch_id, state_fips, county_fips, is_deleted, imported_at
        )
        SELECT
            ISNULL(r.fn, ''), ISNULL(r.file_key, ''), ISNULL(r.header_file_key, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.OriginalValue, ''),
            ISNULL(r.col01varchar, ''), ISNULL(r.col03varchar, ''), ISNULL(r.col04varchar, ''), '', '',
            0,
            r.imported_by_user_id, r.import_batch_id, r.state_fips, r.county_fips, ISNULL(r.is_deleted, 0), r.imported_at
        FROM ranked r
        WHERE r.rn = 1;

        DECLARE @split_table SYSNAME;
        DECLARE @split_update_sql NVARCHAR(MAX);
        DECLARE split_flag_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT t.[name]
            FROM sys.tables t
            WHERE t.[name] LIKE 'gdi[_]%'
              AND t.[name] <> 'gdi_audit'
              AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'is_split_book')
              AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'imported_by_user_id')
              AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'state_fips')
              AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'county_fips')
              AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'header_file_key')
              AND EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.[name] = 'col01varchar');

        OPEN split_flag_cursor;
        FETCH NEXT FROM split_flag_cursor INTO @split_table;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@split_table)) AND [name] = 'book')
            BEGIN
                SET @split_update_sql = N'
                    UPDATE tgt
                    SET tgt.is_split_book = CASE
                        WHEN @has_range = 1
                             AND CASE
                                 WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(tgt.book, '''')))), 1) LIKE ''[A-Z]''
                                      AND LEN(LTRIM(RTRIM(ISNULL(tgt.book, '''')))) > 1
                                     THEN RIGHT(''000000'' + LEFT(UPPER(LTRIM(RTRIM(ISNULL(tgt.book, '''')))), LEN(LTRIM(RTRIM(ISNULL(tgt.book, '''')))) - 1), 6)
                                          + RIGHT(UPPER(LTRIM(RTRIM(ISNULL(tgt.book, '''')))), 1)
                                 ELSE RIGHT(''000000'' + UPPER(LTRIM(RTRIM(ISNULL(tgt.book, '''')))), 6)
                             END BETWEEN @split_start_key AND @split_end_key
                            THEN 1
                        ELSE 0
                    END
                    FROM dbo.' + QUOTENAME(@split_table) + N' tgt
                    WHERE tgt.imported_by_user_id = @uid
                      AND tgt.state_fips = @sf
                      AND tgt.county_fips = @cf;';
            END
            ELSE
            BEGIN
                SET @split_update_sql = N'
                    UPDATE tgt
                    SET tgt.is_split_book = CASE
                        WHEN @has_range = 1
                             AND CASE
                                 WHEN RIGHT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '''')))), 1) LIKE ''[A-Z]''
                                      AND LEN(LTRIM(RTRIM(ISNULL(h.book, '''')))) > 1
                                     THEN RIGHT(''000000'' + LEFT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '''')))), LEN(LTRIM(RTRIM(ISNULL(h.book, '''')))) - 1), 6)
                                          + RIGHT(UPPER(LTRIM(RTRIM(ISNULL(h.book, '''')))), 1)
                                 ELSE RIGHT(''000000'' + UPPER(LTRIM(RTRIM(ISNULL(h.book, '''')))), 6)
                             END BETWEEN @split_start_key AND @split_end_key
                            THEN 1
                        ELSE 0
                    END
                    FROM dbo.' + QUOTENAME(@split_table) + N' tgt
                    LEFT JOIN dbo.gdi_instruments h
                      ON h.imported_by_user_id = tgt.imported_by_user_id
                     AND h.state_fips = tgt.state_fips
                     AND h.county_fips = tgt.county_fips
                     AND ISNULL(h.header_file_key, '''') = ISNULL(tgt.header_file_key, '''')
                     AND ISNULL(h.col01varchar, '''') = ISNULL(tgt.col01varchar, '''')
                    WHERE tgt.imported_by_user_id = @uid
                      AND tgt.state_fips = @sf
                      AND tgt.county_fips = @cf;';
            END;
            EXEC sys.sp_executesql
                @split_update_sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5), @has_range BIT, @split_start_key VARCHAR(7), @split_end_key VARCHAR(7)',
                @ImportedByUserId, @state_fips, @county_fips, @has_split_book_range, @split_book_start_key, @split_book_end_key;

            FETCH NEXT FROM split_flag_cursor INTO @split_table;
        END;
        CLOSE split_flag_cursor;
        DEALLOCATE split_flag_cursor;

        DROP TABLE IF EXISTS #gdi_scope_parts;
        SELECT
            sp.fn,
            sp.col01varchar,
            sp.OriginalValue,
            sp.import_batch_id,
            sp.file_key,
            sp.tag,
            sp.file_suffix,
            sp.header_file_key
        INTO #gdi_scope_parts
        FROM #gdi_scope_parts_fast sp;

        DROP TABLE IF EXISTS #gdi_batch_parts;
        SELECT *
        INTO #gdi_batch_parts
        FROM #gdi_scope_parts
        WHERE import_batch_id = @batch_id;

        DROP TABLE IF EXISTS #gdi_split_counts;
        CREATE TABLE #gdi_split_counts (
            tag NVARCHAR(120) NOT NULL,
            table_name SYSNAME NOT NULL,
            source_row_count INT NOT NULL,
            actual_row_count INT NULL
        );

        INSERT INTO #gdi_split_counts (tag, table_name, source_row_count)
        SELECT
            sp.tag,
            CASE
                WHEN sp.tag = N'header' THEN N'gdi_instruments'
                WHEN sp.tag = N'images' THEN N'gdi_pages'
                WHEN sp.tag = N'names' THEN N'gdi_parties'
                WHEN sp.tag = N'references' THEN N'gdi_instrument_references'
                WHEN sp.tag = N'legals' THEN N'gdi_legals'
                ELSE N'gdi_' + sp.tag
            END AS table_name,
            COUNT(1) AS source_row_count
        FROM #gdi_scope_parts sp
        GROUP BY sp.tag;

        DECLARE @count_sql NVARCHAR(MAX);
        DROP TABLE IF EXISTS #gdi_actual_counts;
        CREATE TABLE #gdi_actual_counts (
            tag NVARCHAR(120) NOT NULL,
            table_name SYSNAME NOT NULL,
            actual_row_count INT NOT NULL
        );

        SELECT
            @count_sql = STUFF((
                SELECT
                    N' UNION ALL SELECT N''' + REPLACE(sc.tag, '''', '''''') + N''' AS tag, N''' + REPLACE(sc.table_name, '''', '''''') + N''' AS table_name, COUNT(1) AS actual_row_count FROM dbo.' + QUOTENAME(sc.table_name) + N' WHERE imported_by_user_id = @uid AND state_fips = @sf AND county_fips = @cf'
                FROM #gdi_split_counts sc
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 11, N'');

        IF ISNULL(@count_sql, N'') <> N''
        BEGIN
            SET @count_sql = N'INSERT INTO #gdi_actual_counts (tag, table_name, actual_row_count) ' + @count_sql + N';';
            EXEC sys.sp_executesql
                @count_sql,
                N'@uid INT, @sf CHAR(2), @cf CHAR(5)',
                @ImportedByUserId, @state_fips, @county_fips;
        END;

        UPDATE sc
        SET sc.actual_row_count = ac.actual_row_count
        FROM #gdi_split_counts sc
        LEFT JOIN #gdi_actual_counts ac
          ON ac.tag = sc.tag
         AND ac.table_name = sc.table_name;

        DECLARE @split_table_count INT = (SELECT COUNT(DISTINCT tag) FROM #gdi_scope_parts);
        DECLARE @split_row_count INT = (SELECT COUNT(1) FROM #gdi_scope_parts);
        DECLARE @orphan_count INT;
        DECLARE @duplicate_header_groups INT;
        DECLARE @duplicate_header_rows INT;
        DECLARE @misc_tag_count INT;
        DECLARE @duplicate_file_keys INT;
        DECLARE @non_header_without_header_suffix INT;
        DECLARE @generic_scope_row_count INT = (
            SELECT COUNT(1)
            FROM dbo.GenericDataImport
            WHERE imported_by_user_id = @ImportedByUserId
              AND state_fips = @state_fips
              AND county_fips = @county_fips
        );
        DECLARE @actual_split_row_total INT = (
            SELECT ISNULL(SUM(ISNULL(actual_row_count, 0)), 0)
            FROM #gdi_split_counts
        );
        DECLARE @split_vs_generic_delta INT = ISNULL(@actual_split_row_total, 0) - ISNULL(@generic_scope_row_count, 0);
        DECLARE @row_count_delta INT = ISNULL(@source_row_count, 0) - ISNULL(@parsed_row_count, 0);

        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, file_key, tag, file_suffix, details
        )
        VALUES (
            CASE WHEN ISNULL(@row_count_delta, 0) = 0 THEN 'info' ELSE 'warn' END,
            'split_source_vs_parsed_rows',
            CASE
                WHEN ISNULL(@row_count_delta, 0) = 0
                    THEN N'Source row count matches parsed row count for split processing.'
                ELSE N'Source row count does not match parsed row count before split processing.'
            END,
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName, @file_key, @tag, @file_suffix,
            CONCAT(
                N'{"sourceRowCount":', CAST(ISNULL(@source_row_count, 0) AS NVARCHAR(40)),
                N',"parsedRowCount":', CAST(ISNULL(@parsed_row_count, 0) AS NVARCHAR(40)),
                N',"delta":', CAST(ISNULL(@row_count_delta, 0) AS NVARCHAR(40)), N'}'
            )
        );

        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
        )
        VALUES (
            CASE WHEN ISNULL(@split_vs_generic_delta, 0) = 0 THEN 'info' ELSE 'warn' END,
            'split_vs_generic_scope_rows',
            CASE
                WHEN ISNULL(@split_vs_generic_delta, 0) = 0
                    THEN N'Total rows across split tables match scoped GenericDataImport row count.'
                ELSE N'Total rows across split tables do not match scoped GenericDataImport row count.'
            END,
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            CONCAT(
                N'{"splitRowTotal":', CAST(ISNULL(@actual_split_row_total, 0) AS NVARCHAR(40)),
                N',"genericScopeRowCount":', CAST(ISNULL(@generic_scope_row_count, 0) AS NVARCHAR(40)),
                N',"delta":', CAST(ISNULL(@split_vs_generic_delta, 0) AS NVARCHAR(40)), N'}'
            )
        );

        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, tag, details
        )
        SELECT
            CASE WHEN ISNULL(sc.actual_row_count, 0) = sc.source_row_count THEN 'info' ELSE 'warn' END AS severity,
            'split_table_row_count',
            CASE
                WHEN ISNULL(sc.actual_row_count, 0) = sc.source_row_count
                    THEN N'Split table row count verified.'
                ELSE N'Split table row count mismatch.'
            END,
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            sc.tag,
            CONCAT(
                N'{"tableName":"', sc.table_name,
                N'","sourceRowCount":', CAST(sc.source_row_count AS NVARCHAR(40)),
                N',"actualRowCount":', CAST(ISNULL(sc.actual_row_count, 0) AS NVARCHAR(40)),
                N',"delta":', CAST(ISNULL(sc.actual_row_count, 0) - sc.source_row_count AS NVARCHAR(40)), N'}'
            )
        FROM #gdi_split_counts sc;

        SELECT @orphan_count = COUNT(1)
        FROM #gdi_scope_parts src
        LEFT JOIN #gdi_scope_parts hdr
            ON hdr.tag = 'header'
           AND hdr.header_file_key = src.header_file_key
           AND hdr.col01varchar = src.col01varchar
        WHERE src.tag <> 'header'
          AND hdr.header_file_key IS NULL;

        IF ISNULL(@orphan_count, 0) > 0
        BEGIN
            INSERT INTO dbo.gdi_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'warn',
                'orphan_non_header_rows',
                N'One or more non-header rows do not map to a header row.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(N'{"orphanRowCount":', CAST(@orphan_count AS NVARCHAR(40)), N'}')
            );
        END;

        SELECT @misc_tag_count = COUNT(1)
        FROM #gdi_batch_parts
        WHERE tag = 'misc';

        IF ISNULL(@misc_tag_count, 0) > 0
        BEGIN
            INSERT INTO dbo.gdi_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'warn',
                'misc_tag_rows',
                N'Rows were loaded with a misc tag due to unexpected filename patterns.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(N'{"rowCount":', CAST(@misc_tag_count AS NVARCHAR(40)), N'}')
            );
        END;

        ;WITH dup_file_key AS (
            SELECT file_key
            FROM #gdi_batch_parts
            GROUP BY file_key
            HAVING COUNT(DISTINCT fn) > 1
        )
        SELECT @duplicate_file_keys = COUNT(1) FROM dup_file_key;

        IF ISNULL(@duplicate_file_keys, 0) > 0
        BEGIN
            INSERT INTO dbo.gdi_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'warn',
                'duplicate_file_keys_in_batch',
                N'Multiple source files mapped to the same file key in this batch.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(N'{"duplicateFileKeyCount":', CAST(@duplicate_file_keys AS NVARCHAR(40)), N'}')
            );
        END;

        ;WITH dup AS (
            SELECT header_file_key, col01varchar, COUNT(1) AS cnt
            FROM #gdi_scope_parts
            WHERE tag = 'header'
            GROUP BY header_file_key, col01varchar
            HAVING COUNT(1) > 1
        )
        SELECT
            @duplicate_header_groups = COUNT(1),
            @duplicate_header_rows = SUM(cnt - 1)
        FROM dup;

        IF ISNULL(@duplicate_header_groups, 0) > 0
        BEGIN
            INSERT INTO dbo.gdi_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'warn',
                'duplicate_header_keys',
                N'Duplicate header keys were detected for file + col01 combinations.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(
                    N'{"duplicateHeaderGroups":', CAST(ISNULL(@duplicate_header_groups, 0) AS NVARCHAR(40)),
                    N',"duplicateHeaderRows":', CAST(ISNULL(@duplicate_header_rows, 0) AS NVARCHAR(40)), N'}'
                )
            );
        END;

        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, tag, file_suffix, details
        )
        SELECT
            'warn',
            'missing_group_file',
            N'Expected grouped CSV file is missing for this suffix group.',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            expected_tags.tag,
            header_suffix.file_suffix,
            CONCAT(
                N'{"missingTag":"', expected_tags.tag,
                N'","fileSuffix":"', header_suffix.file_suffix,
                N'","expectedFileKey":"', expected_tags.tag, header_suffix.file_suffix,
                N'","expectedFileName":"', expected_tags.tag, header_suffix.file_suffix, N'.csv"',
                N',"headerFileName":"header', header_suffix.file_suffix, N'.csv"}'
            )
        FROM (
            SELECT DISTINCT file_suffix
            FROM #gdi_batch_parts
            WHERE tag = 'header'
              AND ISNULL(file_suffix, '') <> ''
        ) header_suffix
        CROSS JOIN (
            SELECT DISTINCT tag
            FROM #gdi_batch_parts
            WHERE tag NOT IN ('header', 'misc')
        ) expected_tags
        LEFT JOIN (
            SELECT DISTINCT file_suffix, tag
            FROM #gdi_batch_parts
        ) actual
            ON actual.file_suffix = header_suffix.file_suffix
           AND actual.tag = expected_tags.tag
        WHERE actual.tag IS NULL;

        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, tag, file_suffix, details
        )
        SELECT
            'info',
            'header_without_reference_files',
            N'Header file has no companion non-header files in this batch.',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            'header',
            hs.file_suffix,
            CONCAT(
                N'{"headerFileKey":"header', hs.file_suffix,
                N'","headerFileName":"header', hs.file_suffix, N'.csv"}'
            )
        FROM (
            SELECT DISTINCT file_suffix
            FROM #gdi_batch_parts
            WHERE tag = 'header'
              AND ISNULL(file_suffix, '') <> ''
        ) hs
        WHERE NOT EXISTS (
            SELECT 1
            FROM #gdi_batch_parts b
            WHERE b.file_suffix = hs.file_suffix
              AND b.tag NOT IN ('header', 'misc')
        );

        SELECT @non_header_without_header_suffix = COUNT(1)
        FROM (
            SELECT DISTINCT b.file_suffix
            FROM #gdi_batch_parts b
            WHERE b.tag NOT IN ('header', 'misc')
              AND ISNULL(b.file_suffix, '') <> ''
              AND NOT EXISTS (
                  SELECT 1
                  FROM #gdi_batch_parts h
                  WHERE h.tag = 'header'
                    AND h.file_suffix = b.file_suffix
              )
        ) x;

        IF ISNULL(@non_header_without_header_suffix, 0) > 0
        BEGIN
            INSERT INTO dbo.gdi_audit (
                severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
            )
            VALUES (
                'warn',
                'missing_header_group_file',
                N'One or more grouped file suffixes have non-header rows but no header file.',
                @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
                CONCAT(N'{"suffixCount":', CAST(@non_header_without_header_suffix AS NVARCHAR(40)), N'}')
            );
        END;

        INSERT INTO dbo.gdi_audit (
            severity, event_type, message, import_batch_id, imported_by_user_id, state_fips, county_fips, import_file_name, details
        )
        VALUES (
            'info',
            'split_rebuild_complete',
            N'Split table rebuild completed.',
            @batch_id, @ImportedByUserId, @state_fips, @county_fips, @ImportFileName,
            CONCAT(
                N'{"tableCount":', CAST(ISNULL(@split_table_count, 0) AS NVARCHAR(40)),
                N',"rowCount":', CAST(ISNULL(@split_row_count, 0) AS NVARCHAR(40)), N'}'
            )
        );
    END;

END;
