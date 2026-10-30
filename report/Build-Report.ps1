<#
.SYNOPSIS
    Builds report/audit-report.html from the measured results.

.DESCRIPTION
    Every number in the report comes from a file this repository produced:
      audit/results/*.csv          the baseline audit (before any fix)
      audit/results-after/*.csv    the same audit after all fixes, same workload
      fixes/*/*.result.json        the before/after proof of each fix
      workload/results/*.csv       how many calls each workload run completed
    The text around the numbers is written here, by hand.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$inv = [Globalization.CultureInfo]::InvariantCulture

function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function N($v, [int]$dec = 0) { if ($null -eq $v -or "$v" -eq '') { return '' } ([double]$v).ToString("N$dec", $inv) }
function Ms($v) {
    $d = [double]$v
    if ($d -ge 1000) { return (($d / 1000).ToString('0.0', $inv) + ' s') }
    return ($d.ToString('0', $inv) + ' ms')
}
function Times($old, $new) {
    $o = [double]$old; $n = [double]$new
    if ($n -le 0) { return 'all' }
    $x = $o / $n
    if ($x -ge 100) { return ($x.ToString('N0', $inv) + 'x') }
    if ($x -ge 10) { return ($x.ToString('0', $inv) + 'x') }
    return ($x.ToString('0.0', $inv) + 'x')
}
function Csv([string]$dir, [string]$name) { Import-Csv (Join-Path $root "audit/$dir/$name.csv") }
function Fix([string]$folder, [string]$file = 'fix') {
    Get-Content -Raw (Join-Path $root "fixes/$folder/$file.result.json") | ConvertFrom-Json
}

# ---------- Query Store, per procedure ----------
function Get-ByProc([string]$dir) {
    $rows = Csv $dir '04-querystore-top'
    $rows | Where-Object { $_.object_name -ne '(ad hoc)' } | Group-Object object_name | ForEach-Object {
        $g = $_.Group
        $calls = ($g | ForEach-Object { [double]$_.executions } | Measure-Object -Maximum).Maximum
        $cpu = ($g | ForEach-Object { [double]$_.total_cpu_ms } | Measure-Object -Sum).Sum
        $reads = ($g | ForEach-Object { [double]$_.total_logical_reads } | Measure-Object -Sum).Sum
        $dur = ($g | ForEach-Object { [double]$_.avg_duration_ms * [double]$_.executions } | Measure-Object -Sum).Sum
        $maxReads = ($g | ForEach-Object { [double]$_.max_logical_reads } | Measure-Object -Maximum).Maximum
        [pscustomobject]@{
            Proc = $_.Name; Calls = $calls; CpuMs = $cpu; Reads = $reads
            AvgCpuMs = $cpu / $calls; AvgDurMs = $dur / $calls; AvgReads = $reads / $calls; MaxReads = $maxReads
        }
    }
}
$before = @(Get-ByProc 'results')
$after = @(Get-ByProc 'results-after')
function P($name, $set) { $set | Where-Object Proc -eq $name }
# The workload has no think time, so the faster server finished many more calls in the same
# 20 minutes. Totals of the two runs are not comparable. To compare like with like, "after" is
# the after-run average per call times the before-run call count, procedure by procedure.
$cpuBefore = ($before | Measure-Object CpuMs -Sum).Sum
$readsBefore = ($before | Measure-Object Reads -Sum).Sum
$cpuAfter = ($before | ForEach-Object { $_.Calls * (P $_.Proc $after).AvgCpuMs } | Measure-Object -Sum).Sum
$readsAfter = ($before | ForEach-Object { $_.Calls * (P $_.Proc $after).AvgReads } | Measure-Object -Sum).Sum
function Share($name) { 100.0 * (P $name $before).CpuMs / $cpuBefore }
function ReadShare($name) { 100.0 * (P $name $before).Reads / $readsBefore }

$callsBefore = Import-Csv (Join-Path $root 'workload/results/workload-run.csv')
$callsAfter = Import-Csv (Join-Path $root 'workload/results/workload-run-after.csv')
$totalCallsBefore = ($callsBefore | ForEach-Object { [double]$_.Calls } | Measure-Object -Sum).Sum
$totalCallsAfter = ($callsAfter | ForEach-Object { [double]$_.Calls } | Measure-Object -Sum).Sum
function Calls($set, $name) { [double](($set | Where-Object Procedure -eq $name).Calls) }

# ---------- waits, files, per-query waits ----------
function LockSeconds([string]$dir) {
    ((Csv $dir '02-wait-stats') | Where-Object { $_.wait_type -like 'LCK_*' } | ForEach-Object { [double]$_.wait_s } | Measure-Object -Sum).Sum
}
function AllWaitSeconds([string]$dir) { ((Csv $dir '02-wait-stats') | ForEach-Object { [double]$_.wait_s } | Measure-Object -Sum).Sum }
function DataMbRead([string]$dir) {
    [double]((Csv $dir '03-file-latency') | Where-Object { $_.database_name -eq 'StackOverflow2010' -and $_.type_desc -eq 'ROWS' }).mb_read
}
function DataReadMs([string]$dir) {
    [double]((Csv $dir '03-file-latency') | Where-Object { $_.database_name -eq 'StackOverflow2010' -and $_.type_desc -eq 'ROWS' }).avg_read_ms
}
function QueryWait([string]$dir, [string]$proc, [string]$cat) {
    $r = (Csv $dir '09-querystore-waits') | Where-Object { $_.object_name -eq $proc -and $_.wait_category_desc -eq $cat }
    if ($r) { [double]($r | Select-Object -First 1).wait_ms_per_run } else { 0 }
}
$lockBefore = LockSeconds 'results'; $lockAfter = LockSeconds 'results-after'
$waitBefore = AllWaitSeconds 'results'
$mbBefore = DataMbRead 'results'; $mbAfter = DataMbRead 'results-after'
$pvLockBefore = QueryWait 'results' 'app.RecordPostView' 'Lock'
$pvLockAfter = QueryWait 'results-after' 'app.RecordPostView' 'Lock'

# ---------- settings ----------
$box = (Csv 'results' '01-server-settings-1')[0]
$cfg = @{}; foreach ($r in (Csv 'results' '01-server-settings-2')) { $cfg[$r.name] = $r.value_in_use }
$db = (Csv 'results' '01-server-settings-3')[0]
$mem = (Csv 'results' '01-server-settings-6')[0]
$usage = Csv 'results' '05-index-usage'
$unused = $usage | Where-Object index_name -eq 'IX_Posts_LastActivityDate'
$startsLine = (Get-Content (Join-Path $root 'fixes/00-auto-close-off/evidence-before.txt') | Where-Object { $_ -match '^\d+\s+\d{4}-' } | Select-Object -First 1)
$dbStarts = ($startsLine -split '\s+')[0]
$sniff = (Csv 'results' '08-parameter-sensitivity') | Where-Object object_name -eq 'app.GetTopAnswerers'
$postsPk = $usage | Where-Object index_name -eq 'PK_Posts__Id'
$votesPk = $usage | Where-Object index_name -eq 'PK_Votes__Id'
$postsGb = N ([double]$postsPk.size_mb / 1024) 1
$postsM = N ([double]$postsPk.row_count / 1e6) 1
$votesM = N ([double]$votesPk.row_count / 1e6) 0
$newIx = (Csv 'results-after' '05-index-usage') | Where-Object index_name -eq 'IX_Posts_PostTypeId_CreationDate'

# ---------- fixes ----------
$f01 = Fix '01-votes-postid-index'
$f02 = Fix '02-implicit-conversion' 'final'
$f02t = Fix '02-implicit-conversion' 'twins'
$f03 = Fix '03-daily-counts-sargable' 'final'
$f03t = Fix '03-daily-counts-sargable' 'twins'
$f04 = Fix '04-search-tag-index'
$f05 = Fix '05-top-answerers-sniffing'
$f06 = Fix '06-drop-unused-index'
function Call($fix, [string]$label) { $fix.Calls | Where-Object Label -eq $label }
function IdentityLine($fix) {
    $n = @($fix.Calls).Count
    $same = @($fix.Calls | Where-Object { $_.Identity.Identical }).Count
    $empty = @($fix.Calls | Where-Object { $_.Identity.EmptyBothSides }).Count
    $rows = ($fix.Calls | ForEach-Object { [int]$_.Identity.RowsBefore } | Measure-Object -Sum).Sum
    $s = "Same result: $same of $n calls identical, $rows rows compared with EXCEPT both ways, row order included."
    if ($empty -eq 1) { $s += " 1 call returns no rows on both sides; it shows cost only, not identity." }
    elseif ($empty -gt 1) { $s += " $empty calls return no rows on both sides; they show cost only, not identity." }
    $s
}
function FixTable($fix) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<table class="nums"><thead><tr><th>Test call</th><th>Reads before</th><th>Reads after</th><th>CPU before</th><th>CPU after</th><th>Elapsed before</th><th>Elapsed after</th><th>Rows</th><th>Same</th></tr></thead><tbody>')
    foreach ($c in $fix.Calls) {
        $same = if ($c.Identity.EmptyBothSides) { 'empty' } elseif ($c.Identity.Identical) { 'yes' } else { 'NO' }
        [void]$sb.Append("<tr><td>$(Enc $c.Label)</td><td>$(N $c.Before.LogicalReads)</td><td>$(N $c.After.LogicalReads)</td><td>$(Ms $c.Before.CpuMs)</td><td>$(Ms $c.After.CpuMs)</td><td>$(Ms $c.Before.ElapsedMs)</td><td>$(Ms $c.After.ElapsedMs)</td><td>$(N $c.Identity.RowsAfter)</td><td>$same</td></tr>")
    }
    [void]$sb.Append('</tbody></table>')
    $sb.ToString()
}

$v1 = Call $f01 'post with most votes (4,504)'; $v1w = Call $f01 'write: cast a vote (rolled back)'
$c2 = Call $f02 'known id'
$m3 = Call $f03 '2010-06'
$s4 = Call $f04 "search 'memory leak'"; $s4n = Call $f04 'search, no match'
$t4 = Call $f04 "tag 'c#'"; $t4h = Call $f04 "tag 'haskell'"; $t4s = Call $f04 "tag 'sql-server'"
$y5 = Call $f05 'year, after a day plan'; $d5 = Call $f05 'day, own plan'
$tagCpuAfter = @($f04.Calls | Where-Object { $_.Label -like "tag *" } | ForEach-Object { [double]$_.After.CpuMs }) | Measure-Object -Minimum -Maximum
$w6 = Call $f06 'write: record a page view'; $w6v = Call $f06 'write: cast an up-vote'

$tag = 'app.GetTopAnswersByTag'; $search = 'app.SearchQuestions'; $votes = 'app.GetPostVoteCounts'
$crm = 'app.GetUserByExternalId'; $month = 'app.GetDailyPostCounts'; $top = 'app.GetTopAnswerers'
$profile = 'app.GetUserProfile'

$allIdentical = -not (@($f01, $f02, $f03, $f04, $f05, $f06) | Where-Object { -not $_.AllIdentical })
$totalIdentityCalls = (@($f01, $f02, $f03, $f04, $f05, $f06) | ForEach-Object { @($_.Calls).Count } | Measure-Object -Sum).Sum

# ---------- workload comparison table ----------
$procOrder = @($tag, $votes, $search, $crm, $month, $top, $profile, 'app.GetQuestionPage', 'app.RecordPostView', 'app.CastVote')
$wl = [System.Text.StringBuilder]::new()
[void]$wl.Append('<table class="nums"><thead><tr><th>Procedure</th><th>Calls before</th><th>Calls after</th><th>Avg CPU before</th><th>Avg CPU after</th><th>Avg duration before</th><th>Avg duration after</th><th>Avg reads before</th><th>Avg reads after</th></tr></thead><tbody>')
foreach ($p in $procOrder) {
    $b = P $p $before; $a = P $p $after
    if (-not $b -or -not $a) { continue }
    [void]$wl.Append("<tr><td>$(Enc $p)</td><td>$(N (Calls $callsBefore $p))</td><td>$(N (Calls $callsAfter $p))</td><td>$(Ms $b.AvgCpuMs)</td><td>$(Ms $a.AvgCpuMs)</td><td>$(Ms $b.AvgDurMs)</td><td>$(Ms $a.AvgDurMs)</td><td>$(N $b.AvgReads)</td><td>$(N $a.AvgReads)</td></tr>")
}
[void]$wl.Append("<tr class=""total""><td>All calls</td><td>$(N $totalCallsBefore)</td><td>$(N $totalCallsAfter)</td><td colspan=""6""></td></tr>")
[void]$wl.Append('</tbody></table>')

$cpuCut = 100.0 * ($cpuBefore - $cpuAfter) / $cpuBefore
$tagShareAfter = [double](((Csv 'results-after' '04-querystore-top') | Where-Object object_name -eq 'app.GetTopAnswersByTag' | Select-Object -First 1).pct_of_cpu)
$tagTempdb = (Csv 'results-after' '10-querystore-tempdb') | Where-Object object_name -eq 'app.GetTopAnswersByTag' | Select-Object -First 1
$readsCut = 100.0 * ($readsBefore - $readsAfter) / $readsBefore
$capturedAt = (Get-Content (Join-Path $root 'audit/results/captured-at.txt')).Replace('Captured at ', '')

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SQL Server Performance Audit</title>
<style>
  :root { --ink:#1d2433; --muted:#5b6475; --line:#d9dee7; --soft:#f4f6f9; --accent:#1f5fae; --good:#1d7a4a; --warn:#a15c00; --bad:#b3261e; }
  * { box-sizing: border-box; }
  html { background:#fff; }
  body { margin:0; color:var(--ink); background:#fff; font: 15px/1.55 "Segoe UI", system-ui, -apple-system, Roboto, Arial, sans-serif; }
  main { max-width: 980px; margin: 0 auto; padding: 40px 16px 64px; }
  h1 { font-size: 28px; line-height:1.2; margin: 0 0 6px; }
  h2 { font-size: 20px; margin: 40px 0 12px; padding-top: 8px; border-top: 2px solid var(--ink); }
  h3 { font-size: 16px; margin: 28px 0 8px; }
  p { margin: 0 0 10px; }
  .meta { color: var(--muted); font-size: 13px; margin-bottom: 24px; }
  .tiles { display:grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; margin: 18px 0 8px; }
  .tile { border:1px solid var(--line); border-radius:8px; padding:12px 14px; background:var(--soft); }
  .tile .k { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
  .tile .v { font-size: 22px; font-weight: 600; margin-top: 2px; }
  .tile .s { font-size: 13px; color: var(--muted); }
  .table-wrap { overflow-x: auto; margin: 8px 0 14px; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; }
  th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { background: var(--soft); font-weight: 600; }
  table.nums td:not(:first-child), table.nums th:not(:first-child) { text-align: right; white-space: nowrap; }
  tr.total td { font-weight: 600; border-top: 2px solid var(--line); }
  .rank { font-weight: 700; color: var(--accent); }
  .fix { border:1px solid var(--line); border-radius:8px; padding: 4px 18px 10px; margin: 18px 0; break-inside: avoid-page; }
  .facts { display:grid; grid-template-columns: 150px 1fr; gap: 4px 14px; font-size: 14px; margin: 10px 0; }
  .facts div:nth-child(odd) { color: var(--muted); }
  .ok { color: var(--good); font-weight: 600; }
  .note { font-size: 13px; color: var(--muted); }
  code { font-family: Consolas, "Cascadia Mono", monospace; font-size: 12.5px; background: var(--soft); padding: 1px 4px; border-radius: 3px; }
  ul { margin: 0 0 10px; padding-left: 20px; }
  li { margin: 3px 0; }
  @media print {
    main { padding: 0; max-width: none; }
    body { font-size: 11pt; }
    h2 { break-before: auto; }
    .fix, table, .tiles { break-inside: avoid; }
    a { color: inherit; text-decoration: none; }
  }
</style>
</head>
<body>
<main>

<h1>SQL Server Performance Audit</h1>
<div class="meta">Sample engagement on public data &middot; StackOverflow2010 database &middot; SQL Server 2025 ($(Enc $box.product_version)) $(Enc $box.edition) &middot; baseline captured $(Enc $capturedAt)</div>

<h2>Summary</h2>
<p><strong>Six changes cut the CPU of the app's calls by $(N $cpuCut 0)% and their logical reads by $(N $readsCut 0)%. In the same 20 minutes, the same four workers finished $(N ($totalCallsAfter/$totalCallsBefore) 0) times as many calls.</strong>
No query returns a different answer: $totalIdentityCalls test calls were compared row by row before and after.</p>
<p>Two procedures used $(N ((Share $tag) + (Share $votes)) 0)% of all CPU. The tag page read the whole $postsGb GB posts table on every call. The vote counter scanned all $votesM million votes to count the votes of one post.
Both now read a small index. Page views no longer wait behind the tag page: their writes waited $(Ms $pvLockBefore) on average before, and $(Ms $pvLockAfter) after.</p>
<p>All six changes are indexes or small procedure edits. None needs an application release. Each one has a rollback script. Most of them touch objects the app vendor owns, so section 5 lists what to clear with them first.</p>

<div class="tiles">
  <div class="tile"><div class="k">CPU for the baseline's calls</div><div class="v">$(Ms $cpuBefore) &rarr; $(Ms $cpuAfter)</div><div class="s">$(N $cpuCut 0)% less</div></div>
  <div class="tile"><div class="k">Logical reads, same calls</div><div class="v">$(N ($readsBefore/1e6) 0)M &rarr; $(N ($readsAfter/1e6) 0)M</div><div class="s">$(N $readsCut 0)% less</div></div>
  <div class="tile"><div class="k">Calls done in 20 minutes</div><div class="v">$(N $totalCallsBefore) &rarr; $(N $totalCallsAfter)</div><div class="s">4 workers, same mix, no pauses</div></div>
  <div class="tile"><div class="k">Time waiting on locks</div><div class="v">$(N $lockBefore 0) s &rarr; $(N $lockAfter 0) s</div><div class="s">server wait stats, 20 minutes</div></div>
</div>

<h2>1. Findings, ranked by impact</h2>
<p>Ranked by share of server time in the baseline run, then by the worst wait a user can hit. Shares come from Query Store over the 20-minute workload.</p>
<div class="table-wrap"><table>
<thead><tr><th>#</th><th>Finding</th><th>Evidence</th><th>Fix</th><th>Effort</th></tr></thead>
<tbody>
<tr><td class="rank">1</td><td>Search and the tag page read the whole posts table. The tag page also blocks page-view writes while it runs.</td><td>$(N (Share $tag) 1)% + $(N (Share $search) 1)% of CPU, $(N ((ReadShare $tag) + (ReadShare $search)) 0)% of reads. Lock waits were $(N (100*$lockBefore/$waitBefore) 0)% of all waits.</td><td>Fix 04: a narrow index for both, two columns added to an existing index</td><td>2 index changes, $(N $f04.ApplySeconds 0) s build</td></tr>
<tr><td class="rank">2</td><td>The vote counter scans all votes for every question page.</td><td>$(N (Share $votes) 1)% of CPU, $(N (P $votes $before).AvgReads) reads per call. Top missing-index hint.</td><td>Fix 01: index on votes by post</td><td>1 index, $(N $f01.ApplySeconds 0) s build</td></tr>
<tr><td class="rank">3</td><td>The top answerers report reuses whatever plan the first call compiled. A year after a day takes seconds instead of milliseconds.</td><td>Worst call $(N $sniff.max_reads) reads and $(Ms $sniff.max_duration_ms), best call $(N $sniff.min_reads) reads, same plan.</td><td>Fix 05: one column added to the index from fix 04</td><td>1 index change, $(N $f05.ApplySeconds 0) s build</td></tr>
<tr><td class="rank">4</td><td>The CRM lookup converts every row of its index from varchar to nvarchar.</td><td>$(N (Share $crm) 1)% of CPU, $(N (P $crm $before).AvgReads) reads per call for one row. The plan carries a conversion warning.</td><td>Fix 02: convert the parameter, not the column</td><td>2 lines in 1 procedure</td></tr>
<tr><td class="rank">5</td><td>The month report wraps the date column in YEAR() and MONTH(), so it cannot seek.</td><td>$(N (Share $month) 1)% of CPU, $(N (P $month $before).AvgReads) reads for any month.</td><td>Fix 03: a plain date range</td><td>4 lines in 1 procedure</td></tr>
<tr><td class="rank">6</td><td>One vendor index is never read, but every page view and vote updates it.</td><td>$(N $unused.total_reads) reads, $(N $unused.writes) writes, $(N $unused.size_mb 0) MB.</td><td>Fix 06: drop it</td><td>1 statement</td></tr>
<tr><td class="rank">7</td><td>AUTO_CLOSE is on. The database shuts down when the last connection leaves.</td><td>$dbStarts database starts in 28 minutes, no server restart. Each start empties the cache and the index counters.</td><td>Fix 00: turn it off</td><td>1 setting</td></tr>
<tr><td class="rank">8</td><td>The profile page does a key lookup for every post of the user.</td><td>$(N (Share $profile) 2)% of CPU. Up to $(N (P $profile $before).MaxReads) reads for the heaviest users.</td><td>Not fixed. Too small to be worth a wider index today.</td><td>Revisit if traffic grows</td></tr>
</tbody></table></div>

<h2>2. The fixes</h2>
<p>Each fix was measured the same way: one warm-up call, then the median of five calls, from <code>SET STATISTICS IO, TIME</code>. CPU time comes in steps of about 16 ms, so 0 ms means less than one step. Every row each call returned was saved before and after the change and compared in SQL with <code>EXCEPT</code> both ways. The fixes are numbered in the order they were applied.</p>

<div class="fix">
<h3>Fix 01. Index the votes by post</h3>
<p>Every question page shows a vote breakdown. To count the votes of one post, SQL Server read all $votesM million votes. The fix is one index on <code>Votes (PostId, VoteTypeId)</code>.</p>
<div class="facts">
<div>Result</div><div>$(N $v1.Before.LogicalReads) reads &rarr; $(N $v1.After.LogicalReads) for the most-voted post. $(Ms $v1.Before.CpuMs) CPU &rarr; $(Ms $v1.After.CpuMs).</div>
<div>Cost</div><div>$(N $f01.ApplySeconds 0) s to build. A vote insert reads $(N $v1w.Before.LogicalReads) pages before and $(N $v1w.After.LogicalReads) after.</div>
<div>Proof</div><div class="ok">$(Enc (IdentityLine $f01))</div>
<div>Files</div><div><code>fixes/01-votes-postid-index/</code></div>
</div>
<div class="table-wrap">$(FixTable $f01)</div>
</div>

<div class="fix">
<h3>Fix 02. Stop the implicit conversion in the CRM lookup</h3>
<p>The external contact id column is <code>varchar(20)</code>. The procedure takes <code>nvarchar(20)</code>, which is what .NET sends by default. So SQL Server converted every row of the index to nvarchar and scanned it, to find one row. The new version converts the parameter once and seeks. It then re-checks the found row with the original comparison, so no input can match a different row than before. The procedure signature does not change.</p>
<div class="facts">
<div>Result</div><div>$(N $c2.Before.LogicalReads) reads &rarr; $(N $c2.After.LogicalReads). $(Ms $c2.Before.CpuMs) CPU &rarr; $(Ms $c2.After.CpuMs). This is the most frequent read after page views.</div>
<div>Proof</div><div class="ok">$(Enc (IdentityLine $f02))</div>
<div>Also tested</div><div>Old and new body side by side as test twins first: $(@($f02t.Calls | Where-Object { $_.Identity.Identical }).Count) of $(@($f02t.Calls).Count) identical, including lower case, a trailing space and a full-width digit.</div>
<div>Files</div><div><code>fixes/02-implicit-conversion/</code></div>
</div>
<div class="table-wrap">$(FixTable $f02)</div>
</div>

<div class="fix">
<h3>Fix 03. Make the month report seek</h3>
<p>The report filtered with <code>YEAR(CreationDate) = @Year AND MONTH(CreationDate) = @Month</code>. A function around a column hides it from the index, so SQL Server computed both functions for all $postsM million posts. A range from the first day of the month to the first day of the next selects the same rows and seeks. An invalid month still returns no rows instead of an error.</p>
<div class="facts">
<div>Result</div><div>June 2010: $(N $m3.Before.LogicalReads) reads &rarr; $(N $m3.After.LogicalReads). $(Ms $m3.Before.CpuMs) CPU &rarr; $(Ms $m3.After.CpuMs).</div>
<div>Proof</div><div class="ok">$(Enc (IdentityLine $f03))</div>
<div>Also tested</div><div>Test twins first: $(@($f03t.Calls | Where-Object { $_.Identity.Identical }).Count) of $(@($f03t.Calls).Count) identical.</div>
<div>Files</div><div><code>fixes/03-daily-counts-sargable/</code></div>
</div>
<div class="table-wrap">$(FixTable $f03)</div>
</div>

<div class="fix">
<h3>Fix 04. Give search and the tag page a narrow index</h3>
<p>Both procedures filter with <code>LIKE '%term%'</code>. A leading wildcard can never seek, so both read every question, from the clustered index that also holds every post body. The fix keeps the queries as they are and gives them less to read: a new index on <code>Posts (PostTypeId, CreationDate)</code> with only the columns they use. Search can now stop after its first 50 hits, because the index is already in date order. The tag page also looked up every answer of every matching question; adding <code>Score</code> and <code>OwnerUserId</code> to the vendor's <code>IX_Posts_ParentId</code> removed those lookups.</p>
<div class="facts">
<div>Result</div><div>Search 'memory leak': $(N $s4.Before.LogicalReads) reads &rarr; $(N $s4.After.LogicalReads). A search with no match: $(Ms $s4n.Before.ElapsedMs) &rarr; $(Ms $s4n.After.ElapsedMs). Tag 'c#': $(Ms $t4.Before.ElapsedMs) &rarr; $(Ms $t4.After.ElapsedMs).</div>
<div>Cost</div><div>$(N $f04.ApplySeconds 0) s to build both. The new index is $(N $newIx.size_mb 0) MB after fix 05. Votes now also update <code>IX_Posts_ParentId</code>, because it carries the score.</div>
<div>Left over</div><div>The tag page still runs <code>LIKE</code> over every question's tags: $(Ms $tagCpuAfter.Minimum) to $(Ms $tagCpuAfter.Maximum) of CPU per call. Only a tag table or full-text search removes that. Both change results or code, so they are vendor work.</div>
<div>Proof</div><div class="ok">$(Enc (IdentityLine $f04))</div>
<div>Files</div><div><code>fixes/04-search-tag-index/</code>, with the two steps in <code>iterations.md</code></div>
</div>
<div class="table-wrap">$(FixTable $f04)</div>
</div>

<div class="fix">
<h3>Fix 05. Make the top answerers report cheap for every date range</h3>
<p>SQL Server compiles a procedure's plan for the parameters of its first call and reuses it. For a one-day range it picks a seek plus one lookup per row. That is right for a day and very wrong for a year. Each test call below first clears the plan, then runs one call to choose the cached plan, then measures the call that has to live with it. Adding <code>OwnerUserId</code> to the index from fix 04 covers the report, so every range is one seek and one range read, whatever ran first. No <code>OPTION (RECOMPILE)</code> was needed.</p>
<div class="facts">
<div>Result</div><div>A year after a day plan: $(N $y5.Before.LogicalReads) reads and $(Ms $y5.Before.ElapsedMs) &rarr; $(N $y5.After.LogicalReads) reads and $(Ms $y5.After.ElapsedMs). One day: $(N $d5.Before.LogicalReads) &rarr; $(N $d5.After.LogicalReads) reads.</div>
<div>Cost</div><div>$(N $f05.ApplySeconds 0) s to rebuild the index from fix 04 with one more column.</div>
<div>Proof</div><div class="ok">$(Enc (IdentityLine $f05))</div>
<div>Files</div><div><code>fixes/05-top-answerers-sniffing/</code></div>
</div>
<div class="table-wrap">$(FixTable $f05)</div>
</div>

<div class="fix">
<h3>Fix 06. Drop the index nobody reads</h3>
<p><code>IX_Posts_LastActivityDate</code> was never read during the workload. None of the plans in Query Store reads it. Three write plans maintain it, because it carries <code>ViewCount</code> and <code>Score</code>, which change on every page view and vote. Writes below run inside a transaction that rolls back, so the data stays the same.</p>
<div class="facts">
<div>Result</div><div>A page view: $(N $w6.Before.LogicalReads) &rarr; $(N $w6.After.LogicalReads) reads. A vote: $(N $w6v.Before.LogicalReads) &rarr; $(N $w6v.After.LogicalReads). $(N $unused.size_mb 0) MB freed.</div>
<div>Proof</div><div>Dropping an index cannot change a result. The proof here is that nothing uses it: 0 seeks, scans and lookups in the index counters, and 0 Query Store plans that read it (<code>evidence-before-drop.txt</code>). A rare monthly job could still need it, so the rollback script stays with the change.</div>
<div>Files</div><div><code>fixes/06-drop-unused-index/</code></div>
</div>
<div class="table-wrap">$(FixTable $f06)</div>
</div>

<div class="fix">
<h3>Fix 00. Turn AUTO_CLOSE off</h3>
<p>The first workload run lost its index counters the moment it ended. The error log showed why: the database started $dbStarts times in 28 minutes with no server restart. Two of those starts were setup steps; the rest were AUTO_CLOSE. With <code>AUTO_CLOSE</code> on, every time the last connection leaves, SQL Server closes the database and throws away its cached pages and plans. Express creates databases this way by default. The baseline in this report was taken after this change.</p>
<div class="facts"><div>Files</div><div><code>fixes/00-auto-close-off/</code></div></div>
</div>

<h2>3. The same workload, before and after</h2>
<p>The workload ran twice for 20 minutes with 4 workers and the same weighted mix: once before the fixes, once after. The numbers below are Query Store averages per call for each run.</p>
<div class="table-wrap">$($wl.ToString())</div>
<p>The workers send the next call as soon as the last one returns. So when calls got faster, they sent more: $(N $totalCallsAfter) calls instead of $(N $totalCallsBefore). That is why the summary compares CPU and reads for the same calls: the after-run average per call, times the before-run number of calls, procedure by procedure.</p>
<p>Even with $(N ($totalCallsAfter/$totalCallsBefore) 0) times the calls, the data file served $(N ($mbAfter/1024) 1) GB of reads instead of $(N ($mbBefore/1024) 0) GB. The disk was never slow: $(N (DataReadMs 'results') 2) ms per read on average. The volume was the problem.</p>
<p>One call got more expensive. A vote reads $(N (P 'app.CastVote' $after).AvgReads) pages instead of $(N (P 'app.CastVote' $before).AvgReads), because two of the new indexes carry columns a vote changes. It still takes $(Ms (P 'app.CastVote' $after).AvgDurMs), and votes are a small share of the traffic.</p>
<p><strong>What is left.</strong> The tag page is now $(N $tagShareAfter 0)% of the CPU that remains, at $(Ms (P $tag $after).AvgCpuMs) per call. Its hash join also spills to tempdb: up to $(N $tagTempdb.tempdb_mb_max_one_call 0) MB per call, and $(N ([double]$tagTempdb.tempdb_mb_total/1024) 0) GB over the after run. The next step is the tag table or full-text search in section 5. That needs the vendor.</p>

<h2>4. Server and database settings</h2>
<div class="table-wrap"><table>
<thead><tr><th>Setting</th><th>Now</th><th>What it means</th><th>Advice</th></tr></thead>
<tbody>
<tr><td>Max server memory</td><td>$(N $cfg['max server memory (MB)']) MB</td><td>No cap. Express limits the buffer pool to about 1.4 GB anyway: $(N $mem.buffer_pool_mb_total) MB in use against a $(N $mem.data_file_mb) MB data file.</td><td>On a full edition, cap it and leave the OS a few GB. On Express, the fixes above matter more because memory cannot grow.</td></tr>
<tr><td>MAXDOP</td><td>$($cfg['max degree of parallelism'])</td><td>One query may use every core.</td><td>Set it to the cores per NUMA node, at most 8.</td></tr>
<tr><td>Cost threshold for parallelism</td><td>$($cfg['cost threshold for parallelism'])</td><td>The original default. Small queries go parallel.</td><td>Start at 50 and check Query Store after a week.</td></tr>
<tr><td>Compatibility level</td><td>$($db.compatibility_level)</td><td>The optimizer behaves like SQL Server 2008. Newer features that soften parameter sniffing and memory grants are off.</td><td>Raise it only with the vendor and a test run. Query Store can force the old plans back if one regresses.</td></tr>
<tr><td>Read committed snapshot</td><td>$(if ($db.is_read_committed_snapshot_on -eq 'True') { 'on' } else { 'off' })</td><td>Readers and writers block each other. That is how the tag page held up page views.</td><td>Ask the vendor if the app supports it. It removes this whole class of waits.</td></tr>
<tr><td>Query Store</td><td>on</td><td>The source of most numbers in this report.</td><td>Keep it on.</td></tr>
<tr><td>Data file latency</td><td>$(N (DataReadMs 'results') 2) ms per read</td><td>Fast storage.</td><td>No action.</td></tr>
</tbody></table></div>

<h2>5. What to clear with the app vendor</h2>
<p>A database behind a vendor app is shared ground. These items touch objects the vendor ships, or need their answer:</p>
<ul>
<li><strong>New and changed indexes</strong> (fixes 01, 04, 05). Some vendors drop unknown indexes during upgrades, and some refuse support while they exist. Ask whether they accept them, or will ship them in their next release.</li>
<li><strong>Dropping their index</strong> (fix 06). Ask if any report, job or upgrade script reads it. It was unused for this workload only.</li>
<li><strong>Procedure edits</strong> (fixes 02 and 03). Their next upgrade will overwrite them. Send them the scripts so the fix lands in their code.</li>
<li><strong>The CRM id column type.</strong> The cleaner fix for 02 is in the app: send the parameter as varchar, or make the column nvarchar.</li>
<li><strong>Search and tags.</strong> Full-text search or a tag table would remove the remaining scan. Both change results slightly, so they are a product decision.</li>
<li><strong>Read committed snapshot and the compatibility level.</strong> Both are database settings the vendor should confirm they support.</li>
</ul>

<h2>6. How this was done</h2>
<ul>
<li>Read-only access was enough for the audit: <code>VIEW SERVER STATE</code> and <code>VIEW DATABASE STATE</code>. Ten scripts collect settings, waits, file latency, Query Store top queries with their waits and tempdb use, index usage, missing-index hints, plan warnings and parameter sensitivity.</li>
<li>The fixes were tested on a copy, never on the live server. A fix is done when every row matches, not when it "should" match.</li>
<li>Fewer reads at a higher elapsed time counts as a regression, not a win.</li>
<li>A rewrite that uses existing indexes comes before a new index. Every index here has its build time and write cost next to it.</li>
<li>The database is the public StackOverflow2010 copy (Stack Exchange data dump, cc-by-sa 4.0) with a small app built on top of it to play a vendor system. Every number comes from a run in this repository, and the scripts reproduce it.</li>
</ul>
<p class="note">Lab: SQL Server 2025 ($(Enc $box.product_version)) $(Enc $box.edition), $($box.cpu_count) cores, $(N ($box.physical_memory_mb/1024) 0) GB RAM, NVMe SSD.</p>

</main>
</body>
</html>
"@

$out = Join-Path $PSScriptRoot 'audit-report.html'
[IO.File]::WriteAllText($out, $html, [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $out"
if (-not $allIdentical) { Write-Warning 'A fix has a call that is not identical. Check the result files.' }
