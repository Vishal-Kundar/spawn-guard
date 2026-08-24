---
name: spawn-guard
description: Enforce model, effort, and output defaults on every subagent spawn with per-chat overrides and auto-correction
whenToUse: When the user wants to configure, check, or change subagent spawn defaults (model, effort, output style), or when they say "use X model for this chat"
---

# Spawn Guard

Enforce consistent model, effort, and output style across every subagent spawn (Agent tool and Workflow `agent()` calls). Catches misconfigured spawns via a PreToolUse hook and auto-corrects them.

## Invocation Routing

Parse the user's invocation to determine intent:

| Invocation | Action |
|---|---|
| `/spawn-guard` (no args) | Show status or run first-time setup |
| `/spawn-guard setup` | Run first-time setup (even if already configured) |
| `/spawn-guard status` | Show current config and hook status |
| `/spawn-guard set <key> <value>` | Change a default (e.g., `set model sonnet`) |
| `/spawn-guard override <key> <value>` | Set a per-chat override for this session |
| `/spawn-guard clear-override` | Remove all per-chat overrides |
| `/spawn-guard disable` | Temporarily disable enforcement |
| `/spawn-guard enable` | Re-enable enforcement |
| `/spawn-guard uninstall` | Remove hook, config, and CLAUDE.md snippet |

---

## First-Time Setup

Run this flow when no config exists at `~/.claude/spawn-guard.json`, or when the user explicitly says `setup`.

### Step 1: Ask for defaults

Use `AskUserQuestion` with these questions (all in one call):

**Question 1 - Default model:**
- Header: "Model"
- Question: "What model should subagents use by default?"
- Options: Opus, Sonnet, Haiku, Fable
- multiSelect: false
- The user may select "Other" and type a custom model string (e.g., `claude-opus-4-6[1m]`, `claude-sonnet-5`, or any future model ID). Store the exact string they provide. The hook normalizer handles known families automatically (anything containing "opus" resolves to `opus` for comparison), but truly novel model IDs are compared as literal strings.

**Question 2 - Default effort:**
- Header: "Effort"
- Question: "What reasoning effort should subagents use by default?"
- Options: low, medium, high, xhigh, max
- multiSelect: false

**Question 3 - Output style:**
- Header: "Output"
- Question: "How verbose should subagent output be?"
- Options:
  - concise (short, results-first responses)
  - normal (standard detail level)
  - verbose (thorough, detailed responses)
- multiSelect: false

**Question 4 - Enforcement mode:**
- Header: "Enforcement"
- Question: "What should happen when a subagent is spawned with wrong settings?"
- Options:
  - auto-correct (block and let Claude retry with correct settings)
  - warn (allow but show a warning)
  - block (block and require manual fix)
- multiSelect: false

### Step 2: Write config

Write the config to `~/.claude/spawn-guard.json`:

```json
{
  "version": "1.0.0",
  "enabled": true,
  "defaults": {
    "model": "<user-choice>",
    "effort": "<user-choice>",
    "output": "<user-choice>"
  },
  "enforcement": "<user-choice>"
}
```

### Step 3: Install the hook

Determine the platform and install the appropriate hook:

**On Windows (win32):**
1. Copy the hook script from the skill's installed directory to `~/.claude/hooks/spawn-guard.ps1`
   - The installed skill directory is where THIS SKILL.md file lives (check its path)
   - The hook source is at `hooks/spawn-guard.ps1` relative to the skill root
   - If the source hook file is NOT found at the relative path, check `~/.claude/skills/*/hooks/spawn-guard.ps1` via glob
   - If STILL not found, generate the hook inline using the **Hook Script: PowerShell** section below
2. Add the hook to `~/.claude/settings.json` under `hooks.PreToolUse`:

```json
{
  "matcher": "Agent|Workflow",
  "hooks": [
    {
      "type": "command",
      "command": "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"<HOME>\\.claude\\hooks\\spawn-guard.ps1\"",
      "timeout": 5
    }
  ]
}
```

Replace `<HOME>` with the actual home directory path. Append to the existing `PreToolUse` array if one exists; do not overwrite other hooks.

