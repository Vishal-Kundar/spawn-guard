# spawn-guard PreToolUse hook (Windows)
# Enforces model/effort defaults on Agent and Workflow tool calls
# Config: ~/.claude/spawn-guard.json
# Session overrides: ~/.claude/spawn-guard-session.json

$ErrorActionPreference = 'SilentlyContinue'

try {
    $json = [Console]::In.ReadToEnd()
    $hookData = $json | ConvertFrom-Json
} catch {
    exit 0
}

$toolName = $hookData.tool_name
if ($toolName -ne 'Agent' -and $toolName -ne 'Workflow') { exit 0 }

$configPath = Join-Path $env:USERPROFILE '.claude\spawn-guard.json'
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
$enforcement = if ($config.enforcement) { $config.enforcement } else { 'auto-correct' }

# Check session override (expires after 24h)
$overridePath = Join-Path $env:USERPROFILE '.claude\spawn-guard-session.json'
if (Test-Path $overridePath) {
    try {
        $override = Get-Content $overridePath -Raw | ConvertFrom-Json
        $ts = [datetime]::Parse($override.timestamp)
        if (([datetime]::UtcNow - $ts).TotalHours -lt 24) {
            if ($override.model) { $effectiveModel = Normalize-Model $override.model }
            if ($override.effort) { $effectiveEffort = $override.effort.ToLower().Trim() }
        }
    } catch {}
}

function Write-Decision {
    param([string]$Decision, [string]$Reason)
    $escapedReason = $Reason -replace '"', '\"' -replace '\\', '\\\\'
    Write-Output "{`"decision`":`"$Decision`",`"reason`":`"$escapedReason`"}"
}

function Decide {
    param([string]$Reason)
    if ($enforcement -eq 'warn') {
        Write-Decision -Decision 'approve' -Reason $Reason
    } else {
        Write-Decision -Decision 'block' -Reason $Reason
    }
}

# --- Agent tool checks ---
if ($toolName -eq 'Agent') {
    $toolInput = $hookData.tool_input
    $requestedModel = Normalize-Model $toolInput.model

    if ($requestedModel -and $effectiveModel -and $requestedModel -ne $effectiveModel) {
        Decide "Spawn Guard: model mismatch. Requested '$requestedModel', configured default is '$effectiveModel'. Re-spawn with model='$effectiveModel'."
        exit 0
    }
}

# --- Workflow tool checks ---
if ($toolName -eq 'Workflow') {
    $script = $hookData.tool_input.script
    if (-not $script) { exit 0 }

    # Check model in agent() opts
    if ($effectiveModel) {
        $modelPattern = "model:\s*['""](\w+)['""]"
        $modelMatches = [regex]::Matches($script, $modelPattern)
        foreach ($m in $modelMatches) {
            $found = Normalize-Model $m.Groups[1].Value
            if ($found -ne $effectiveModel) {
                Decide "Spawn Guard: workflow script uses model '$found', configured default is '$effectiveModel'. Update to model: '$effectiveModel'."
                exit 0
            }
        }
    }

    # Check effort in agent() opts
    if ($effectiveEffort) {
        $effortPattern = "effort:\s*['""](\w+)['""]"
        $effortMatches = [regex]::Matches($script, $effortPattern)
        foreach ($m in $effortMatches) {
            $found = $m.Groups[1].Value
            if ($found -ne $effectiveEffort) {
                Decide "Spawn Guard: workflow script uses effort '$found', configured default is '$effectiveEffort'. Update to effort: '$effectiveEffort'."
                exit 0
            }
        }
    }
}

exit 0
