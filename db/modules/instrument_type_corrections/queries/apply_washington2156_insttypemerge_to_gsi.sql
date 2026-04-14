USE [GSI];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/*
    Purpose
    -------
    Import washington2156.dbo.InstTypeMerge into the live GSI instrument-type
    correction workflow for Washington County, Oklahoma.

    Rules implemented
    -----------------
    1. Treat each InstTypeMerge row as a primary-pass mapping by default.
    2. If a primary-pass mapping already exists for that original value:
       - skip when the existing primary value already matches the incoming value
       - otherwise apply it as a secondary-pass mapping
    3. If an identical secondary-pass mapping already exists, skip it.
    4. Update the same tables the manual tool uses so the UI reflects the work:
       - gdi_instrument_types
       - corrections_instrument_types
       - corrections_instrument_types_second_pass
       - corrections_instrument_types_dq
       - legacy_instrument_types
       - legacy_instrument_types_second_pass
       - *_audit tables

    Notes
    -----
    - The script auto-resolves the current active import batch for the target
      scope. If more than one batch exists, set @CurrentBatchId manually.
    - Default mode is preview-only. Change @CommitChanges to 1 to commit.
*/

DECLARE @ImportedByUserId INT = 1;
DECLARE @StateFips CHAR(2) = '40';
DECLARE @CountyFips CHAR(5) = '40147';
DECLARE @CurrentBatchId VARCHAR(36) = NULL;
DECLARE @CommitChanges BIT = 0;
DECLARE @RunLabel VARCHAR(200) = 'washington2156 InstTypeMerge import';
DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

IF DB_ID(N'washington2156') IS NULL
    THROW 50000, 'Source database washington2156 was not found.', 1;

IF OBJECT_ID(N'dbo.gdi_instrument_types', N'U') IS NULL
    THROW 50000, 'Target table dbo.gdi_instrument_types was not found in GSI.', 1;

IF OBJECT_ID(N'dbo.corrections_instrument_types', N'U') IS NULL
    THROW 50000, 'Target table dbo.corrections_instrument_types was not found in GSI.', 1;

IF OBJECT_ID(N'dbo.corrections_instrument_types_second_pass', N'U') IS NULL
    THROW 50000, 'Target table dbo.corrections_instrument_types_second_pass was not found in GSI.', 1;

IF OBJECT_ID(N'dbo.legacy_instrument_types', N'U') IS NULL
    THROW 50000, 'Target table dbo.legacy_instrument_types was not found in GSI.', 1;

IF OBJECT_ID(N'dbo.legacy_instrument_types_second_pass', N'U') IS NULL
    THROW 50000, 'Target table dbo.legacy_instrument_types_second_pass was not found in GSI.', 1;

IF OBJECT_ID(N'dbo.keli_instrument_types', N'U') IS NULL
    THROW 50000, 'Target table dbo.keli_instrument_types was not found in GSI.', 1;

IF OBJECT_ID(N'[washington2156].dbo.InstTypeMerge', N'U') IS NULL
    THROW 50000, 'Source table washington2156.dbo.InstTypeMerge was not found.', 1;

IF @CurrentBatchId IS NULL
BEGIN
    DECLARE @BatchCount INT;

    SELECT @BatchCount = COUNT(*)
    FROM (
        SELECT CAST(import_batch_id AS VARCHAR(36)) AS import_batch_id
        FROM dbo.gdi_instrument_types
        WHERE imported_by_user_id = @ImportedByUserId
          AND state_fips = @StateFips
          AND county_fips = @CountyFips
        GROUP BY CAST(import_batch_id AS VARCHAR(36))
    ) b;

    IF ISNULL(@BatchCount, 0) = 0
        THROW 50000, 'No import batch was found for the requested GSI scope.', 1;

    IF @BatchCount > 1
        THROW 50000, 'Multiple import batches exist for this scope. Set @CurrentBatchId manually before running.', 1;

    SELECT TOP 1
        @CurrentBatchId = CAST(import_batch_id AS VARCHAR(36))
    FROM dbo.gdi_instrument_types
    WHERE imported_by_user_id = @ImportedByUserId
      AND state_fips = @StateFips
      AND county_fips = @CountyFips
    GROUP BY CAST(import_batch_id AS VARCHAR(36));
END;

