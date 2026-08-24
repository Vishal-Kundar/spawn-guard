# spawn-guard

**Stop subagents from running on the wrong model, effort, or output style.**

Set your defaults once. Every `Agent` and `Workflow` spawn is checked automatically. Wrong settings get auto-corrected before they waste your tokens.

## Install

```bash
npx skills add Vishal-Kundar/spawn-guard -g -y
```

Then run `/spawn-guard` in Claude Code to configure your defaults.

## Quick Start

```
/spawn-guard              # first-time setup wizard
/spawn-guard status       # show current config
/spawn-guard set model sonnet   # change default model
```

Or override per-chat without touching your defaults:

```
/spawn-guard override model sonnet
```

You can also just say it naturally: *"use sonnet for this chat"* and the guard picks it up.

## What It Enforces

| Setting | Agent tool | Workflow `agent()` |
|---------|-----------|-------------------|
| Model | Hook-enforced | Hook-enforced |
| Effort | Session-inherited | Hook-enforced |
| Output | Prompt-injected | Prompt-injected |

Two layers of enforcement:

1. **Soft** -- CLAUDE.md instructions tell Claude to apply your defaults proactively before every spawn. Handles most cases silently.
2. **Hard** -- PreToolUse hook catches anything that slips through. Blocks the wrong spawn, Claude auto-retries with correct settings.

## Configuration

Config lives at `~/.claude/spawn-guard.json`:

```json
{
  "version": "1.0.0",
  "enabled": true,
  "defaults": {
    "model": "opus",
    "effort": "high",
    "output": "concise"
  },
  "enforcement": "auto-correct"
}
```

| Setting | Values | Description |
|---------|--------|-------------|
| `model` | `opus` `sonnet` `haiku` `fable` or custom ID | Default model for subagents |
| `effort` | `low` `medium` `high` `xhigh` `max` | Default reasoning effort |
| `output` | `concise` `normal` `verbose` | Output verbosity |
| `enforcement` | `auto-correct` `warn` `block` | What happens on mismatch |

Model names are normalized: `claude-opus-4-6`, `claude-opus-4-6[1m]`, `Opus`, and `opus` all resolve to `opus`. No false blocks from format mismatches. You can also set a custom model ID for new or non-standard models -- these are compared as literal strings.

## Commands

| Command | What it does |
|---------|--------------|
| `/spawn-guard` | Show status or run setup |
| `/spawn-guard setup` | Re-run first-time setup |
| `/spawn-guard set <key> <value>` | Change a default |
| `/spawn-guard override <key> <value>` | Per-chat override |
| `/spawn-guard clear-override` | Remove per-chat overrides |
| `/spawn-guard disable` | Temporarily disable |
| `/spawn-guard enable` | Re-enable |
| `/spawn-guard uninstall` | Remove everything |

Per-chat overrides expire after 24 hours automatically.

## How It Works

The setup wizard (`/spawn-guard`) does three things:

1. **Writes your config** to `~/.claude/spawn-guard.json`
2. **Installs a PreToolUse hook** that intercepts `Agent` and `Workflow` tool calls, compares model/effort against your config, and blocks mismatches
3. **Adds a CLAUDE.md snippet** that tells Claude to apply your defaults proactively (so the hook rarely needs to fire)

The hook reads config fresh on every call, so changes via `/spawn-guard set` take effect immediately.

## Platform Support

| Platform | Hook | Requirements |
|----------|------|-------------|
| Windows | PowerShell (.ps1) | PowerShell 5.1+ (included) |
| macOS | Bash (.sh) | jq (`brew install jq`) |
| Linux | Bash (.sh) | jq (`sudo apt install jq`) |

## Limitations

- The `Agent` tool has no `effort` parameter. Effort enforcement only works on `Workflow` `agent()` calls. For `Agent` spawns, effort is inherited from the session's global setting.
- Output style is enforced by appending instructions to the subagent prompt. It depends on the subagent following them.
- Workflow script checking uses regex, not a JS parser. It catches `model: 'xxx'` and `effort: 'xxx'` but may false-positive on values in comments and can miss dynamically computed values.

## Uninstalling

Run `/spawn-guard uninstall`, or manually:

1. Remove the `Agent|Workflow` hook entry from `~/.claude/settings.json`
2. Delete `~/.claude/hooks/spawn-guard.ps1` (or `.sh`)
3. Delete `~/.claude/spawn-guard.json`
4. Delete `~/.claude/spawn-guard-session.json` if it exists
5. Remove the `<!-- SPAWN-GUARD:START -->` ... `<!-- SPAWN-GUARD:END -->` block from `~/.claude/CLAUDE.md`

## Security

This skill has no network access, stores no secrets, and executes no user code. The hook is read-only: it reads stdin (tool call JSON) and your config file, then outputs a JSON decision. See [SECURITY.md](SECURITY.md) for the full policy.

## License

[MIT](LICENSE)
