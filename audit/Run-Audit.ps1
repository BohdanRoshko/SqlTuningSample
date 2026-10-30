<#
.SYNOPSIS
    Runs every read-only audit script and saves each result set as CSV.

.EXAMPLE
    pwsh -File audit\Run-Audit.ps1                         # writes to audit\results
    pwsh -File audit\Run-Audit.ps1 -OutDir audit\results-after
#>
param(
    [string]$Server = '.\SQLEXPRESS',
    [string]$OutDir = (Join-Path $PSScriptRoot 'results'))

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$cs = "Server=$Server;Database=StackOverflow2010;Integrated Security=true;TrustServerCertificate=true;Application Name=Audit"

foreach ($file in Get-ChildItem $PSScriptRoot -Filter '*.sql' | Sort-Object Name) {
    $conn = [System.Data.SqlClient.SqlConnection]::new($cs)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = Get-Content -Raw $file.FullName
        $cmd.CommandTimeout = 600
        $ds = [System.Data.DataSet]::new()
        [void][System.Data.SqlClient.SqlDataAdapter]::new($cmd).Fill($ds)
        $n = 0
        foreach ($t in $ds.Tables) {
            $n++
            $name = if ($ds.Tables.Count -gt 1) { "$($file.BaseName)-$n.csv" } else { "$($file.BaseName).csv" }
            $t.Rows | Select-Object ($t.Columns.ColumnName) | Export-Csv -NoTypeInformation -Path (Join-Path $OutDir $name)
        }
        Write-Host ("{0}: {1} result set(s)" -f $file.Name, $ds.Tables.Count)
    }
    finally { $conn.Dispose() }
}
'Captured at ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') | Set-Content (Join-Path $OutDir 'captured-at.txt')
