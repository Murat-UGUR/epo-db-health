# 🩺 epo-db-health

**Read-only T-SQL diagnostics for the Trellix (McAfee) ePolicy Orchestrator SQL Server database.**
Use it when the ePO console is slow, the database or transaction log keeps growing, or you need a quick health snapshot before an upgrade.

![T-SQL](https://img.shields.io/badge/T--SQL-CC2927?style=flat-square&logo=microsoftsqlserver&logoColor=white)
![Read-only](https://img.shields.io/badge/mode-read--only-success?style=flat-square)
![PowerShell](https://img.shields.io/badge/runner-PowerShell-5391FE?style=flat-square&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![Status](https://img.shields.io/badge/status-untested%20%C2%B7%20work%20in%20progress-orange?style=flat-square)

> [!WARNING]
> **Work in progress: these scripts have not yet been validated against a live ePO database.**
> They were written against the documented SQL Server DMVs and the ePO 5.x schema, but have not been run end-to-end on a real ePO / SQL Server instance yet.
> Table or column names may differ on your version. **Run them in a lab or test environment first, never directly on production.**
> Scripts will be corrected and marked as validated once lab testing is complete (see [Testing status](#testing-status)).
>
> 🇹🇷 **Geliştirme aşamasında: Bu sorgular henüz canlı bir ePO veritabanında test edilmedi.** Sürümünüze göre tablo veya kolon adları farklı olabilir. Önce lab/test ortamında çalıştırın, doğrudan production'da çalıştırmayın. Lab testleri tamamlandığında gerekli düzeltmeler yapılıp sorgular "doğrulandı" olarak işaretlenecektir.

> 🇹🇷 **Türkçe özet:** Trellix ePO'nun SQL Server veritabanının sağlığını kontrol eden T-SQL sorguları. Sorgular yalnızca okuma yapar, veritabanında hiçbir değişiklik yapmaz. ePO konsolu yavaşladığında, veritabanı ya da transaction log sürekli büyüdüğünde veya bir sürüm yükseltmesinden önce hızlı bir durum tespiti için kullanılır. Sorgular şunları gösterir:
>
> - En çok yer kaplayan tablolar
> - Bakım gerektiren (parçalanmış) index'ler
> - Transaction log'un neden büyüdüğü
> - Aylık tehdit olayı sayıları ve en çok olay üreten ürünler
> - ePO ile uzun süredir haberleşmeyen agent'lar
> - En çok CPU tüketen sorgular

## Scripts

| # | Script | Answers the question | ePO-specific? |
|:-:|---|---|:-:|
| 00 | [`overview`](sql/00_overview.sql) | Why is my log growing? How full are the data/log files? Is auto-shrink on? | — |
| 01 | [`table_sizes`](sql/01_table_sizes.sql) | Which tables eat the space? Is the event purge working? | — |
| 02 | [`index_fragmentation`](sql/02_index_fragmentation.sql) | Which indexes need maintenance? Prints suggested `ALTER INDEX` statements without running them | — |
| 03 | [`event_volume`](sql/03_event_volume.sql) | How many threat events per month? Which event IDs and products are the noisiest? | ✅ |
| 04 | [`stale_agents`](sql/04_stale_agents.sql) | How many agents have not checked in for 1/7/30+ days, and which ones? | ✅ |
| 05 | [`top_queries`](sql/05_top_queries.sql) | Which queries burn the most CPU (dashboards, queries, server tasks)? | — |

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

A login with `db_datareader` on the ePO database plus `VIEW SERVER STATE` (scripts 00, 02, 05) and `VIEW DATABASE STATE` is enough.

## Compatibility

- **System DMV scripts** (00, 01, 02, 05) work on any supported SQL Server version.
- **ePO-specific scripts** (03, 04) target the ePO 5.x schema (`EPOEvents`, `EPOLeafNode`, `EPOComputerProperties`). Column names can differ between versions, so verify them in a lab first.

## Testing status

| # | Script | Status |
|:-:|---|---|
| 00 | `overview` | ⏳ Not yet validated on a live ePO |
| 01 | `table_sizes` | ⏳ Not yet validated on a live ePO |
| 02 | `index_fragmentation` | ⏳ Not yet validated on a live ePO |
| 03 | `event_volume` | ⏳ Not yet validated. ePO-specific column names need checking |
| 04 | `stale_agents` | ⏳ Not yet validated. ePO-specific column names need checking |
| 05 | `top_queries` | ⏳ Not yet validated on a live ePO |
| — | `run_all.ps1` | ⏳ Not yet validated |

Found a problem? Please [open an issue](../../issues) with your ePO and SQL Server versions and the error message.

## Roadmap

- [ ] Validate all scripts on a lab ePO + SQL Server and fix any schema differences
- [ ] CSV / HTML report output
- [ ] Per-product event breakdown (ENS, DLP, HX)
- [ ] Server-task history and failed-task report

## License

MIT © Murat UĞUR
