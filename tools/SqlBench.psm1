# Small helpers for running SQL and measuring it with SET STATISTICS IO, TIME.
# Uses System.Data.SqlClient, which ships with PowerShell 7.

$script:DefaultServer   = '.\SQLEXPRESS'
$script:DefaultDatabase = 'StackOverflow2010'

function New-SqlConnection {
    param([string]$Server = $script:DefaultServer, [string]$Database = $script:DefaultDatabase)
    $cs = "Server=$Server;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Application Name=SqlBench;Pooling=false"
    $conn = [System.Data.SqlClient.SqlConnection]::new($cs)
    $conn.Open()
    $conn
}

function Invoke-Sql {
    <# Runs a batch and returns the first result set as objects. #>
    param(
        [Parameter(Mandatory)][string]$Sql,
        [string]$Database = $script:DefaultDatabase,
        [int]$TimeoutSeconds = 600)
    $conn = New-SqlConnection -Database $Database
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Sql
        $cmd.CommandTimeout = $TimeoutSeconds
        $da = [System.Data.SqlClient.SqlDataAdapter]::new($cmd)
        $ds = [System.Data.DataSet]::new()
        [void]$da.Fill($ds)
        if ($ds.Tables.Count -gt 0) { $ds.Tables[0].Rows | ForEach-Object { $_ } }
    }
    finally { $conn.Dispose() }
}

function Measure-SqlOnce {
    <# Runs a batch once with STATISTICS IO and TIME on, reads every row, and parses the messages.
       Logical reads are summed over every table line (LOB reads are counted apart).
       CPU and elapsed come from the last "SQL Server Execution Times" block,
       which for "EXEC proc" is the whole procedure call. #>
    param(
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory)][string]$Sql,
        [int]$TimeoutSeconds = 600)

    $messages = [System.Collections.Generic.List[string]]::new()
    $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] { param($s, $e) $messages.Add($e.Message) }
    $Connection.add_InfoMessage($handler)
    try {
        $on = $Connection.CreateCommand()
        $on.CommandText = 'SET STATISTICS IO, TIME ON;'
        [void]$on.ExecuteNonQuery()
        $messages.Clear()

        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $Sql
        $cmd.CommandTimeout = $TimeoutSeconds
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $rows = 0
        $reader = $cmd.ExecuteReader()
        do { while ($reader.Read()) { $rows++ } } while ($reader.NextResult())
        $reader.Dispose()
        $sw.Stop()

        $off = $Connection.CreateCommand()
        $off.CommandText = 'SET STATISTICS IO, TIME OFF;'
        [void]$off.ExecuteNonQuery()
    }
    finally { $Connection.remove_InfoMessage($handler) }

    $text = $messages -join "`n"
    $logical = 0; $physical = 0; $readAhead = 0; $lob = 0
    foreach ($m in [regex]::Matches($text, '(?<!lob )logical reads (\d+), physical reads (\d+)')) {
        $logical += [long]$m.Groups[1].Value; $physical += [long]$m.Groups[2].Value
    }
    foreach ($m in [regex]::Matches($text, '(?<!page server )read-ahead reads (\d+)')) { $readAhead += [long]$m.Groups[1].Value }
    foreach ($m in [regex]::Matches($text, 'lob logical reads (\d+)')) { $lob += [long]$m.Groups[1].Value }
    $times = [regex]::Matches($text, 'SQL Server Execution Times:\s*CPU time = (\d+) ms,\s*elapsed time = (\d+) ms')
    $cpu = 0; $elapsed = 0
    if ($times.Count -gt 0) {
        $last = $times[$times.Count - 1]
        $cpu = [long]$last.Groups[1].Value; $elapsed = [long]$last.Groups[2].Value
    }
    $worktable = [regex]::Matches($text, "Table '(Worktable|Workfile)'").Count -gt 0

    [pscustomobject]@{
        LogicalReads   = $logical
        PhysicalReads  = $physical
        ReadAheadReads = $readAhead
        LobLogicalReads = $lob
        CpuMs          = $cpu
        ElapsedMs      = $elapsed
        ClientMs       = [long]$sw.Elapsed.TotalMilliseconds
        Rows           = $rows
        UsedWorktable  = $worktable
        Messages       = $text
    }
}

function Get-Median([double[]]$Values) {
    $s = $Values | Sort-Object
    $n = $s.Count
    if ($n -eq 0) { return $null }
    if ($n % 2) { return $s[[int][math]::Floor($n / 2)] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

function Measure-Sql {
    <# Runs a batch -Warmup times (not counted), then -Runs times, and returns the medians.
       -Setup runs before every timed run on the same connection (for example sp_recompile and a
       first call that decides which plan gets cached). Its cost is not counted. #>
    param(
        [Parameter(Mandatory)][string]$Sql,
        [string]$Setup,
        [int]$Runs = 5,
        [int]$Warmup = 1,
        [string]$Database = $script:DefaultDatabase)

    $conn = New-SqlConnection -Database $Database
    try {
        $all = @()
        for ($i = 0; $i -lt ($Warmup + $Runs); $i++) {
            if ($Setup) {
                $c = $conn.CreateCommand(); $c.CommandText = $Setup; $c.CommandTimeout = 600
                $r = $c.ExecuteReader(); do { while ($r.Read()) {} } while ($r.NextResult()); $r.Dispose()
            }
            $m = Measure-SqlOnce -Connection $conn -Sql $Sql
            if ($i -ge $Warmup) { $all += $m }
        }
    }
    finally { $conn.Dispose() }

    [pscustomobject]@{
        Sql           = $Sql
        Runs          = $Runs
        LogicalReads  = Get-Median ($all.LogicalReads)
        PhysicalReads = Get-Median ($all.PhysicalReads)
        CpuMs         = Get-Median ($all.CpuMs)
        ElapsedMs     = Get-Median ($all.ElapsedMs)
        Rows          = $all[0].Rows
        UsedWorktable = ($all.UsedWorktable -contains $true)
        Detail        = $all | Select-Object LogicalReads, PhysicalReads, ReadAheadReads, CpuMs, ElapsedMs, ClientMs, Rows
        LastMessages  = $all[-1].Messages
    }
}

Export-ModuleMember -Function New-SqlConnection, Invoke-Sql, Measure-SqlOnce, Measure-Sql, Get-Median
