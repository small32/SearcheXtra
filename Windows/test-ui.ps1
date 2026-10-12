param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$taskTestRoot = Join-Path ([IO.Path]::GetTempPath()) ('SearcheXtra-ui-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTestRoot | Out-Null
$taskPreviousData = $env:SEARCHEXTRA_DATA_DIR
$taskPreviousReport = $env:SEARCHEXTRA_SMOKE_TEST
try {
    $env:SEARCHEXTRA_DATA_DIR = $taskTestRoot
    $env:SEARCHEXTRA_SMOKE_TEST = Join-Path $taskTestRoot 'report.json'
    $taskProcess = Start-Process -FilePath $Executable -WindowStyle Hidden -PassThru
    if (-not $taskProcess.WaitForExit(90000)) {
        Stop-Process -Id $taskProcess.Id
        throw "UI tests timed out. Data: $taskTestRoot"
    }
    if (-not (Test-Path -LiteralPath $env:SEARCHEXTRA_SMOKE_TEST)) { throw "No UI test report. Exit code: $($taskProcess.ExitCode). Data: $taskTestRoot" }
    $taskReport = Get-Content -LiteralPath $env:SEARCHEXTRA_SMOKE_TEST -Raw | ConvertFrom-Json
    if ($taskReport -is [array] -or $taskReport.success -ne $true) { throw "UI test report failed or is invalid: $($taskReport.error). Report: $env:SEARCHEXTRA_SMOKE_TEST" }
    Write-Host "PASS: $($taskReport.checks.Count) WebView2 integration checks"
    Write-Output $taskReport.measurements
    Write-Host "Report: $env:SEARCHEXTRA_SMOKE_TEST"
} finally {
    $env:SEARCHEXTRA_DATA_DIR = $taskPreviousData
    $env:SEARCHEXTRA_SMOKE_TEST = $taskPreviousReport
}
