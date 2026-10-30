/*  Which queries use tempdb, from Query Store. Read-only. Run in the user database.
    Sorts and hash joins that do not get enough memory spill to tempdb.
    Query Store counts tempdb space in 8 KB pages.
    Added after the baseline run, so only audit/results-after has its output.  */
USE StackOverflow2010;
SET NOCOUNT ON;

SELECT ISNULL(OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id), N'(ad hoc)') AS object_name,
       q.query_id,
       SUM(rs.count_executions)                                                          AS executions,
       CAST(SUM(rs.avg_tempdb_space_used * rs.count_executions) * 8 / 1024.0 AS decimal(12, 0)) AS tempdb_mb_total,
       CAST(MAX(rs.max_tempdb_space_used) * 8 / 1024.0 AS decimal(12, 1))                AS tempdb_mb_max_one_call
FROM sys.query_store_query AS q
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
GROUP BY q.object_id, q.query_id
HAVING SUM(rs.avg_tempdb_space_used * rs.count_executions) > 0
ORDER BY tempdb_mb_total DESC;
