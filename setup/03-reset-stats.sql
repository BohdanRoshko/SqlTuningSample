/*  Lab only: start the workload from clean counters, so the audit sees only the workload.
    On a client server you never do this. You read the counters as they are, since the last restart.  */
USE master;
GO
ALTER DATABASE StackOverflow2010 SET QUERY_STORE CLEAR;
GO
-- Taking the database offline and back resets sys.dm_db_index_usage_stats for it.
ALTER DATABASE StackOverflow2010 SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE StackOverflow2010 SET ONLINE;
GO
DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);
GO
DBCC FREEPROCCACHE;
GO
