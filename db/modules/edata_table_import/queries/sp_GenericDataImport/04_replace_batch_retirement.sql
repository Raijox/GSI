/* ============================================================================
   File: 04_replace_batch_retirement.sql
   Procedure: dbo.sp_GenericDataImport
   Role in assembly:
   - Final-pass drop-mode cleanup for the active folder import.
   - Retires the immediately previous import batch as soft-deleted history and
     deletes batches older than the retained previous+current window.
   Why this file exists:
   - Replace/drop semantics are batch-wide, not file-by-file, so this logic is
     intentionally isolated from the per-file insert path.
   Maintenance notes:
   - This fragment must run only after the current batch is fully inserted.
   - Do not let this section retire the active @batch_id rows themselves.
   ============================================================================ */
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
