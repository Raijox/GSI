/* ============================================================================
   File: 06_final_hygiene_and_end.sql
   Procedure: dbo.sp_EdataTableSetup
   Role in assembly:
   - Runs the final scoped hygiene pass across GenericDataImport and gdi_* tables
     and closes the sp_EdataTableSetup procedure definition.
   Why this file exists:
   - Ending with a dedicated cleanup fragment makes the procedure easier to audit
     and gives one clear home for last-pass null-to-empty-string rules.
   Maintenance notes:
   - This fragment must remain last because it depends on all setup seeding and
     consolidation work having already completed.
   ============================================================================ */
	    -- -------------------------------------------------------------------------
	    -- Section 8: Final data hygiene pass
	    -- Convert all nullable text columns to empty string by scope.
	    -- -------------------------------------------------------------------------
	    DECLARE @table_name SYSNAME;
	    DECLARE @set_clause NVARCHAR(MAX);
	    DECLARE @null_predicate NVARCHAR(MAX);
        DECLARE @batch_scope_predicate NVARCHAR(200);

    DECLARE tcur CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name
        FROM sys.tables t
        WHERE (t.name = 'GenericDataImport' OR t.name LIKE 'gdi[_]%')
          AND EXISTS (
              SELECT 1
              FROM sys.columns s
              WHERE s.object_id = t.object_id
                AND s.name IN ('imported_by_user_id', 'state_fips', 'county_fips')
              GROUP BY s.object_id
              HAVING COUNT(DISTINCT s.name) = 3
          )
          AND EXISTS (
              SELECT 1
              FROM sys.columns c
              JOIN sys.types ty ON c.user_type_id = ty.user_type_id
              WHERE c.object_id = t.object_id
                AND c.is_computed = 0
                AND ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
          );

    OPEN tcur;
    FETCH NEXT FROM tcur INTO @table_name;
	    WHILE @@FETCH_STATUS = 0
	    BEGIN
                SET @batch_scope_predicate = CASE
                    WHEN @scope_import_batch_id IS NOT NULL
                         AND COL_LENGTH(N'dbo.' + @table_name, 'import_batch_id') IS NOT NULL
                        THEN N' AND t.import_batch_id = @batch_id'
                    ELSE N''
                END;
		        SELECT
		            @set_clause = STUFF((
	                SELECT
	                    N', ' + QUOTENAME(c.name) + N' = ISNULL(' + QUOTENAME(c.name) + N', '''')'
	                FROM sys.columns c
	                JOIN sys.types ty ON c.user_type_id = ty.user_type_id
	                WHERE c.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@table_name))
	                  AND c.is_computed = 0
	                  AND c.is_nullable = 1
	                  AND ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
	                FOR XML PATH(''), TYPE
	            ).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
	            @null_predicate = STUFF((
	                SELECT
	                    N' OR t.' + QUOTENAME(c.name) + N' IS NULL'
	                FROM sys.columns c
	                JOIN sys.types ty ON c.user_type_id = ty.user_type_id
	                WHERE c.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@table_name))
	                  AND c.is_computed = 0
	                  AND c.is_nullable = 1
	                  AND ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
	                FOR XML PATH(''), TYPE
	            ).value('.', 'NVARCHAR(MAX)'), 1, 4, N'');

		        IF ISNULL(@set_clause, N'') <> N'' AND ISNULL(@null_predicate, N'') <> N''
		        BEGIN
		            SET @sql = N'UPDATE t SET ' + @set_clause
		                + N' FROM dbo.' + QUOTENAME(@table_name) + N' t'
		                + N' WHERE t.imported_by_user_id = @uid AND t.state_fips = @sf AND t.county_fips = @cf'
                        + @batch_scope_predicate
		                + N' AND (' + @null_predicate + N')';
		            EXEC sys.sp_executesql
		                @sql,
		                N'@uid INT, @sf CHAR(2), @cf CHAR(5), @batch_id UNIQUEIDENTIFIER',
		                @uid = @ImportedByUserId,
		                @sf = @StateFips,
	                @cf = @CountyFips,
                        @batch_id = @scope_import_batch_id;
	        END;

        FETCH NEXT FROM tcur INTO @table_name;
    END
    CLOSE tcur;
    DEALLOCATE tcur;
END;