DROP TABLE IF EXISTS #keli_lookup;
DROP TABLE IF EXISTS #merge_map;
DROP TABLE IF EXISTS #primary_history;
DROP TABLE IF EXISTS #secondary_history;
DROP TABLE IF EXISTS #actions;
DROP TABLE IF EXISTS #primary_source_rows;
DROP TABLE IF EXISTS #secondary_source_rows;
DROP TABLE IF EXISTS #primary_apply;
DROP TABLE IF EXISTS #secondary_apply;
DROP TABLE IF EXISTS #primary_dq_rows;

;WITH keli_ranked AS (
    SELECT
        LTRIM(RTRIM(ISNULL(k.name, ''))) AS name,
        CAST(k.id AS VARCHAR(100)) AS keli_id,
        LTRIM(RTRIM(ISNULL(k.record_type, ''))) AS record_type,
        CASE
            WHEN TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(k.active, ''))), '')) IS NOT NULL
                THEN CASE WHEN TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(ISNULL(k.active, ''))), '')) <> 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END
            WHEN LOWER(LTRIM(RTRIM(ISNULL(k.active, '')))) IN ('true', 'yes', 'active')
                THEN CAST(1 AS BIT)
            WHEN LOWER(LTRIM(RTRIM(ISNULL(k.active, '')))) IN ('false', 'no', 'inactive')
                THEN CAST(0 AS BIT)
            ELSE NULL
        END AS is_active,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(LTRIM(RTRIM(ISNULL(k.name, ''))))
            ORDER BY k.imported_at DESC, CAST(k.id AS VARCHAR(100)) DESC
        ) AS rn
    FROM dbo.keli_instrument_types k
    WHERE k.imported_by_user_id = @ImportedByUserId
      AND k.state_fips = @StateFips
      AND k.county_fips = @CountyFips
)
SELECT
    name,
    keli_id,
    record_type,
    is_active
INTO #keli_lookup
FROM keli_ranked
WHERE rn = 1;

SELECT
    LTRIM(RTRIM(m.OriginalDocType)) AS original_value,
    LTRIM(RTRIM(m.CustomerDocType)) AS incoming_value,
    kl.keli_id,
    kl.record_type,
    kl.is_active
INTO #merge_map
FROM [washington2156].dbo.InstTypeMerge m
LEFT JOIN #keli_lookup kl
  ON LOWER(kl.name) = LOWER(LTRIM(RTRIM(ISNULL(m.CustomerDocType, ''))))
WHERE LTRIM(RTRIM(ISNULL(m.OriginalDocType, ''))) <> ''
  AND LTRIM(RTRIM(ISNULL(m.CustomerDocType, ''))) <> '';

IF EXISTS (
    SELECT 1
    FROM #merge_map
    GROUP BY LOWER(original_value)
    HAVING COUNT(*) > 1
)
    THROW 50000, 'InstTypeMerge contains duplicate original values. Resolve those duplicates first.', 1;

IF EXISTS (
    SELECT 1
    FROM #merge_map
    WHERE keli_id IS NULL
)
    THROW 50000, 'One or more CustomerDocType values do not exist in dbo.keli_instrument_types.', 1;

;WITH primary_ranked AS (
    SELECT
        LTRIM(RTRIM(ISNULL(l.original_value, ''))) AS original_value,
        LTRIM(RTRIM(ISNULL(l.new_value, ''))) AS primary_value,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(LTRIM(RTRIM(ISNULL(l.original_value, ''))))
            ORDER BY l.updated_at DESC, l.id DESC
        ) AS rn
    FROM dbo.legacy_instrument_types l
    WHERE l.imported_by_user_id = @ImportedByUserId
      AND l.state_fips = @StateFips
      AND l.county_fips = @CountyFips
      AND ISNULL(l.is_deleted, 0) = 0
)
SELECT
    original_value,
    primary_value
INTO #primary_history
FROM primary_ranked
WHERE rn = 1;

;WITH secondary_ranked AS (
    SELECT
        LTRIM(RTRIM(ISNULL(l.original_value, ''))) AS original_value,
        LTRIM(RTRIM(ISNULL(l.new_value, ''))) AS secondary_value,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(LTRIM(RTRIM(ISNULL(l.original_value, ''))))
            ORDER BY l.updated_at DESC, l.id DESC
        ) AS rn
    FROM dbo.legacy_instrument_types_second_pass l
    WHERE l.imported_by_user_id = @ImportedByUserId
      AND l.state_fips = @StateFips
      AND l.county_fips = @CountyFips
      AND ISNULL(l.is_deleted, 0) = 0
)
SELECT
    original_value,
    secondary_value
INTO #secondary_history
FROM secondary_ranked
WHERE rn = 1;

