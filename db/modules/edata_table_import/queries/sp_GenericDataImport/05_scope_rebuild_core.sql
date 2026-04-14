/* ============================================================================
   File: 05_scope_rebuild_core.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - Normalizes scoped source text, resolves split-book context, rebuilds the
     primary scoped gdi_* tables from the active batch, and synchronizes page
     metadata across related split tables.
   Why this file exists:
   - This is the core fan-out stage that turns GenericDataImport rows into the
     working import tables the rest of the application reads.
   Maintenance notes:
   - This fragment is intentionally large because the table rebuild loop, header
     joins, and image/page synchronization are tightly coupled execution phases.
   - Keep it after replace cleanup and before derived helper table rebuilds.
   ============================================================================ */
    IF ISNULL(@SkipSplitRebuild, 0) = 0
    BEGIN
        UPDATE g
        SET g.OriginalValue = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(g.OriginalValue, ''), '"', ''), ',', '|'), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''), ' ', '')
        FROM dbo.GenericDataImport g
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @state_fips
          AND g.county_fips = @county_fips
          AND g.import_batch_id = @batch_id
          AND ISNULL(g.is_deleted, 0) = 0
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

        DROP TABLE IF EXISTS #gdi_scope_batches_fast;
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
        INTO #gdi_scope_batches_fast
        FROM ranked_batches rb;
        CREATE UNIQUE CLUSTERED INDEX IX_gdi_scope_batches_fast_batch ON #gdi_scope_batches_fast (import_batch_id);
        CREATE INDEX IX_gdi_scope_batches_fast_rn ON #gdi_scope_batches_fast (rn, import_batch_id);

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
        JOIN #gdi_scope_batches_fast sb
          ON sb.import_batch_id = g.import_batch_id
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
          -- Append rebuilds only the active batch. Drop rebuilds the retained
          -- current+previous batch window so the split tables mirror GenericDataImport.
          AND (
                (@mode = 'D' AND sb.rn <= 2)
             OR (@mode <> 'D' AND g.import_batch_id = @batch_id)
          );

        CREATE INDEX IX_gdi_scope_parts_fast_tag ON #gdi_scope_parts_fast (tag);
        CREATE INDEX IX_gdi_scope_parts_fast_batch ON #gdi_scope_parts_fast (import_batch_id);
        CREATE INDEX IX_gdi_scope_parts_fast_source ON #gdi_scope_parts_fast (source_id);
        CREATE INDEX IX_gdi_scope_parts_fast_tag_hdr ON #gdi_scope_parts_fast (tag, header_file_key, col01varchar) INCLUDE (file_key, file_suffix, import_batch_id, fn, OriginalValue);
        CREATE INDEX IX_gdi_scope_parts_fast_suffix_tag ON #gdi_scope_parts_fast (file_suffix, tag) INCLUDE (file_key);

        DROP TABLE IF EXISTS #gdi_scope_headers_fast;
        SELECT
            h.import_batch_id,
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
        CREATE INDEX IX_gdi_scope_headers_fast_col01 ON #gdi_scope_headers_fast (import_batch_id, imported_by_user_id, state_fips, county_fips, col01varchar) INCLUDE (hdr_file_key, OriginalValue);
        CREATE INDEX IX_gdi_scope_headers_fast_hdr ON #gdi_scope_headers_fast (import_batch_id, imported_by_user_id, state_fips, county_fips, hdr_file_key) INCLUDE (col01varchar, OriginalValue);

        -- Clear stale scope rows only when a retained batch window no longer has
        -- that tag at all. If the tag exists in the retained window, the table is
        -- rebuilt from #gdi_scope_parts_fast below.
        IF OBJECT_ID(N'dbo.gdi_instruments', N'U') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM #gdi_scope_parts_fast WHERE tag = 'header')
        BEGIN
            DELETE FROM dbo.gdi_instruments
            WHERE imported_by_user_id = @ImportedByUserId
              AND state_fips = @state_fips
              AND county_fips = @county_fips;
        END;

        IF OBJECT_ID(N'dbo.gdi_pages', N'U') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM #gdi_scope_parts_fast WHERE tag = 'images')
        BEGIN
            DELETE FROM dbo.gdi_pages
            WHERE imported_by_user_id = @ImportedByUserId
              AND state_fips = @state_fips
              AND county_fips = @county_fips;
        END;

        IF OBJECT_ID(N'dbo.gdi_parties', N'U') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM #gdi_scope_parts_fast WHERE tag = 'names')
        BEGIN
            DELETE FROM dbo.gdi_parties
            WHERE imported_by_user_id = @ImportedByUserId
              AND state_fips = @state_fips
              AND county_fips = @county_fips;
        END;

        IF OBJECT_ID(N'dbo.gdi_instrument_references', N'U') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM #gdi_scope_parts_fast WHERE tag = 'references')
        BEGIN
            DELETE FROM dbo.gdi_instrument_references
            WHERE imported_by_user_id = @ImportedByUserId
              AND state_fips = @state_fips
              AND county_fips = @county_fips;
        END;

        IF OBJECT_ID(N'dbo.gdi_legals', N'U') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM #gdi_scope_parts_fast WHERE tag = 'legals')
        BEGIN
            DELETE FROM dbo.gdi_legals
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
                ON hdr.import_batch_id = src.import_batch_id
               AND hdr.imported_by_user_id = src.imported_by_user_id
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
                import_batch_id UNIQUEIDENTIFIER NOT NULL,
                image_id INT NOT NULL,
                book_value VARCHAR(1000) NOT NULL,
                page_value VARCHAR(1000) NOT NULL
            );
            CREATE UNIQUE CLUSTERED INDEX IX_gdi_image_page_values_image ON #gdi_image_page_values (import_batch_id, image_id);

            DROP TABLE IF EXISTS #gdi_image_page_bounds;
            CREATE TABLE #gdi_image_page_bounds (
                import_batch_id UNIQUEIDENTIFIER NOT NULL,
                header_file_key NVARCHAR(260) NOT NULL,
                col01varchar VARCHAR(1000) NOT NULL,
                book_value VARCHAR(1000) NOT NULL,
                begin_value VARCHAR(1000) NOT NULL,
                end_value VARCHAR(1000) NOT NULL
            );
            CREATE UNIQUE CLUSTERED INDEX IX_gdi_image_page_bounds_header ON #gdi_image_page_bounds (import_batch_id, header_file_key, col01varchar);

            SET @sql = N'
                ;WITH raw_paths AS (
                    SELECT
                        i.id,
                        i.import_batch_id,
                        ISNULL(i.col01varchar, '''') AS col01varchar,
                        REPLACE(REPLACE(LTRIM(RTRIM(COALESCE(
                            NULLIF(CAST(i.col03varchar AS VARCHAR(2000)), ''''),
                            ''''
                        ))), ''/'', CHAR(92)), ''"'', '''') AS normalized_path
                    FROM dbo.' + QUOTENAME(@image_table) + N' i
                    WHERE i.imported_by_user_id = @uid
                      AND i.state_fips = @sf
                      AND i.county_fips = @cf
                ),
                parsed AS (
                    SELECT
                        r.id,
                        r.import_batch_id,
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
                        p.import_batch_id,
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
                        x.import_batch_id,
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
                        s.import_batch_id,
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
                        n.import_batch_id,
                        n.book_value,
                        n.page_raw,
                        n.page_base,
                        n.should_dedupe,
                        ROW_NUMBER() OVER (
                            PARTITION BY n.import_batch_id, n.book_value, n.page_base, n.should_dedupe
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
                INSERT INTO #gdi_image_page_values (import_batch_id, image_id, book_value, page_value)
                SELECT
                    d.import_batch_id,
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
                        i.import_batch_id,
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
                      ON i.import_batch_id = v.import_batch_id
                     AND i.id = v.image_id
                    WHERE i.imported_by_user_id = @uid
                      AND i.state_fips = @sf
                      AND i.county_fips = @cf
                ),
                ordered AS (
                    SELECT
                        r.import_batch_id,
                        r.header_file_key,
                        r.col01varchar,
                        r.book_value,
                        r.page_value,
                        ROW_NUMBER() OVER (
                            PARTITION BY r.import_batch_id, r.header_file_key, r.col01varchar
                            ORDER BY CASE WHEN r.page_num IS NULL THEN 1 ELSE 0 END, r.page_num, r.page_value, r.image_id
                        ) AS rn_asc,
                        ROW_NUMBER() OVER (
                            PARTITION BY r.import_batch_id, r.header_file_key, r.col01varchar
                            ORDER BY CASE WHEN r.page_num IS NULL THEN 1 ELSE 0 END, r.page_num DESC, r.page_value DESC, r.image_id DESC
                        ) AS rn_desc
                    FROM ranked r
                )
                INSERT INTO #gdi_image_page_bounds (import_batch_id, header_file_key, col01varchar, book_value, begin_value, end_value)
                SELECT
                    o.import_batch_id,
                    o.header_file_key,
                    o.col01varchar,
                    MAX(CASE WHEN o.book_value <> '''' THEN o.book_value ELSE '''' END) AS book_value,
                    MAX(CASE WHEN o.rn_asc = 1 THEN ISNULL(o.page_value, '''') ELSE '''' END) AS begin_value,
                    MAX(CASE WHEN o.rn_desc = 1 THEN ISNULL(o.page_value, '''') ELSE '''' END) AS end_value
                FROM ordered o
                GROUP BY o.import_batch_id, o.header_file_key, o.col01varchar;';
            EXEC sys.sp_executesql @sql, N'@uid INT, @sf CHAR(2), @cf CHAR(5)', @ImportedByUserId, @state_fips, @county_fips;

            SET @sql = N'
                UPDATE i
                SET
                    i.book = ISNULL(v.book_value, ''''),
                    i.page_number = ISNULL(v.page_value, '''')
                FROM dbo.' + QUOTENAME(@image_table) + N' i
                JOIN #gdi_image_page_values v
                  ON v.import_batch_id = i.import_batch_id
                 AND v.image_id = i.id
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
              ON b.import_batch_id = h.import_batch_id
             AND b.header_file_key = h.header_file_key
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
                         AND src.import_batch_id = tgt.import_batch_id
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
