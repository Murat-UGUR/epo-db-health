/* 03_event_volume.sql
   Threat-event volume in ePO: per month, noisiest event IDs and noisiest products.
   Spikes here usually explain database growth and slow queries/dashboards.
   ePO-SPECIFIC: built for the EPOEvents view (ePO 5.x). Verify column names on your version.
   READ-ONLY. */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @Days INT = 30;   -- look-back window for the "top" lists

-- 1) Events per month (last 12 months)
SELECT  DATEFROMPARTS(YEAR(e.DetectedUTC), MONTH(e.DetectedUTC), 1) AS month_utc,
        COUNT_BIG(*)                                               AS events
FROM    dbo.EPOEvents AS e
WHERE   e.DetectedUTC >= DATEADD(MONTH, -12, SYSUTCDATETIME())
GROUP BY DATEFROMPARTS(YEAR(e.DetectedUTC), MONTH(e.DetectedUTC), 1)
ORDER BY month_utc;

-- 2) Noisiest event IDs in the window
SELECT TOP (20)
        e.ThreatEventID,
        COUNT_BIG(*) AS events
FROM    dbo.EPOEvents AS e
WHERE   e.DetectedUTC >= DATEADD(DAY, -@Days, SYSUTCDATETIME())
GROUP BY e.ThreatEventID
ORDER BY events DESC;

-- 3) Noisiest reporting products in the window
SELECT TOP (20)
        e.AnalyzerName,
        COUNT_BIG(*) AS events
FROM    dbo.EPOEvents AS e
WHERE   e.DetectedUTC >= DATEADD(DAY, -@Days, SYSUTCDATETIME())
GROUP BY e.AnalyzerName
ORDER BY events DESC;
