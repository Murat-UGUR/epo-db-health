<#
  CI only: runs run_all.ps1 against the mock ePO database loaded by run_sql_ci.sh and checks the
  TXT, CSV and HTML reports. The password is the throwaway SA password of the CI container.
#>
param([Parameter(Mandatory)] [string] $Password)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $root 'runner-output'

$secure = New-Object System.Security.SecureString
foreach ($ch in $Password.ToCharArray()) { $secure.AppendChar($ch) }
$credential = New-Object System.Management.Automation.PSCredential('sa', $secure)

& (Join-Path $root 'run_all.ps1') -Server 'localhost,1433' -Database 'ePO_CI' `
    -Credential $credential -OutDir $out
if ($LASTEXITCODE) { throw "run_all.ps1 exited with $LASTEXITCODE" }

$failures = 0
function Assert-That([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "OK   $Message" }
    else { Write-Host "::error::$Message"; $script:failures++ }
}

$html = Get-Content (Join-Path $out 'report.html') -Raw
$scriptCount = @(Get-ChildItem (Join-Path $root 'sql') -Filter *.sql).Count
Assert-That (([regex]::Matches($html, '<section id=')).Count -eq $scriptCount) "HTML has one section per script ($scriptCount)"
Assert-That ($html -notmatch 'badge failed') 'no script failed'
Assert-That ($html -like '*STALE-HOST-01*') 'HTML lists the stale host'
Assert-That ($html -like '*REBUILD*') 'HTML shows the REBUILD suggestion'
Assert-That ($html -like '*LOUD-HOST-01*') 'HTML shows the loudest host (08)'
Assert-That ($html -like '*class="warn"*') 'WARNING rows are highlighted'
Assert-That ($html -notlike '*<script*') 'no script tags in the report'

$csv = Join-Path $out '04_stale_agents_2.csv'
Assert-That (Test-Path $csv) 'CSV written per result set'
if (Test-Path $csv) {
    $rows = @(Import-Csv $csv)
    Assert-That (@($rows | Where-Object { $_.NodeName -eq 'STALE-HOST-02' }).Count -eq 1) 'CSV contains STALE-HOST-02'
    Assert-That (@($rows | Where-Object { $_.NodeName -eq 'FRESH-HOST-01' }).Count -eq 0) 'CSV does not contain FRESH-HOST-01'
}
$txt = Get-Content (Join-Path $out '09_purge_check.txt') -Raw
Assert-That ($txt -like '*WARNING: data older than 90 days*') 'TXT report of 09 contains the purge warning'

if ($failures) { throw "$failures runner assertion(s) failed" }
