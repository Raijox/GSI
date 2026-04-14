/* ============================================================================
   File: 05_scan_legals_references_and_finalize.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Final bootstrap fragment.
   - Finishes dbo.sp_DataQualityCorrectionsScan with legal, reference,
     lookup-driven queue population, import-batch stamping, and the returned
     queue counts used by the UI.
   What lives here:
   - Legal quarter-section and section-range validation.
   - Reference book/page range and numeric-format validation.
   - Instrument-type, additions, record-series, and township-range lookup
     checks.
   - Import-batch propagation for newly inserted pending rows.
   - Final SELECT returning per-queue counts and closing the ALTER PROCEDURE
     dynamic SQL wrapper.
   Why this file exists:
   - These are the downstream and lookup-backed validations that build on the
     shared scope prepared in earlier fragments, so they fit naturally as the
     closeout segment of the scan procedure.
   Maintenance notes:
   - This file closes the dynamic procedure definition. Any future fragments
     added after it would need the procedure wrapper to be rebalanced.
   ============================================================================ */
    -- -------------------------------------------------------------------------
    -- 7) Legal issue detection block
    --    Supports either gdi_legals or legacy gdi_legal table name.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_legals'', ''U'') IS NOT NULL
    BEGIN
        -- 7.1 (moved) township/range lookup checks now populate corrections_township_range_dq

        -- 7.2 Quarter section token outside allowed set
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeQuarterSections'', ''Quarter section value is outside allowed set.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col08='', ISNULL(l.col08varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legals l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(l.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))<>''''
          AND UPPER(LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))) NOT IN (''N2'',''S2'',''E2'',''W2'',''NE'',''NW'',''SE'',''SW'',''N'',''S'',''E'',''W'')
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeQuarterSections'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );

        -- 7.3 Section value not numeric or out of 1..36
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeSection'', ''Section value is outside allowed range.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col02='', ISNULL(l.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legals l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(l.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))<>''''
          AND (
              LTRIM(RTRIM(ISNULL(l.col02varchar,''''))) = ''?''
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) IS NULL
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) NOT BETWEEN 1 AND 36
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeSection'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );
    END;
    ELSE IF OBJECT_ID(''dbo.gdi_legal'', ''U'') IS NOT NULL
    BEGIN
        -- 7.1 (moved) township/range lookup checks now populate corrections_township_range_dq

        -- 7.2 Quarter section token outside allowed set (legacy table)
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeQuarterSections'', ''Quarter section value is outside allowed set.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col08='', ISNULL(l.col08varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legal l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(l.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))<>''''
          AND UPPER(LTRIM(RTRIM(ISNULL(l.col08varchar,'''')))) NOT IN (''N2'',''S2'',''E2'',''W2'',''NE'',''NW'',''SE'',''SW'',''N'',''S'',''E'',''W'')
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeQuarterSections'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );

        -- 7.3 Section value not numeric or out of 1..36 (legacy table)
        INSERT INTO dbo.corrections_legal (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT l.id, ''legalOutOfRangeSection'', ''Section value is outside allowed range.'', ISNULL(l.header_file_key,''''), ISNULL(l.file_key,''''), ISNULL(l.col01varchar,''''), CONCAT(''col02='', ISNULL(l.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_legal l
        WHERE l.imported_by_user_id=@ImportedByUserId AND l.state_fips=@StateFips AND l.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(l.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(l.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))<>''''
          AND (
              LTRIM(RTRIM(ISNULL(l.col02varchar,''''))) = ''?''
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) IS NULL
              OR TRY_CONVERT(INT, LTRIM(RTRIM(ISNULL(l.col02varchar,'''')))) NOT BETWEEN 1 AND 36
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_legal cl
              WHERE cl.imported_by_user_id=@ImportedByUserId AND cl.state_fips=@StateFips AND cl.county_fips=@CountyFips
                AND cl.error_key=''legalOutOfRangeSection'' AND cl.source_row_id=l.id AND ISNULL(cl.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 8) Reference issue detection block
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''tempdb..#scope_reference'', ''U'') IS NOT NULL
        DROP TABLE #scope_reference;
    CREATE TABLE #scope_reference (
        id INT NOT NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL,
        is_split_book BIT NOT NULL,
        header_file_key NVARCHAR(260) NULL,
        file_key NVARCHAR(260) NULL,
        col01varchar VARCHAR(1000) NULL,
        referenced_book VARCHAR(1000) NULL,
        referenced_page VARCHAR(1000) NULL
    );
    CREATE CLUSTERED INDEX IX_scope_reference_id ON #scope_reference (id);
    CREATE INDEX IX_scope_reference_book_page ON #scope_reference (referenced_book, referenced_page);

    IF OBJECT_ID(''dbo.gdi_instrument_references'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_reference (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, referenced_book, referenced_page
        )
        SELECT
            r.id,
            r.imported_by_user_id,
            r.state_fips,
            r.county_fips,
            r.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            r.header_file_key,
            r.file_key,
            r.col01varchar,
            r.referenced_book,
            r.referenced_page
        FROM dbo.gdi_instrument_references r
        WHERE r.imported_by_user_id=@ImportedByUserId
          AND r.state_fips=@StateFips
          AND r.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(r.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(r.is_deleted,0)=0;

        -- 8.1 Recorded reference book is outside the books seen in header scope
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refRecordedNotWithinBookRange'', ''Reference recorded book does not match any header book in scope.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, ''''), ''; referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM #scope_header_books hb
              WHERE hb.book6 = RIGHT(''000000'' +
                                     CASE
                                         WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                              AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                             THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                                         ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                                     END, 6)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refRecordedNotWithinBookRange'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.2 Reference book should be six digits with optional one suffix
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refBookSixDigits'', ''Reference book should be 6 digits.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                  AND (
                      LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) <> 6
                      OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL
                  )
              )
              OR (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
                  AND (
                      LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) <> 6
                      OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL
                  )
              )
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refBookSixDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.3 Reference page should be four digits with optional one suffix
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refPageFourDigits'', ''Reference page should be 4 digits (optional one suffix).'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) <> 4
                          OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL
                      )
                  )
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) <> 4
                          OR TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL
                      )
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refPageFourDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.4 Missing reference book
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingBookNumber'', ''Reference book is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.5 Missing reference page
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingPageNumber'', ''Reference page is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_page is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.6 Non numeric reference book
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericBookNumber'', ''Reference book contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL)
              OR
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.7 Non numeric reference page
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericPageNumber'', ''Reference page contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL)
                  OR
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL)
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL)
                  OR
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL)
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );
    END;
    ELSE IF OBJECT_ID(''dbo.gdi_instrument_references'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_reference (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, referenced_book, referenced_page
        )
        SELECT
            r.id,
            r.imported_by_user_id,
            r.state_fips,
            r.county_fips,
            r.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            r.header_file_key,
            r.file_key,
            r.col01varchar,
            r.referenced_book,
            r.referenced_page
        FROM dbo.gdi_instrument_references r
        WHERE r.imported_by_user_id=@ImportedByUserId
          AND r.state_fips=@StateFips
          AND r.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(r.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(r.is_deleted,0)=0;

        -- 8.1 Recorded reference book is outside the books seen in header scope (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refRecordedNotWithinBookRange'', ''Reference recorded book does not match any header book in scope.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, ''''), ''; referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM #scope_header_books hb
              WHERE hb.book6 = RIGHT(''000000'' +
                                     CASE
                                         WHEN RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                                              AND LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) > 1
                                             THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)
                                         ELSE LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))
                                     END, 6)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refRecordedNotWithinBookRange'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.2 Reference book should be six digits with optional one suffix (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refBookSixDigits'', ''Reference book should be 6 digits.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
                  AND (
                      LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) <> 6
                      OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL
                  )
              )
              OR (
                  RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
                  AND (
                      LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) <> 6
                      OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL
                  )
              )
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refBookSixDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.3 Reference page should be four digits with optional one suffix (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refPageFourDigits'', ''Reference page should be 4 digits (optional one suffix).'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) <> 4
                          OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL
                      )
                  )
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                      AND (
                          LEN(LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) <> 4
                          OR TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL
                      )
                  )
                  OR (
                      RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                      AND (
                          LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) <> 4
                          OR TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL
                      )
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refPageFourDigits'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.4 Missing reference book (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingBookNumber'', ''Reference book is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.5 Missing reference page (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refMissingPageNumber'', ''Reference page is blank.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), ''referenced_page is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refMissingPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.6 Non numeric reference book (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericBookNumber'', ''Reference book contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_book='', ISNULL(r.referenced_book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))<>''''
          AND (
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) - 1)) IS NULL)
              OR
              (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_book, ''''))), 1) NOT LIKE ''[A-Z]''
               AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_book, '''')))) IS NULL)
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericBookNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );

        -- 8.7 Non numeric reference page (legacy table)
        INSERT INTO dbo.corrections_instrument_references (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT r.id, ''refNonNumericPageNumber'', ''Reference page contains non-numeric characters.'', ISNULL(r.header_file_key,''''), ISNULL(r.file_key,''''), ISNULL(r.col01varchar,''''), CONCAT(''referenced_page='', ISNULL(r.referenced_page, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_reference r
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))<>''''
          AND (
              (ISNULL(r.is_split_book, 0) = 0 AND (
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), LEN(LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1)) IS NULL)
                  OR
                  (RIGHT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) IS NULL)
              ))
              OR
              (ISNULL(r.is_split_book, 0) = 1 AND (
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) - 1)) IS NULL)
                  OR
                  (RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END, 1) NOT LIKE ''[A-Z]''
                   AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(r.referenced_page, '''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(r.referenced_page, ''''))) END) IS NULL)
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_reference cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''refNonNumericPageNumber'' AND cr.source_row_id=r.id AND ISNULL(cr.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 9) Instrument Types issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_instrument_types'', ''U'') IS NOT NULL
       AND OBJECT_ID(''dbo.keli_instrument_types'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_instrument_types_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT it.id, ''instTypeMissingLookup'', ''Instrument type does not match keli lookup.'', ISNULL(it.header_file_key,''''), ISNULL(it.file_key,''''), ISNULL(it.col01varchar,''''), CONCAT(''original='', LTRIM(RTRIM(ISNULL(it.col03varchar, '''')))), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_instrument_types it
        WHERE it.imported_by_user_id=@ImportedByUserId AND it.state_fips=@StateFips AND it.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(it.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(it.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(it.col03varchar, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.keli_instrument_types k
              WHERE LOWER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(1000)), '''')))) = LOWER(LTRIM(RTRIM(ISNULL(it.col03varchar, ''''))))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_inst_types ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''instTypeMissingLookup'' AND ci.source_row_id=it.id AND ISNULL(ci.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 10) Additions issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_additions'', ''U'') IS NOT NULL
       AND OBJECT_ID(''dbo.keli_additions'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_additions_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT a.id, ''additionMissingLookup'', ''Addition does not match keli lookup.'', ISNULL(a.header_file_key,''''), ISNULL(a.file_key,''''), ISNULL(a.col01varchar,''''), CONCAT(''original='', LTRIM(RTRIM(ISNULL(a.col05varchar, '''')))), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_additions a
        WHERE a.imported_by_user_id=@ImportedByUserId AND a.state_fips=@StateFips AND a.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(a.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(a.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(a.col05varchar, '''')))<>''''
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.keli_additions k
              WHERE RIGHT(''00'' + LTRIM(RTRIM(ISNULL(CAST(k.state_fips AS VARCHAR(1000)), ''''))), 2) = @StateFips
                AND RIGHT(''00000'' + LTRIM(RTRIM(ISNULL(CAST(k.county_fips AS VARCHAR(1000)), ''''))), 5) = @CountyFips
                AND LOWER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(1000)), '''')))) = LOWER(LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_additions ca
              WHERE ca.imported_by_user_id=@ImportedByUserId AND ca.state_fips=@StateFips AND ca.county_fips=@CountyFips
                AND ca.error_key=''additionMissingLookup'' AND ca.source_row_id=a.id AND ISNULL(ca.is_fixed,0)=1
          );
    END;

    -- -------------------------------------------------------------------------
    -- 11) Record Series issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_record_series'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_record_series_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT rs.id, ''recordSeriesMissingYear'', ''Record series year is blank.'', ISNULL(rs.header_file_key,''''), ISNULL(rs.file_key,''''), ISNULL(rs.col01varchar,''''), ''year is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_record_series rs
        WHERE rs.imported_by_user_id=@ImportedByUserId AND rs.state_fips=@StateFips AND rs.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(rs.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(rs.is_deleted,0)=0
          AND LTRIM(RTRIM(ISNULL(rs.[year], '''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_record_series cr
              WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                AND cr.error_key=''recordSeriesMissingYear'' AND cr.source_row_id=rs.id AND ISNULL(cr.is_fixed,0)=1
          );

        IF OBJECT_ID(''dbo.keli_record_series'', ''U'') IS NOT NULL
        BEGIN
            INSERT INTO dbo.corrections_record_series_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
            SELECT rs.id, ''recordSeriesMissingLookup'', ''Record series year not found in keli_record_series.'', ISNULL(rs.header_file_key,''''), ISNULL(rs.file_key,''''), ISNULL(rs.col01varchar,''''), CONCAT(''year='', LTRIM(RTRIM(ISNULL(rs.[year], '''')))), @ImportedByUserId, @StateFips, @CountyFips
            FROM dbo.gdi_record_series rs
            WHERE rs.imported_by_user_id=@ImportedByUserId AND rs.state_fips=@StateFips AND rs.county_fips=@CountyFips
              AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(rs.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
              AND ISNULL(rs.is_deleted,0)=0
              AND LTRIM(RTRIM(ISNULL(rs.[year], '''')))<>''''
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.keli_record_series k
                  WHERE UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(rs.[year], ''''))))
              )
              AND NOT EXISTS (
                  SELECT 1 FROM #fixed_record_series cr
                  WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                    AND cr.error_key=''recordSeriesMissingLookup'' AND cr.source_row_id=rs.id AND ISNULL(cr.is_fixed,0)=1
              );

            INSERT INTO dbo.corrections_record_series_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
            SELECT rs.id, ''recordSeriesIncorrectInternalId'', ''Record series internal id does not match year mapping.'', ISNULL(rs.header_file_key,''''), ISNULL(rs.file_key,''''), ISNULL(rs.col01varchar,''''), CONCAT(''year='', ISNULL(rs.[year], ''''), ''; record_series_internal_id='', ISNULL(rs.record_series_internal_id, '''')), @ImportedByUserId, @StateFips, @CountyFips
            FROM dbo.gdi_record_series rs
            JOIN dbo.keli_record_series k
              ON UPPER(LTRIM(RTRIM(ISNULL(CAST(k.[name] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(rs.[year], ''''))))
            WHERE rs.imported_by_user_id=@ImportedByUserId AND rs.state_fips=@StateFips AND rs.county_fips=@CountyFips
              AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(rs.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
              AND ISNULL(rs.is_deleted,0)=0
              AND LTRIM(RTRIM(ISNULL(rs.[year],'''')))<>''''
              AND ISNULL(rs.record_series_internal_id, '''') <> CAST(k.id AS VARCHAR(1000))
              AND NOT EXISTS (
                  SELECT 1 FROM #fixed_record_series cr
                  WHERE cr.imported_by_user_id=@ImportedByUserId AND cr.state_fips=@StateFips AND cr.county_fips=@CountyFips
                    AND cr.error_key=''recordSeriesIncorrectInternalId'' AND cr.source_row_id=rs.id AND ISNULL(cr.is_fixed,0)=1
              );
        END;
    END;

    -- -------------------------------------------------------------------------
    -- 12) Township/Range issue detection
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''dbo.gdi_township_range'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO dbo.corrections_township_range_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT tr.id, ''townshipRangeMissingValues'', ''Township or range is blank.'', ISNULL(tr.header_file_key,''''), ISNULL(tr.file_key,''''), ISNULL(tr.col01varchar,''''), CONCAT(''township='', ISNULL(tr.col03varchar, ''''), ''; range='', ISNULL(tr.col04varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM dbo.gdi_township_range tr
        WHERE tr.imported_by_user_id=@ImportedByUserId AND tr.state_fips=@StateFips AND tr.county_fips=@CountyFips AND ISNULL(tr.is_deleted,0)=0
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(tr.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND (LTRIM(RTRIM(ISNULL(tr.col03varchar, '''')))='''' OR LTRIM(RTRIM(ISNULL(tr.col04varchar, '''')))='''')
          AND (
                OBJECT_ID(''dbo.gdi_additions'', ''U'') IS NULL
                OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.gdi_additions a
                    WHERE a.imported_by_user_id = tr.imported_by_user_id
                      AND a.state_fips = tr.state_fips
                      AND a.county_fips = tr.county_fips
                      AND ISNULL(a.is_deleted, 0) = 0
                      AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(a.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
                      AND ISNULL(a.header_file_key, '''') = ISNULL(tr.header_file_key, '''')
                      AND ISNULL(a.col01varchar, '''') = ISNULL(tr.col01varchar, '''')
                      AND LTRIM(RTRIM(ISNULL(a.col05varchar, ''''))) <> ''''
                )
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_township_range ct
              WHERE ct.imported_by_user_id=@ImportedByUserId AND ct.state_fips=@StateFips AND ct.county_fips=@CountyFips
                AND ct.error_key=''townshipRangeMissingValues'' AND ct.source_row_id=tr.id AND ISNULL(ct.is_fixed,0)=1
          );

        IF OBJECT_ID(''dbo.keli_township_ranges'', ''U'') IS NOT NULL
        BEGIN
            INSERT INTO dbo.corrections_township_range_dq (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
            SELECT tr.id, ''townshipRangeOutOfCounty'', ''Township/Range not valid for county lookup.'', ISNULL(tr.header_file_key,''''), ISNULL(tr.file_key,''''), ISNULL(tr.col01varchar,''''), CONCAT(''township='', ISNULL(tr.col03varchar, ''''), ''; range='', ISNULL(tr.col04varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
            FROM dbo.gdi_township_range tr
            WHERE tr.imported_by_user_id=@ImportedByUserId AND tr.state_fips=@StateFips AND tr.county_fips=@CountyFips AND ISNULL(tr.is_deleted,0)=0
              AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(tr.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
              AND LTRIM(RTRIM(ISNULL(tr.col03varchar, ''''))) <> ''''
              AND LTRIM(RTRIM(ISNULL(tr.col04varchar, ''''))) <> ''''
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.keli_township_ranges ktr
                  WHERE UPPER(LTRIM(RTRIM(ISNULL(CAST(ktr.township AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(tr.col03varchar, ''''))))
                    AND UPPER(LTRIM(RTRIM(ISNULL(CAST(ktr.[range] AS VARCHAR(100)), '''')))) = UPPER(LTRIM(RTRIM(ISNULL(tr.col04varchar, ''''))))
                    AND ISNULL(ktr.active, 0) = 1
              )
              AND NOT EXISTS (
                  SELECT 1 FROM #fixed_township_range ct
                  WHERE ct.imported_by_user_id=@ImportedByUserId AND ct.state_fips=@StateFips AND ct.county_fips=@CountyFips
                    AND ct.error_key=''townshipRangeOutOfCounty'' AND ct.source_row_id=tr.id AND ISNULL(ct.is_fixed,0)=1
              );
        END;
    END;

    IF ISNULL(@scope_import_batch_id, '''') <> ''''
    BEGIN
        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_instruments c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_pages c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_legal c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_parties c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_instrument_references c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_instrument_types_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_additions_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_record_series_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';

        UPDATE c
        SET c.import_batch_id = @scope_import_batch_id
        FROM dbo.corrections_township_range_dq c
        WHERE c.imported_by_user_id = @ImportedByUserId
          AND c.state_fips = @StateFips
          AND c.county_fips = @CountyFips
          AND ISNULL(c.is_fixed, 0) = 0
          AND ISNULL(c.import_batch_id, '''') = '''';
    END;

    -- -------------------------------------------------------------------------
    -- 13) Return pending counts for each correction queue
    -- -------------------------------------------------------------------------
    SELECT
        (SELECT COUNT(1) FROM dbo.corrections_instruments WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS header_count,
        (SELECT COUNT(1) FROM dbo.corrections_pages WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS images_count,
        (SELECT COUNT(1) FROM dbo.corrections_legal WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS legal_count,
        (SELECT COUNT(1) FROM dbo.corrections_parties WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS names_count,
        (SELECT COUNT(1) FROM dbo.corrections_instrument_references WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS reference_count,
        (SELECT COUNT(1) FROM dbo.corrections_instrument_types_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS instrument_types_count,
        (SELECT COUNT(1) FROM dbo.corrections_additions_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS additions_count,
        (SELECT COUNT(1) FROM dbo.corrections_record_series_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS record_series_count,
        (SELECT COUNT(1) FROM dbo.corrections_township_range_dq WHERE imported_by_user_id=@ImportedByUserId AND state_fips=@StateFips AND county_fips=@CountyFips AND ISNULL(is_fixed,0)=0) AS township_range_count;
END;');
