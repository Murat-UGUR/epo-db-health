/* 04_stale_agents.sql
   Agent check-in hygiene: how many managed systems have not communicated with ePO in 1 / 7 / 30 / 90+ days,
   plus the list of systems silent for more than @StaleDays.
   ePO-SPECIFIC: EPOLeafNode.LastUpdate = last agent-to-server communication (not the DAT date).
   Verify column names on your version.
   READ-ONLY. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @StaleDays INT = 7;

-- 1) Buckets
SELECT  bucket,
        COUNT(*) AS systems
FROM (
    SELECT CASE
             WHEN ln.LastUpdate IS NULL                                   THEN '5 - never'
             WHEN ln.LastUpdate >= DATEADD(DAY,  -1, GETUTCDATE())        THEN '1 - < 1 day'
             WHEN ln.LastUpdate >= DATEADD(DAY,  -7, GETUTCDATE())        THEN '2 - 1-7 days'
             WHEN ln.LastUpdate >= DATEADD(DAY, -30, GETUTCDATE())        THEN '3 - 7-30 days'
             ELSE                                                              '4 - > 30 days'
           END AS bucket
    FROM   dbo.EPOLeafNode AS ln
) AS b
GROUP BY bucket
ORDER BY bucket;

-- 2) Stale systems
SELECT  ln.NodeName,
        cp.IPAddress,
        cp.OSType,
        ln.LastUpdate                                    AS last_communication,
        DATEDIFF(DAY, ln.LastUpdate, GETUTCDATE())       AS days_silent
FROM    dbo.EPOLeafNode AS ln
LEFT JOIN dbo.EPOComputerProperties AS cp
        ON cp.ParentID = ln.AutoID
WHERE   ln.LastUpdate < DATEADD(DAY, -@StaleDays, GETUTCDATE())
ORDER BY ln.LastUpdate;
