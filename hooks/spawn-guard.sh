#!/usr/bin/env bash
# spawn-guard PreToolUse hook (macOS/Linux)
# Enforces model/effort defaults on Agent and Workflow tool calls
# Config: ~/.claude/spawn-guard.json
# Session overrides: ~/.claude/spawn-guard-session.json
# Requires: jq

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" != "Agent" && "$TOOL_NAME" != "Workflow" ]] && exit 0

CONFIG_PATH="$HOME/.claude/spawn-guard.json"
[[ ! -f "$CONFIG_PATH" ]] && exit 0

ENABLED=$(jq -r '.enabled // true' "$CONFIG_PATH")
[[ "$ENABLED" == "false" ]] && exit 0

normalize_model() {
    local m="${1,,}"  # lowercase
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
ENFORCEMENT=$(jq -r '.enforcement // "auto-correct"' "$CONFIG_PATH")

EFFECTIVE_MODEL=$(normalize_model "$DEFAULTS_MODEL")
EFFECTIVE_EFFORT="$DEFAULTS_EFFORT"

# Check session override (expires after 24h)
OVERRIDE_PATH="$HOME/.claude/spawn-guard-session.json"
if [[ -f "$OVERRIDE_PATH" ]]; then
    OVERRIDE_TS=$(jq -r '.timestamp // empty' "$OVERRIDE_PATH")
    if [[ -n "$OVERRIDE_TS" ]]; then
        # GNU date vs BSD date
        if OVERRIDE_EPOCH=$(date -d "$OVERRIDE_TS" +%s 2>/dev/null); then
            :
        elif OVERRIDE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${OVERRIDE_TS%%.*}" +%s 2>/dev/null); then
            :
        else
            OVERRIDE_EPOCH=0
        fi
        NOW_EPOCH=$(date +%s)
        DIFF=$(( NOW_EPOCH - OVERRIDE_EPOCH ))
        if (( DIFF < 86400 )); then
            OV_MODEL=$(jq -r '.model // empty' "$OVERRIDE_PATH")
            OV_EFFORT=$(jq -r '.effort // empty' "$OVERRIDE_PATH")
            [[ -n "$OV_MODEL" ]] && EFFECTIVE_MODEL=$(normalize_model "$OV_MODEL")
            [[ -n "$OV_EFFORT" ]] && EFFECTIVE_EFFORT="${OV_EFFORT,,}"
        fi
    fi
fi

decide() {
    local reason="$1"
    # Escape quotes for JSON
    reason=$(echo "$reason" | sed 's/"/\\"/g')
    if [[ "$ENFORCEMENT" == "warn" ]]; then
        printf '{"decision":"approve","reason":"%s"}\n' "$reason"
    else
        printf '{"decision":"block","reason":"%s"}\n' "$reason"
    fi
}

# --- Agent tool checks ---
if [[ "$TOOL_NAME" == "Agent" ]]; then
    REQUESTED_MODEL=$(normalize_model "$(echo "$INPUT" | jq -r '.tool_input.model // empty')")
    if [[ -n "$REQUESTED_MODEL" && -n "$EFFECTIVE_MODEL" && "$REQUESTED_MODEL" != "$EFFECTIVE_MODEL" ]]; then
        decide "Spawn Guard: model mismatch. Requested '$REQUESTED_MODEL', configured default is '$EFFECTIVE_MODEL'. Re-spawn with model='$EFFECTIVE_MODEL'."
        exit 0
    fi
fi

# --- Workflow tool checks ---
if [[ "$TOOL_NAME" == "Workflow" ]]; then
    SCRIPT=$(echo "$INPUT" | jq -r '.tool_input.script // empty')

    # Check model in agent() opts
    if [[ -n "$SCRIPT" && -n "$EFFECTIVE_MODEL" ]]; then
        FOUND_MODELS=$(echo "$SCRIPT" | grep -oP "model:\s*['\"](\K\w+)" 2>/dev/null || true)
        for RAW_MODEL in $FOUND_MODELS; do
            MODEL=$(normalize_model "$RAW_MODEL")
            if [[ "$MODEL" != "$EFFECTIVE_MODEL" ]]; then
                decide "Spawn Guard: workflow uses model '$MODEL', configured default is '$EFFECTIVE_MODEL'. Update to model: '$EFFECTIVE_MODEL'."
                exit 0
            fi
        done
    fi

    # Check effort in agent() opts
    if [[ -n "$SCRIPT" && -n "$EFFECTIVE_EFFORT" ]]; then
        FOUND_EFFORTS=$(echo "$SCRIPT" | grep -oP "effort:\s*['\"](\K\w+)" 2>/dev/null || true)
        for EFFORT in $FOUND_EFFORTS; do
            if [[ "$EFFORT" != "$EFFECTIVE_EFFORT" ]]; then
                decide "Spawn Guard: workflow uses effort '$EFFORT', configured default is '$EFFECTIVE_EFFORT'. Update to effort: '$EFFECTIVE_EFFORT'."
                exit 0
            fi
        done
    fi
fi

exit 0
