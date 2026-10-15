<#
  CI only: runs run_all.ps1 against the mock ePO database and checks the TXT, CSV and HTML reports.

  Linux job:   -Server 'localhost,1433' -Password <throwaway SA password>   (SQL authentication)
  Windows job: -Server '(localdb)\ci'                                       (Windows authentication)

  Must stay compatible with Windows PowerShell 5.1. Non-ASCII test values are built from char
  codes, because 5.1 reads BOM-less .ps1 files in the ANSI code page.
#>
param(
    [string] $Server = 'localhost,1433',
    [string] $Password
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $root 'runner-output'
$runner = Join-Path $root 'run_all.ps1'

$auth = @{}
if ($Password) {
    $secure = New-Object System.Security.SecureString
    foreach ($ch in $Password.ToCharArray()) { $secure.AppendChar($ch) }
    $auth['Credential'] = New-Object System.Management.Automation.PSCredential('sa', $secure)
}
Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), server $Server"

& $runner -Server $Server -Database 'ePO_CI' -OutDir $out @auth
if ($LASTEXITCODE) { throw "run_all.ps1 exited with $LASTEXITCODE" }

$failures = 0
function Assert-That([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "OK   $Message" }
    else { Write-Host "::error::$Message"; $script:failures++ }
}

$turkishHost = [string] [char] 0x130 + 'STANBUL-PC-01'   # "İSTANBUL-PC-01"

$html = Get-Content (Join-Path $out 'report.html') -Raw -Encoding UTF8
$scriptCount = @(Get-ChildItem (Join-Path $root 'sql') -Filter *.sql).Count
Assert-That (([regex]::Matches($html, '<section id=')).Count -eq $scriptCount) "HTML has one section per script ($scriptCount)"
Assert-That ($html -notmatch 'badge failed') 'no script failed'
Assert-That ($html -like '*STALE-HOST-01*') 'HTML lists the stale host'
Assert-That ($html.Contains($turkishHost)) 'HTML keeps Turkish characters (UTF-8 end to end)'
Assert-That ($html -like '*REBUILD*') 'HTML shows the REBUILD suggestion'
Assert-That ($html -like '*LOUD-HOST-01*') 'HTML shows the loudest host (08)'
Assert-That ($html -like '*class="warn"*') 'WARNING rows are highlighted'
Assert-That ($html -notlike '*<script*') 'no script tags in the report'

$csv = Join-Path $out '04_stale_agents_2.csv'
Assert-That (Test-Path $csv) 'CSV written per result set'
if (Test-Path $csv) {
    $rows = @(Import-Csv $csv -Encoding UTF8)
    Assert-That (@($rows | Where-Object { $_.NodeName -eq 'STALE-HOST-02' }).Count -eq 1) 'CSV contains STALE-HOST-02'
    Assert-That (@($rows | Where-Object { $_.NodeName -eq 'FRESH-HOST-01' }).Count -eq 0) 'CSV does not contain FRESH-HOST-01'
    Assert-That (@($rows | Where-Object { $_.NodeName -eq $turkishHost }).Count -eq 1) 'CSV keeps Turkish characters'
}
$txt = Get-Content (Join-Path $out '09_purge_check.txt') -Raw -Encoding UTF8
Assert-That ($txt -like '*WARNING: data older than 90 days*') 'TXT report of 09 contains the purge warning'

# Regression: a relative -OutDir must land under the current PowerShell location, even when it
# differs from the process working directory (.NET file APIs use the latter).
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('epo-rel-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location $work
try {
    & $runner -Server $Server -Database 'ePO_CI' -OutDir 'relative-out' -Include 00 -Format Html @auth
    $expected = Join-Path (Join-Path $work 'relative-out') 'report.html'
    Assert-That ((-not $LASTEXITCODE) -and (Test-Path $expected)) 'relative -OutDir resolves against the current location'
} finally {
    Pop-Location
}

if ($failures) { throw "$failures runner assertion(s) failed" }
