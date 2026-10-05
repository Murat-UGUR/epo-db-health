/* 07_wait_stats.sql
   Top server waits since the last SQL Server restart, with benign/idle waits filtered out,
   and a hint about what each wait usually means: disk I/O, CPU, blocking, memory...
   Use it together with 05_top_queries when the ePO console or server tasks are slow.
   SERVER-WIDE (not only the ePO database). READ-ONLY. Requires VIEW SERVER STATE. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

WITH waits AS (
    SELECT  wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count
    FROM    sys.dm_os_wait_stats
    WHERE   waiting_tasks_count > 0
      AND   wait_type NOT LIKE 'SLEEP%'
      AND   wait_type NOT LIKE 'BROKER%'
      AND   wait_type NOT LIKE 'XE%'
      AND   wait_type NOT LIKE 'QDS%'
      AND   wait_type NOT LIKE 'HADR%'
      AND   wait_type NOT LIKE 'PARALLEL_REDO%'
      AND   wait_type NOT LIKE 'PWAIT%'
      AND   wait_type NOT LIKE 'SQLTRACE%'
      AND   wait_type NOT LIKE 'WAIT_XTP%'
      AND   wait_type NOT LIKE 'DBMIRROR%'
      AND   wait_type NOT LIKE 'FT_IFTS%'
      AND   wait_type NOT IN (
                'CHECKPOINT_QUEUE', 'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
                'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE', 'EXECSYNC', 'FSAGENT',
                'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE', 'MEMORY_ALLOCATION_EXT',
                'ONDEMAND_TASK_QUEUE', 'PREEMPTIVE_XE_GETTARGETSTATE', 'REDO_THREAD_PENDING_WORK',
                'REQUEST_FOR_DEADLOCK_SEARCH', 'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK',
                'SNI_HTTP_ACCEPT', 'SOS_WORK_DISPATCHER', 'SP_SERVER_DIAGNOSTICS_SLEEP',
                'VDI_CLIENT_OTHER', 'WAIT_FOR_RESULTS', 'WAITFOR', 'WAITFOR_TASKSHUTDOWN')
)
SELECT TOP (15)
        wait_type,
        CAST(wait_time_ms / 1000.0 AS DECIMAL(18, 1))                                   AS wait_s,
        CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(5, 1)) AS pct_of_total,
        CAST((wait_time_ms - signal_wait_time_ms) / 1000.0 AS DECIMAL(18, 1))           AS resource_wait_s,
        CAST(signal_wait_time_ms / 1000.0 AS DECIMAL(18, 1))                            AS signal_wait_s,
        waiting_tasks_count,
        CAST(1.0 * wait_time_ms / waiting_tasks_count AS DECIMAL(18, 2))                AS avg_wait_ms,
        CASE
            WHEN wait_type LIKE 'PAGEIOLATCH%'
              OR wait_type IN ('WRITELOG', 'IO_COMPLETION', 'ASYNC_IO_COMPLETION')    THEN 'Disk I/O'
            WHEN wait_type LIKE 'LCK_M_%'                                             THEN 'Blocking / locks'
            WHEN wait_type IN ('SOS_SCHEDULER_YIELD', 'CXPACKET', 'CXCONSUMER', 'THREADPOOL') THEN 'CPU / parallelism'
            WHEN wait_type LIKE 'PAGELATCH%'                                          THEN 'In-memory page contention (often tempdb)'
            WHEN wait_type = 'RESOURCE_SEMAPHORE'                                     THEN 'Memory grants'
            WHEN wait_type = 'ASYNC_NETWORK_IO'                                       THEN 'Client reading results slowly (console / app server)'
            ELSE 'Other'
        END                                                                             AS likely_area
FROM    waits
ORDER BY wait_time_ms DESC;
