/* mock_epo_schema.sql  (CI only)
   Minimal stand-in for the ePO tables the scripts read, plus seed data, so CI can execute every
   script end-to-end on a real SQL Server. Column names follow the ePO 5.x schema used by the scripts.
   This is NOT the real ePO schema: passing CI proves syntax and logic, not live-ePO compatibility. */
SET NOCOUNT ON;
IF DB_ID(N'ePO_CI') IS NULL CREATE DATABASE ePO_CI;
GO
USE ePO_CI;
GO

CREATE TABLE dbo.EPOLeafNode (
    AutoID     INT IDENTITY(1, 1) PRIMARY KEY,
    NodeName   NVARCHAR(256) NOT NULL,
    LastUpdate DATETIME NULL
);
CREATE TABLE dbo.EPOComputerProperties (
    AutoID    INT IDENTITY(1, 1) PRIMARY KEY,
    ParentID  INT NOT NULL,
    IPAddress NVARCHAR(64) NULL,
    OSType    NVARCHAR(100) NULL
);
CREATE TABLE dbo.EPOEvents (
    AutoID            BIGINT IDENTITY(1, 1) PRIMARY KEY,
    DetectedUTC       DATETIME NOT NULL,
    ThreatEventID     INT NOT NULL,
    AnalyzerName      NVARCHAR(128) NULL,
    ThreatName        NVARCHAR(256) NULL,
    ThreatCategory    NVARCHAR(128) NULL,
    ThreatActionTaken NVARCHAR(128) NULL,
    TargetHostName    NVARCHAR(256) NULL
);
CREATE TABLE dbo.EPOEventFilterDesc (
    EventId  INT NOT NULL,
    Language VARCHAR(4) NOT NULL,
    Name     NVARCHAR(256) NOT NULL
);
INSERT dbo.EPOEventFilterDesc (EventId, Language, Name) VALUES
    (1092, '0409', N'Mock: Exploit prevention rule triggered'),
    (1027, '0409', N'Mock: Infected file deleted'),
    (1092, '041f', N'Mock: Turkish text that must not be shown');

-- Purge targets for 09_purge_check:
--   OrionAuditLog is a VIEW over OrionAuditLogMT (like ePO 5.x) with 400-day-old rows -> WARNING
--   OrionSchedulerTaskLog has recent rows (clustered PK)                              -> OK
--   OrionSchedulerTaskLogDetail is a small HEAP (no clustered index)                  -> MIN/MAX path
--   EPOProductEvents and EPORollup_Events do not exist                                -> not present
CREATE TABLE dbo.OrionAuditLogMT (
    AutoID    INT IDENTITY(1, 1) PRIMARY KEY,
    TenantId  INT NOT NULL DEFAULT 1,
    StartTime DATETIME NOT NULL,
    EndTime   DATETIME NULL
);
GO
CREATE VIEW dbo.OrionAuditLog AS SELECT AutoID, StartTime, EndTime FROM dbo.OrionAuditLogMT;
GO
CREATE TABLE dbo.OrionSchedulerTaskLog (
    AutoID    INT IDENTITY(1, 1) PRIMARY KEY,
    StartDate DATETIME NOT NULL
);
CREATE TABLE dbo.OrionSchedulerTaskLogDetail (
    MessageDate DATETIME NOT NULL
);
INSERT dbo.OrionAuditLogMT (StartTime, EndTime)
SELECT DATEADD(DAY, -400 + v.n, GETDATE()), DATEADD(DAY, -400 + v.n, GETDATE())
FROM (VALUES (0), (100), (200), (300), (390)) AS v(n);
INSERT dbo.OrionSchedulerTaskLog (StartDate)
SELECT DATEADD(DAY, -v.n, GETDATE()) FROM (VALUES (10), (5), (1)) AS v(n);
INSERT dbo.OrionSchedulerTaskLogDetail (MessageDate)
SELECT DATEADD(DAY, -v.n, GETDATE()) FROM (VALUES (12), (2)) AS v(n);
GO

-- Agents: one fresh, two stale, one that never communicated
INSERT dbo.EPOLeafNode (NodeName, LastUpdate) VALUES
    (N'FRESH-HOST-01', DATEADD(HOUR, -2,  GETUTCDATE())),
    (N'STALE-HOST-01', DATEADD(DAY,  -10, GETUTCDATE())),
    (N'STALE-HOST-02', DATEADD(DAY,  -45, GETUTCDATE())),
    (N'NEVER-HOST-01', NULL);
INSERT dbo.EPOComputerProperties (ParentID, IPAddress, OSType)
SELECT AutoID, CONCAT(N'10.0.0.', AutoID), N'Windows 11' FROM dbo.EPOLeafNode;

-- 6 000 events over the last ~6 months; event 1092 is the noisiest, LOUD-HOST-01 the loudest host
;WITH n AS (
    SELECT TOP (6000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
)
INSERT dbo.EPOEvents (DetectedUTC, ThreatEventID, AnalyzerName, ThreatName, ThreatCategory,
                      ThreatActionTaken, TargetHostName)
SELECT DATEADD(MINUTE, -(i * 40), GETUTCDATE()),
       CASE WHEN i % 3 = 0 THEN 1027 ELSE 1092 END,
       CASE WHEN i % 4 = 0 THEN N'Endpoint Security Threat Prevention'
            ELSE N'Endpoint Security Adaptive Threat Protection' END,
       CASE WHEN i % 5 = 0 THEN N'Mock.Trojan.A' ELSE N'Mock.PUP.B' END,
       CASE WHEN i % 5 = 0 THEN N'av.detect' ELSE N'av.pup' END,
       CASE WHEN i % 2 = 0 THEN N'IDS_ALERT_ACT_TAK_DEL' ELSE N'IDS_ALERT_ACT_TAK_WOULD_BLOCK' END,
       CASE WHEN i % 10 < 7 THEN N'LOUD-HOST-01' ELSE CONCAT(N'HOST-', i % 10) END
FROM n;
GO

-- A deliberately fragmented table (random GUID clustering key) so 02_index_fragmentation has rows to report
CREATE TABLE dbo.CI_FragTest (
    Id  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    Pad CHAR(400) NOT NULL
);
-- inserted in 50 small batches: each batch lands at random places in the key range and splits pages
DECLARE @i INT = 0;
WHILE @i < 50
BEGIN
    INSERT dbo.CI_FragTest (Pad)
    SELECT TOP (1000) 'x' FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;
    SET @i += 1;
END;
GO

-- Backup history for 06_backup_history (FULL recovery + full backup, but no log backup -> warning expected)
ALTER DATABASE ePO_CI SET RECOVERY FULL;
BACKUP DATABASE ePO_CI TO DISK = N'/var/opt/mssql/data/ePO_CI.bak' WITH INIT, NAME = N'ePO_CI CI backup';
GO
