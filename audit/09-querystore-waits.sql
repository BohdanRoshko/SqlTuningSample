/*  What each query waited on, from Query Store. Read-only. Run in the user database.
    Server wait stats say what the box waits on. This says which query does the waiting:
    a write that spends its time in the Lock category is blocked by somebody else.  */
USE StackOverflow2010;
SET NOCOUNT ON;

WITH waits AS (
    SELECT q.query_id,
           ISNULL(OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id), N'(ad hoc)') AS object_name,
           ws.wait_category_desc,
           SUM(ws.total_query_wait_time_ms) AS wait_ms
    FROM sys.query_store_query AS q
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_wait_stats AS ws ON ws.plan_id = p.plan_id
    GROUP BY q.query_id, q.object_id, ws.wait_category_desc
), runs AS (
    SELECT p.query_id, SUM(rs.count_executions) AS executions,
           SUM(rs.avg_duration * rs.count_executions) / 1000.0 AS total_duration_ms
    FROM sys.query_store_plan AS p
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    GROUP BY p.query_id
)
SELECT TOP (20)
       w.object_name, w.query_id, w.wait_category_desc,
       CAST(w.wait_ms / 1000.0 AS decimal(12, 1))                         AS wait_s,
       r.executions,
       CAST(w.wait_ms * 1.0 / NULLIF(r.executions, 0) AS decimal(12, 1))  AS wait_ms_per_run,
       CAST(100.0 * w.wait_ms / NULLIF(r.total_duration_ms, 0) AS decimal(5, 1)) AS pct_of_query_duration
FROM waits AS w
JOIN runs AS r ON r.query_id = w.query_id
WHERE w.wait_ms > 0
ORDER BY w.wait_ms DESC;
