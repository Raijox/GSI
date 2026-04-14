/* ============================================================================
   File: 03_scan_headers_and_names.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Third bootstrap fragment.
   - Continues dbo.sp_DataQualityCorrectionsScan with the instrument/header and
     party/name issue-detection blocks.
   What lives here:
   - Header duplicate, blank, range, numeric-format, and fixed-length checks.
   - Name duplicate detection using normalized instrument-scope, party-type, and
     party-name matching rules.
   Why this file exists:
   - Header and party issues are core eData quality checks with their own dense
     rule set, so they are easier to reason about when isolated from image,
     legal, and lookup-driven validation.
   Maintenance notes:
   - Keep the error keys stable. The UI, fixed-row preservation logic, and audit
     history all depend on these exact identifiers remaining unchanged.
   ============================================================================ */
    -- -------------------------------------------------------------------------
    -- 4) Header issue detection block
    -- -------------------------------------------------------------------------

    -- 4.1 Duplicate book + beginning page
    ;WITH header_dups AS (
        SELECT
            h.id,
            h.header_file_key,
            h.file_key,
            h.col01varchar,
            h.col02varchar,
            h.col04varchar,
            h.col05varchar,
            h.col06varchar,
            h.book,
            h.beginning_page,
            COUNT(1) OVER (PARTITION BY ISNULL(h.book, ''''), ISNULL(h.beginning_page, '''')) AS dup_count
        FROM #scope_header h
        WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
    )
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerDuplicateBookPageNumber'', ''Duplicate book + beginning page.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''book='', ISNULL(h.book, ''''), ''; beginning_page='', ISNULL(h.beginning_page, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM header_dups h
    WHERE h.dup_count > 1
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerDuplicateBookPageNumber''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.2 Blank instrument number in col02varchar
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerDuplicateInstrumentNumber'', ''Instrument number (col02varchar) is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''col02varchar is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))=''''
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerDuplicateInstrumentNumber''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.3 (moved) record series lookup checks now populate corrections_record_series_dq

    -- 4.4 Non numeric beginning_page
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerNonNumericPageNumber'', ''Page number contains non-numeric characters.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''beginning_page='', ISNULL(h.beginning_page, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))<>''''
      AND (
          (ISNULL(h.is_split_book, 0) = 0
            AND TRY_CONVERT(BIGINT, REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))),''-'',''''),''_'',''''),''.'','''')) IS NULL
          )
          OR
          (ISNULL(h.is_split_book, 0) = 1
            AND NOT (
                (
                    LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 4
                    AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) IS NOT NULL
                )
                OR
                (
                    LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 5
                    AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 4)) IS NOT NULL
                    AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 1) LIKE ''[A-Z]''
                )
            )
          )
      )
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerNonNumericPageNumber''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.5 Invalid book range
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerValidBookRange'', ''Book number outside valid range.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''book='', ISNULL(h.book, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND (TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(h.book,''''))),'''')) IS NULL OR TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(h.book,''''))),'''')) NOT BETWEEN 1 AND 999999)
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId
            AND ch.state_fips=@StateFips
            AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerValidBookRange''
            AND ch.source_row_id=h.id
            AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.6 Missing beginning_page
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingBeginningPageNumber'', ''Beginning page number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''beginning_page is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingBeginningPageNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.7 Missing book
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingBookNumber'', ''Book number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''book is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.book,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingBookNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.8 Missing instrument number
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingInstrumentNumber'', ''Instrument number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''col02varchar is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingInstrumentNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.9 Non numeric instrument number
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerNonNumericInstrumentNumber'', ''Instrument number is non-numeric.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(h.col02varchar, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))<>''''
      AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) IS NULL
      AND NOT (
          RIGHT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), 1) LIKE ''[A-Z]''
          AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) - 1)) IS NOT NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerNonNumericInstrumentNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.10 Unexpected alpha suffix instrument number format
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerInstrumentNumberSixDigits'', ''Instrument number suffix format is unexpected.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(h.col02varchar, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND RIGHT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), 1) LIKE ''[A-Z]''
      AND (
          LEN(LEFT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) - 1)) <> 6
          OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(h.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(h.col02varchar,'''')))) - 1)) IS NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerInstrumentNumberSixDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.11 (moved) record series id checks now populate corrections_record_series_dq

    -- 4.12 Missing ending_page
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerMissingEndingPageNumber'', ''Ending page number is blank.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), ''ending_page is blank'', ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.ending_page,'''')))=''''
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerMissingEndingPageNumber'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.13 Book is not six-digit numeric
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerBookSixDigits'', ''Book number should be 6 digits.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''book='', ISNULL(h.book, '''')), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.book,'''')))<>''''
      AND (
          LEN(LTRIM(RTRIM(ISNULL(h.book,'''')))) <> 6
          OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.book,'''')))) IS NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerBookSixDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.14 Beginning page length/format check
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerBeginningPageFourDigits'', ''Beginning page should be fixed-length numeric by county split-image setting.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''beginning_page='', ISNULL(h.beginning_page, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))<>''''
      AND (
          (ISNULL(h.is_split_book, 0) = 0 AND (
              LEN(LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) <> @page_digits
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) IS NULL
          ))
          OR
          (ISNULL(h.is_split_book, 0) = 1 AND NOT (
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 4
                  AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) IS NOT NULL
              )
              OR
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END) = 5
                  AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 4)) IS NOT NULL
                  AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.beginning_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.beginning_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.beginning_page,''''))) END, 1) LIKE ''[A-Z]''
              )
          ))
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerBeginningPageFourDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- 4.15 Ending page length/format check
    INSERT INTO dbo.corrections_instruments (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, new_col02varchar, new_col03varchar, new_col04varchar, new_col05varchar, new_col06varchar, new_col07varchar, new_col08varchar, imported_by_user_id, state_fips, county_fips)
    SELECT h.id, ''headerEndingPageFourDigits'', ''Ending page should be fixed-length numeric by county split-image setting.'', ISNULL(h.header_file_key,''''), ISNULL(h.file_key,''''), ISNULL(h.col01varchar,''''), CONCAT(''ending_page='', ISNULL(h.ending_page, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), ISNULL(h.col02varchar,''''), CAST('''' AS VARCHAR(1000)), ISNULL(h.col04varchar,''''), ISNULL(h.col05varchar,''''), ISNULL(h.col06varchar,''''), CAST('''' AS VARCHAR(1000)), CAST('''' AS VARCHAR(1000)), @ImportedByUserId, @StateFips, @CountyFips
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId AND h.state_fips=@StateFips AND h.county_fips=@CountyFips AND ISNULL(h.is_deleted,0)=0
      AND LTRIM(RTRIM(ISNULL(h.ending_page,'''')))<>''''
      AND (
          (ISNULL(h.is_split_book, 0) = 0 AND (
              LEN(LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) <> @page_digits
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) IS NULL
          ))
          OR
          (ISNULL(h.is_split_book, 0) = 1 AND NOT (
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END) = 4
                  AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END) IS NOT NULL
              )
              OR
              (
                  LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END) = 5
                  AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END, 4)) IS NOT NULL
                  AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(h.ending_page,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(h.ending_page,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(h.ending_page,''''))) END, 1) LIKE ''[A-Z]''
              )
          ))
      )
      AND NOT EXISTS (
          SELECT 1 FROM #fixed_header ch
          WHERE ch.imported_by_user_id=@ImportedByUserId AND ch.state_fips=@StateFips AND ch.county_fips=@CountyFips
            AND ch.error_key=''headerEndingPageFourDigits'' AND ch.source_row_id=h.id AND ISNULL(ch.is_fixed,0)=1
      );

    -- -------------------------------------------------------------------------
    -- 5) Names issue detection block
    -- -------------------------------------------------------------------------
    -- 5.1 Duplicate party rows:
    --     duplicate only when same instrument + same party type + same party name.
    --     Grantor vs Grantee with same name is NOT a duplicate.
    ;WITH normalized_party_rows AS (
        SELECT
            n.id,
            n.header_file_key,
            n.file_key,
            n.col01varchar,
            n.col02varchar,
            n.col03varchar,
            ISNULL(
                NULLIF(LTRIM(RTRIM(ISNULL(n.header_file_key, ''''))), ''''),
                ISNULL(
                    NULLIF(LTRIM(RTRIM(ISNULL(n.file_key, ''''))), ''''),
                    LTRIM(RTRIM(ISNULL(n.fn, '''')))
                )
            ) AS instrument_scope_key,
            UPPER(LTRIM(RTRIM(ISNULL(n.col02varchar, '''')))) AS norm_party_type,
            UPPER(LTRIM(RTRIM(ISNULL(n.col03varchar, '''')))) AS norm_party_name
        FROM dbo.gdi_parties n
        WHERE n.imported_by_user_id=@ImportedByUserId
          AND n.state_fips=@StateFips
          AND n.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(n.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(n.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(n.col01varchar,'''')))<>''''
          AND LTRIM(RTRIM(ISNULL(n.col03varchar,'''')))<>''''
    ),
    name_dups AS (
        SELECT
            n.id,
            n.header_file_key,
            n.file_key,
            n.col01varchar,
            n.col02varchar,
            n.col03varchar,
            COUNT(1) OVER (
                PARTITION BY
                    n.instrument_scope_key,
                    ISNULL(n.col01varchar, ''''),
                    n.norm_party_type,
                    n.norm_party_name
            ) AS dup_count
        FROM normalized_party_rows n
        WHERE n.instrument_scope_key <> ''''
          AND n.norm_party_type <> ''''
          AND n.norm_party_name <> ''''
    )
    INSERT INTO dbo.corrections_parties (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
    SELECT n.id, ''nameDuplicateNames'', ''Duplicate name rows.'', ISNULL(n.header_file_key,''''), ISNULL(n.file_key,''''), ISNULL(n.col01varchar,''''), CONCAT(''type='', ISNULL(n.col02varchar, ''''), ''; name='', ISNULL(n.col03varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
    FROM name_dups n
    WHERE n.dup_count > 1
      AND NOT EXISTS (
          SELECT 1
          FROM #fixed_names cn
          WHERE cn.imported_by_user_id=@ImportedByUserId
            AND cn.state_fips=@StateFips
            AND cn.county_fips=@CountyFips
            AND cn.error_key=''nameDuplicateNames''
            AND cn.source_row_id=n.id
            AND ISNULL(cn.is_fixed,0)=1
      );