SELECT
    mm.original_value,
    mm.incoming_value,
    mm.keli_id,
    mm.record_type,
    mm.is_active,
    ph.primary_value,
    sh.secondary_value,
    CASE
        WHEN ph.primary_value IS NULL THEN 'primary'
        WHEN LOWER(ph.primary_value) = LOWER(mm.incoming_value) THEN 'skip_same_as_primary'
        WHEN sh.secondary_value IS NOT NULL AND LOWER(sh.secondary_value) = LOWER(mm.incoming_value) THEN 'skip_same_as_secondary'
        ELSE 'secondary'
    END AS action
INTO #actions
FROM #merge_map mm
LEFT JOIN #primary_history ph
  ON LOWER(ph.original_value) = LOWER(mm.original_value)
LEFT JOIN #secondary_history sh
  ON LOWER(sh.original_value) = LOWER(mm.original_value);

SELECT
    it.id AS source_row_id,
    CAST(it.import_batch_id AS VARCHAR(36)) AS import_batch_id,
    a.original_value,
    a.incoming_value,
    a.keli_id,
    a.record_type,
    a.is_active
INTO #primary_source_rows
FROM #actions a
JOIN dbo.gdi_instrument_types it
  ON a.action = 'primary'
 AND it.imported_by_user_id = @ImportedByUserId
 AND it.state_fips = @StateFips
 AND it.county_fips = @CountyFips
 AND CAST(it.import_batch_id AS VARCHAR(36)) = @CurrentBatchId
 AND ISNULL(it.is_deleted, 0) = 0
 AND LOWER(LTRIM(RTRIM(ISNULL(it.col03varchar, '')))) = LOWER(a.original_value);

SELECT
    c.source_row_id,
    ISNULL(c.import_batch_id, '') AS import_batch_id,
    a.original_value,
    a.incoming_value,
    a.keli_id,
    a.record_type,
    a.is_active,
    LTRIM(RTRIM(ISNULL(c.new_instrument_type_name, ''))) AS primary_pass_value
INTO #secondary_source_rows
FROM #actions a
JOIN dbo.corrections_instrument_types c
  ON a.action = 'secondary'
 AND c.imported_by_user_id = @ImportedByUserId
 AND c.state_fips = @StateFips
 AND c.county_fips = @CountyFips
 AND ISNULL(c.import_batch_id, '') = @CurrentBatchId
 AND LOWER(LTRIM(RTRIM(ISNULL(c.original_instrument_type, '')))) = LOWER(a.original_value)
 AND LTRIM(RTRIM(ISNULL(c.new_instrument_type_name, ''))) <> ''
JOIN dbo.gdi_instrument_types it
  ON it.id = c.source_row_id
 AND it.imported_by_user_id = c.imported_by_user_id
 AND it.state_fips = c.state_fips
 AND it.county_fips = c.county_fips
 AND CAST(it.import_batch_id AS VARCHAR(36)) = @CurrentBatchId
 AND ISNULL(it.is_deleted, 0) = 0;

IF EXISTS (
    SELECT 1
    FROM #secondary_source_rows
    GROUP BY LOWER(original_value)
    HAVING COUNT(DISTINCT LOWER(primary_pass_value)) > 1
)
    THROW 50000, 'A secondary-pass original value matched more than one primary-pass value. Review that original manually.', 1;

SELECT
    original_value,
    incoming_value,
    keli_id,
    record_type,
    is_active,
    COUNT(*) AS source_row_count
INTO #primary_apply
FROM #primary_source_rows
GROUP BY
    original_value,
    incoming_value,
    keli_id,
    record_type,
    is_active;

SELECT
    original_value,
    incoming_value,
    keli_id,
    record_type,
    is_active,
    MIN(primary_pass_value) AS primary_pass_value,
    COUNT(*) AS source_row_count
INTO #secondary_apply
FROM #secondary_source_rows
GROUP BY
    original_value,
    incoming_value,
    keli_id,
    record_type,
    is_active;

SELECT
    psr.original_value,
    COUNT(*) AS dq_row_count
INTO #primary_dq_rows
FROM #primary_source_rows psr
JOIN dbo.corrections_instrument_types_dq dq
  ON dq.source_row_id = psr.source_row_id
 AND dq.imported_by_user_id = @ImportedByUserId
 AND dq.state_fips = @StateFips
 AND dq.county_fips = @CountyFips
 AND ISNULL(dq.import_batch_id, '') = psr.import_batch_id
WHERE ISNULL(dq.is_fixed, 0) = 0
GROUP BY psr.original_value;

