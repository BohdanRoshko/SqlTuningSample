/*  Fix 06: drop IX_Posts_LastActivityDate.
    No query read it during the whole workload, and no plan in Query Store references it.
    It carries ViewCount and Score, so every page view and every vote updated it.
    Keep rollback.sql with the change: if the vendor has a rare job that needs it, it goes back in minutes.  */
USE StackOverflow2010;
GO
DROP INDEX IF EXISTS IX_Posts_LastActivityDate ON dbo.Posts;
GO
