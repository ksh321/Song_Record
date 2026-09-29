#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Worker','Reviewer')][string]$Role,
    [Parameter(Mandatory)][string]$PromptFile,
    [ValidateSet('Explore','Implement','Complex','Sensitive','Escalation')][string]$Risk = 'Implement'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$model = switch ($Risk) { Explore {'gpt-6-luna'} Sensitive {'gpt-6-astra'} Escalation {'gpt-6-astra'} default {'gpt-6-sol'} }
$effort = switch ($Risk) { Complex {'high'} Sensitive {'high'} Escalation {'xhigh'} default {'medium'} }
# No API fallback, automatic login, credit purchase or sandbox bypass.
$login = (& codex login status 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $login -notmatch 'Logged in using ChatGPT') { throw 'ChatGPT subscription login required; API authentication is not allowed' }
$prompt = Get-Content -LiteralPath $PromptFile -Raw
$outDir = Join-Path $root '.local/workflow'
New-Item -ItemType Directory -Force $outDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$prefix = Join-Path $outDir "$Role-$stamp"
$settings = [ordered]@{role=$Role; risk=$Risk; requested_model=$model; requested_reasoning=$effort; requested_service_tier='default'; fast_mode=$false; authentication='ChatGPT'; runtime_tier_verified=$false; input_mode='provided evidence; no tool use'; result="$prefix.md"}
$settings | ConvertTo-Json | Set-Content "$prefix.json" -Encoding utf8
# Evidence-only mode avoids nested Windows sandbox failures. Master supplies a scoped
# source bundle/diff. Worker proposes a patch; master applies it; separate Reviewer checks it.
$instruction = "Role: $Role. Use only the supplied evidence. Do not call tools or spawn agents. Reply in Korean. Do not claim tests ran or files changed. Worker: produce bounded concrete findings or a proposed patch. Reviewer: independently identify actionable defects and missing evidence; never approve unobserved execution. Standard/default requested and Fast off; runtime tier must remain unverified absent telemetry.`n"
($instruction + $prompt) | & codex exec --ignore-user-config --strict-config -c 'forced_login_method="chatgpt"' -c 'service_tier="default"' -c 'features.fast_mode=false' -c "model_reasoning_effort=`"$effort`"" -m $model -s read-only --ephemeral --color never -o "$prefix.md" - *> "$prefix.log"
$code = $LASTEXITCODE
Write-Host "Role=$Role model=$model reasoning=$effort exit=$code; result=$prefix.md; settings=$prefix.json"
if ($code -ne 0) { throw 'Agent failed. Preserve local evidence; do not retry with paid API or purchase credits.' }
Get-Content "$prefix.md"
