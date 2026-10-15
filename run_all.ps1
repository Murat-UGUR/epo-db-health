<#
.SYNOPSIS
  Runs the diagnostic scripts in .\sql against the ePO database and writes TXT, CSV and HTML reports.

.DESCRIPTION
  Uses the .NET SqlClient that ships with Windows PowerShell 5.1 and PowerShell 7, so sqlcmd is not
  required and passwords are never passed on a command line. Every script is read-only.

  Output (default .\reports\<timestamp>\):
    <script>.txt              all result sets of the script as text tables
    <script>_<n>.csv          one CSV per result set (UTF-8)
    report.html               one self-contained HTML report with every result set

  The exit code is 1 when at least one script failed, so the runner can be used in automation.

.PARAMETER Server
  SQL Server instance, e.g. "SQL01\EPO" or "sql01.corp.local,1433".
.PARAMETER Database
  ePO database name, e.g. "ePO_EPOSERVER".
.PARAMETER SqlAuth
  Prompt for a SQL login instead of using Windows authentication.
.PARAMETER Credential
  SQL login as a PSCredential (for scheduled or automated runs). Implies SQL authentication.
.PARAMETER Format
  Any of Txt, Csv, Html. Default: all three.
.PARAMETER Include
  Only run scripts whose file name starts with one of these prefixes, e.g. -Include 03,04,09
.PARAMETER Encrypt
  Encrypt the connection. Combine with -TrustServerCertificate for self-signed SQL certificates.
.PARAMETER TimeoutSec
  Command timeout per script in seconds. Default 300.

.EXAMPLE
  .\run_all.ps1 -Server "SQL01\EPO" -Database "ePO_EPOSERVER"
.EXAMPLE
  .\run_all.ps1 -Server "SQL01" -Database "ePO_EPOSERVER" -SqlAuth -Format Html
.EXAMPLE
  .\run_all.ps1 -Server "SQL01" -Database "ePO_EPOSERVER" -Include 04,09 -Encrypt -TrustServerCertificate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [switch] $SqlAuth,
    [System.Management.Automation.PSCredential] $Credential,
    [ValidateSet('Txt', 'Csv', 'Html')] [string[]] $Format = @('Txt', 'Csv', 'Html'),
    [string[]] $Include,
    [string] $OutDir = (Join-Path '.' (Join-Path 'reports' (Get-Date -Format 'yyyy-MM-dd_HHmm'))),
    [switch] $Encrypt,
    [switch] $TrustServerCertificate,
    [int] $TimeoutSec = 300
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName System.Data.SqlClient -ErrorAction Stop
} catch {
    Add-Type -AssemblyName System.Data   # Windows PowerShell 5.1 ships SqlClient inside System.Data
}

