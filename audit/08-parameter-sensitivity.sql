/*  Queries whose cost swings a lot between runs of the same plan.
    A plan that reads 100 pages on one call and 10 million on another was compiled for
    different parameter values than it is getting now: the parameter sniffing pattern.
    Read-only. Run in the user database.  */
USE StackOverflow2010;
SET NOCOUNT ON;

SELECT OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id) AS object_name,
       q.query_id, p.plan_id,
       SUM(rs.count_executions)                                AS executions,
       CAST(MIN(rs.min_logical_io_reads) AS bigint)            AS min_reads,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions) AS bigint) AS avg_reads,
       CAST(MAX(rs.max_logical_io_reads) AS bigint)            AS max_reads,
       CAST(MIN(rs.min_duration) / 1000.0 AS decimal(12, 1))   AS min_duration_ms,
       CAST(MAX(rs.max_duration) / 1000.0 AS decimal(12, 1))   AS max_duration_ms,
       CAST(MAX(rs.max_logical_io_reads) / NULLIF(MIN(rs.min_logical_io_reads), 0) AS decimal(14, 0)) AS max_to_min_ratio
FROM sys.query_store_query AS q
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE q.object_id > 0
GROUP BY q.object_id, q.query_id, p.plan_id
HAVING MAX(rs.max_logical_io_reads) > 100 * NULLIF(MIN(rs.min_logical_io_reads), 0)
ORDER BY max_to_min_ratio DESC;
