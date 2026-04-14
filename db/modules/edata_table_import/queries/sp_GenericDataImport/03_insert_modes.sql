/* ============================================================================
   File: 03_insert_modes.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - Applies append-mode dedupe rules, inserts the parsed rows into
     dbo.GenericDataImport, and records append skip audit entries.
   Why this file exists:
   - The append and drop paths share parsing, but only append needs row-level
     duplicate suppression before insert.
   Maintenance notes:
   - Keep all GenericDataImport insert column lists aligned between the append
     and drop branches.
   - Any change to parsed staging columns must be reflected here deliberately.
   ============================================================================ */
    IF @mode = 'A'
    BEGIN
        DROP TABLE IF EXISTS #gdi_scope_existing_rows;
        CREATE TABLE #gdi_scope_existing_rows (
            fn VARCHAR(1000) NOT NULL,
            col01varchar VARCHAR(1000) NOT NULL,
            original_value VARCHAR(MAX) NOT NULL
        );
        CREATE INDEX IX_gdi_scope_existing_rows_match ON #gdi_scope_existing_rows (fn, col01varchar) INCLUDE (original_value);

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