function Get-ScriptDescription {
    # The leading /* ... */ comment, without its first line (the file name).
    param([string] $Text)
    if ($Text -match '(?s)^\s*/\*(.*?)\*/') {
        $lines = @($Matches[1] -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        return (($lines | Select-Object -Skip 1) -join ' ')
    }
    return ''
}

function Split-SqlBatch {
    # Splits a script on lines that contain only GO, as SSMS and sqlcmd do.
    param([string] $Text)
    return @(($Text -split '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() })
}

function Invoke-SqlScript {
    param([System.Data.SqlClient.SqlConnection] $Connection, [string] $Text)
    $tables = New-Object System.Collections.Generic.List[System.Data.DataTable]
    foreach ($batch in (Split-SqlBatch -Text $Text)) {
        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $batch
        $cmd.CommandTimeout = $TimeoutSec
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $set = New-Object System.Data.DataSet
        [void] $adapter.Fill($set)
        foreach ($t in $set.Tables) { $tables.Add($t) }
    }
    return , $tables
}

function ConvertTo-Rows {
    # DataRow objects carry extra properties (RowState, Table, ...); keep only the columns.
    param([System.Data.DataTable] $Table)
    $columns = @($Table.Columns | ForEach-Object { $_.ColumnName })
    foreach ($row in $Table.Rows) {
        $o = [ordered]@{}
        foreach ($c in $columns) {
            $v = $row[$c]
            if ($v -is [System.DBNull]) { $v = $null }
            elseif ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm:ss') }
            $o[$c] = $v
        }
        [pscustomobject] $o
    }
}

function ConvertTo-HtmlTable {
    param([System.Data.DataTable] $Table)
    if ($Table.Rows.Count -eq 0) { return '<p class="muted">No rows.</p>' }
    $sb = New-Object System.Text.StringBuilder
    [void] $sb.Append('<div class="scroll"><table><thead><tr>')
    foreach ($c in $Table.Columns) {
        [void] $sb.Append('<th>' + [System.Net.WebUtility]::HtmlEncode($c.ColumnName) + '</th>')
    }
    [void] $sb.Append('</tr></thead><tbody>')
    foreach ($r in @(ConvertTo-Rows -Table $Table)) {
        $values = @($r.PSObject.Properties | ForEach-Object { $_.Value })
        $isWarning = @($values | Where-Object { [string] $_ -like 'WARNING*' }).Count -gt 0
        if ($isWarning) { [void] $sb.Append('<tr class="warn">') } else { [void] $sb.Append('<tr>') }
        foreach ($v in $values) {
            if ($null -eq $v) { $cell = '<span class="muted">NULL</span>' }
            else { $cell = [System.Net.WebUtility]::HtmlEncode([string] $v) }
            [void] $sb.Append("<td>$cell</td>")
        }
        [void] $sb.Append('</tr>')
    }
    [void] $sb.Append('</tbody></table></div>')
    return $sb.ToString()
}

function Get-HtmlText {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string] $Value)
}

# --------------------------------------------------------------------------- connection
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = $Database
$builder['Application Name'] = 'epo-db-health'
$builder['Encrypt'] = [bool] $Encrypt
$builder['TrustServerCertificate'] = [bool] $TrustServerCertificate
$builder['Connect Timeout'] = 15

if ($SqlAuth -and -not $Credential) {
    $Credential = Get-Credential -Message "SQL login for $Server"
}
$connection = New-Object System.Data.SqlClient.SqlConnection
if ($Credential) {
    # SqlCredential keeps the password in a SecureString: it never appears in the connection
    # string, on a command line or in logs.
    $secure = $Credential.Password.Copy()
    $secure.MakeReadOnly()
    $connection.Credential = New-Object System.Data.SqlClient.SqlCredential($Credential.UserName, $secure)
} else {
    $builder['Integrated Security'] = $true
}
$connection.ConnectionString = $builder.ConnectionString

$scripts = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'sql') -Filter *.sql | Sort-Object Name)
if ($Include) {
    $scripts = @($scripts | Where-Object {
            $name = $_.Name
            @($Include | Where-Object { $name.StartsWith($_) }).Count -gt 0
        })
}
if ($scripts.Count -eq 0) { throw 'No scripts selected.' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# .NET file APIs resolve relative paths against the process directory, which in Windows
# PowerShell is not the current PowerShell location: always hand them an absolute path.
$OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sections = New-Object System.Collections.Generic.List[string]
$summary = New-Object System.Collections.Generic.List[object]
$failed = 0
$serverVersion = ''

try {
    $connection.Open()
    $serverVersion = $connection.ServerVersion
    Write-Host "Connected to $Server / $Database (SQL Server $serverVersion)" -ForegroundColor Green

    foreach ($file in $scripts) {
        Write-Host "-> $($file.Name)" -ForegroundColor Cyan
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $description = Get-ScriptDescription -Text $text
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $tables = Invoke-SqlScript -Connection $connection -Text $text
            $status = 'OK'
            $errorText = ''
        } catch {
            $tables = New-Object System.Collections.Generic.List[System.Data.DataTable]
            $status = 'FAILED'
            $errorText = $_.Exception.GetBaseException().Message
            $failed++
            Write-Warning "$($file.Name) failed: $errorText"
        }
        $watch.Stop()
        $summary.Add([pscustomobject]@{
                Script     = $file.BaseName
                Status     = $status
                ResultSets = $tables.Count
                Seconds    = [math]::Round($watch.Elapsed.TotalSeconds, 1)
                Error      = $errorText
            })

        if ($Format -contains 'Txt') {
            $txt = New-Object System.Text.StringBuilder
            [void] $txt.AppendLine("== $($file.Name)  [$status]")
            if ($errorText) { [void] $txt.AppendLine("ERROR: $errorText") }
            $i = 0
            foreach ($t in $tables) {
                $i++
                [void] $txt.AppendLine("-- result set $i ($($t.Rows.Count) rows)")
                $tableText = @(ConvertTo-Rows -Table $t) | Format-Table -AutoSize | Out-String -Width 4096
                [void] $txt.AppendLine($tableText.TrimEnd())
                [void] $txt.AppendLine()
            }
            [System.IO.File]::WriteAllText((Join-Path $OutDir "$($file.BaseName).txt"), $txt.ToString(), $utf8)
        }

        if ($Format -contains 'Csv') {
            $i = 0
            foreach ($t in $tables) {
                $i++
                $csvPath = Join-Path $OutDir ('{0}_{1}.csv' -f $file.BaseName, $i)
                $lines = @(@(ConvertTo-Rows -Table $t) | ConvertTo-Csv -NoTypeInformation)
                if ($lines.Count -eq 0) {
                    $lines = @((@($t.Columns | ForEach-Object { '"' + $_.ColumnName + '"' })) -join ',')
                }
                [System.IO.File]::WriteAllLines($csvPath, [string[]] $lines, $utf8)
            }
        }

        if ($Format -contains 'Html') {
            $id = Get-HtmlText $file.BaseName
            $body = New-Object System.Text.StringBuilder
            [void] $body.Append("<section id=""$id""><h2>$id <span class=""badge $($status.ToLower())"">$status</span></h2>")
            if ($description) { [void] $body.Append('<p class="muted">' + (Get-HtmlText $description) + '</p>') }
            if ($errorText) { [void] $body.Append('<p class="error">' + (Get-HtmlText $errorText) + '</p>') }
            $i = 0
            foreach ($t in $tables) {
                $i++
                if ($tables.Count -gt 1) { [void] $body.Append("<h3>Result $i</h3>") }
                [void] $body.Append((ConvertTo-HtmlTable -Table $t))
            }
            [void] $body.Append('</section>')
            $sections.Add($body.ToString())
        }
    }
} finally {
    $connection.Dispose()
}

