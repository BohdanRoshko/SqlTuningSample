<#
.SYNOPSIS
    Cross-check: runs Brent Ozar's First Responder Kit and saves every result set as CSV.

.DESCRIPTION
    The kit is free (MIT license) and widely used, so clients and other DBAs know its output.
    It is not part of this repository. Install version 8.34 (release 20260708) into master first:
      https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/releases/tag/20260708
      sqlcmd -S .\SQLEXPRESS -E -C -I -d master -i sp_ineachdb.sql   (then the same for sp_Blitz,
                                                                   sp_BlitzFirst, sp_BlitzCache, sp_BlitzIndex)
    -I matters: sqlcmd creates procedures with QUOTED_IDENTIFIER OFF without it, and sp_BlitzFirst then fails.
    The procedures only read. Installing them is the one change this needs on a client server,
    so ask first; some clients already have them.

    Plan XML columns are dropped from the CSV files and long text is cut to 2,000 characters,
    to keep the files readable in git. The machine and Windows user names become <host> and <user>.
    Rows about other user databases on the same instance are
    dropped too: the audit covers one database, and the others are not the client's business here.

.EXAMPLE
    pwsh -File audit\Run-Blitz.ps1 -OutDir audit\blitz-before
#>
param(
    [string]$Server = '.\SQLEXPRESS',
    [string]$Database = 'StackOverflow2010',
    [Parameter(Mandatory)][string]$OutDir)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$cs = "Server=$Server;Database=master;Integrated Security=true;TrustServerCertificate=true;Application Name=Audit"

# Other user databases on this instance. A row that names one of them is left out.
$conn0 = [System.Data.SqlClient.SqlConnection]::new($cs); $conn0.Open()
$c0 = $conn0.CreateCommand()
$c0.CommandText = "SELECT name FROM sys.databases WHERE database_id > 4 AND name <> @db"
[void]$c0.Parameters.AddWithValue('@db', $Database)
$r0 = $c0.ExecuteReader(); $otherDbs = @(while ($r0.Read()) { $r0.GetString(0) }); $conn0.Dispose()
function Test-OtherDb([string]$text) {
    foreach ($d in $otherDbs) {
        $e = [regex]::Escape($d)
        if ($text -eq $d -or $text.Contains("[$d]") -or $text.Contains("'$d'") -or $text -match "(?i)\b(in|database|db)\s+$e\b") { return $true }
    }
    return $false
}

# The machine and Windows user names of the lab box stay out of the published files.
# Host names come from Windows, from @@SERVERNAME and from the login's domain part, which can differ.
$conn1 = [System.Data.SqlClient.SqlConnection]::new($cs); $conn1.Open()
$c1 = $conn1.CreateCommand(); $c1.CommandText = 'SELECT @@SERVERNAME, SUSER_SNAME();'
$r1 = $c1.ExecuteReader(); [void]$r1.Read(); $serverName = $r1.GetString(0); $loginName = $r1.GetString(1); $conn1.Dispose()
$hostNames = @($env:COMPUTERNAME, ($serverName -split '\\')[0], ($loginName -split '\\')[0]) | Where-Object { $_ } | Sort-Object -Unique
$userNames = @($env:USERNAME, ($loginName -split '\\')[-1]) | Where-Object { $_ } | Sort-Object -Unique
function Hide-Names([string]$text) {
    foreach ($h in $hostNames) { $text = [regex]::Replace($text, "(?i)(?<![\w-])$([regex]::Escape($h))(?![\w-])", '<host>') }
    foreach ($u in $userNames) { $text = [regex]::Replace($text, "(?i)(?<![\w-])$([regex]::Escape($u))(?![\w-])", '<user>') }
    $text
}

$runs = [ordered]@{
    'sp_Blitz'               = 'EXEC dbo.sp_Blitz @CheckServerInfo = 1, @CheckUserDatabaseObjects = 1;'
    'sp_BlitzFirst-since-startup' = 'EXEC dbo.sp_BlitzFirst @SinceStartup = 1;'
    'sp_BlitzCache-cpu'      = "EXEC dbo.sp_BlitzCache @SortOrder = 'cpu', @Top = 10, @DatabaseName = N'$Database';"
    'sp_BlitzCache-reads'    = "EXEC dbo.sp_BlitzCache @SortOrder = 'reads', @Top = 10, @DatabaseName = N'$Database';"
    'sp_BlitzIndex'          = "EXEC dbo.sp_BlitzIndex @DatabaseName = N'$Database', @Mode = 0;"
}

foreach ($name in $runs.Keys) {
    $conn = [System.Data.SqlClient.SqlConnection]::new($cs)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $runs[$name]
        $cmd.CommandTimeout = 900
        $ds = [System.Data.DataSet]::new()
        [void][System.Data.SqlClient.SqlDataAdapter]::new($cmd).Fill($ds)
        $n = 0
        foreach ($t in $ds.Tables) {
            $n++
            $cols = $t.Columns | Where-Object { $_.ColumnName -notmatch 'plan' -or $_.ColumnName -match 'plan_?count|plans|warnings' } |
                ForEach-Object { $_.ColumnName }
            $rows = foreach ($r in $t.Rows) {
                if (@($t.Columns | Where-Object { Test-OtherDb ([string]$r[$_.ColumnName]) }).Count -gt 0) { continue }
                $o = [ordered]@{}
                foreach ($c in $cols) {
                    $v = [string]$r[$c]
                    if ($v.Length -gt 2000) { $v = $v.Substring(0, 2000) + ' ...' }
                    $v = Hide-Names $v
                    $o[$c] = $v
                }
                [pscustomobject]$o
            }
            $file = if ($ds.Tables.Count -gt 1) { "$name-$n.csv" } else { "$name.csv" }
            $rows | Export-Csv -NoTypeInformation -Path (Join-Path $OutDir $file)
        }
        Write-Host ("{0}: {1} result set(s)" -f $name, $ds.Tables.Count)
    }
    finally { $conn.Dispose() }
}
'Captured at ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ' with First Responder Kit 8.34 (20260708)' |
    Set-Content (Join-Path $OutDir 'captured-at.txt')
