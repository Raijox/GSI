/* ============================================================================
   File: 01_proc_header_and_normalization.sql
   Procedure: dbo.sp_EdataTableSetup
   Role in assembly:
   - First fragment of the ordered setup procedure definition.
   - Owns procedure declaration, scope validation, base GenericDataImport
     normalization, and split-table normalization.
   Why this file exists:
   - Setup begins by making imported text consistent before downstream reference,
     legal, and default-row logic depends on those values.
   Maintenance notes:
   - Keep the procedure header and normalization contract together here so every
     later setup fragment can assume the scope and text cleanup are complete.
   ============================================================================ */
/* ============================================================================
   Procedure: dbo.sp_EdataTableSetup
   Purpose:
   - Normalize imported eData row values after import/split.
   - Ensure supporting indexes exist.
   - Seed default legal rows where needed.
   - Force nullable text fields to empty strings for consistent UI behavior.
   ============================================================================ */
CREATE OR ALTER PROCEDURE dbo.sp_EdataTableSetup
    @ImportedByUserId INT,
    @StateFips CHAR(2),
    @CountyFips CHAR(5)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- -------------------------------------------------------------------------
    -- Section 1: Input validation and scope normalization
    -- -------------------------------------------------------------------------
    IF @ImportedByUserId IS NULL OR @ImportedByUserId <= 0
        THROW 50001, 'ImportedByUserId is required.', 1;
    IF @StateFips IS NULL OR LEN(LTRIM(RTRIM(@StateFips))) <> 2
        THROW 50002, 'StateFips must be 2 characters.', 1;
    IF @CountyFips IS NULL OR LEN(LTRIM(RTRIM(@CountyFips))) <> 5
        THROW 50003, 'CountyFips must be 5 characters.', 1;

    SET @StateFips = RIGHT('00' + LTRIM(RTRIM(@StateFips)), 2);
    SET @CountyFips = RIGHT('00000' + LTRIM(RTRIM(@CountyFips)), 5);

    IF OBJECT_ID(N'dbo.GenericDataImport', N'U') IS NULL
        THROW 50004, 'GenericDataImport table does not exist.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.GenericDataImport g
        WHERE g.imported_by_user_id = @ImportedByUserId
          AND g.state_fips = @StateFips
          AND g.county_fips = @CountyFips
    )
        RETURN;

    DECLARE @scope_import_batch_id UNIQUEIDENTIFIER = NULL;
    SELECT TOP 1 @scope_import_batch_id = g.import_batch_id
    FROM dbo.GenericDataImport g
    WHERE g.imported_by_user_id = @ImportedByUserId
      AND g.state_fips = @StateFips
      AND g.county_fips = @CountyFips
      AND g.import_batch_id IS NOT NULL
    ORDER BY g.ID DESC;

    -- -------------------------------------------------------------------------
    -- Section 2: Normalize base imported values (GenericDataImport)
    -- -------------------------------------------------------------------------
	    UPDATE g
	    SET g.fn = REPLACE(REPLACE(REPLACE(ISNULL(g.fn, ''), 'Images', 'Image'), 'Legals', 'Legal'), 'Names', 'Name')
	    FROM dbo.GenericDataImport g
	    WHERE g.imported_by_user_id = @ImportedByUserId
	      AND g.state_fips = @StateFips
	      AND g.county_fips = @CountyFips
          AND (@scope_import_batch_id IS NULL OR g.import_batch_id = @scope_import_batch_id)
	      AND (
	            ISNULL(g.fn, '') LIKE '%Images%'
	         OR ISNULL(g.fn, '') LIKE '%Legals%'
	         OR ISNULL(g.fn, '') LIKE '%Names%'
	      );

    UPDATE g
    SET g.col03varchar = REPLACE(
            ISNULL(g.col03varchar, ''),
            SUBSTRING(ISNULL(g.col03varchar, ''), CHARINDEX('_', ISNULL(g.col03varchar, '')), CHARINDEX('.', ISNULL(g.col03varchar, '')) - CHARINDEX('_', ISNULL(g.col03varchar, ''))),
            ''
        )
    FROM dbo.GenericDataImport g
    WHERE g.imported_by_user_id = @ImportedByUserId
      AND g.state_fips = @StateFips
      AND g.county_fips = @CountyFips
      AND (@scope_import_batch_id IS NULL OR g.import_batch_id = @scope_import_batch_id)
      AND LOWER(ISNULL(g.fn, '')) LIKE '%image%'
      AND CHARINDEX('_', ISNULL(g.col03varchar, '')) > 0
      AND CHARINDEX('.', ISNULL(g.col03varchar, '')) > CHARINDEX('_', ISNULL(g.col03varchar, ''));

    -- -------------------------------------------------------------------------
    -- Section 3: Apply the same normalization to all split gdi_* tables
    -- -------------------------------------------------------------------------
    DECLARE @fix_tbl SYSNAME;
    DECLARE @fix_sql NVARCHAR(MAX);
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @fix_scope_filter NVARCHAR(200);

    DECLARE fix_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name
        FROM sys.tables t
        WHERE t.name LIKE 'gdi[_]%'
          AND EXISTS (
              SELECT 1
              FROM sys.columns c
              WHERE c.object_id = t.object_id
                AND c.name = 'fn'
          );

    OPEN fix_cur;
    FETCH NEXT FROM fix_cur INTO @fix_tbl;
	    WHILE @@FETCH_STATUS = 0
	    BEGIN
                SET @fix_scope_filter = CASE
                    WHEN @scope_import_batch_id IS NOT NULL
                         AND COL_LENGTH(N'dbo.' + @fix_tbl, 'import_batch_id') IS NOT NULL
                        THEN N' AND t.import_batch_id = @batch_id'
                    ELSE N''
                END;
		        SET @fix_sql = N'
		            UPDATE t
		            SET t.fn = REPLACE(REPLACE(REPLACE(ISNULL(t.fn, ''''), ''Images'', ''Image''), ''Legals'', ''Legal''), ''Names'', ''Name'')
		            FROM dbo.' + QUOTENAME(@fix_tbl) + N' t
		            WHERE t.imported_by_user_id = @uid
		              AND t.state_fips = @sf
		              AND t.county_fips = @cf' + @fix_scope_filter + N'
		              AND (
		                    ISNULL(t.fn, '''') LIKE ''%Images%''
		                 OR ISNULL(t.fn, '''') LIKE ''%Legals%''
		                 OR ISNULL(t.fn, '''') LIKE ''%Names%''
		              );';
        EXEC sys.sp_executesql
            @fix_sql,
            N'@uid INT, @sf CHAR(2), @cf CHAR(5), @batch_id UNIQUEIDENTIFIER',
            @uid = @ImportedByUserId,
            @sf = @StateFips,
            @cf = @CountyFips,
            @batch_id = @scope_import_batch_id;

        IF COL_LENGTH(N'dbo.' + @fix_tbl, 'col03varchar') IS NOT NULL
        BEGIN
	            SET @fix_sql = N'
	                UPDATE t
	                SET t.col03varchar = REPLACE(
	                        ISNULL(t.col03varchar, ''''),
	                        SUBSTRING(ISNULL(t.col03varchar, ''''), CHARINDEX(''_'', ISNULL(t.col03varchar, '''')), CHARINDEX(''.'', ISNULL(t.col03varchar, '''')) - CHARINDEX(''_'', ISNULL(t.col03varchar, ''''))),
	                        ''''
	                    )
	                FROM dbo.' + QUOTENAME(@fix_tbl) + N' t
	                WHERE t.imported_by_user_id = @uid
	                  AND t.state_fips = @sf
	                  AND t.county_fips = @cf' + @fix_scope_filter + N'
	                  AND LOWER(ISNULL(t.fn, '''')) LIKE ''%image%''
	                  AND CHARINDEX(''_'', ISNULL(t.col03varchar, '''')) > 0
	                  AND CHARINDEX(''.'', ISNULL(t.col03varchar, '''')) > CHARINDEX(''_'', ISNULL(t.col03varchar, ''''));';
	            EXEC sys.sp_executesql
	                @fix_sql,
	                N'@uid INT, @sf CHAR(2), @cf CHAR(5), @batch_id UNIQUEIDENTIFIER',
	                @uid = @ImportedByUserId,
	                @sf = @StateFips,
	                @cf = @CountyFips,
                    @batch_id = @scope_import_batch_id;
	        END;

        FETCH NEXT FROM fix_cur INTO @fix_tbl;
    END
    CLOSE fix_cur;
    DEALLOCATE fix_cur;
