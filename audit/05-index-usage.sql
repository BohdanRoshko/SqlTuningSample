/*  Every index in the database: how often queries read it, how often writes maintain it, and its size.
    Read-only. Run in the user database. Counters reset at restart and when the database goes offline.
    An index with zero reads and many writes is pure cost.  */
USE StackOverflow2010;
SET NOCOUNT ON;

SELECT OBJECT_SCHEMA_NAME(i.object_id) + N'.' + OBJECT_NAME(i.object_id) AS table_name,
       i.name                                       AS index_name,
       i.type_desc,
       i.is_primary_key,
       ISNULL(us.user_seeks, 0)                     AS seeks,
       ISNULL(us.user_scans, 0)                     AS scans,
       ISNULL(us.user_lookups, 0)                   AS lookups,
       ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0) AS total_reads,
       ISNULL(us.user_updates, 0)                   AS writes,
       us.last_user_seek, us.last_user_scan, us.last_user_update,
       sz.size_mb,
       sz.row_count,
       STUFF((SELECT N', ' + c.name
              FROM sys.index_columns AS ic JOIN sys.columns AS c
                ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
              ORDER BY ic.key_ordinal FOR XML PATH('')), 1, 2, N'') AS key_columns,
       STUFF((SELECT N', ' + c.name
              FROM sys.index_columns AS ic JOIN sys.columns AS c
                ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
              ORDER BY c.name FOR XML PATH('')), 1, 2, N'') AS included_columns
FROM sys.indexes AS i
JOIN sys.objects AS o ON o.object_id = i.object_id AND o.is_ms_shipped = 0 AND o.type = 'U'
LEFT JOIN sys.dm_db_index_usage_stats AS us
       ON us.database_id = DB_ID() AND us.object_id = i.object_id AND us.index_id = i.index_id
CROSS APPLY (SELECT CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS decimal(12, 1)) AS size_mb,
                    SUM(ps.row_count) AS row_count
             FROM sys.dm_db_partition_stats AS ps
             WHERE ps.object_id = i.object_id AND ps.index_id = i.index_id) AS sz
WHERE i.index_id > 0
ORDER BY CASE WHEN i.index_id > 1 AND ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0) = 0 THEN 0 ELSE 1 END,
         ISNULL(us.user_updates, 0) DESC;
