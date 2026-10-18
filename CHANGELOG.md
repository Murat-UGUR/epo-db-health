# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Pending
- Validation of every script against a live ePO database.
- Failed server-task report (needs the `OrionSchedulerTaskLog` status values from a lab ePO).

## [0.2.0] - 2026-10-19

### Added
- `08_events_by_product.sql`: events per product and category, top threats with the action
  taken, loudest hosts, English event descriptions.
- `09_purge_check.sql`: oldest / newest rows of the tables ePO purge tasks clean, with a warning
  for data older than 90 days. Version tolerant (follows views to `...MT` tables, reports missing
  tables and columns) and low impact (clustered-key seek instead of a full scan).
- `run_all.ps1`: TXT, CSV and a self-contained HTML report; `-Credential`, `-Include`,
  `-Format`, `-Encrypt`, `-TrustServerCertificate`; exit code 1 when a script fails.
- CI runs `run_all.ps1` end to end on PowerShell 7 (Linux, SQL Server 2022, SQL auth) and on
  Windows PowerShell 5.1 (SQL Server LocalDB, Windows auth), including a Turkish host name.

### Changed
- `run_all.ps1` uses the .NET SqlClient instead of sqlcmd: sqlcmd is no longer required and the
  SQL password is no longer passed on a command line.
- CI uses Node 24 based actions.

### Fixed
- `run_all.ps1` on Windows PowerShell 5.1: a relative `-OutDir` (including the default) could
  fail because .NET resolves it against the process directory, not the current location.

## [0.1.0] - 2026-10-05

### Added
- Read-only scripts 00–07: overview, table sizes, index fragmentation, event volume, stale
  agents, top queries, backup history, wait statistics.
- `run_all.ps1` runner (sqlcmd based).
- CI that runs every script on SQL Server 2022 against a mock ePO schema.
