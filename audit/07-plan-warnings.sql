/*  What the cached plans in Query Store say about themselves:
    implicit conversions, key lookups, spills, scans, and queries that have more than one plan.
    Read-only. Run in the user database. Looks at the latest plan of every query from a procedure.  */
USE StackOverflow2010;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;   -- XML methods need it; sqlcmd defaults it to OFF

WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'),
plans AS (
    SELECT q.query_id, p.plan_id,
           OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id) AS object_name,
           TRY_CAST(p.query_plan AS xml) AS plan_xml,
           ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY p.last_execution_time DESC) AS rn,
           COUNT(*) OVER (PARTITION BY q.query_id) AS plan_count
    FROM sys.query_store_query AS q
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    WHERE q.object_id > 0
)
SELECT pl.object_name, pl.query_id, pl.plan_id, pl.plan_count,
       pl.plan_xml.exist('//PlanAffectingConvert')                                   AS has_implicit_convert,
       pl.plan_xml.value('(//PlanAffectingConvert/@Expression)[1]', 'nvarchar(400)')   AS convert_expression,
       pl.plan_xml.exist('//IndexScan[@Lookup="true" or @Lookup="1"]')                                 AS has_key_lookup,
       pl.plan_xml.exist('//SpillToTempDb')                                          AS has_spill,
       pl.plan_xml.exist('//MissingIndexes')                                         AS asks_for_index,
       pl.plan_xml.exist('//RelOp[@PhysicalOp="Clustered Index Scan" or @PhysicalOp="Index Scan"]') AS has_scan,
       pl.plan_xml.value('(//StmtSimple/@StatementSubTreeCost)[1]', 'float')         AS est_cost,
       pl.plan_xml.value('(//QueryPlan/@DegreeOfParallelism)[1]', 'int')             AS dop
FROM plans AS pl
WHERE pl.rn = 1
ORDER BY pl.object_name, pl.query_id;
