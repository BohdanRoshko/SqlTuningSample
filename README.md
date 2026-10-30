# SQL Server performance audit: a worked sample

This repository is a complete weekend performance audit, done on public data.
It shows what a client gets: the scripts that were run, the raw output, the fixes
with before and after numbers, and the report.

Open `report/audit-report.html` in a browser to read the report. It prints to PDF.

## Results

- Six changes cut the CPU of the app's calls by 89% and their logical reads by 95%.
- With the same four workers and the same 20 minutes, the server finished 184,662 calls instead of 14,846.
- Page-view writes stopped waiting on locks: 633 ms per call on average before, 0 ms after.
- 34 test calls were compared row by row before and after each change. All of them match.

The problems in this database were built in on purpose, one of each common kind, so the gains are large.
On a real system, expect smaller gains, mostly from the top two or three queries.

## What is in it

| Folder | What it holds |
|---|---|
| `setup/` | Attach the database, build the "vendor app" on top of it, reset counters (lab only). |
| `workload/` | `Run-Workload.ps1` plays the app's traffic. `results/` has the call counts of each run. |
| `audit/` | Ten read-only diagnostic scripts and `Run-Audit.ps1`. `results/` is the baseline audit, `results-after/` the same audit after the fixes (script 10 was added after the baseline, so only `results-after/` has its output). |
| `audit/Run-Blitz.ps1`, `audit/blitz-before/`, `audit/blitz-after/` | A cross-check with Brent Ozar's First Responder Kit 8.34 (not included; MIT license, install it from GitHub). Rows about other databases on the lab instance and the lab's host and user names are left out. |
| `fixes/NN-name/` | One folder per fix: the change, its rollback, the test definition (`*.psd1`) and the measured result (`*.result.json`). |
| `tools/` | `SqlBench.psm1` (run and measure SQL) and `Test-Fix.ps1` (prove a fix). |
| `report/` | The HTML report and the script that builds it from the result files. |

## The setup

- Database: StackOverflow2010 from Brent Ozar's site
  (<https://www.brentozar.com/archive/2015/10/how-to-download-the-stack-overflow-database-via-bittorrent/>),
  direct download <https://downloads.brentozar.com/StackOverflow2010.7z>, 1.17 GB, about 9 GB attached.
  The data is the Stack Exchange data dump, licensed cc-by-sa 4.0.
- Server: SQL Server 2025 Express (17.0.1000.7), 8 cores, 64 GB RAM, NVMe disk.
  Express caps the buffer pool at about 1.4 GB, so most of the 9 GB database lives on disk.
- The "app" is a set of stored procedures in the `app` schema, a mapping table to an external CRM,
  and four indexes the vendor shipped. The problems in it are deliberate and common:
  a missing index, a non-SARGable predicate, an implicit conversion, parameter sniffing,
  key lookups, and an index nobody reads.

## How to reproduce it

You need PowerShell 7, `sqlcmd`, and a SQL Server 2016 or newer instance (Express works).
Windows' own `tar` unpacks the `.7z` file.

```powershell
# 1. Download and unpack (keep the .7z: you will want a clean copy again)
curl.exe -L -o _data\download\StackOverflow2010.7z https://downloads.brentozar.com/StackOverflow2010.7z
tar -xf _data\download\StackOverflow2010.7z -C _data\db
icacls _data\db\StackOverflow2010.mdf     /grant "Everyone:F"   # lab only, see setup\01-attach.sql
icacls _data\db\StackOverflow2010_log.ldf /grant "Everyone:F"

# 2. Attach, build the app, turn AUTO_CLOSE off, clear the counters
sqlcmd -S .\SQLEXPRESS -E -C -i setup\01-attach.sql -v DataDir='"E:\SqlTuningSample\_data\db"'
sqlcmd -S .\SQLEXPRESS -E -C -i setup\02-app-schema.sql
sqlcmd -S .\SQLEXPRESS -E -C -i fixes\00-auto-close-off\fix.sql
sqlcmd -S .\SQLEXPRESS -E -C -i setup\03-reset-stats.sql

# 3. Run the workload, then the audit
pwsh -File workload\Run-Workload.ps1 -Minutes 20 -Workers 4
pwsh -File audit\Run-Audit.ps1

# 4. Prove each fix (it measures, applies the fix, measures again, compares every row)
pwsh -File tools\Test-Fix.ps1 -Definition fixes\01-votes-postid-index\fix.psd1
#    ...and so on for each folder. Fixes 02 and 03 first run twins.psd1 (old and new body
#    side by side), then final.psd1 (the live procedure before and after the change).

# 5. Run the same workload again, audit into results-after, build the report
sqlcmd -S .\SQLEXPRESS -E -C -i setup\03-reset-stats.sql
pwsh -File workload\Run-Workload.ps1 -Minutes 20 -Workers 4 -OutFile workload\results\workload-run-after.csv
pwsh -File audit\Run-Audit.ps1 -OutDir audit\results-after
pwsh -File report\Build-Report.ps1

# 6. Optional cross-check with the First Responder Kit (install it into master first, see audit\Run-Blitz.ps1)
pwsh -File audit\Run-Blitz.ps1 -OutDir audit\blitz-after
```

Your numbers will differ from mine with other hardware. The shape will not:
the same queries will be on top, and the fixes will cut them by the same orders of magnitude.

## How a fix is proven

`tools/Test-Fix.ps1` does the same five steps for every fix:

1. Runs each test call and saves every row of every result set, with its row number.
2. Measures each call: one warm-up, then the median of five runs, from `SET STATISTICS IO, TIME`.
3. Applies the fix.
4. Saves and measures again.
5. Compares the saved rows in SQL with `EXCEPT` both ways. The row number is part of the row,
   so a change in order counts as a difference too.

A call that returns no rows on both sides proves nothing about identity, so it is flagged
(`EmptyBothSides`) and not counted as proof. Each fix also has calls that return rows.
Writes are measured inside a transaction that rolls back, so the data stays the same.

## Rules the audit follows

- Every diagnostic script is read-only. On a client server they need `VIEW SERVER STATE`
  and `VIEW DATABASE STATE`, nothing more.
- The answer never changes, only its cost. A change is done when the row compare is empty.
- Fewer reads at a higher elapsed time is a regression, not a fix.
- A rewrite beats a new index. A new index is a proposal with its write cost written next to it.
- `OPTION (RECOMPILE)` is a last resort.
