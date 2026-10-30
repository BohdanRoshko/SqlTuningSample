/*  Server and database settings that change how every query runs.
    Read-only. Needs VIEW SERVER STATE.  */
SET NOCOUNT ON;

-- 1. The box
SELECT SERVERPROPERTY('ProductVersion')      AS product_version,
       SERVERPROPERTY('Edition')             AS edition,
       i.cpu_count,
       i.scheduler_count,
       i.physical_memory_kb / 1024           AS physical_memory_mb,
       i.committed_target_kb / 1024          AS sql_target_memory_mb,
       i.sqlserver_start_time,
       DATEDIFF(HOUR, i.sqlserver_start_time, SYSDATETIME()) AS hours_since_start
FROM sys.dm_os_sys_info AS i;

-- 2. Instance settings that matter most for performance
SELECT c.name, c.value_in_use, c.value AS configured_value,
       CASE c.name
            WHEN 'max server memory (MB)'          THEN 'Leave room for the OS. 2147483647 means no cap.'
            WHEN 'max degree of parallelism'       THEN '0 means one query can use every core.'
            WHEN 'cost threshold for parallelism'  THEN 'Default 5 sends small queries parallel.'
            WHEN 'optimize for ad hoc workloads'   THEN 'Keeps single-use ad hoc plans small.'
            ELSE N'' END AS note
FROM sys.configurations AS c
WHERE c.name IN ('max server memory (MB)', 'min server memory (MB)', 'max degree of parallelism',
                 'cost threshold for parallelism', 'optimize for ad hoc workloads',
                 'backup compression default', 'remote admin connections')
ORDER BY c.name;

-- 3. Database settings
SELECT d.name, d.compatibility_level, d.recovery_model_desc, d.page_verify_option_desc,
       d.is_auto_create_stats_on, d.is_auto_update_stats_on, d.is_auto_update_stats_async_on,
       d.is_read_committed_snapshot_on, d.snapshot_isolation_state_desc,
       d.is_query_store_on, d.is_auto_shrink_on, d.is_auto_close_on
FROM sys.databases AS d
WHERE d.database_id = DB_ID();   -- run this script in the database you audit

-- 4. Database scoped settings that override the instance
SELECT name, value, value_for_secondary
FROM StackOverflow2010.sys.database_scoped_configurations
WHERE name IN ('MAXDOP', 'LEGACY_CARDINALITY_ESTIMATION', 'PARAMETER_SNIFFING', 'QUERY_OPTIMIZER_HOTFIXES');

-- 5. Query Store state and size
SELECT actual_state_desc, desired_state_desc, query_capture_mode_desc,
       current_storage_size_mb, max_storage_size_mb, interval_length_minutes, readonly_reason
FROM StackOverflow2010.sys.database_query_store_options;

-- 6. How much of the database fits in memory right now, against its size
SELECT CAST(COUNT_BIG(*) * 8 / 1024.0 AS decimal(12, 0)) AS buffer_pool_mb_this_db,
       (SELECT CAST(SUM(size) * 8 / 1024.0 AS decimal(12, 0)) FROM sys.database_files WHERE type = 0) AS data_file_mb,
       (SELECT CAST(SUM(pages_kb) / 1024.0 AS decimal(12, 0)) FROM sys.dm_os_memory_clerks WHERE type = 'MEMORYCLERK_SQLBUFFERPOOL') AS buffer_pool_mb_total
FROM sys.dm_os_buffer_descriptors
WHERE database_id = DB_ID();

-- 7. tempdb files
SELECT name, type_desc, size * 8 / 1024 AS size_mb, growth, is_percent_growth
FROM tempdb.sys.database_files;
