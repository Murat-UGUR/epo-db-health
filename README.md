# 🩺 epo-db-health

**Read-only T-SQL diagnostics for the Trellix (McAfee) ePolicy Orchestrator SQL Server database.**
Use it when the ePO console is slow, the database or transaction log keeps growing, or you need a quick health snapshot before an upgrade.

[![SQL CI](https://github.com/Murat-UGUR/epo-db-health/actions/workflows/sql-ci.yml/badge.svg)](https://github.com/Murat-UGUR/epo-db-health/actions/workflows/sql-ci.yml)
![T-SQL](https://img.shields.io/badge/T--SQL-CC2927?style=flat-square&logo=microsoftsqlserver&logoColor=white)
![Read-only](https://img.shields.io/badge/mode-read--only-success?style=flat-square)
![PowerShell](https://img.shields.io/badge/runner-PowerShell-5391FE?style=flat-square&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![Status](https://img.shields.io/badge/status-CI%20tested%20%C2%B7%20not%20yet%20validated%20on%20live%20ePO-orange?style=flat-square)

> [!WARNING]
> **Work in progress: not yet validated against a live ePO database.**
> Every script is executed in CI on a real **SQL Server 2022** instance loaded with a minimal *mock* ePO schema (see [How it's tested](#how-its-tested)). That catches syntax and runtime errors and checks the results, but the mock is not the real ePO schema.
> Table or column names may differ on your ePO version. **Run the scripts in a lab or test environment first, never directly on production.**
> Scripts will be corrected and marked as validated once lab testing on a real ePO is complete (see [Testing status](#testing-status)).
>
> 🇹🇷 **Geliştirme aşamasında: Sorgular henüz canlı bir ePO veritabanında doğrulanmadı.** Her sorgu, CI'da gerçek bir SQL Server 2022 üzerinde, ePO tablolarını taklit eden basit bir test şemasıyla otomatik olarak çalıştırılıyor. Bu, sözdizimi ve çalışma hatalarını yakalar ama gerçek ePO şemasının yerini tutmaz. Sürümünüze göre tablo veya kolon adları farklı olabilir. Önce lab/test ortamında çalıştırın, doğrudan production'da çalıştırmayın. Gerçek bir ePO'da yapılacak lab testleri tamamlandığında gerekli düzeltmeler yapılıp sorgular "doğrulandı" olarak işaretlenecektir.

> 🇹🇷 **Türkçe özet:** Trellix ePO'nun SQL Server veritabanının sağlığını kontrol eden T-SQL sorguları. Sorgular yalnızca okuma yapar, veritabanında hiçbir değişiklik yapmaz. ePO konsolu yavaşladığında, veritabanı ya da transaction log sürekli büyüdüğünde veya bir sürüm yükseltmesinden önce hızlı bir durum tespiti için kullanılır. Sorgular şunları gösterir:
>
> - En çok yer kaplayan tablolar
> - Bakım gerektiren (parçalanmış) index'ler
> - Transaction log'un neden büyüdüğü
> - Aylık tehdit olayı sayıları ve en çok olay üreten ürünler
> - ePO ile uzun süredir haberleşmeyen agent'lar
> - En çok CPU tüketen sorgular
> - Yedekleme durumu ve log'un neden büyüdüğüne dair uyarı
> - SQL Server'ın en çok neyi beklediği (disk, CPU, kilitlenme, bellek)

## Scripts

| # | Script | Answers the question | ePO-specific? |
|:-:|---|---|:-:|
| 00 | [`overview`](sql/00_overview.sql) | Why is my log growing? How full are the data/log files? Is auto-shrink on? | — |
| 01 | [`table_sizes`](sql/01_table_sizes.sql) | Which tables eat the space? Is the event purge working? | — |
| 02 | [`index_fragmentation`](sql/02_index_fragmentation.sql) | Which indexes need maintenance? Prints suggested `ALTER INDEX` statements without running them | — |
| 03 | [`event_volume`](sql/03_event_volume.sql) | How many threat events per month? Which event IDs and products are the noisiest? | ✅ |
| 04 | [`stale_agents`](sql/04_stale_agents.sql) | How many agents have not checked in for 1/7/30+ days, and which ones? | ✅ |
| 05 | [`top_queries`](sql/05_top_queries.sql) | Which queries burn the most CPU (dashboards, queries, server tasks)? | — |
| 06 | [`backup_history`](sql/06_backup_history.sql) | When was the last full / diff / log backup? Is the log growing because log backups are missing? | — |
| 07 | [`wait_stats`](sql/07_wait_stats.sql) | What is SQL Server waiting on: disk, CPU, blocking or memory? | — |

## Design principles

- **Read-only.** Nothing is written, deleted or rebuilt. Maintenance statements are *generated*, never executed.
- **Low impact.** Uses `READ UNCOMMITTED` and `LIMITED` index scans. Still, run 02 outside business hours on large databases.
- **Native first.** Purge old events with ePO's own **Purge Events** server tasks rather than deleting rows by hand.

## Usage

**SSMS:** open a script, select your ePO database (e.g. `ePO_<SERVERNAME>`) and execute.

**All at once (PowerShell + sqlcmd):**

```powershell
.\run_all.ps1 -Server "SQL01\EPO" -Database "ePO_EPOSERVER"           # Windows auth
.\run_all.ps1 -Server "SQL01" -Database "ePO_EPOSERVER" -SqlAuth      # SQL login prompt
```

Reports are written to `.\reports\<timestamp>\`, one file per script.

### Permissions

A login with `db_datareader` on the ePO database, `VIEW DATABASE STATE`, and `VIEW SERVER STATE` (scripts 00, 02, 05, 07) is enough. Script 06 also needs read access to the backup history in `msdb`.

## Compatibility

- **System DMV / msdb scripts** (00, 01, 02, 05, 06, 07) work on any supported SQL Server version.
- **ePO-specific scripts** (03, 04) target the ePO 5.x schema (`EPOEvents`, `EPOLeafNode`, `EPOComputerProperties`). Column names can differ between versions, so verify them in a lab first.

## How it's tested

The [SQL CI](.github/workflows/sql-ci.yml) workflow runs on every push and pull request:

1. Starts a **SQL Server 2022** container.
2. Loads [`tests/ci/mock_epo_schema.sql`](tests/ci/mock_epo_schema.sql): minimal `EPOLeafNode`, `EPOComputerProperties` and `EPOEvents` tables with seed data (fresh, stale and never-seen agents, 6 000 events), a deliberately fragmented table and a full backup with no log backup.
3. Executes **every** script in `sql/` and fails on any T-SQL error.
4. Checks the results. For example: the stale-agent script must list the hosts silent for 10 and 45 days but **not** the one that checked in 2 hours ago; the fragmentation script must flag the GUID-keyed table for `REBUILD`; the backup script must warn about FULL recovery without log backups.
5. Lints `run_all.ps1` with PSScriptAnalyzer.

The output of every script is attached to each run as the `sql-output` artifact.

## Testing status

| # | Script | CI (SQL Server 2022, mock schema) | Live ePO |
|:-:|---|:-:|:-:|
| 00 | `overview` | ✅ | ⏳ not yet validated |
| 01 | `table_sizes` | ✅ | ⏳ not yet validated |
| 02 | `index_fragmentation` | ✅ | ⏳ not yet validated |
| 03 | `event_volume` | ✅ | ⏳ not yet validated, ePO column names need checking |
| 04 | `stale_agents` | ✅ | ⏳ not yet validated, ePO column names need checking |
| 05 | `top_queries` | ✅ | ⏳ not yet validated |
| 06 | `backup_history` | ✅ | ⏳ not yet validated |
| 07 | `wait_stats` | ✅ | ⏳ not yet validated |
| — | `run_all.ps1` | ✅ lint only | ⏳ not yet validated |

Found a problem? Please [open an issue](../../issues) with your ePO and SQL Server versions and the error message.

## Roadmap

- [x] CI: execute every script on SQL Server 2022 against a mock ePO schema
- [x] Backup history and wait statistics scripts
- [ ] Validate all scripts on a lab ePO and fix any schema differences
- [ ] CSV / HTML report output
- [ ] Per-product event breakdown (ENS, DLP, HX)
- [ ] Server-task history and failed-task report

## License

MIT © Murat UĞUR