DECLARE @PrimaryMappingCount INT = ISNULL((SELECT COUNT(*) FROM #primary_apply), 0);
DECLARE @PrimarySourceRowCount INT = ISNULL((SELECT SUM(source_row_count) FROM #primary_apply), 0);
DECLARE @SecondaryMappingCount INT = ISNULL((SELECT COUNT(*) FROM #secondary_apply), 0);
DECLARE @SecondarySourceRowCount INT = ISNULL((SELECT SUM(source_row_count) FROM #secondary_apply), 0);
DECLARE @SkipSameAsPrimaryCount INT = ISNULL((SELECT COUNT(*) FROM #actions WHERE action = 'skip_same_as_primary'), 0);
DECLARE @SkipSameAsSecondaryCount INT = ISNULL((SELECT COUNT(*) FROM #actions WHERE action = 'skip_same_as_secondary'), 0);

SELECT
    @RunLabel AS run_label,
    @ImportedByUserId AS imported_by_user_id,
    @StateFips AS state_fips,
    @CountyFips AS county_fips,
    @CurrentBatchId AS import_batch_id,
    @PrimaryMappingCount AS primary_mapping_count,
    @PrimarySourceRowCount AS primary_source_row_count,
    @SecondaryMappingCount AS secondary_mapping_count,
    @SecondarySourceRowCount AS secondary_source_row_count,
    @SkipSameAsPrimaryCount AS skip_same_as_primary_count,
    @SkipSameAsSecondaryCount AS skip_same_as_secondary_count,
    @CommitChanges AS commit_changes;

BEGIN TRANSACTION;

UPDATE it
SET it.col03varchar = psr.incoming_value
FROM dbo.gdi_instrument_types it
JOIN #primary_source_rows psr
  ON psr.source_row_id = it.id
WHERE it.imported_by_user_id = @ImportedByUserId
  AND it.state_fips = @StateFips
  AND it.county_fips = @CountyFips
  AND CAST(it.import_batch_id AS VARCHAR(36)) = @CurrentBatchId;

UPDATE c
SET c.original_instrument_type = psr.original_value,
    c.new_instrument_type_name = psr.incoming_value,
    c.new_instrument_type_id = psr.keli_id,
    c.new_record_type = psr.record_type,
    c.new_is_active = psr.is_active,
    c.updated_at = @Now,
    c.updated_by_user_id = @ImportedByUserId
FROM dbo.corrections_instrument_types c
JOIN #primary_source_rows psr
  ON psr.source_row_id = c.source_row_id
 AND psr.import_batch_id = ISNULL(c.import_batch_id, '')
WHERE c.imported_by_user_id = @ImportedByUserId
  AND c.state_fips = @StateFips
  AND c.county_fips = @CountyFips;

INSERT INTO dbo.corrections_instrument_types (
    source_row_id,
    original_instrument_type,
    new_instrument_type_name,
    new_instrument_type_id,
    new_record_type,
    new_is_active,
    import_batch_id,
    imported_by_user_id,
    state_fips,
    county_fips,
    updated_by_user_id
)
SELECT
    psr.source_row_id,
    psr.original_value,
    psr.incoming_value,
    psr.keli_id,
    psr.record_type,
    psr.is_active,
    psr.import_batch_id,
    @ImportedByUserId,
    @StateFips,
    @CountyFips,
    @ImportedByUserId
FROM #primary_source_rows psr
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.corrections_instrument_types c
    WHERE c.imported_by_user_id = @ImportedByUserId
      AND c.state_fips = @StateFips
      AND c.county_fips = @CountyFips
      AND ISNULL(c.import_batch_id, '') = psr.import_batch_id
      AND c.source_row_id = psr.source_row_id
);

UPDATE dq
SET dq.is_fixed = 1,
    dq.fixed_note = 'manual_insttypemerge_primary_import',
    dq.updated_at = @Now,
    dq.updated_by_user_id = @ImportedByUserId
FROM dbo.corrections_instrument_types_dq dq
JOIN #primary_source_rows psr
  ON psr.source_row_id = dq.source_row_id
 AND psr.import_batch_id = ISNULL(dq.import_batch_id, '')
WHERE dq.imported_by_user_id = @ImportedByUserId
  AND dq.state_fips = @StateFips
  AND dq.county_fips = @CountyFips
  AND ISNULL(dq.is_fixed, 0) = 0;

UPDATE li
SET li.original_value = pa.original_value,
    li.new_value = pa.incoming_value,
    li.is_deleted = 0,
    li.updated_at = @Now,
    li.updated_by_user_id = @ImportedByUserId
FROM dbo.legacy_instrument_types li
JOIN #primary_apply pa
  ON LOWER(LTRIM(RTRIM(ISNULL(li.original_value, '')))) = LOWER(pa.original_value)
WHERE li.imported_by_user_id = @ImportedByUserId
  AND li.state_fips = @StateFips
  AND li.county_fips = @CountyFips;

INSERT INTO dbo.legacy_instrument_types (
    original_value,
    new_value,
    is_deleted,
    imported_by_user_id,
    state_fips,
    county_fips,
    updated_by_user_id
)
SELECT
    pa.original_value,
    pa.incoming_value,
    0,
    @ImportedByUserId,
    @StateFips,
    @CountyFips,
    @ImportedByUserId
FROM #primary_apply pa
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.legacy_instrument_types li
    WHERE li.imported_by_user_id = @ImportedByUserId
      AND li.state_fips = @StateFips
      AND li.county_fips = @CountyFips
      AND LOWER(LTRIM(RTRIM(ISNULL(li.original_value, '')))) = LOWER(pa.original_value)
);

INSERT INTO dbo.corrections_instrument_types_audit (
    severity,
    event_type,
    message,
    imported_by_user_id,
    state_fips,
    county_fips,
    original_instrument_type,
    details
)
SELECT
    'info',
    'assignment_updated',
    'Instrument type correction updated from InstTypeMerge import.',
    @ImportedByUserId,
    @StateFips,
    @CountyFips,
    pa.original_value,
    CONCAT(
        '{',
        '"importSource":"washington2156.dbo.InstTypeMerge",',
        '"passStage":"primary",',
        '"originalInstrumentType":"', STRING_ESCAPE(pa.original_value, 'json'), '",',
        '"oldNewValue":"",',
        '"newNewValue":"', STRING_ESCAPE(pa.incoming_value, 'json'), '",',
        '"newTypeId":"', STRING_ESCAPE(pa.keli_id, 'json'), '",',
        '"newRecordType":"', STRING_ESCAPE(ISNULL(pa.record_type, ''), 'json'), '",',
        '"newIsActive":', CASE WHEN pa.is_active IS NULL THEN 'null' WHEN pa.is_active = 1 THEN '1' ELSE '0' END, ',',
        '"sourceRowsUpdated":', CAST(pa.source_row_count AS VARCHAR(20)), ',',
        '"dqRowsFixed":', CAST(ISNULL(pdq.dq_row_count, 0) AS VARCHAR(20)), ',',
        '"appliedToAllMatchingOriginal":true',
        '}'
    )
FROM #primary_apply pa
LEFT JOIN #primary_dq_rows pdq
  ON pdq.original_value = pa.original_value;

UPDATE it
SET it.col03varchar = ssr.incoming_value
FROM dbo.gdi_instrument_types it
JOIN #secondary_source_rows ssr
  ON ssr.source_row_id = it.id
WHERE it.imported_by_user_id = @ImportedByUserId
  AND it.state_fips = @StateFips
  AND it.county_fips = @CountyFips
  AND CAST(it.import_batch_id AS VARCHAR(36)) = @CurrentBatchId;

UPDATE sp
SET sp.original_instrument_type = ssr.original_value,
    sp.initial_instrument_type_value = ssr.original_value,
    sp.primary_pass_instrument_type_value = ssr.primary_pass_value,
    sp.new_instrument_type_name = ssr.incoming_value,
    sp.new_instrument_type_id = ssr.keli_id,
    sp.new_record_type = ssr.record_type,
    sp.new_is_active = ssr.is_active,
    sp.updated_at = @Now,
    sp.updated_by_user_id = @ImportedByUserId
FROM dbo.corrections_instrument_types_second_pass sp
JOIN #secondary_source_rows ssr
  ON ssr.source_row_id = sp.source_row_id
 AND ssr.import_batch_id = ISNULL(sp.import_batch_id, '')
WHERE sp.imported_by_user_id = @ImportedByUserId
  AND sp.state_fips = @StateFips
  AND sp.county_fips = @CountyFips;

INSERT INTO dbo.corrections_instrument_types_second_pass (
    source_row_id,
    original_instrument_type,
    new_instrument_type_name,
    new_instrument_type_id,
    new_record_type,
    new_is_active,
    initial_instrument_type_value,
    primary_pass_instrument_type_value,
    import_batch_id,
    imported_by_user_id,
    state_fips,
    county_fips,
    updated_by_user_id
)
SELECT
    ssr.source_row_id,
    ssr.original_value,
    ssr.incoming_value,
    ssr.keli_id,
    ssr.record_type,
    ssr.is_active,
    ssr.original_value,
    ssr.primary_pass_value,
    ssr.import_batch_id,
    @ImportedByUserId,
    @StateFips,
    @CountyFips,
    @ImportedByUserId
FROM #secondary_source_rows ssr
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.corrections_instrument_types_second_pass sp
    WHERE sp.imported_by_user_id = @ImportedByUserId
      AND sp.state_fips = @StateFips
      AND sp.county_fips = @CountyFips
      AND ISNULL(sp.import_batch_id, '') = ssr.import_batch_id
      AND sp.source_row_id = ssr.source_row_id
);

UPDATE li
SET li.original_value = sa.original_value,
    li.new_value = sa.incoming_value,
    li.is_deleted = 0,
    li.updated_at = @Now,
    li.updated_by_user_id = @ImportedByUserId
FROM dbo.legacy_instrument_types_second_pass li
JOIN #secondary_apply sa
  ON LOWER(LTRIM(RTRIM(ISNULL(li.original_value, '')))) = LOWER(sa.original_value)
WHERE li.imported_by_user_id = @ImportedByUserId
  AND li.state_fips = @StateFips
  AND li.county_fips = @CountyFips;

INSERT INTO dbo.legacy_instrument_types_second_pass (
    original_value,
    new_value,
    is_deleted,
    imported_by_user_id,
    state_fips,
    county_fips,
    updated_by_user_id
)
SELECT
    sa.original_value,
    sa.incoming_value,
    0,
    @ImportedByUserId,
    @StateFips,
    @CountyFips,
    @ImportedByUserId
FROM #secondary_apply sa
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.legacy_instrument_types_second_pass li
    WHERE li.imported_by_user_id = @ImportedByUserId
      AND li.state_fips = @StateFips
      AND li.county_fips = @CountyFips
      AND LOWER(LTRIM(RTRIM(ISNULL(li.original_value, '')))) = LOWER(sa.original_value)
);

INSERT INTO dbo.corrections_instrument_types_second_pass_audit (
    severity,
    event_type,
    message,
    imported_by_user_id,
    state_fips,
    county_fips,
    original_instrument_type,
    details
)
SELECT
    'info',
    'assignment_updated',
    'Instrument type second-pass correction updated from InstTypeMerge import.',
    @ImportedByUserId,
    @StateFips,
    @CountyFips,
    sa.original_value,
    CONCAT(
        '{',
        '"importSource":"washington2156.dbo.InstTypeMerge",',
        '"passStage":"secondary",',
        '"originalInstrumentType":"', STRING_ESCAPE(sa.original_value, 'json'), '",',
        '"primaryPassValue":"', STRING_ESCAPE(sa.primary_pass_value, 'json'), '",',
        '"secondaryPassValue":"', STRING_ESCAPE(sa.incoming_value, 'json'), '",',
        '"newTypeId":"', STRING_ESCAPE(sa.keli_id, 'json'), '",',
        '"newRecordType":"', STRING_ESCAPE(ISNULL(sa.record_type, ''), 'json'), '",',
        '"newIsActive":', CASE WHEN sa.is_active IS NULL THEN 'null' WHEN sa.is_active = 1 THEN '1' ELSE '0' END, ',',
        '"sourceRowsUpdated":', CAST(sa.source_row_count AS VARCHAR(20)), ',',
        '"appliedToAllMatchingOriginal":true',
        '}'
    )
FROM #secondary_apply sa;

IF @CommitChanges = 1
BEGIN
    COMMIT TRANSACTION;
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
END;

SELECT
    @RunLabel AS run_label,
    @ImportedByUserId AS imported_by_user_id,
    @StateFips AS state_fips,
    @CountyFips AS county_fips,
    @CurrentBatchId AS import_batch_id,
    @PrimaryMappingCount AS primary_mapping_count,
    @PrimarySourceRowCount AS primary_source_row_count,
    @SecondaryMappingCount AS secondary_mapping_count,
    @SecondarySourceRowCount AS secondary_source_row_count,
    @SkipSameAsPrimaryCount AS skip_same_as_primary_count,
    @SkipSameAsSecondaryCount AS skip_same_as_secondary_count,
    CASE WHEN @CommitChanges = 1 THEN 'committed' ELSE 'preview_only_rolled_back' END AS execution_mode;
