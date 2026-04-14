/*
    GenericDataImport scoping metadata for shared-table workflow.
    Supports county/user scoped replace-and-import behavior.
*/

IF OBJECT_ID('dbo.GenericDataImport', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericDataImport (
        ID INT NOT NULL IDENTITY PRIMARY KEY,
        FN VARCHAR(1000),
        OriginalValue VARCHAR(MAX),
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
        col01other VARCHAR(1000),
        col02other VARCHAR(1000),
        col03other VARCHAR(1000),
        col04other VARCHAR(1000),
        col05other VARCHAR(1000),
        col06other VARCHAR(1000),
        col07other VARCHAR(1000),
        col08other VARCHAR(1000),
        col09other VARCHAR(1000),
        col10other VARCHAR(1000),
        col11other VARCHAR(1000),
        col12other VARCHAR(1000),
        col13other VARCHAR(1000),
        col14other VARCHAR(1000),
        col15other VARCHAR(1000),
        col16other VARCHAR(1000),
        col17other VARCHAR(1000),
        col18other VARCHAR(1000),
        col19other VARCHAR(1000),
        col20other VARCHAR(1000),
        uf1 VARCHAR(1000),
        uf2 VARCHAR(1000),
        uf3 VARCHAR(1000),
        leftovers VARCHAR(1000),
        imported_by_user_id INT NULL,
        import_batch_id UNIQUEIDENTIFIER NULL,
        state_fips CHAR(2) NULL,
        county_fips CHAR(5) NULL,
        imported_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_GenericDataImport_imported_at DEFAULT SYSDATETIMEOFFSET()
    );
END
GO

IF COL_LENGTH('dbo.GenericDataImport', 'imported_by_user_id') IS NULL
BEGIN
    ALTER TABLE dbo.GenericDataImport ADD imported_by_user_id INT NULL;
END
GO

IF COL_LENGTH('dbo.GenericDataImport', 'import_batch_id') IS NULL
BEGIN
    ALTER TABLE dbo.GenericDataImport ADD import_batch_id UNIQUEIDENTIFIER NULL;
END
GO

IF COL_LENGTH('dbo.GenericDataImport', 'state_fips') IS NULL
BEGIN
    ALTER TABLE dbo.GenericDataImport ADD state_fips CHAR(2) NULL;
END
GO

IF COL_LENGTH('dbo.GenericDataImport', 'county_fips') IS NULL
BEGIN
    ALTER TABLE dbo.GenericDataImport ADD county_fips CHAR(5) NULL;
END
GO

IF COL_LENGTH('dbo.GenericDataImport', 'imported_at') IS NULL
BEGIN
    ALTER TABLE dbo.GenericDataImport ADD imported_at DATETIMEOFFSET NOT NULL
        CONSTRAINT DF_GenericDataImport_imported_at_legacy DEFAULT SYSDATETIMEOFFSET();
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_GenericDataImport_scope'
      AND object_id = OBJECT_ID('dbo.GenericDataImport')
)
BEGIN
    CREATE INDEX IX_GenericDataImport_scope
        ON dbo.GenericDataImport (state_fips, county_fips, imported_by_user_id);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_GenericDataImport_import_batch'
      AND object_id = OBJECT_ID('dbo.GenericDataImport')
)
BEGIN
    CREATE INDEX IX_GenericDataImport_import_batch
        ON dbo.GenericDataImport (import_batch_id);
END
GO
