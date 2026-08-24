# spawn-guard PreToolUse hook (Windows)
# Enforces model/effort defaults on Agent and Workflow tool calls

$ErrorActionPreference = 'SilentlyContinue'

try {
    $json = [Console]::In.ReadToEnd()
    $hookData = $json | ConvertFrom-Json
} catch {
    exit 0
}

$toolName = $hookData.tool_name
if ($toolName -ne 'Agent' -and $toolName -ne 'Workflow') { exit 0 }

if ($toolName -eq 'Agent' -and $hookData.tool_input.subagent_type -eq 'fork') { exit 0 }

$homePath = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$configPath = Join-Path $homePath '.claude\spawn-guard.json'
if (-not (Test-Path $configPath)) { exit 0 }

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch { exit 0 }

if ($config.enabled -eq $false) { exit 0 }

$defaults = $config.defaults
if (-not $defaults) { exit 0 }

function Normalize-Model {
    param([string]$Name)
    if (-not $Name) { return $Name }
    $n = $Name.ToLower().Trim()
    if ($n -match 'opus')   { return 'opus' }
    if ($n -match 'sonnet') { return 'sonnet' }
    if ($n -match 'haiku')  { return 'haiku' }
    if ($n -match 'fable')  { return 'fable' }
    return $n
}

$effectiveModel = Normalize-Model $defaults.model
$effectiveEffort = if ($defaults.effort) { $defaults.effort.ToLower().Trim() } else { $null }
$enforcement = if ($config.enforcement) { $config.enforcement.ToLower().Trim() } else { 'auto-correct' }

$overridePath = Join-Path $homePath '.claude\spawn-guard-session.json'
if (Test-Path $overridePath) {
    try {
        $override = Get-Content $overridePath -Raw | ConvertFrom-Json
        $ts = [DateTimeOffset]::Parse($override.timestamp).UtcDateTime
        $age = ([datetime]::UtcNow - $ts).TotalHours
        if ($age -ge 0 -and $age -lt 24) {
            if ($override.model) { $effectiveModel = Normalize-Model $override.model }
            if ($override.effort) { $effectiveEffort = $override.effort.ToLower().Trim() }
        }
    } catch {}
}

function Decide {
    param([string]$Message, [string]$Correction)
    if ($enforcement -eq 'warn') {
        [Console]::Error.WriteLine("spawn-guard warning: $Message")
        exit 0
    }
    $reason = if ($enforcement -eq 'block') {
        "Spawn Guard: $Message Do not retry automatically. Ask the user how to proceed."
    } else {
        "Spawn Guard: $Message $Correction"
    }
    @{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
}

if ($toolName -eq 'Agent') {
    $requestedModel = Normalize-Model $hookData.tool_input.model

    if ($requestedModel -and $effectiveModel -and ($requestedModel -cne $effectiveModel)) {
        Decide "model mismatch. Requested '$requestedModel', configured default is '$effectiveModel'." "Re-spawn with model='$effectiveModel'."
        exit 0
    }
}

if ($toolName -eq 'Workflow') {
    $script = $hookData.tool_input.script
    if (-not $script) { exit 0 }

    if ($effectiveModel) {
        $modelPattern = "model:\s*['""]([A-Za-z0-9._\[\]-]+)['""]"
        $modelMatches = [regex]::Matches($script, $modelPattern)
        foreach ($m in $modelMatches) {
            $found = Normalize-Model $m.Groups[1].Value
            if ($found -cne $effectiveModel) {
                Decide "workflow script uses model '$found', configured default is '$effectiveModel'." "Update to model: '$effectiveModel'."
                exit 0
            }
        }
    }

    if ($effectiveEffort) {
        $effortPattern = "effort:\s*['""]([A-Za-z0-9._-]+)['""]"
        $effortMatches = [regex]::Matches($script, $effortPattern)
        foreach ($m in $effortMatches) {
            $found = $m.Groups[1].Value.ToLower().Trim()
            if ($found -ne $effectiveEffort) {
                Decide "workflow script uses effort '$found', configured default is '$effectiveEffort'." "Update to effort: '$effectiveEffort'."
                exit 0
            }
        }
    }
}

exit 0
