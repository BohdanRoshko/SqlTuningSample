<#
.SYNOPSIS
    Proves one fix: same answer, lower cost.

.DESCRIPTION
    For every call in the fix definition:
      1. Saves every row of every result set the old version returns.
      2. Measures the old version: median of -Runs warm runs, from SET STATISTICS IO, TIME.
    Then applies the fix scripts (if any), and does the same for the new version.
    Last, it compares old and new rows in SQL with EXCEPT both ways. The row number is part
    of each row, so a change in row order also counts as a difference.

    A definition is a .psd1 file next to the fix:
      @{
        Title  = 'Index Votes by PostId'
        Apply  = @('index.sql')                 # run between the two phases; optional
        Calls  = @(
          @{ Label = 'post 4'; Sql = 'EXEC app.GetPostVoteCounts @PostId = 4' }
          @{ Label = 'year';  Sql = 'EXEC app.X_TestOld ...'; AfterSql = 'EXEC app.X_Test ...'; Setup = '...' }
        )
      }
    Setup runs before every timed run and before the result capture, and is not measured.
    Use it to put a specific plan in cache first (parameter sniffing).

    Writes <definition name>.result.json next to the definition.
    A call that returns no rows on both sides proves nothing about identity, so the
    output flags it (EmptyBothSides) and the report must not count it as proof.
    Elapsed time that rises is flagged too: fewer reads at a higher elapsed time is a regression.
#>
param(
    [Parameter(Mandatory)][string]$Definition,
    [int]$Runs = 5,
    [switch]$SkipApply)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SqlBench.psm1') -Force
$fixDir = Split-Path -Parent (Resolve-Path $Definition)
$def = Import-PowerShellDataFile $Definition
$fixName = Split-Path $fixDir -Leaf

# Scratch database for the saved rows, so the audited database only gets the fix itself.
Invoke-Sql -Database master -Sql "IF DB_ID(N'AuditScratch') IS NULL CREATE DATABASE AuditScratch;" | Out-Null
Invoke-Sql -Database AuditScratch -Sql @"
IF OBJECT_ID(N'dbo.ResultRows') IS NULL
    CREATE TABLE dbo.ResultRows (
        FixName   nvarchar(100) NOT NULL,
        Side      varchar(6)    NOT NULL,   -- before / after
        CallLabel nvarchar(100) NOT NULL,
        ResultSet int           NOT NULL,
        RowNum    int           NOT NULL,
        RowText   nvarchar(max) NOT NULL);
DELETE dbo.ResultRows WHERE FixName = N'$fixName';
"@ | Out-Null

function Format-Value($v) {
    if ($v -is [System.DBNull]) { return '<NULL>' }
    if ($v -is [datetime]) { return $v.ToString('o') }
    if ($v -is [System.IFormattable]) { return $v.ToString($null, [Globalization.CultureInfo]::InvariantCulture) }
    return [string]$v
}

function Save-Rows([string]$side, $call, [string]$sql) {
    $conn = New-SqlConnection
    try {
        if ($call.Setup) {
            $c = $conn.CreateCommand(); $c.CommandText = $call.Setup; $c.CommandTimeout = 600
            $r = $c.ExecuteReader(); do { while ($r.Read()) {} } while ($r.NextResult()); $r.Dispose()
        }
        $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 600
        $reader = $cmd.ExecuteReader()
        $table = [System.Data.DataTable]::new()
        foreach ($n in 'FixName', 'Side', 'CallLabel') { [void]$table.Columns.Add($n, [string]) }
        foreach ($n in 'ResultSet', 'RowNum') { [void]$table.Columns.Add($n, [int]) }
        [void]$table.Columns.Add('RowText', [string])
        $set = 0
        do {
            $set++; $rowNum = 0
            while ($reader.Read()) {
                $rowNum++
                $vals = for ($i = 0; $i -lt $reader.FieldCount; $i++) { Format-Value $reader.GetValue($i) }
                [void]$table.Rows.Add($fixName, $side, $call.Label, $set, $rowNum, ($vals -join ' | '))
            }
        } while ($reader.NextResult())
        $reader.Dispose()
    }
    finally { $conn.Dispose() }

    $bulk = [System.Data.SqlClient.SqlBulkCopy]::new(
        "Server=.\SQLEXPRESS;Database=AuditScratch;Integrated Security=true;TrustServerCertificate=true")
    $bulk.DestinationTableName = 'dbo.ResultRows'
    foreach ($col in $table.Columns) { [void]$bulk.ColumnMappings.Add($col.ColumnName, $col.ColumnName) }
    $bulk.WriteToServer($table)
    $bulk.Close()
}

