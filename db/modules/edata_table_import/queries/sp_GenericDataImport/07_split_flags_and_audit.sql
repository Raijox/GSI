/* ============================================================================
   File: 07_split_flags_and_audit.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - Applies split-book flags across scoped gdi tables, validates split counts,
     emits import audit telemetry, and closes the procedure definition.
   Why this file exists:
   - This is the verification and observability layer for the import. Keeping it
     separate makes it easier to adjust diagnostics without touching load logic.
   Maintenance notes:
   - This fragment must remain last because it assumes all rebuild work is done.
   - If you add new gdi_* tables that participate in audits or split flags,
     wire them here after their build step exists earlier in the assembly.
   ============================================================================ */
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
                     AND h.import_batch_id = tgt.import_batch_id
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
        FROM #gdi_scope_parts_fast sp
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

        DECLARE @split_table_count INT = (SELECT COUNT(DISTINCT tag) FROM #gdi_scope_parts_fast);
        DECLARE @split_row_count INT = (SELECT COUNT(1) FROM #gdi_scope_parts_fast);
        DECLARE @orphan_count INT;
        DECLARE @duplicate_header_groups INT;
        DECLARE @duplicate_header_rows INT;
        DECLARE @misc_tag_count INT;
        DECLARE @duplicate_file_keys INT;
        DECLARE @non_header_without_header_suffix INT;
        DECLARE @generic_scope_row_count INT = ISNULL(@split_row_count, 0);
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
        FROM #gdi_scope_parts_fast src
        LEFT JOIN #gdi_scope_parts_fast hdr
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
        FROM #gdi_scope_parts_fast
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
            FROM #gdi_scope_parts_fast
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
            FROM #gdi_scope_parts_fast
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
            FROM #gdi_scope_parts_fast
            WHERE tag = 'header'
              AND ISNULL(file_suffix, '') <> ''
        ) header_suffix
        CROSS JOIN (
            SELECT DISTINCT tag
            FROM #gdi_scope_parts_fast
            WHERE tag NOT IN ('header', 'misc')
        ) expected_tags
        LEFT JOIN (
            SELECT DISTINCT file_suffix, tag
            FROM #gdi_scope_parts_fast
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
            FROM #gdi_scope_parts_fast
            WHERE tag = 'header'
              AND ISNULL(file_suffix, '') <> ''
        ) hs
        WHERE NOT EXISTS (
            SELECT 1
            FROM #gdi_scope_parts_fast b
            WHERE b.file_suffix = hs.file_suffix
              AND b.tag NOT IN ('header', 'misc')
        );

        SELECT @non_header_without_header_suffix = COUNT(1)
        FROM (
            SELECT DISTINCT b.file_suffix
            FROM #gdi_scope_parts_fast b
            WHERE b.tag NOT IN ('header', 'misc')
              AND ISNULL(b.file_suffix, '') <> ''
              AND NOT EXISTS (
                  SELECT 1
                  FROM #gdi_scope_parts_fast h
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
