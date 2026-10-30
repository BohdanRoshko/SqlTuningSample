/*  Proof that nothing reads IX_Posts_LastActivityDate. Read-only. Run before the drop.
    1. Every plan Query Store holds for this database. A plan that reads the index has it under
       an IndexScan operator (seek or scan). A write plan lists it under the Update operator,
       because the write has to maintain it. Only the first kind would break.
       This shreds plan XML in SQL. On a busy production server, export the plans and
       search them offline instead.
    2. The usage counters since the last restart (also in audit/results/05-index-usage.csv).  */
USE StackOverflow2010;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;   -- XML methods need it; sqlcmd defaults it to OFF

WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'),
plans AS (
    SELECT p.plan_id, q.object_id, TRY_CAST(p.query_plan AS xml) AS x
    FROM sys.query_store_plan AS p
    JOIN sys.query_store_query AS q ON q.query_id = p.query_id
)
SELECT COUNT(*) AS plans_in_query_store,
       SUM(CASE WHEN x.exist('//IndexScan/Object[@Index="[IX_Posts_LastActivityDate]"]') = 1 THEN 1 ELSE 0 END) AS plans_that_read_it,
       SUM(CASE WHEN x.exist('//Update/Object[@Index="[IX_Posts_LastActivityDate]"]') = 1 THEN 1 ELSE 0 END) AS plans_that_maintain_it,
       STRING_AGG(CASE WHEN x.exist('//Update/Object[@Index="[IX_Posts_LastActivityDate]"]') = 1
                       THEN OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) END, N', ') AS maintained_by
FROM plans;

SELECT i.name, ISNULL(us.user_seeks, 0) AS seeks, ISNULL(us.user_scans, 0) AS scans,
       ISNULL(us.user_lookups, 0) AS lookups, ISNULL(us.user_updates, 0) AS writes
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us
       ON us.database_id = DB_ID() AND us.object_id = i.object_id AND us.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dbo.Posts') AND i.name = N'IX_Posts_LastActivityDate';
