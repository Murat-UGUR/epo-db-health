<#
.SYNOPSIS
  Runs every script in .\sql against the ePO database and saves each result as a text report.
.EXAMPLE
  .\run_all.ps1 -Server "SQL01\EPO" -Database "ePO_EPOSERVER"
  .\run_all.ps1 -Server "SQL01" -Database "ePO_EPOSERVER" -SqlAuth   # prompts for SQL login
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [switch] $SqlAuth,
    [string] $OutDir = ".\reports\$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw "sqlcmd not found. Install SQL Server command-line tools."
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$auth = @('-E')                       # Windows authentication by default
if ($SqlAuth) {
    $cred = Get-Credential -Message "SQL login for $Server"
    $auth = @('-U', $cred.UserName, '-P', $cred.GetNetworkCredential().Password)
}

Get-ChildItem -Path "$PSScriptRoot\sql" -Filter *.sql | Sort-Object Name | ForEach-Object {
    $out = Join-Path $OutDir ($_.BaseName + '.txt')
    Write-Host "-> $($_.Name)" -ForegroundColor Cyan
    & sqlcmd -S $Server -d $Database @auth -b -W -s '|' -i $_.FullName -o $out
    if ($LASTEXITCODE -ne 0) { Write-Warning "$($_.Name) failed, see $out" }
}
Write-Host "Reports saved to $OutDir" -ForegroundColor Green
