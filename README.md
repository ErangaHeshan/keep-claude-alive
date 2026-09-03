# Keep Claude Alive

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

macOS LaunchAgent that keeps a Claude subscription usage window open.

Claude meters usage in rolling 5-hour windows that expire on their own. This checks
every 10 minutes whether a window is open and, if not, sends one Haiku prompt to
open a fresh one. Cost: one minimal call per window - checking is free.

This is a quota-gaming tool. It spends a slice of your allowance so a window is
always available.

## Prerequisites

- macOS
- Claude Code - `brew install --cask claude-code`
- Logged in to Claude CLI - `claude -p "hi" --model haiku` (if this prompts for login instead of replying, make sure to login)

The installer checks all of these and stops with the fix if any are missing.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ErangaHeshan/keep-claude-alive/main/install.sh)
```

Idempotent - re-run to upgrade, repair, or change a setting.

### Options

| Setting | Default | What it does |
|---|---|---|
| `KCA_INTERVAL` | `600` | How often to check whether your Claude session is still open, in seconds. |
| `KCA_ACTIVE` | `05:00-00:00` | Only ping inside these hours. `always` to never stop. |
| `KCA_REF` | `main` | Branch or tag to install from. |

e.g.: Prefix the install command with a setting to change it. To check every 5
minutes instead of the default 10:

```bash
KCA_INTERVAL=300 bash <(curl -fsSL https://raw.githubusercontent.com/ErangaHeshan/keep-claude-alive/main/install.sh)
```

**Pro tip 💡:** Set `KCA_ACTIVE` to start earlier than you normally start your day.
The first window opens then, so it is already part-spent by the time you sit down.

## Verify

```bash
launchctl list | grep keep-claude-alive                        # app is running in background
tail -f ~/.keep-claude-alive/keepalive.log                     # what it has done
ls -l ~/.keep-claude-alive/last-check                          # when it last checked
~/.keep-claude-alive/KeepClaudeAlive.app/Contents/MacOS/keep-claude-alive   # run a check now
```

The log is silent while a window is open, so use `last-check` to tell a running
agent from a stopped one.

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ErangaHeshan/keep-claude-alive/main/install.sh) --uninstall
```

## Notes

- Starts at login, not boot. A sleeping Mac runs nothing.
- "Item from unidentified developer" in Login Items is expected - no Developer ID.
- Parses `/usage` output, which Anthropic can change. On a parse failure it assumes
  a window is open and logs a warning rather than pinging every 10 minutes.

## License

[MIT](LICENSE) © Eranga Heshan
