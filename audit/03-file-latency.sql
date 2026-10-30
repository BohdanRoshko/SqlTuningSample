/*  Read and write latency per database file, since the last restart.
    Read-only. Rough guide: data reads under 10 ms are fine, log writes under 2 ms are fine.  */
SET NOCOUNT ON;

SELECT DB_NAME(s.database_id)                                        AS database_name,
       f.name                                                        AS file_name,
       f.type_desc,
       f.physical_name,
       s.num_of_reads,
       CAST(s.num_of_bytes_read / 1048576.0 AS decimal(12, 1))        AS mb_read,
       CAST(s.io_stall_read_ms * 1.0 / NULLIF(s.num_of_reads, 0) AS decimal(10, 2))   AS avg_read_ms,
       s.num_of_writes,
       CAST(s.num_of_bytes_written / 1048576.0 AS decimal(12, 1))     AS mb_written,
       CAST(s.io_stall_write_ms * 1.0 / NULLIF(s.num_of_writes, 0) AS decimal(10, 2)) AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS s
JOIN sys.master_files AS f
  ON f.database_id = s.database_id AND f.file_id = s.file_id
WHERE s.num_of_reads + s.num_of_writes > 0
  AND s.database_id IN (DB_ID(), DB_ID(N'tempdb'))   -- the audited database and tempdb
ORDER BY s.io_stall_read_ms + s.io_stall_write_ms DESC;
