<#
  CI only: executes a .sql file (split on GO lines) with the .NET SqlClient, so no sqlcmd is needed.
  Uses Windows authentication. Example:  .\tests\ci\load_sql.ps1 -Server '(localdb)\ci' -Path tests\ci\mock_epo_schema.sql
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Path
)

$ErrorActionPreference = 'Stop'
try { Add-Type -AssemblyName System.Data.SqlClient -ErrorAction Stop } catch { Add-Type -AssemblyName System.Data }

$connection = New-Object System.Data.SqlClient.SqlConnection("Data Source=$Server;Integrated Security=true;Connect Timeout=60")
$connection.Open()
try {
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)
    $batches = @(($text -split '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() })
    $n = 0
    foreach ($batch in $batches) {
        $n++
        $cmd = $connection.CreateCommand()
        $cmd.CommandText = $batch
        $cmd.CommandTimeout = 600
        [void] $cmd.ExecuteNonQuery()
    }
    Write-Host "Executed $n batch(es) from $Path on $Server"
} finally {
    $connection.Dispose()
}