**On macOS/Linux (darwin/linux):**
1. Copy `hooks/spawn-guard.sh` to `~/.claude/hooks/spawn-guard.sh`
   - Same fallback logic as Windows if source not found
   - Run `chmod +x ~/.claude/hooks/spawn-guard.sh`
2. Add to `~/.claude/settings.json`:

```json
{
  "matcher": "Agent|Workflow",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/spawn-guard.sh",
      "timeout": 5
    }
  ]
}
```

### Step 4: Add CLAUDE.md snippet

Append the following to the user's global CLAUDE.md (`~/.claude/CLAUDE.md`). Place it after existing content. Use the exact delimiters shown:

```
<!-- SPAWN-GUARD:START -->
## Spawn Guard (auto-enforced)
Before spawning any subagent (Agent tool or Workflow agent()):
1. Read `~/.claude/spawn-guard.json` for defaults (model, effort, output)
2. Check `~/.claude/spawn-guard-session.json` for per-chat overrides (takes precedence over defaults)
3. Apply the resolved model and effort to the Agent tool's `model` parameter or Workflow `agent()` opts
4. For output style: if set to "concise", append "Keep your response concise and focused." to the subagent prompt; if "verbose", append "Be thorough and detailed in your response."
5. If the user explicitly specifies different settings for a specific spawn, honor that one-time override
When the user says "use [model] for this chat", "set effort to [level]", or similar per-chat directives:
- Write the override to `~/.claude/spawn-guard-session.json` as `{"model":"...","effort":"...","output":"...","timestamp":"<ISO-8601>"}`
- Only include the fields being overridden; omitted fields fall back to defaults
<!-- SPAWN-GUARD:END -->
```

### Step 5: Confirm

Tell the user setup is complete and that they should **restart Claude Code** (or start a new session) for the hook to take effect. Show:
- The configured defaults
- Hook installation status
- That a restart is needed to activate the hook
- How to change settings (`/spawn-guard set model sonnet`)
- How to set temporary overrides (`/spawn-guard override model sonnet` or just say "use sonnet for this chat")

---

## Show Status

Read `~/.claude/spawn-guard.json` and display:
- Enabled/disabled state
- Default model, effort, output
- Enforcement mode
- Whether a session override is active (check `~/.claude/spawn-guard-session.json`)
- Hook installation status (check if the hook entry exists in `~/.claude/settings.json`)

---

## Change a Setting

For `/spawn-guard set <key> <value>`:

Valid keys and values:
- `model`: opus, sonnet, haiku, fable, or any custom model ID (e.g., `claude-opus-4-6[1m]`, `claude-sonnet-5`). Custom IDs are stored as-is; known families are normalized for comparison.
- `effort`: low, medium, high, xhigh, max
- `output`: concise, normal, verbose
- `enforcement`: auto-correct, warn, block

Read the config, update the specified field, write it back. Confirm the change.

---

## Per-Chat Override

For `/spawn-guard override <key> <value>`:

Write or update `~/.claude/spawn-guard-session.json` with the override and a timestamp.

When the user says things like "use sonnet for this chat" or "low effort for subagents today" outside of the slash command, the CLAUDE.md snippet instructs Claude to write the session override automatically.

---

## Disable / Enable

Set `"enabled": false` or `true` in `~/.claude/spawn-guard.json`. When disabled, the hook allows all spawns without checking.

---

## Uninstall

1. Remove the hook entry from `~/.claude/settings.json` (the one matching `spawn-guard`)
2. Delete `~/.claude/hooks/spawn-guard.ps1` (or `.sh`)
3. Delete `~/.claude/spawn-guard.json`
4. Delete `~/.claude/spawn-guard-session.json` if it exists
5. Remove the `<!-- SPAWN-GUARD:START -->` ... `<!-- SPAWN-GUARD:END -->` block from `~/.claude/CLAUDE.md`

---

## Hook Script: PowerShell

If the hook file cannot be found in the skill's installed directory, generate it inline with this content:

