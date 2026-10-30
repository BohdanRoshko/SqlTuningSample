/*  Attach the StackOverflow2010 database.
    Source: https://downloads.brentozar.com/StackOverflow2010.7z (cc-by-sa 4.0, Stack Exchange data dump).
    Run with: sqlcmd -S .\SQLEXPRESS -E -C -i setup\01-attach.sql -v DataDir='"E:\SqlTuningSample\_data\db"'

    The SQL Server service account needs full control on that folder.
    With Windows authentication, SQL Server opens the files as the caller, and a non-elevated
    caller gets "Access is denied". A short-lived SQL login makes SQL Server open the files
    as its own service account instead. The login is dropped at the end.  */
USE master;
GO
IF DB_ID(N'StackOverflow2010') IS NULL
BEGIN
    DECLARE @pwd nvarchar(64) = CONVERT(nvarchar(64), NEWID()) + N'aA1!';
    EXEC (N'CREATE LOGIN attach_helper WITH PASSWORD = ''' + @pwd + N''', CHECK_POLICY = OFF;');
    ALTER SERVER ROLE sysadmin ADD MEMBER attach_helper;

    EXECUTE AS LOGIN = N'attach_helper';
    CREATE DATABASE StackOverflow2010
    ON (FILENAME = N'$(DataDir)\StackOverflow2010.mdf'),
       (FILENAME = N'$(DataDir)\StackOverflow2010_log.ldf')
    FOR ATTACH;
    REVERT;

    ALTER AUTHORIZATION ON DATABASE::StackOverflow2010 TO [sa];
    DROP LOGIN attach_helper;
END
GO
SELECT name, compatibility_level, recovery_model_desc, is_query_store_on
FROM sys.databases WHERE name = N'StackOverflow2010';
SELECT name, type_desc, size * 8 / 1024 AS size_mb FROM StackOverflow2010.sys.database_files;
GO
