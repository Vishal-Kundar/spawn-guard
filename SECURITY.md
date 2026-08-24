# Security Policy

## Scope

spawn-guard is a Claude Code skill consisting of:
- A SKILL.md instruction file (no executable code)
- PreToolUse hook scripts (PowerShell and Bash) that read stdin and a config file, then output a JSON decision

## What this skill does NOT do

- **No network access**: the hook makes no HTTP requests, DNS lookups, or outbound connections
- **No secrets**: the config file (`~/.claude/spawn-guard.json`) contains only model/effort/output preferences and an enforcement mode. No API keys, tokens, or credentials
- **No code execution**: the hook does not eval, exec, or run any user-supplied code. It reads JSON from stdin, compares strings against a config file, and writes JSON to stdout
- **No file mutation**: the hook does not write, delete, or modify any files. Config changes are made by Claude following the SKILL.md instructions, not by the hook itself
- **No data exfiltration**: no telemetry, analytics, or phone-home behavior

## Trust model

- The config file at `~/.claude/spawn-guard.json` is trusted input (written by the user or by Claude on user request)
- The session override file at `~/.claude/spawn-guard-session.json` is trusted input with a 24-hour TTL
- Hook stdin (tool call JSON from Claude Code) is **untrusted** for parsing and output construction. The `tool_input` fields are model-generated content that could contain adversarial strings. The hook uses safe JSON serializers (`ConvertTo-Json` on Windows, `jq` on Unix) to prevent injection through these values
- The hook treats all input fields as data, never as instructions to execute

## Supported versions

Only the latest version is supported with security updates.

## Reporting a vulnerability

If you find a security issue, please use [GitHub's private security advisory feature](https://github.com/Vishal-Kundar/spawn-guard/security/advisories/new) to report it privately. Do not open a public issue for security vulnerabilities. There is no bug bounty program.

For issues in Claude Code itself (the harness, hooks system, or tool execution), report to Anthropic at https://github.com/anthropics/claude-code/issues.
