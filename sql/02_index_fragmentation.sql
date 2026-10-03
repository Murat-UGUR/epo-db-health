/* 02_index_fragmentation.sql
   Fragmented indexes (> 10 %, > 1000 pages) with a SUGGESTED action.
   Nothing is executed: copy the generated statements into a maintenance window yourself.
   Uses LIMITED mode, the cheapest scan, but still run it outside business hours on large databases.
   READ-ONLY. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT  OBJECT_SCHEMA_NAME(ips.object_id)               AS schema_name,
        OBJECT_NAME(ips.object_id)                      AS table_name,
        i.name                                          AS index_name,
        ips.index_type_desc,
        ips.page_count,
        CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5, 1)) AS fragmentation_pct,
        CASE WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
             ELSE 'REORGANIZE' END                      AS suggested_action,
        CONCAT('ALTER INDEX ', QUOTENAME(i.name), ' ON ',
               QUOTENAME(OBJECT_SCHEMA_NAME(ips.object_id)), '.', QUOTENAME(OBJECT_NAME(ips.object_id)),
               CASE WHEN ips.avg_fragmentation_in_percent >= 30 THEN ' REBUILD;' ELSE ' REORGANIZE;' END)
                                                        AS suggested_statement
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
JOIN    sys.indexes AS i
        ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE   ips.index_id > 0                      -- skip heaps
  AND   ips.page_count > 1000
  AND   ips.avg_fragmentation_in_percent > 10
ORDER BY ips.avg_fragmentation_in_percent DESC, ips.page_count DESC;
