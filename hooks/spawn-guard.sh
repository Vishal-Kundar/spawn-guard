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
