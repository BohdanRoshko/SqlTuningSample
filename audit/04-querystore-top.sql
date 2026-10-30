/*  Top queries from Query Store: by total CPU, by total logical reads, by run count.
    One row per statement, not per procedure: a procedure is a bag of statements,
    and the fix goes on the heavy statement.
    High reads with few rows out means a scan. max_dop above 1 means a parallel plan.
    Read-only. Run in the user database.
    Query Store keeps time in microseconds and reads in 8 KB pages.  */
USE StackOverflow2010;
SET NOCOUNT ON;

WITH per_query AS (
    SELECT q.query_id,
           ISNULL(OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id), N'(ad hoc)') AS object_name,
           SUM(rs.count_executions)                                   AS executions,
           SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0        AS total_cpu_ms,
           SUM(rs.avg_logical_io_reads * rs.count_executions)         AS total_logical_reads,
           SUM(rs.avg_duration * rs.count_executions) / 1000.0        AS total_duration_ms,
           MAX(rs.max_logical_io_reads)                               AS max_logical_reads,
           MIN(rs.min_logical_io_reads)                               AS min_logical_reads,
           SUM(rs.avg_rowcount * rs.count_executions)                 AS total_rows,
           MAX(rs.max_dop)                                            AS max_dop,
           COUNT(DISTINCT p.plan_id)                                  AS plans
    FROM sys.query_store_query AS q
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    GROUP BY q.query_id, q.object_id
), ranked AS (
    SELECT pq.*,
           CAST(100.0 * total_cpu_ms / SUM(total_cpu_ms) OVER () AS decimal(5, 1))                 AS pct_of_cpu,
           CAST(100.0 * total_logical_reads / SUM(total_logical_reads) OVER () AS decimal(5, 1))   AS pct_of_reads,
           ROW_NUMBER() OVER (ORDER BY total_cpu_ms DESC)        AS rank_cpu,
           ROW_NUMBER() OVER (ORDER BY total_logical_reads DESC) AS rank_reads,
           ROW_NUMBER() OVER (ORDER BY executions DESC)          AS rank_runs
    FROM per_query AS pq
)
SELECT r.rank_cpu, r.rank_reads, r.rank_runs,
       r.query_id, r.object_name, r.executions, r.plans,
       CAST(r.total_cpu_ms AS decimal(14, 0))                       AS total_cpu_ms,
       r.pct_of_cpu,
       CAST(r.total_logical_reads AS bigint)                        AS total_logical_reads,
       r.pct_of_reads,
       CAST(r.total_cpu_ms / NULLIF(r.executions, 0) AS decimal(12, 2))          AS avg_cpu_ms,
       CAST(r.total_duration_ms / NULLIF(r.executions, 0) AS decimal(12, 2))     AS avg_duration_ms,
       CAST(r.total_logical_reads / NULLIF(r.executions, 0) AS bigint)           AS avg_logical_reads,
       CAST(r.min_logical_reads AS bigint)                          AS min_logical_reads,
       CAST(r.max_logical_reads AS bigint)                          AS max_logical_reads,
       CAST(r.total_rows / NULLIF(r.executions, 0) AS decimal(12, 1))            AS avg_rows,
       r.max_dop,
       LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), N' '), CHAR(10), N' '), 200) AS query_text
FROM ranked AS r
JOIN sys.query_store_query AS q ON q.query_id = r.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE r.rank_cpu <= 15 OR r.rank_reads <= 15 OR r.rank_runs <= 10
ORDER BY r.total_cpu_ms DESC;
