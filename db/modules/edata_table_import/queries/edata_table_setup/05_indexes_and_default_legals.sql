/* ============================================================================
   File: 05_indexes_and_default_legals.sql
   Procedure: dbo.sp_EdataTableSetup
   Role in assembly:
   - Ensures the key working indexes exist for the scoped import tables and seeds
     default legal rows for headers that still have no legal entry.
   Why this file exists:
   - Index setup and default-legal seeding are both post-normalization concerns
     that prepare the working scope for fast downstream tooling.
   Maintenance notes:
   - Keep index names and default legal row shape aligned with application code
     that queries these tables directly.
   ============================================================================ */
    -- -------------------------------------------------------------------------
    -- Section 7: Ensure scope indexes exist for key working tables
    -- -------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_GenericDataImport_scope_fn_col01'
          AND object_id = OBJECT_ID('dbo.GenericDataImport')
    )
        CREATE INDEX IX_GenericDataImport_scope_fn_col01
            ON dbo.GenericDataImport (state_fips, county_fips, imported_by_user_id, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_instruments', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_header_scope_file_col01'
          AND object_id = OBJECT_ID('dbo.gdi_instruments')
    )
        CREATE INDEX IX_gdi_header_scope_file_col01
            ON dbo.gdi_instruments (state_fips, county_fips, imported_by_user_id, file_key, col01varchar);

    DECLARE @gdi_legal_table SYSNAME = NULL;
    IF OBJECT_ID(N'dbo.gdi_legals', N'U') IS NOT NULL
        SET @gdi_legal_table = N'gdi_legals';
    ELSE IF OBJECT_ID(N'dbo.gdi_legal', N'U') IS NOT NULL
        SET @gdi_legal_table = N'gdi_legal';

    IF @gdi_legal_table IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_legal_scope_header_col01'
          AND object_id = OBJECT_ID(N'dbo.' + @gdi_legal_table)
    )
    BEGIN
        SET @sql = N'CREATE INDEX IX_gdi_legal_scope_header_col01
            ON dbo.' + QUOTENAME(@gdi_legal_table) + N' (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);';
        EXEC sys.sp_executesql @sql;
    END;

    IF OBJECT_ID(N'dbo.gdi_parties', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_names_scope_header_col01'
          AND object_id = OBJECT_ID('dbo.gdi_parties')
    )
        CREATE INDEX IX_gdi_names_scope_header_col01
            ON dbo.gdi_parties (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_pages', N'U') IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_gdi_pages_scope_header_col01'
          AND object_id = OBJECT_ID('dbo.gdi_pages')
    )
        CREATE INDEX IX_gdi_pages_scope_header_col01
            ON dbo.gdi_pages (state_fips, county_fips, imported_by_user_id, header_file_key, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE name = 'IX_gdi_instrument_references_scope_header_col01'
              AND object_id = OBJECT_ID('dbo.gdi_instrument_references')
       )
        CREATE INDEX IX_gdi_instrument_references_scope_header_col01
            ON dbo.gdi_instrument_references (state_fips, county_fips, imported_by_user_id, is_deleted, header_file_key, col01varchar);

    IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
       AND @gdi_ref_id_col IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM sys.indexes
            WHERE name = 'IX_gdi_instrument_references_scope_internal'
              AND object_id = OBJECT_ID('dbo.gdi_instrument_references')
       )
    BEGIN
        SET @sql = N'CREATE INDEX IX_gdi_instrument_references_scope_internal
            ON dbo.gdi_instrument_references (state_fips, county_fips, imported_by_user_id, is_deleted, ' + QUOTENAME(@gdi_ref_id_col) + N');';
        EXEC sys.sp_executesql @sql;
    END;

    -- -------------------------------------------------------------------------
    -- Section 7: Seed default legal rows for headers missing legal records
    -- -------------------------------------------------------------------------
    IF @gdi_legal_table IS NOT NULL
    BEGIN
        SET @sql = N'
        INSERT INTO dbo.' + QUOTENAME(@gdi_legal_table) + N' (
            fn, file_key, header_file_key, keyOriginalValue, OriginalValue,
            col01varchar, col02varchar,
            col06varchar, col07varchar, col08varchar,
            book, page_number, internal_id, instrument_internal_id, instrument_external_id, line, legal_type,
            block, lot, section, location, free_form_legal,
            imported_by_user_id, import_batch_id, state_fips, county_fips, imported_at
        )
        SELECT
            REPLACE(REPLACE(ISNULL(h.fn, ''''), ''HEADER'', ''Legal''), ''header'', ''legal'') AS fn,
            CASE
                WHEN LOWER(ISNULL(h.file_key, '''')) LIKE ''header%'' THEN STUFF(h.file_key, 1, 6, ''legals'')
                ELSE ''legals_'' + ISNULL(h.file_key, '''')
            END AS file_key,
            ISNULL(h.header_file_key, ''''),
            ISNULL(h.keyOriginalValue, ISNULL(h.OriginalValue, '''')),
            '''',
            ISNULL(h.col01varchar, ''''), '''',
            '''', '''', '''',
            ISNULL(h.book, ''''), ISNULL(h.beginning_page, ''''), '''', '''', '''', '''', ''Other'',
            '''', '''', '''', '''', ''No Legal Description'',
            h.imported_by_user_id, h.import_batch_id, h.state_fips, h.county_fips, SYSDATETIMEOFFSET()
        FROM dbo.gdi_instruments h
        LEFT JOIN dbo.' + QUOTENAME(@gdi_legal_table) + N' l
            ON l.imported_by_user_id = h.imported_by_user_id
           AND l.state_fips = h.state_fips
           AND l.county_fips = h.county_fips
           AND l.import_batch_id = h.import_batch_id
           AND l.header_file_key = h.header_file_key
           AND l.col01varchar = h.col01varchar
        WHERE h.imported_by_user_id = @uid
          AND h.state_fips = @sf
          AND h.county_fips = @cf
          AND (@batch_id IS NULL OR h.import_batch_id = @batch_id)
          AND l.ID IS NULL;';

        EXEC sys.sp_executesql
            @sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @batch_id UNIQUEIDENTIFIER',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips,
            @batch_id = @scope_import_batch_id;
    END;
