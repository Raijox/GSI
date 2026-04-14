/* ============================================================================
   File: 04_scan_images.sql
   Module: Data Quality Corrections
   Role in assembly:
   - Fourth bootstrap fragment.
   - Continues dbo.sp_DataQualityCorrectionsScan with the page/image validation
     workflow, including both current and legacy table-shape handling.
   What lives here:
   - Scoped image temp-table preparation.
   - Duplicate book/page checks.
   - Path-shape and page-length profile review logic.
   - Numeric, blank, range, and fixed-length checks for image book/page values.
   - Header-book staging used by later reference validation.
   Why this file exists:
   - Image validation is one of the widest scan sections and contains the most
     profile-analysis logic, so isolating it keeps the rest of the procedure far
     easier to navigate.
   Maintenance notes:
   - The current and legacy branches intentionally mirror each other. Changes to
     one branch should be reviewed against the other so installs with older
     table contracts do not drift in behavior.
   ============================================================================ */
    -- -------------------------------------------------------------------------
    -- 6) Images issue detection block
    --    Supports either gdi_pages or legacy gdi_pages table name.
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(''tempdb..#scope_images'', ''U'') IS NOT NULL
        DROP TABLE #scope_images;
    CREATE TABLE #scope_images (
        id INT NOT NULL,
        imported_by_user_id INT NOT NULL,
        state_fips CHAR(2) NOT NULL,
        county_fips CHAR(5) NOT NULL,
        is_deleted BIT NOT NULL,
        is_split_book BIT NOT NULL,
        header_file_key NVARCHAR(260) NULL,
        file_key NVARCHAR(260) NULL,
        col01varchar VARCHAR(1000) NULL,
        col02varchar VARCHAR(1000) NULL,
        col03varchar VARCHAR(1000) NULL,
        book VARCHAR(1000) NULL,
        page_number VARCHAR(1000) NULL
    );
    CREATE CLUSTERED INDEX IX_scope_images_id ON #scope_images (id);
    CREATE INDEX IX_scope_images_book_page ON #scope_images (book, page_number);

    IF OBJECT_ID(''dbo.gdi_pages'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_images (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, col02varchar, col03varchar, book, page_number
        )
        SELECT
            i.id,
            i.imported_by_user_id,
            i.state_fips,
            i.county_fips,
            i.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(i.book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(i.book, ''''))), LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(i.book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            i.header_file_key,
            i.file_key,
            i.col01varchar,
            i.col02varchar,
            i.col03varchar,
            i.book,
            i.page_number
        FROM dbo.gdi_pages i
        WHERE i.imported_by_user_id=@ImportedByUserId
          AND i.state_fips=@StateFips
          AND i.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(i.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(i.is_deleted,0)=0;

        -- 6.1 Duplicate image book + page
        ;WITH image_dups AS (
            SELECT
                i.id,
                i.header_file_key,
                i.file_key,
                i.col01varchar,
                i.book,
                i.page_number,
                COUNT(1) OVER (PARTITION BY ISNULL(i.book, ''''), ISNULL(i.page_number, '''')) AS dup_count
            FROM #scope_images i
            WHERE 1=1
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageDuplicateBookPageNumber'', ''Duplicate image book+page combination.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, ''''), ''; page='', ISNULL(i.page_number, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM image_dups i
        WHERE i.dup_count > 1
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageDuplicateBookPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.2 Image path book segment length/format issues
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageIncorrectBookLength'', ''Image path book part is not 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col03varchar='', ISNULL(i.col03varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (
              LEN(LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) <> 6
              OR TRY_CONVERT(INT, LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectBookLength'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.3 Page length profile anomalies
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256) AS page_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256)) AS page_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT page_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY page_len
        ),
        dominant AS (
            SELECT TOP 1 page_len AS dominant_len
            FROM freq
            WHERE page_len > 0
            ORDER BY cnt DESC, page_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE page_len > 0
        ),
        major AS (
            SELECT f.page_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.page_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.page_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.page_value) AS page_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.page_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPageLength'',
            ''Image page_number length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_page_number='', s.page_value,
                ''; page_len='', CAST(s.page_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.page_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.page_len = s.page_len))
            OR (mc.major_groups < 2 AND s.page_len > 0 AND s.page_len <> ISNULL(d.dominant_len, s.page_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPageLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.4 Path length profile anomalies
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512) AS path_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512)) AS path_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT path_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY path_len
        ),
        dominant AS (
            SELECT TOP 1 path_len AS dominant_len
            FROM freq
            WHERE path_len > 0
            ORDER BY cnt DESC, path_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE path_len > 0
        ),
        major AS (
            SELECT f.path_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.path_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.path_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.path_value) AS path_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.path_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPathLength'',
            ''Image path length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_referenced_page='', s.path_value,
                ''; path_len='', CAST(s.path_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.path_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.path_len = s.path_len))
            OR (mc.major_groups < 2 AND s.path_len > 0 AND s.path_len <> ISNULL(d.dominant_len, s.path_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPathLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.5 Non numeric page number values
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericPageNumber'', ''Image page number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(i.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) IS NULL
          AND NOT (
              RIGHT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), 1) LIKE ''[A-Z]''
              AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) - 1)) IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.6 Non numeric book
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericBookNumber'', ''Image book number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.7 Missing book
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingBookNumber'', ''Image book number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.8 Missing page
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingPageNumber'', ''Image page number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''page_number is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.9 Book range
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageValidBookRange'', ''Image book number outside valid range.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) IS NULL OR TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) NOT BETWEEN 1 AND 999999)
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageValidBookRange'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.10 Book should be six digits
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageBookSixDigits'', ''Image book should be 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND (
              LEN(LTRIM(RTRIM(ISNULL(i.book,'''')))) <> 6
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageBookSixDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.11 Page should be fixed-length numeric by split-image setting
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imagePageFourDigits'', ''Image page should be fixed-length numeric by county split-image setting.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''page_number='', ISNULL(i.page_number, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))<>''''
          AND (
              (ISNULL(i.is_split_book, 0) = 0 AND (
                  LEN(LTRIM(RTRIM(ISNULL(i.page_number,'''')))) <> @page_digits
                  OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.page_number,'''')))) IS NULL
              ))
              OR
              (ISNULL(i.is_split_book, 0) = 1 AND NOT (
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 4
                      AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) IS NOT NULL
                  )
                  OR
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 5
                      AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 4)) IS NOT NULL
                      AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 1) LIKE ''[A-Z]''
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imagePageFourDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );
    END;
    ELSE IF OBJECT_ID(''dbo.gdi_pages'', ''U'') IS NOT NULL
    BEGIN
        INSERT INTO #scope_images (
            id, imported_by_user_id, state_fips, county_fips, is_deleted, is_split_book,
            header_file_key, file_key, col01varchar, col02varchar, col03varchar, book, page_number
        )
        SELECT
            i.id,
            i.imported_by_user_id,
            i.state_fips,
            i.county_fips,
            i.is_deleted,
            CASE
                WHEN @has_split_book_range = 1
                     AND TRY_CONVERT(INT, CASE
                            WHEN RIGHT(LTRIM(RTRIM(ISNULL(i.book, ''''))), 1) LIKE ''[A-Z]''
                                 AND LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) > 1
                                THEN LEFT(LTRIM(RTRIM(ISNULL(i.book, ''''))), LEN(LTRIM(RTRIM(ISNULL(i.book, '''')))) - 1)
                            ELSE LTRIM(RTRIM(ISNULL(i.book, '''')))
                        END) BETWEEN @split_book_start AND @split_book_end
                    THEN 1
                ELSE 0
            END,
            i.header_file_key,
            i.file_key,
            i.col01varchar,
            i.col02varchar,
            i.col03varchar,
            i.book,
            i.page_number
        FROM dbo.gdi_pages i
        WHERE i.imported_by_user_id=@ImportedByUserId
          AND i.state_fips=@StateFips
          AND i.county_fips=@CountyFips
          AND (ISNULL(@scope_import_batch_id, '''') = '''' OR CAST(i.import_batch_id AS VARCHAR(36)) = @scope_import_batch_id)
          AND ISNULL(i.is_deleted,0)=0;

        -- 6.1 Duplicate image book + page (legacy table)
        ;WITH image_dups AS (
            SELECT
                i.id,
                i.header_file_key,
                i.file_key,
                i.col01varchar,
                i.book,
                i.page_number,
                COUNT(1) OVER (PARTITION BY ISNULL(i.book, ''''), ISNULL(i.page_number, '''')) AS dup_count
            FROM #scope_images i
            WHERE 1=1
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageDuplicateBookPageNumber'', ''Duplicate image book+page combination.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, ''''), ''; page='', ISNULL(i.page_number, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM image_dups i
        WHERE i.dup_count > 1
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageDuplicateBookPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.2 Image path book segment length/format issues (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageIncorrectBookLength'', ''Image path book part is not 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col03varchar='', ISNULL(i.col03varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (
              LEN(LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) <> 6
              OR TRY_CONVERT(INT, LEFT(REPLACE(ISNULL(i.col03varchar,''''),''/'',''\''),
                       NULLIF(CHARINDEX(''\'', REPLACE(ISNULL(i.col03varchar,''''),''/'',''\'') + ''\''),0)-1)) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectBookLength'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.3 Page length profile anomalies (legacy table)
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256) AS page_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.page_number, ''''))), 256)) AS page_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT page_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY page_len
        ),
        dominant AS (
            SELECT TOP 1 page_len AS dominant_len
            FROM freq
            WHERE page_len > 0
            ORDER BY cnt DESC, page_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE page_len > 0
        ),
        major AS (
            SELECT f.page_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.page_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.page_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.page_value) AS page_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.page_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPageLength'',
            ''Image page_number length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_page_number='', s.page_value,
                ''; page_len='', CAST(s.page_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.page_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.page_len = s.page_len))
            OR (mc.major_groups < 2 AND s.page_len > 0 AND s.page_len <> ISNULL(d.dominant_len, s.page_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPageLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.4 Path length profile anomalies (legacy table)
        ;WITH lens AS (
            SELECT
                i.id,
                ISNULL(i.header_file_key, '''') AS header_file_key,
                ISNULL(i.file_key, '''') AS file_key,
                ISNULL(i.col01varchar, '''') AS col01varchar,
                LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512) AS path_value,
                LEN(LEFT(LTRIM(RTRIM(ISNULL(i.col03varchar, ''''))), 512)) AS path_len
            FROM #scope_images i
            WHERE 1=1
        ),
        freq AS (
            SELECT path_len, COUNT(1) AS cnt
            FROM lens
            GROUP BY path_len
        ),
        dominant AS (
            SELECT TOP 1 path_len AS dominant_len
            FROM freq
            WHERE path_len > 0
            ORDER BY cnt DESC, path_len DESC
        ),
        stats AS (
            SELECT ISNULL(SUM(cnt), 0) AS total_count
            FROM freq
            WHERE path_len > 0
        ),
        major AS (
            SELECT f.path_len
            FROM freq f
            CROSS JOIN stats s
            WHERE f.path_len > 0
              AND s.total_count > 0
              AND CAST(f.cnt AS FLOAT) / CAST(s.total_count AS FLOAT) >= 0.25
        ),
        major_count AS (
            SELECT COUNT(1) AS major_groups
            FROM major
        ),
        sample_by_len AS (
            SELECT
                l.path_len,
                MIN(l.id) AS sample_id,
                MAX(l.header_file_key) AS header_file_key,
                MAX(l.file_key) AS file_key,
                MAX(l.col01varchar) AS col01varchar,
                MAX(l.path_value) AS path_value,
                COUNT(1) AS sample_count
            FROM lens l
            GROUP BY l.path_len
        )
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT
            s.sample_id,
            ''imageIncorrectPathLength'',
            ''Image path length profile review.'',
            s.header_file_key,
            s.file_key,
            s.col01varchar,
            CONCAT(
                ''sample_referenced_page='', s.path_value,
                ''; path_len='', CAST(s.path_len AS VARCHAR(20)),
                ''; dominant_len='', ISNULL(CAST(d.dominant_len AS VARCHAR(20)), ''none''),
                ''; major_groups='', CAST(mc.major_groups AS VARCHAR(20)),
                ''; group_count='', CAST(s.sample_count AS VARCHAR(20))
            ),
            @ImportedByUserId, @StateFips, @CountyFips
        FROM sample_by_len s
        CROSS JOIN major_count mc
        OUTER APPLY (SELECT dominant_len FROM dominant) d
        WHERE (
            s.path_len = 0
            OR (mc.major_groups >= 2 AND EXISTS (SELECT 1 FROM major m WHERE m.path_len = s.path_len))
            OR (mc.major_groups < 2 AND s.path_len > 0 AND s.path_len <> ISNULL(d.dominant_len, s.path_len))
        )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageIncorrectPathLength'' AND ci.source_row_id=s.sample_id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.5 Non numeric page number values (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericPageNumber'', ''Image page number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''col02varchar='', ISNULL(i.col02varchar, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) IS NULL
          AND NOT (
              RIGHT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), 1) LIKE ''[A-Z]''
              AND TRY_CONVERT(BIGINT, LEFT(LTRIM(RTRIM(ISNULL(i.col02varchar,''''))), LEN(LTRIM(RTRIM(ISNULL(i.col02varchar,'''')))) - 1)) IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.6 Non numeric book (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageNonNumericBookNumber'', ''Image book number contains non-numeric characters.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageNonNumericBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.7 Missing book (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingBookNumber'', ''Image book number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''book is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingBookNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.8 Missing page (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageMissingPageNumber'', ''Image page number is blank.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), ''page_number is blank'', @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))=''''
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageMissingPageNumber'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.9 Book range (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageValidBookRange'', ''Image book number outside valid range.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND (TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) IS NULL OR TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(i.book,''''))),'''')) NOT BETWEEN 1 AND 999999)
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageValidBookRange'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.10 Book should be six digits (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imageBookSixDigits'', ''Image book should be 6 digits.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''book='', ISNULL(i.book, '''')), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.book,'''')))<>''''
          AND (
              LEN(LTRIM(RTRIM(ISNULL(i.book,'''')))) <> 6
              OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.book,'''')))) IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imageBookSixDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );

        -- 6.11 Page should be fixed-length numeric by split-image setting (legacy table)
        INSERT INTO dbo.corrections_pages (source_row_id, error_key, error_label, header_file_key, file_key, col01varchar, snapshot, imported_by_user_id, state_fips, county_fips)
        SELECT i.id, ''imagePageFourDigits'', ''Image page should be fixed-length numeric by county split-image setting.'', ISNULL(i.header_file_key,''''), ISNULL(i.file_key,''''), ISNULL(i.col01varchar,''''), CONCAT(''page_number='', ISNULL(i.page_number, ''''), ''; required_digits='', CAST(@page_digits AS VARCHAR(10))), @ImportedByUserId, @StateFips, @CountyFips
        FROM #scope_images i
        WHERE 1=1
          AND LTRIM(RTRIM(ISNULL(i.page_number,'''')))<>''''
          AND (
              (ISNULL(i.is_split_book, 0) = 0 AND (
                  LEN(LTRIM(RTRIM(ISNULL(i.page_number,'''')))) <> @page_digits
                  OR TRY_CONVERT(BIGINT, LTRIM(RTRIM(ISNULL(i.page_number,'''')))) IS NULL
              ))
              OR
              (ISNULL(i.is_split_book, 0) = 1 AND NOT (
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 4
                      AND TRY_CONVERT(BIGINT, CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) IS NOT NULL
                  )
                  OR
                  (
                      LEN(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END) = 5
                      AND TRY_CONVERT(BIGINT, LEFT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 4)) IS NOT NULL
                      AND RIGHT(CASE WHEN CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) > 0 THEN LEFT(LTRIM(RTRIM(ISNULL(i.page_number,''''))), CHARINDEX(''-'', LTRIM(RTRIM(ISNULL(i.page_number,'''')))) - 1) ELSE LTRIM(RTRIM(ISNULL(i.page_number,''''))) END, 1) LIKE ''[A-Z]''
                  )
              ))
          )
          AND NOT EXISTS (
              SELECT 1 FROM #fixed_images ci
              WHERE ci.imported_by_user_id=@ImportedByUserId AND ci.state_fips=@StateFips AND ci.county_fips=@CountyFips
                AND ci.error_key=''imagePageFourDigits'' AND ci.source_row_id=i.id AND ISNULL(ci.is_fixed,0)=1
          );
    END;

    IF OBJECT_ID(''tempdb..#scope_header_books'', ''U'') IS NOT NULL
        DROP TABLE #scope_header_books;
    CREATE TABLE #scope_header_books (
        book6 CHAR(6) NOT NULL PRIMARY KEY
    );
    INSERT INTO #scope_header_books (book6)
    SELECT DISTINCT RIGHT(''000000'' + LTRIM(RTRIM(ISNULL(h.book, ''''))), 6)
    FROM #scope_header h
    WHERE h.imported_by_user_id=@ImportedByUserId
      AND h.state_fips=@StateFips
      AND h.county_fips=@CountyFips
      AND ISNULL(h.is_deleted,0)=0;
