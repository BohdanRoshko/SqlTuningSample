<#
.SYNOPSIS
    Plays the app's traffic against StackOverflow2010 so Query Store and the DMVs have data.

.DESCRIPTION
    Several workers call the app procedures in a weighted mix until the time is up.
    Strings go over as nvarchar, the way most .NET data access sends them.
    Parameter values come from the data itself, picked with fixed seeds, so a rerun
    sends the same mix.

.EXAMPLE
    pwsh -File workload\Run-Workload.ps1 -Minutes 20 -Workers 4
#>
param(
    [int]$Minutes = 20,
    [int]$Workers = 4,
    [string]$Server = '.\SQLEXPRESS',
    [string]$Database = 'StackOverflow2010',
    [string]$OutFile = (Join-Path $PSScriptRoot 'results\workload-run.csv'))

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\SqlBench.psm1') -Force

# Parameter pools, sampled from the data with fixed rules so every run uses the same values.
$questionIds = @(Invoke-Sql -Database $Database -Sql 'SELECT Id FROM dbo.Posts WHERE PostTypeId = 1 AND Id % 211 = 0' | ForEach-Object { [int]$_.Id })
$userIds = @(Invoke-Sql -Database $Database -Sql @'
SELECT Id FROM dbo.Users WHERE Reputation > 50 AND Id % 37 = 0
UNION
SELECT h.OwnerUserId FROM (
    SELECT TOP (25) OwnerUserId FROM dbo.Posts WHERE OwnerUserId > 0
    GROUP BY OwnerUserId ORDER BY COUNT(*) DESC) AS h
'@ | ForEach-Object { [int]$_.Id })
$searchTerms = @('linq', 'python', 'regex', 'performance', 'django', 'jquery', 'null', 'thread',
                 'unicode', 'datetime', 'iphone', 'mysql', 'memory leak', 'git', 'unit test')
$tags = @('sql-server', 'c#', 'java', 'python', 'javascript', 'php', 'iphone', 'ruby', 'haskell', 'delphi')
Write-Host ("Pools: {0} questions, {1} users" -f $questionIds.Count, $userIds.Count)

$cs = "Server=$Server;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Application Name=AppWorkload"
$deadline = (Get-Date).AddMinutes($Minutes)

$results = 1..$Workers | ForEach-Object -ThrottleLimit $Workers -Parallel {
    $workerId = $_
    $rand = [System.Random]::new(1000 + $workerId)
    $conn = [System.Data.SqlClient.SqlConnection]::new($using:cs)
    $conn.Open()
    $q = $using:questionIds; $u = $using:userIds; $terms = $using:searchTerms; $tagList = $using:tags
    $counts = @{}; $errors = 0

    function Call([string]$proc, [hashtable]$p) {
        $cmd = $conn.CreateCommand()
        $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
        $cmd.CommandText = $proc
        $cmd.CommandTimeout = 300
        foreach ($k in $p.Keys) {
            $v = $p[$k]
            $param = $cmd.Parameters.AddWithValue("@$k", $v)
            if ($v -is [string]) { $param.SqlDbType = [System.Data.SqlDbType]::NVarChar; $param.Size = 4000 }
        }
        $r = $cmd.ExecuteReader(); do { while ($r.Read()) {} } while ($r.NextResult()); $r.Dispose()
        $counts[$proc] = 1 + ($counts[$proc] ?? 0)
    }

    while ((Get-Date) -lt $using:deadline) {
        $roll = $rand.Next(100)
        try {
            if ($roll -lt 40) {
                # A question page view: the page, its vote breakdown, and the view counter.
                $id = $q[$rand.Next($q.Count)]
                Call 'app.GetQuestionPage' @{ PostId = $id }
                Call 'app.GetPostVoteCounts' @{ PostId = $id }
                Call 'app.RecordPostView' @{ PostId = $id }
            }
            elseif ($roll -lt 70) {
                # The CRM sync looks up users by their external contact id.
                $uid = $u[$rand.Next($u.Count)]
                Call 'app.GetUserByExternalId' @{ ExternalContactId = ('CRM-' + $uid.ToString('00000000')) }
            }
            elseif ($roll -lt 85) {
                Call 'app.GetUserProfile' @{ UserId = $u[$rand.Next($u.Count)] }
            }
            elseif ($roll -lt 90) {
                $vt = @(2, 2, 2, 3, 1, 5)[$rand.Next(6)]
                Call 'app.CastVote' @{ PostId = $q[$rand.Next($q.Count)]; UserId = $u[$rand.Next($u.Count)]; VoteTypeId = $vt }
            }
            elseif ($roll -lt 94) {
                Call 'app.SearchQuestions' @{ Term = $terms[$rand.Next($terms.Count)] }
            }
            elseif ($roll -lt 96) {
                $m = $rand.Next(29)   # 2008-08 .. 2010-12
                $d = ([datetime]'2008-08-01').AddMonths($m)
                Call 'app.GetDailyPostCounts' @{ Year = $d.Year; Month = $d.Month }
            }
            elseif ($roll -lt 98) {
                # Most report runs cover a day or a week. A few cover a month or a year.
                $start = ([datetime]'2009-01-01').AddDays($rand.Next(700))
                $pick = $rand.Next(100)
                $days = if ($pick -lt 70) { 1 } elseif ($pick -lt 92) { 7 } elseif ($pick -lt 98) { 30 } else { 365 }
                Call 'app.GetTopAnswerers' @{ From = $start; To = $start.AddDays($days) }
            }
            else {
                Call 'app.GetTopAnswersByTag' @{ Tag = $tagList[$rand.Next($tagList.Count)] }
            }
        }
        catch { $errors++; Write-Warning "worker ${workerId}: $($_.Exception.Message)" }
    }
    $conn.Dispose()
    foreach ($k in $counts.Keys) { [pscustomobject]@{ Worker = $workerId; Procedure = $k; Calls = $counts[$k]; Errors = $errors } }
}

$summary = $results | Group-Object Procedure | ForEach-Object {
    [pscustomobject]@{ Procedure = $_.Name; Calls = ($_.Group | Measure-Object Calls -Sum).Sum }
} | Sort-Object Calls -Descending
New-Item -ItemType Directory -Force (Split-Path $OutFile) | Out-Null
$summary | Export-Csv -NoTypeInformation -Path $OutFile
$summary | Format-Table -AutoSize
"Errors: " + (($results | Group-Object Worker | ForEach-Object { $_.Group[0].Errors }) | Measure-Object -Sum).Sum
