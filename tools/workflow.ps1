#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Doctor','Quick','Mobile','Api','Phone','Plan','Run','Resume','Stop','Status','RunnerDoctor')][string]$Mode = 'Doctor',
    [string]$SourcePath,
    [string]$Python,
    [string]$DeviceId,
    [switch]$Reverse,
    [string]$EndTask
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
$reportDir = Join-Path $root '.local/workflow'
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$outDir = Join-Path $reportDir "runs/$runId"
New-Item -ItemType Directory -Force $outDir | Out-Null
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($Name, $State, $Detail) {
    $results.Add([pscustomobject]@{check=$Name; status=$State; detail=$Detail})
    Write-Host "$Name : $State - $Detail"
}
function Resolve-Tool($Name, $Fallback) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in $Fallback) { if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate } }
    return $null
}
function Run-Check($Name, $Exe, $Arguments) {
    if (-not $Exe) { Add-Result $Name 'PENDING' 'Tool unavailable'; return }
    # Keep raw logs local: tests can contain private data. Publish only reviewed summaries.
    $log = Join-Path $outDir ($Name + '.log')
    & $Exe @Arguments *> $log
    $code = $LASTEXITCODE
    Add-Result $Name $(if ($code -eq 0) {'PASS'} else {'FAIL'}) "exit=$code; local log=$Name.log"
}
$git = Resolve-Tool 'git' @()
$flutter = Resolve-Tool 'flutter' @('C:/flutter/bin/flutter.bat')
$adb = Resolve-Tool 'adb' @("$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe", "$env:ANDROID_HOME/platform-tools/adb.exe")
$docker = Resolve-Tool 'docker' @("$env:LOCALAPPDATA/Programs/DockerDesktop/resources/bin/docker.exe")
if (-not $Python) {
    $Python = Resolve-Tool 'python' @()
    if ($Python -like '*WindowsApps*') { $Python = $null }
    if (-not $Python) {
        $Python = Resolve-Tool '__bundled_python__' @("$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
    }
}
if ($Mode -in @('Plan','Run','Resume','Stop','Status','RunnerDoctor')) {
    if (-not $Python) { throw 'Python is required for the local sequential controller.' }
    $runnerMode = if ($Mode -eq 'RunnerDoctor') { 'doctor' } else { $Mode.ToLowerInvariant() }
    $runnerArgs = @('tools/sequential_runner.py', $runnerMode)
    if ($EndTask) { $runnerArgs += @('--end-task', $EndTask) }
    & $Python @runnerArgs
    exit $LASTEXITCODE
}
$commit = (& $git -c "safe.directory=$($root.Replace('\','/'))" rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify target commit' }
$startChanges = @(& $git -c "safe.directory=$($root.Replace('\','/'))" status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify working tree state' }
$executionError = $false
try {
    switch ($Mode) {
        Doctor {
            foreach ($pair in @(@('git',$git),@('flutter',$flutter),@('java',(Resolve-Tool 'java' @())),@('docker',$docker),@('adb',$adb),@('python',$Python),@('codex',(Resolve-Tool 'codex' @())))) {
                Add-Result $pair[0] $(if($pair[1]){'PASS'}else{'PENDING'}) $(if($pair[1]){$pair[1]}else{'Not found'})
            }
            Run-Check 'flutter-version' $flutter @('--version')
            Run-Check 'java-version' (Resolve-Tool 'java' @()) @('-version')
            Run-Check 'docker-engine' $docker @('info','--format','{{.ServerVersion}}')
            Run-Check 'docker-compose' $docker @('compose','version')
            $studio = Test-Path 'C:/Program Files/Android/Android Studio/bin/studio64.exe'
            Add-Result 'android-studio' $(if($studio){'PASS'}else{'PENDING'}) 'Standard install path checked; IDE operation not tested'
            $codex = Resolve-Tool 'codex' @()
            if ($codex) {
                $loginText = (& $codex login status 2>&1 | Out-String)
                Add-Result 'chatgpt-login' (Get-LoginState $LASTEXITCODE $loginText) 'Authentication type inspected; credentials not persisted'
            } else { Add-Result 'chatgpt-login' 'PENDING' 'Codex unavailable' }
            if ($adb) {
                $usbOutput = (& $adb -d get-serialno 2>$null | Out-String)
                $usbSerial = Get-UsbSerial $LASTEXITCODE $usbOutput ''
                Add-Result 'usb-device' $(if($usbSerial){'PASS'}else{'PENDING'}) 'adb USB transport selection; connect/authorize exactly one USB device'
            } else { Add-Result 'usb-device' 'PENDING' 'adb unavailable' }
            if ($SourcePath) { Run-Check 'sources' $Python @('tools/index_sources.py','--check','--source',$SourcePath) }
            else { Add-Result 'external-source' 'PENDING' 'Pass actual -SourcePath; never assume it is under repository' }
        }
        Quick {
            Run-Check 'sources' $Python @('tools/index_sources.py','--check')
            Run-Check 'workflow-tests' $Python @('-m','unittest','discover','-s','tools/tests','-p','test_*.py')
            Run-Check 'workflow-gates' (Resolve-Tool 'pwsh' @()) @('-NoProfile','-File','tools/tests/workflow-gates.ps1')
            Run-Check 'whitespace' $git @('-c',"safe.directory=$($root.Replace('\','/'))",'diff','--check')
        }
        Mobile {
            Push-Location apps/mobile
            try {
                Run-Check 'flutter-analyze' $flutter @('analyze','--no-pub')
                if (-not ($results | Where-Object status -ne 'PASS')) {
                    Run-Check 'sync-tests' $flutter @('test','--no-pub','test/dependency_planner_test.dart','test/local_repository_test.dart')
                }
            } finally { Pop-Location }
        }
        Api {
            Push-Location services/api
            try { Run-Check 'api-tests' (Join-Path $PWD 'gradlew.bat') @('test','--offline','--no-daemon') }
            finally { Pop-Location }
        }
        Phone {
            if (-not $adb) { throw 'adb not found' }
            $usbOutput = (& $adb -d get-serialno 2>$null | Out-String)
            $usbSerial = Get-UsbSerial $LASTEXITCODE $usbOutput $DeviceId
            if (-not $usbSerial) {
                Add-Result 'phone' 'PENDING' 'Connect/unlock/authorize exactly one USB phone; disconnect extra USB devices; requested ID must match'
            } else {
                $DeviceId = $usbSerial
                Run-Check 'phone-state' $adb @('-s',$DeviceId,'get-state')
                if ($Reverse) { Run-Check 'phone-reverse' $adb @('-s',$DeviceId,'reverse','tcp:8080','tcp:8080') }
                Add-Result 'phone-manual' 'PENDING' 'Recording, playback/listening, permissions and interruption require user observation'
            }
        }
    }
} catch {
    $executionError = $true
    Add-Result 'execution-error' 'ERROR' 'Execution interrupted; no completed verification claim. Inspect the local command log.'
} finally {
    $endChanges = @(& $git -c "safe.directory=$($root.Replace('\','/'))" status --porcelain)
    if ($LASTEXITCODE -ne 0) { Add-Result 'final-git-status' 'ERROR' 'Cannot identify final working tree state' }
    $overall = Get-OverallState $results.ToArray()
    $reportJson = [ordered]@{schema=2; utc=[DateTime]::UtcNow.ToString('o'); mode=$Mode; base_commit=$commit; evidence_directory=$outDir;
        scope='working_tree'; dirty_at_start=($startChanges.Count -gt 0); changes_at_start=$startChanges;
        dirty_at_end=($endChanges.Count -gt 0); changes_at_end=$endChanges;
        overall=$overall; execution_error=$executionError; results=@($results.ToArray())} |
        ConvertTo-Json -Depth 6
    $reportJson | Set-Content (Join-Path $outDir 'result.json') -Encoding utf8
    $reportJson | Set-Content (Join-Path $reportDir ($Mode.ToLowerInvariant()+'.json')) -Encoding utf8
}
if ($overall -eq 'FAIL') { exit 1 }
if ($overall -eq 'PENDING') { exit 2 }
exit 0