if ($Format -contains 'Html') {
    $rows = @($summary | ForEach-Object {
            $s = Get-HtmlText $_.Script
            "<tr><td><a href=""#$s"">$s</a></td>" +
            "<td><span class=""badge $($_.Status.ToLower())"">$($_.Status)</span></td>" +
            "<td>$($_.ResultSets)</td><td>$($_.Seconds)</td><td>$(Get-HtmlText $_.Error)</td></tr>"
        }) -join ''
    $generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
    $meta = '{0} on {1} &middot; SQL Server {2} &middot; generated {3} by epo-db-health &middot; read-only' -f `
    (Get-HtmlText $Database), (Get-HtmlText $Server), (Get-HtmlText $serverVersion), $generated
    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ePO database health</title>
<style>
:root { --bg:#fff; --fg:#1d2330; --muted:#667085; --line:#e4e7ec; --warn:#fff4e5; --warnfg:#b54708;
  --ok:#067647; --bad:#b42318; --head:#f8f9fb; }
@media (prefers-color-scheme: dark) { :root { --bg:#11151c; --fg:#e6e9ef; --muted:#98a2b3;
  --line:#2a303b; --warn:#3a2a12; --warnfg:#fdb022; --ok:#47cd89; --bad:#f97066; --head:#171c25; } }
body { background:var(--bg); color:var(--fg); font:14px/1.5 system-ui,sans-serif; margin:0 auto;
  max-width:1200px; padding:24px 16px; }
h1 { font-size:20px; margin:0 0 4px; } h2 { font-size:16px; margin:28px 0 4px; }
h3 { font-size:13px; margin:14px 0 4px; color:var(--muted); }
.muted { color:var(--muted); } .error { color:var(--bad); }
.scroll { overflow-x:auto; } table { border-collapse:collapse; width:100%; font-size:13px; }
th, td { border-bottom:1px solid var(--line); padding:6px 8px; text-align:left; vertical-align:top; }
th { background:var(--head); } tr.warn td { background:var(--warn); color:var(--warnfg); }
.badge { font-size:11px; font-weight:600; padding:1px 6px; border-radius:4px; border:1px solid currentColor; }
.ok { color:var(--ok); } .failed { color:var(--bad); }
</style></head><body>
<h1>ePO database health</h1>
<p class="muted">$meta</p>
<table><thead><tr><th>Script</th><th>Status</th><th>Result sets</th><th>Seconds</th><th>Error</th></tr></thead>
<tbody>$rows</tbody></table>
$($sections -join "`n")
</body></html>
"@
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'report.html'), $html, $utf8)
}

$summary | Format-Table Script, Status, ResultSets, Seconds -AutoSize | Out-String | Write-Host
Write-Host "Reports saved to $OutDir" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Warning "$failed script(s) failed."
    exit 1
}
