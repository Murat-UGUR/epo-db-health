/* 06_backup_history.sql
   Last FULL / DIFFERENTIAL / LOG backup of the ePO database, with an assessment.
   A database in FULL (or BULK_LOGGED) recovery without regular log backups is the most common
   reason an ePO transaction log keeps growing.
   READ-ONLY. Reads msdb backup history (needs read access to msdb). */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @LogBackupMaxAgeHours INT = 24;   -- older than this = warning (FULL / BULK_LOGGED only)

-- 1) Summary and assessment
SELECT  d.name                                                       AS database_name,
        d.recovery_model_desc                                        AS recovery_model,
        MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END)    AS last_full_backup,
        MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END)    AS last_diff_backup,
        MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END)    AS last_log_backup,
        CASE
            WHEN MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL
                THEN 'WARNING: no full backup recorded'
            WHEN d.recovery_model_desc <> 'SIMPLE'
                 AND ISNULL(MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), '19000101')
                     < DATEADD(HOUR, -@LogBackupMaxAgeHours, GETDATE())
                THEN 'WARNING: FULL/BULK_LOGGED recovery without a recent log backup - the log will keep growing'
            ELSE 'OK'
        END                                                          AS assessment
FROM    sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
        ON b.database_name = d.name
WHERE   d.database_id = DB_ID()
GROUP BY d.name, d.recovery_model_desc;

-- 2) Last 10 backups (type: D = full, I = differential, L = log)
SELECT TOP (10)
        b.type                                                       AS backup_type,
        b.backup_start_date,
        b.backup_finish_date,
        CAST(b.backup_size / 1048576.0 AS DECIMAL(18, 1))            AS size_mb,
        CAST(b.compressed_backup_size / 1048576.0 AS DECIMAL(18, 1)) AS compressed_mb,
        mf.physical_device_name
FROM    msdb.dbo.backupset AS b
LEFT JOIN msdb.dbo.backupmediafamily AS mf
        ON mf.media_set_id = b.media_set_id
WHERE   b.database_name = DB_NAME()
ORDER BY b.backup_finish_date DESC;