```powershell
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
        $tsRaw = $override.timestamp
        if ($tsRaw -is [datetime]) {
            $ts = $tsRaw.ToUniversalTime()
        } else {
            $ts = [DateTimeOffset]::Parse([string]$tsRaw).UtcDateTime
        }
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
```

## Hook Script: Bash

```bash
#!/usr/bin/env bash
# spawn-guard PreToolUse hook (macOS/Linux)
# Enforces model/effort defaults on Agent and Workflow tool calls
# Requires: bash 4+, jq

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" != "Agent" && "$TOOL_NAME" != "Workflow" ]] && exit 0

if [[ "$TOOL_NAME" == "Agent" ]]; then
    SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty')
    [[ "$SUBAGENT_TYPE" == "fork" ]] && exit 0
fi

CONFIG_PATH="$HOME/.claude/spawn-guard.json"
[[ ! -f "$CONFIG_PATH" ]] && exit 0

ENABLED=$(jq -r 'if .enabled == false then "false" else "true" end' "$CONFIG_PATH")
[[ "$ENABLED" == "false" ]] && exit 0

normalize_model() {
    local m
    m=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$m" in
        *opus*)   echo "opus" ;;
        *sonnet*) echo "sonnet" ;;
        *haiku*)  echo "haiku" ;;
        *fable*)  echo "fable" ;;
        *)        echo "$m" ;;
    esac
}

DEFAULTS_MODEL=$(jq -r '.defaults.model // empty' "$CONFIG_PATH")
DEFAULTS_EFFORT=$(jq -r '.defaults.effort // empty' "$CONFIG_PATH" | tr '[:upper:]' '[:lower:]')
ENFORCEMENT=$(jq -r '.enforcement // "auto-correct"' "$CONFIG_PATH" | tr '[:upper:]' '[:lower:]')

EFFECTIVE_MODEL=$(normalize_model "$DEFAULTS_MODEL")
EFFECTIVE_EFFORT="$DEFAULTS_EFFORT"

OVERRIDE_PATH="$HOME/.claude/spawn-guard-session.json"
if [[ -f "$OVERRIDE_PATH" ]]; then
    OVERRIDE_TS=$(jq -r '.timestamp // empty' "$OVERRIDE_PATH")
    if [[ -n "$OVERRIDE_TS" ]]; then
        OVERRIDE_EPOCH=0
        if OVERRIDE_EPOCH=$(date -d "$OVERRIDE_TS" +%s 2>/dev/null); then
            :
        else
            CLEAN_TS=$(printf '%s' "$OVERRIDE_TS" | sed 's/\.[0-9]*Z$//' | sed 's/Z$//')
            if OVERRIDE_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$CLEAN_TS" +%s 2>/dev/null); then
                :
            else
                OVERRIDE_EPOCH=0
            fi
        fi
        NOW_EPOCH=$(date +%s)
        DIFF=$(( NOW_EPOCH - OVERRIDE_EPOCH ))
        if (( DIFF >= 0 && DIFF < 86400 )); then
            OV_MODEL=$(jq -r '.model // empty' "$OVERRIDE_PATH")
            OV_EFFORT=$(jq -r '.effort // empty' "$OVERRIDE_PATH")
            [[ -n "$OV_MODEL" ]] && EFFECTIVE_MODEL=$(normalize_model "$OV_MODEL")
            [[ -n "$OV_EFFORT" ]] && EFFECTIVE_EFFORT=$(printf '%s' "$OV_EFFORT" | tr '[:upper:]' '[:lower:]')
        fi
    fi
fi

decide() {
    local message="$1"
    local correction="${2:-}"
    if [[ "$ENFORCEMENT" == "warn" ]]; then
        >&2 printf 'spawn-guard warning: %s\n' "$message"
        exit 0
    elif [[ "$ENFORCEMENT" == "block" ]]; then
        jq -n --arg r "Spawn Guard: $message Do not retry automatically. Ask the user how to proceed." \
            '{decision: "block", reason: $r}'
    else
        jq -n --arg r "Spawn Guard: $message $correction" \
            '{decision: "block", reason: $r}'
    fi
}

if [[ "$TOOL_NAME" == "Agent" ]]; then
    RAW_REQUESTED=$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty')
    REQUESTED_MODEL=$(normalize_model "$RAW_REQUESTED")
    if [[ -n "$REQUESTED_MODEL" && -n "$EFFECTIVE_MODEL" && "$REQUESTED_MODEL" != "$EFFECTIVE_MODEL" ]]; then
        decide "model mismatch. Requested '$REQUESTED_MODEL', configured default is '$EFFECTIVE_MODEL'." "Re-spawn with model='$EFFECTIVE_MODEL'."
        exit 0
    fi
fi

if [[ "$TOOL_NAME" == "Workflow" ]]; then
    SCRIPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.script // empty')

    if [[ -n "$SCRIPT" && -n "$EFFECTIVE_MODEL" ]]; then
        FOUND_MODELS=$(printf '%s' "$SCRIPT" | grep -oE "model:[[:space:]]*['\"][^'\"]+['\"]" | sed "s/model:[[:space:]]*['\"]//;s/['\"]$//" || true)
        for RAW_MODEL in $FOUND_MODELS; do
            MODEL=$(normalize_model "$RAW_MODEL")
            if [[ "$MODEL" != "$EFFECTIVE_MODEL" ]]; then
                decide "workflow uses model '$MODEL', configured default is '$EFFECTIVE_MODEL'." "Update to model: '$EFFECTIVE_MODEL'."
                exit 0
            fi
        done
    fi

    if [[ -n "$SCRIPT" && -n "$EFFECTIVE_EFFORT" ]]; then
        FOUND_EFFORTS=$(printf '%s' "$SCRIPT" | grep -oE "effort:[[:space:]]*['\"][^'\"]+['\"]" | sed "s/effort:[[:space:]]*['\"]//;s/['\"]$//" || true)
        for RAW_EFFORT in $FOUND_EFFORTS; do
            EFFORT=$(printf '%s' "$RAW_EFFORT" | tr '[:upper:]' '[:lower:]')
            if [[ "$EFFORT" != "$EFFECTIVE_EFFORT" ]]; then
                decide "workflow uses effort '$EFFORT', configured default is '$EFFECTIVE_EFFORT'." "Update to effort: '$EFFECTIVE_EFFORT'."
                exit 0
            fi
        done
    fi
fi

exit 0
```

