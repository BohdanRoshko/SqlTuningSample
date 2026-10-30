/*  Indexes the optimizer asked for while compiling plans, with the query that asked.
    Read-only. These are hints, not orders: the optimizer does not weigh write cost or overlap
    with existing indexes, so every suggestion gets checked by hand before it becomes a fix.  */
USE StackOverflow2010;
SET NOCOUNT ON;

SELECT CAST(gs.avg_total_user_cost * gs.avg_user_impact * (gs.user_seeks + gs.user_scans) AS decimal(14, 0)) AS score,
       d.statement                                  AS table_name,
       d.equality_columns,
       d.inequality_columns,
       d.included_columns,
       gs.user_seeks + gs.user_scans                AS times_wanted,
       CAST(gs.avg_user_impact AS decimal(5, 1))    AS est_impact_pct,
       CAST(gs.avg_total_user_cost AS decimal(12, 2)) AS avg_query_cost,
       gs.last_user_seek,
       (SELECT TOP (1) LEFT(REPLACE(REPLACE(t.text, CHAR(13), N' '), CHAR(10), N' '), 200)
        FROM sys.dm_db_missing_index_group_stats_query AS q
        CROSS APPLY sys.dm_exec_sql_text(q.last_sql_handle) AS t
        WHERE q.group_handle = gs.group_handle
        ORDER BY q.user_seeks + q.user_scans DESC)   AS sample_query
FROM sys.dm_db_missing_index_group_stats AS gs
JOIN sys.dm_db_missing_index_groups AS g ON g.index_group_handle = gs.group_handle
JOIN sys.dm_db_missing_index_details AS d ON d.index_handle = g.index_handle
WHERE d.database_id = DB_ID()
ORDER BY score DESC;
