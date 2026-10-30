/*  Fix 00: turn AUTO_CLOSE off.

    With AUTO_CLOSE on, SQL Server shuts the database down each time the last connection leaves,
    and starts it again on the next connection. Each start throws away the plan cache for the
    database, the data pages in memory, and the index usage and missing-index counters.
    The first workload run lost its index counters this way, the moment the run ended.

    Express creates databases with AUTO_CLOSE on by default, so databases that were ever
    created or attached on Express often still carry it.  */
ALTER DATABASE StackOverflow2010 SET AUTO_CLOSE OFF WITH NO_WAIT;
GO
SELECT name, is_auto_close_on FROM sys.databases WHERE name = N'StackOverflow2010';
GO