---

## Enforcement Behavior Reference

| Layer | What it enforces | How |
|---|---|---|
| CLAUDE.md snippet | Model, effort, output style | Claude applies defaults proactively before spawning |
| PreToolUse hook | Model (Agent), model + effort (Workflow) | Hard gate: blocks/warns on mismatch |
| Prompt injection | Output style (concise/verbose) | Appended to subagent prompt text |

**What each enforcement mode does:**
- **auto-correct**: Hook blocks the wrong spawn. Claude sees the block reason and re-spawns with correct settings. From the user's perspective, it looks like a brief retry.
- **warn**: Hook exits silently (no decision output). The spawn proceeds through normal permission flow. The CLAUDE.md soft layer handles enforcement proactively.
- **block**: Hook blocks with a reason that instructs Claude not to retry automatically and to ask the user how to proceed.

**Limitations (tell the user during setup):**
- The Agent tool has no `effort` parameter. Effort is only enforceable on Workflow `agent()` calls. For Agent spawns, effort is inherited from the session's global effort level.
- Output style is enforced via prompt text, not a parameter. It's soft enforcement.
- The Workflow script check is regex-based (not a full JS parser). It catches `model: 'xxx'` and `effort: 'xxx'` patterns but could miss computed values.
- Spawns that omit the `model` parameter bypass the hook check. The CLAUDE.md soft layer handles these.
- Fork spawns (`subagent_type: "fork"`) are exempt from model checks since forks always inherit the parent model.
- Temporary overrides (`spawn-guard-session.json`) apply to all concurrent Claude Code sessions, not just the current one.
- Hook registration changes (install/uninstall) require restarting Claude Code to take effect.
