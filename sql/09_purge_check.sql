/* 09_purge_check.sql
   Are ePO's purge server tasks doing their job? For each table that ePO's purge tasks clean up,
   shows the row count, the oldest and newest record and flags data older than @WarnDays.
   A table that keeps growing with years-old rows almost always means the purge task is missing,
   disabled or failing - fix it with the ePO server task, never by deleting rows by hand.

   Version-tolerant: tables or columns that do not exist on your ePO version are reported as
   "not present" instead of failing. Low impact: the oldest row is read through the clustered
   index (a seek, assuming an ever-increasing key such as AutoID); tables without a clustered
   index are only scanned when they hold fewer than @MaxScanRows rows.
   ePO-SPECIFIC. READ-ONLY. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @WarnDays    INT    = 90;        -- older than this = WARNING
DECLARE @MaxScanRows BIGINT = 1000000;   -- never full-scan bigger heaps

DECLARE @Targets TABLE (
    table_name  SYSNAME,
    date_column SYSNAME,
    alt_column  SYSNAME NULL,      -- used when date_column does not exist on this version
    purge_task  NVARCHAR(200)
);
-- Table / date-column pairs as used by ePO's purge tasks and Trellix purge KB articles.
-- Several names exist only on some versions; missing ones are simply reported. Where only a
-- view exists, its multi-tenant base table "<name>MT" is checked instead.
INSERT @Targets VALUES
    (N'EPOEvents',                   N'DetectedUTC', N'ReceivedUTC', N'Purge Threat Event Log'),
    (N'EPOProductEvents',            N'DetectedUTC', N'ReceivedUTC', N'Purge (product events)'),
    (N'OrionAuditLog',               N'StartTime',   N'EndTime',     N'Purge Audit Log'),
    (N'OrionSchedulerTaskLog',       N'StartDate',   NULL,           N'Purge Server Task Log'),
    (N'OrionSchedulerTaskLogDetail', N'MessageDate', NULL,           N'Purge Server Task Log'),
    (N'EPORollup_Events',            N'ReceivedUTC', NULL,           N'Purge (rollup data)');

DECLARE @Results TABLE (
    table_name      SYSNAME,
    date_column     SYSNAME,
    purge_task      NVARCHAR(200),
    row_count       BIGINT   NULL,
    oldest          DATETIME NULL,
    newest          DATETIME NULL,
    note            NVARCHAR(200) NULL
);

DECLARE @t SYSNAME, @c SYSNAME, @alt SYSNAME, @task NVARCHAR(200),
        @obj INT, @rows BIGINT, @key SYSNAME, @sql NVARCHAR(MAX),
        @oldest DATETIME, @newest DATETIME, @note NVARCHAR(200);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT table_name, date_column, alt_column, purge_task FROM @Targets;
OPEN cur;
FETCH NEXT FROM cur INTO @t, @c, @alt, @task;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @obj = OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@t), N'U'),
           @rows = NULL, @key = NULL, @oldest = NULL, @newest = NULL, @note = NULL;

    -- Many ePO 5.x names are views over a multi-tenant base table "<name>MT": use the table.
    IF @obj IS NULL AND OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@t + N'MT'), N'U') IS NOT NULL
    BEGIN
        SET @obj = OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@t + N'MT'), N'U');
        SET @t = @t + N'MT';
    END

    IF @obj IS NULL AND OBJECT_ID(QUOTENAME(N'dbo') + N'.' + QUOTENAME(@t), N'V') IS NOT NULL
        SET @note = N'view only, base table not found - check the schema';
    ELSE IF @obj IS NULL
        SET @note = N'not present (on ePO 5.10+ events may live in the separate events database)';
    ELSE IF COL_LENGTH(N'dbo.' + @t, @c) IS NULL
         AND (@alt IS NULL OR COL_LENGTH(N'dbo.' + @t, @alt) IS NULL)
        SET @note = CONCAT(N'column ', @c, N' not found - check the schema');
    ELSE
    BEGIN
        IF COL_LENGTH(N'dbo.' + @t, @c) IS NULL
            SET @c = @alt;

        SELECT @rows = SUM(ps.row_count)
        FROM   sys.dm_db_partition_stats AS ps
        WHERE  ps.object_id = @obj AND ps.index_id IN (0, 1);

        -- leading column of the clustered index, if any
        SELECT TOP (1) @key = col.name
        FROM   sys.indexes AS i
        JOIN   sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN   sys.columns AS col      ON col.object_id = ic.object_id AND col.column_id = ic.column_id
        WHERE  i.object_id = @obj AND i.index_id = 1 AND ic.key_ordinal = 1;

        IF @key IS NOT NULL
        BEGIN
            SET @sql = CONCAT(
                N'SELECT TOP (1) @o = ', QUOTENAME(@c), N' FROM dbo.', QUOTENAME(@t),
                N' ORDER BY ', QUOTENAME(@key), N' ASC; ',
                N'SELECT TOP (1) @n = ', QUOTENAME(@c), N' FROM dbo.', QUOTENAME(@t),
                N' ORDER BY ', QUOTENAME(@key), N' DESC;');
            EXEC sys.sp_executesql @sql, N'@o DATETIME OUTPUT, @n DATETIME OUTPUT',
                 @o = @oldest OUTPUT, @n = @newest OUTPUT;
            SET @note = CONCAT(N'oldest/newest by clustered key ', @key, N' (approximate)');
        END
        ELSE IF ISNULL(@rows, 0) <= @MaxScanRows
        BEGIN
            SET @sql = CONCAT(
                N'SELECT @o = MIN(', QUOTENAME(@c), N'), @n = MAX(', QUOTENAME(@c),
                N') FROM dbo.', QUOTENAME(@t), N';');
            EXEC sys.sp_executesql @sql, N'@o DATETIME OUTPUT, @n DATETIME OUTPUT',
                 @o = @oldest OUTPUT, @n = @newest OUTPUT;
        END
        ELSE
            SET @note = N'heap too large to scan; dates skipped';
    END

    INSERT @Results VALUES (@t, @c, @task, @rows, @oldest, @newest, @note);
    FETCH NEXT FROM cur INTO @t, @c, @alt, @task;
END
CLOSE cur;
DEALLOCATE cur;

SELECT  table_name,
        purge_task,
        row_count,
        oldest,
        newest,
        DATEDIFF(DAY, oldest, GETDATE())                                  AS oldest_age_days,
        CASE
            WHEN row_count IS NULL                     THEN '-'
            WHEN oldest IS NULL AND row_count > 0      THEN 'UNKNOWN: dates not read'
            WHEN oldest < DATEADD(DAY, -@WarnDays, GETDATE())
                THEN CONCAT('WARNING: data older than ', @WarnDays,
                            ' days - is "', purge_task, '" scheduled and succeeding?')
            ELSE 'OK'
        END                                                               AS assessment,
        note
FROM    @Results
ORDER BY CASE WHEN row_count IS NULL THEN 1 ELSE 0 END, row_count DESC;
