/* 08_events_by_product.sql
   Threat events broken down by reporting product (ENS, DLP, HX, ...), threat, action and host.
   Answers: which product generates the noise, which threats repeat, which hosts are the loudest,
   and what each noisy event ID means.
   ePO-SPECIFIC: EPOEvents view and EPOEventFilterDesc (ePO 5.x). Verify column names on your version.
   READ-ONLY. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @Days INT = 30;   -- look-back window
DECLARE @Since DATETIME = DATEADD(DAY, -@Days, GETUTCDATE());

-- 1) Per product and threat category
SELECT  ISNULL(e.AnalyzerName, N'(unknown)')         AS product,
        ISNULL(e.ThreatCategory, N'(none)')          AS threat_category,
        COUNT_BIG(*)                                 AS events,
        COUNT(DISTINCT e.TargetHostName)             AS hosts,
        MAX(e.DetectedUTC)                           AS last_seen_utc
FROM    dbo.EPOEvents AS e
WHERE   e.DetectedUTC >= @Since
GROUP BY e.AnalyzerName, e.ThreatCategory
ORDER BY events DESC;

-- 2) Top threats with the action taken (the same threat with 'would block' / 'deleted' / 'none'
--    side by side shows where policies are in observe mode or failing to clean)
SELECT TOP (25)
        ISNULL(e.ThreatName, N'(none)')              AS threat_name,
        ISNULL(e.AnalyzerName, N'(unknown)')         AS product,
        ISNULL(e.ThreatActionTaken, N'(none)')       AS action_taken,
        COUNT_BIG(*)                                 AS events,
        COUNT(DISTINCT e.TargetHostName)             AS hosts,
        MAX(e.DetectedUTC)                           AS last_seen_utc
FROM    dbo.EPOEvents AS e
WHERE   e.DetectedUTC >= @Since
GROUP BY e.ThreatName, e.AnalyzerName, e.ThreatActionTaken
ORDER BY events DESC;

-- 3) Loudest hosts (a single host with a reinfection loop or a bad exclusion often dominates)
SELECT TOP (25)
        ISNULL(e.TargetHostName, N'(unknown)')       AS host,
        COUNT_BIG(*)                                 AS events,
        COUNT(DISTINCT e.ThreatName)                 AS distinct_threats,
        COUNT(DISTINCT e.AnalyzerName)               AS products,
        MAX(e.DetectedUTC)                           AS last_seen_utc
FROM    dbo.EPOEvents AS e
WHERE   e.DetectedUTC >= @Since
GROUP BY e.TargetHostName
ORDER BY events DESC;

-- 4) Noisiest event IDs with their English description
SELECT TOP (20)
        x.ThreatEventID                              AS event_id,
        ISNULL(d.Name, N'(no description)')          AS description,
        x.events
FROM (
        SELECT  e.ThreatEventID, COUNT_BIG(*) AS events
        FROM    dbo.EPOEvents AS e
        WHERE   e.DetectedUTC >= @Since
        GROUP BY e.ThreatEventID
     ) AS x
LEFT JOIN dbo.EPOEventFilterDesc AS d
        ON d.EventId = x.ThreatEventID AND d.Language = '0409'
ORDER BY x.events DESC;