function Measure-Side([string]$side) {
    foreach ($call in $def.Calls) {
        $sql = if ($side -eq 'after' -and $call.AfterSql) { $call.AfterSql } else { $call.Sql }
        Save-Rows $side $call $sql
        $m = Measure-Sql -Sql $sql -Setup $call.Setup -Runs $Runs
        Write-Host ("  {0,-6} {1,-28} reads={2,10} cpu={3,7} ms  elapsed={4,7} ms  rows={5}" -f $side, $call.Label, $m.LogicalReads, $m.CpuMs, $m.ElapsedMs, $m.Rows)
        [pscustomobject]@{ Label = $call.Label; Sql = $sql; Measure = $m }
    }
}

Write-Host "== $($def.Title)"
$before = @(Measure-Side 'before')

$applySeconds = $null
if ($def.Apply -and -not $SkipApply) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    foreach ($script in $def.Apply) {
        $path = Join-Path $fixDir $script
        Write-Host "  applying $script"
        $out = sqlcmd -S '.\SQLEXPRESS' -E -C -b -d StackOverflow2010 -i $path 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Applying $script failed:`n$out" }
    }
    $applySeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host "  applied in $applySeconds s"
}

$after = @(Measure-Side 'after')

# EXCEPT both ways, per call, in SQL.
$identity = foreach ($call in $def.Calls) {
    $label = $call.Label.Replace("'", "''")
    $row = Invoke-Sql -Database AuditScratch -Sql @"
WITH b AS (SELECT ResultSet, RowNum, RowText FROM dbo.ResultRows WHERE FixName = N'$fixName' AND CallLabel = N'$label' AND Side = 'before'),
     a AS (SELECT ResultSet, RowNum, RowText FROM dbo.ResultRows WHERE FixName = N'$fixName' AND CallLabel = N'$label' AND Side = 'after')
SELECT (SELECT COUNT(*) FROM b) AS rows_before,
       (SELECT COUNT(*) FROM a) AS rows_after,
       (SELECT COUNT(*) FROM (SELECT * FROM b EXCEPT SELECT * FROM a) x) AS only_before,
       (SELECT COUNT(*) FROM (SELECT * FROM a EXCEPT SELECT * FROM b) y) AS only_after,
       (SELECT CHECKSUM_AGG(CHECKSUM(ResultSet, RowNum, RowText)) FROM b) AS checksum_before,
       (SELECT CHECKSUM_AGG(CHECKSUM(ResultSet, RowNum, RowText)) FROM a) AS checksum_after;
"@
    [pscustomobject]@{
        Label = $call.Label; RowsBefore = $row.rows_before; RowsAfter = $row.rows_after
        OnlyBefore = $row.only_before; OnlyAfter = $row.only_after
        ChecksumBefore = $row.checksum_before; ChecksumAfter = $row.checksum_after
        Identical = ($row.only_before -eq 0 -and $row.only_after -eq 0 -and $row.rows_before -eq $row.rows_after)
        EmptyBothSides = ($row.rows_before -eq 0 -and $row.rows_after -eq 0)
    }
}
$identity | Format-Table -AutoSize | Out-String | Write-Host

function Pct($old, $new) { if ($old -gt 0) { [math]::Round(100.0 * ($old - $new) / $old, 1) } else { $null } }

$calls = for ($i = 0; $i -lt $def.Calls.Count; $i++) {
    $b = $before[$i].Measure; $a = $after[$i].Measure
    [ordered]@{
        Label = $def.Calls[$i].Label
        BeforeSql = $before[$i].Sql; AfterSql = $after[$i].Sql; Setup = $def.Calls[$i].Setup
        Before = [ordered]@{ LogicalReads = $b.LogicalReads; PhysicalReads = $b.PhysicalReads; CpuMs = $b.CpuMs; ElapsedMs = $b.ElapsedMs; Rows = $b.Rows; Detail = $b.Detail }
        After  = [ordered]@{ LogicalReads = $a.LogicalReads; PhysicalReads = $a.PhysicalReads; CpuMs = $a.CpuMs; ElapsedMs = $a.ElapsedMs; Rows = $a.Rows; Detail = $a.Detail }
        ReadsCutPct = Pct $b.LogicalReads $a.LogicalReads
        CpuCutPct = Pct $b.CpuMs $a.CpuMs
        ElapsedCutPct = Pct $b.ElapsedMs $a.ElapsedMs
        ElapsedRegression = ($a.ElapsedMs -gt $b.ElapsedMs)
        Identity = $identity[$i]
    }
}

$result = [ordered]@{
    Fix = $fixName
    Title = $def.Title
    MeasuredAt = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    Runs = $Runs
    ApplySeconds = $applySeconds
    Method = 'Median of warm runs, SET STATISTICS IO, TIME. Identity: EXCEPT both ways on every row, row order included.'
    AllIdentical = -not ($identity.Identical -contains $false)
    Calls = $calls
}
$result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $fixDir ((Split-Path -LeafBase $Definition) + '.result.json'))
Write-Host ("All identical: {0}" -f $result.AllIdentical)
