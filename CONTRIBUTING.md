# Contributing to spawn-guard

Thanks for your interest in contributing.

## How to Contribute

1. **Report bugs** -- Open an issue describing what happened, what you expected, and your platform (Windows/macOS/Linux).

2. **Suggest features** -- Open an issue with the use case. Explain what you're trying to do, not just what you want the tool to do.

3. **Submit a PR** -- Fork the repo, make your changes on a branch, and open a pull request.

## Development Setup

1. Clone the repo
2. The skill is a single `SKILL.md` file plus hook scripts in `hooks/`
3. To test locally, copy the hook to `~/.claude/hooks/` and register it in `~/.claude/settings.json`

## Testing

Test hook scripts by piping mock JSON to them:

```bash
# Test a block (wrong model)
echo '{"tool_name":"Agent","tool_input":{"prompt":"test","model":"haiku"}}' | \
  bash hooks/spawn-guard.sh

# Test an allow (correct model)
echo '{"tool_name":"Agent","tool_input":{"prompt":"test","model":"opus"}}' | \
  bash hooks/spawn-guard.sh
```

You need a `~/.claude/spawn-guard.json` config file in place for the hook to enforce anything.

## Guidelines

- Keep the hook scripts fast (under 500ms). They run on every Agent/Workflow call.
- The hook must fail open: if the config is missing or malformed, exit 0 (allow).
- No network calls in the hook. Ever.
- Test on both PowerShell and Bash when making hook changes.

## Code Style

- PowerShell: follow the patterns in `hooks/spawn-guard.ps1`. Use `ConvertTo-Json` for output, never hand-rolled escaping.
- Bash: `set -euo pipefail`, require `jq`, use `jq -n --arg` for JSON output, handle both GNU and BSD date. Use `tr '[:upper:]' '[:lower:]'` for lowercasing (not `${var,,}` which requires bash 4+). Use `grep -oE` (not `grep -P` which is unavailable on macOS).
- No dependencies beyond what ships with the OS (plus jq on Unix)
- The `hooks/` directory is the canonical source for hook scripts. The inline scripts in SKILL.md are fallbacks and must match.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
