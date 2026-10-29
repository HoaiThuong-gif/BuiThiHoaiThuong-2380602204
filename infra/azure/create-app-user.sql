-- Run in the target database as the migration owner AFTER transferring data.
-- @AppPassword is supplied as a SqlParameter by the deployment tool, never pasted into Git.
IF DATABASE_NAME() <> N'NhomBar2380602204' THROW 51000, 'Unexpected database', 1;
IF @AppPassword IS NULL OR LEN(@AppPassword)<20 OR LEN(@AppPassword)>128 THROW 51001, 'Invalid application password', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'nhombar_app')
BEGIN
    DECLARE @create nvarchar(max)=N'CREATE USER [nhombar_app] WITH PASSWORD='+QUOTENAME(@AppPassword,'''')+N';';
    EXEC sys.sp_executesql @create;
END;
ALTER ROLE db_datareader ADD MEMBER [nhombar_app];
ALTER ROLE db_datawriter ADD MEMBER [nhombar_app];
-- Application account is not db_owner and cannot apply migrations or drop tables.
