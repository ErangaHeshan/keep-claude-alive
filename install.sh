#!/bin/bash
# Installs Keep Claude Alive as a macOS LaunchAgent.
# Sources files from ./src when run from a clone, otherwise downloads them.
set -uo pipefail

REPO="ErangaHeshan/keep-claude-alive"
REF="${KCA_REF:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${REF}/src"

BASE="${HOME}/.keep-claude-alive"
APP="${BASE}/KeepClaudeAlive.app"
LABEL="local.keep-claude-alive"
AGENT="${HOME}/Library/LaunchAgents/${LABEL}.plist"
INTERVAL="${KCA_INTERVAL:-600}"
ACTIVE="${KCA_ACTIVE-05:00-00:00}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { red "✗ $*"; exit 1; }
ok()  { grn "✓ $*"; }

uninstall() {
  launchctl unload "$AGENT" 2>/dev/null
  rm -f "$AGENT"
  rm -rf "$BASE"
  ok "Uninstalled. Removed ${BASE} and ${AGENT}"
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

echo "Keep Claude Alive - installer"
echo

# ---------- prerequisite checks ----------

[ "$(uname -s)" = "Darwin" ] || die "macOS only (launchd). Detected: $(uname -s)"
ok "macOS $(sw_vers -productVersion)"

CLAUDE=""
for c in /opt/homebrew/bin/claude /usr/local/bin/claude \
         "${HOME}/.claude/local/claude" "${HOME}/.local/bin/claude" \
         "$(command -v claude 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && CLAUDE="$c" && break
done

if [ -z "$CLAUDE" ]; then
  red "✗ Claude Code CLI not found."
  command -v brew >/dev/null 2>&1 \
    || echo "  Install Homebrew first (https://brew.sh), then:"
  echo "    brew install --cask claude-code"
  echo "  Then re-run this installer."
  exit 1
fi
ok "Claude Code CLI: ${CLAUDE}"

# /usage is a local command - it costs no quota, so it doubles as the auth check.
if ! usage=$("$CLAUDE" -p "/usage" </dev/null 2>&1) \
   || ! printf '%s' "$usage" | grep -q 'Current session:'; then
  red "✗ Could not read usage non-interactively."
  echo "  Run 'claude' once, log in, exit, then re-run this installer."
  printf '%s\n' "$usage" | head -5 | sed 's/^/    /'
  exit 1
fi
ok "Authenticated - non-interactive mode works"
printf '  %s\n' "$(printf '%s' "$usage" | grep -m1 'Current session:')"

hm='([01][0-9]|2[0-3]):[0-5][0-9]'
if [ -n "$ACTIVE" ] && [ "$ACTIVE" != always ] \
   && ! [[ "$ACTIVE" =~ ^${hm}-${hm}$ ]]; then
  die "KCA_ACTIVE must be HH:MM-HH:MM (00:00-23:59) or 'always' (got '${ACTIVE}')"
fi
ok "Active hours: ${ACTIVE:-always}"

case "$INTERVAL" in
  ''|*[!0-9]*) die "KCA_INTERVAL must be a whole number of seconds (got '${INTERVAL}')" ;;
esac
[ "$INTERVAL" -ge 60 ] || die "KCA_INTERVAL must be at least 60 seconds (got '${INTERVAL}')"
ok "Check interval: ${INTERVAL}s"

# ---------- locate sources ----------

SRC=""
self="${BASH_SOURCE[0]:-}"
if [ -n "$self" ] && [ -f "$self" ]; then
  cand="$(cd "$(dirname "$self")" && pwd)/src"
  [ -d "$cand" ] && SRC="$cand"
fi

if [ -n "$SRC" ]; then
  ok "Using local sources: ${SRC}"
else
  command -v curl >/dev/null 2>&1 || die "curl not found"
  ok "Downloading sources from ${REPO}@${REF}"
fi
echo

# Copies from $SRC, or downloads. $1 = filename in src/, $2 = destination.
fetch() {
  local name="$1" dest="$2"
  if [ -n "$SRC" ]; then
    cp "${SRC}/${name}" "$dest" || die "missing source file: ${SRC}/${name}"
  else
    local enc="${name// /%20}"
    curl -fsSL --retry 2 "${RAW}/${enc}" -o "$dest" \
      || die "download failed: ${RAW}/${enc}"
  fi
  [ -s "$dest" ] || die "empty source file: ${name}"
}

# ---------- install ----------

launchctl unload "$AGENT" 2>/dev/null

mkdir -p "${APP}/Contents/MacOS" "$(dirname "$AGENT")"

# Create the log up front so `tail -f` works before the first ping.
touch "${BASE}/keepalive.log" "${BASE}/last-check"
echo "$(date '+%Y-%m-%d %H:%M:%S') installed - checking every ${INTERVAL}s, active ${ACTIVE:-always}" >> "${BASE}/keepalive.log"

fetch "keep-claude-alive"  "${APP}/Contents/MacOS/keep-claude-alive"
fetch "Keep Claude Alive"  "${APP}/Contents/MacOS/Keep Claude Alive"
fetch "Info.plist"         "${APP}/Contents/Info.plist"

tmpl="$(mktemp)"
fetch "local.keep-claude-alive.plist" "$tmpl"

bash -n "${APP}/Contents/MacOS/keep-claude-alive" || die "agent script failed syntax check"
bash -n "${APP}/Contents/MacOS/Keep Claude Alive" || die "launcher failed syntax check"
plutil -lint "${APP}/Contents/Info.plist" >/dev/null || die "Info.plist is malformed"
ok "Sources verified"

chmod +x "${APP}/Contents/MacOS/keep-claude-alive" "${APP}/Contents/MacOS/Keep Claude Alive"

# Nested executable must be signed before the bundle that contains it.
codesign --force --sign - "${APP}/Contents/MacOS/keep-claude-alive" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1 \
  && ok "Bundle signed (ad-hoc)" \
  || ylw "! Ad-hoc signing failed - harmless, the agent still runs"

# Bake in the binary we just verified, so the agent never has to re-guess.
sed -e "s|__APP__|${APP}|g" -e "s|__BASE__|${BASE}|g" -e "s|__INTERVAL__|${INTERVAL}|g" \
    -e "s|__CLAUDE__|${CLAUDE}|g" -e "s|__ACTIVE__|${ACTIVE}|g" \
  "$tmpl" > "$AGENT"
rm -f "$tmpl"
plutil -lint "$AGENT" >/dev/null || die "generated LaunchAgent is malformed: ${AGENT}"
ok "LaunchAgent written (every ${INTERVAL}s)"

launchctl load "$AGENT" || die "launchctl load failed"
# launchd registers asynchronously, so poll rather than checking once.
listed=""
for _ in 1 2 3 4 5 6; do
  if launchctl list | grep -q "$LABEL"; then listed=1; break; fi
  sleep 0.5
done
[ -n "$listed" ] \
  && ok "Loaded and running" \
  || ylw "! Loaded but not listed - check: launchctl list | grep ${LABEL}"

echo
grn "Done."
echo "  Log:       tail -f ${BASE}/keepalive.log"
echo "  Uninstall: bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh) --uninstall"
