IF OBJECT_ID('dbo.county_work_items', 'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.county_work_items', 'split_book_start') IS NULL
        ALTER TABLE dbo.county_work_items ADD split_book_start INT NULL;

    IF COL_LENGTH('dbo.county_work_items', 'split_book_end') IS NULL
        ALTER TABLE dbo.county_work_items ADD split_book_end INT NULL;
END
GO

