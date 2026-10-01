function Get-CiNotificationResult($Report, [string]$Commit) {
    if ($Report.commit -cne $Commit) { throw 'CI report commit mismatch' }
    $paths = @('.github/workflows/ci.yml', '.github/workflows/api-contract.yml',
        '.github/workflows/idempotency-mysql.yml', '.github/workflows/development-workflow.yml')
    if (@($Report.checks).Count -ne $paths.Count) { throw 'Incomplete CI report' }
    foreach ($path in $paths) {
        $rows = @($Report.checks | Where-Object path -eq $path)
        if ($rows.Count -ne 1 -or $rows[0].status -notin @('PASS','FAIL','PENDING','NOT_APPLICABLE')) {
            throw 'Invalid CI report'
        }
    }
    if(@($Report.checks | Where-Object status -eq 'NOT_APPLICABLE').Count -and
        ($Report.scope_mode -ne 'explicit-push-range' -or $Report.base_commit -cnotmatch '^[0-9a-f]{40}$')) { throw 'Missing exemption evidence' }
    if(@($Report.checks | Where-Object status -ne 'NOT_APPLICABLE').Count -eq 0){return 'NOT_REQUIRED'}
    if (@($Report.checks | Where-Object status -eq 'PENDING').Count) { return 'WAIT' }
    if (@($Report.checks | Where-Object status -eq 'FAIL').Count) { return 'FAIL' }
    return 'PASS'
}

function Get-CiNotificationText([string]$TaskId, [string]$Commit, [string]$Result) {
    $summary = switch ($Result) {
        'PASS' { '필수 CI 모두 성공' }
        'FAIL' { '필수 CI 실패 또는 취소 등 통과하지 못한 결과 발생' }
        'ERROR' { 'CI 조회 오류가 반복되어 감시 중단' }
        'TIMEOUT' { 'CI 확인 제한 시간 도달, 결과 미확인' }
        'NOT_REQUIRED' { '변경 범위상 원격 CI 대상 없음(통과 판정 아님)' }
        default { throw 'Invalid notification result' }
    }
    return "$TaskId $($Commit.Substring(0,7)): $summary. 대화에 CI 확인 후 이어서 진행이라고 알려주세요."
}
