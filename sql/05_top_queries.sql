/* 05_top_queries.sql
   Top 20 cached queries by total CPU. Use this when the ePO console, dashboards or server tasks feel slow.
   Statistics reset when SQL Server restarts or the plan cache is cleared.
   READ-ONLY. Requires VIEW SERVER STATE. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT TOP (20)
        qs.execution_count,
        CAST(qs.total_worker_time   / 1000.0 AS DECIMAL(18, 1))                      AS total_cpu_ms,
        CAST(qs.total_worker_time   / 1000.0 / qs.execution_count AS DECIMAL(18, 2)) AS avg_cpu_ms,
        CAST(qs.total_elapsed_time  / 1000.0 / qs.execution_count AS DECIMAL(18, 2)) AS avg_duration_ms,
        qs.total_logical_reads / qs.execution_count                                  AS avg_logical_reads,
        DB_NAME(st.dbid)                                                             AS database_name,
        SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
                  ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text,
        qs.last_execution_time
FROM    sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE   st.dbid = DB_ID() OR st.dbid IS NULL
ORDER BY qs.total_worker_time DESC;
