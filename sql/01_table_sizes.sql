/* 01_table_sizes.sql
   Top 30 tables by reserved space, with row counts.
   In most ePO databases the event tables are at the top, which tells you whether purge tasks are working.
   READ-ONLY. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT TOP (30)
        s.name                                                       AS schema_name,
        t.name                                                       AS table_name,
        SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.row_count ELSE 0 END) AS row_count,
        CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS DECIMAL(18, 1))  AS reserved_mb,
        CAST(SUM(ps.used_page_count)     * 8 / 1024.0 AS DECIMAL(18, 1))  AS used_mb,
        CAST(SUM(CASE WHEN ps.index_id IN (0, 1)
                      THEN ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count
                      ELSE 0 END) * 8 / 1024.0 AS DECIMAL(18, 1))    AS data_mb
FROM    sys.dm_db_partition_stats AS ps
JOIN    sys.tables  AS t ON t.object_id = ps.object_id
JOIN    sys.schemas AS s ON s.schema_id = t.schema_id
GROUP BY s.name, t.name
ORDER BY reserved_mb DESC;
