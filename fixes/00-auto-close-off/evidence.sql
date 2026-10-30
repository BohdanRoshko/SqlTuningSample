/*  How often the database started since the error log began. Read-only.
    More than one start per SQL Server restart means something is closing it: AUTO_CLOSE, or someone.  */
DECLARE @log TABLE (LogDate datetime, ProcessInfo nvarchar(50), Text nvarchar(max));
INSERT @log EXEC sys.xp_readerrorlog 0, 1, N'Starting up database', N'StackOverflow2010';
SELECT COUNT(*) AS database_starts, MIN(LogDate) AS first_start, MAX(LogDate) AS last_start FROM @log;
SELECT name, is_auto_close_on FROM sys.databases WHERE name = N'StackOverflow2010';
