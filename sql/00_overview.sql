/* 00_overview.sql
   Database-level health: recovery model, log reuse wait, file sizes and free space.
   READ-ONLY. Run in the context of your ePO database (e.g. USE [ePO_SERVERNAME];). */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT  d.name                    AS database_name,
        d.recovery_model_desc     AS recovery_model,
        d.log_reuse_wait_desc     AS log_reuse_wait,   -- anything other than NOTHING/CHECKPOINT explains a growing log
        d.compatibility_level,
        d.state_desc,
        d.is_auto_shrink_on,
        d.is_auto_close_on
FROM    sys.databases AS d
WHERE   d.database_id = DB_ID();

SELECT  f.name                                                        AS logical_name,
        f.type_desc,
        f.physical_name,
        CAST(f.size / 128.0 AS DECIMAL(18, 1))                        AS size_mb,
        CAST(FILEPROPERTY(f.name, 'SpaceUsed') / 128.0 AS DECIMAL(18, 1)) AS used_mb,
        CAST((f.size - FILEPROPERTY(f.name, 'SpaceUsed')) / 128.0 AS DECIMAL(18, 1)) AS free_mb,
        CASE WHEN f.is_percent_growth = 1
             THEN CONCAT(f.growth, ' %')
             ELSE CONCAT(f.growth / 128, ' MB') END                   AS autogrowth,
        CASE WHEN f.max_size = -1 THEN 'unlimited'
             ELSE CONCAT(CAST(f.max_size / 128 AS BIGINT), ' MB') END AS max_size
FROM    sys.database_files AS f
ORDER BY f.type, f.file_id;
