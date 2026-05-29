#!/bin/bash
set -e

# ── Claude Code settings merge (testable, no root, no install needed) ─────────
# Sets env.USE_BUILTIN_RIPGREP="0" in the given settings.json while preserving
# everything else. Honors SMARTRG_JSON_ENGINE=jq|python3|auto (default: auto)
# so the smoke test can exercise each code path. Returns non-zero if no JSON
# tool is available.
merge_claude_setting() {
    local settings="$1"
    local engine="${SMARTRG_JSON_ENGINE:-auto}"
    mkdir -p "$(dirname "$settings")"

    # Fresh / empty file → write a minimal valid settings file.
    if [ ! -s "$settings" ]; then
        printf '{\n  "env": { "USE_BUILTIN_RIPGREP": "0" }\n}\n' > "$settings"
        echo "✓ Created $settings (USE_BUILTIN_RIPGREP=0)"
        return 0
    fi

    if { [ "$engine" = "jq" ] || [ "$engine" = "auto" ]; } && command -v jq >/dev/null 2>&1; then
        local tmp; tmp="$(mktemp)"
        if jq '.env = (((.env // {}) | if type == "object" then . else {} end) + {"USE_BUILTIN_RIPGREP":"0"})' \
               "$settings" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            mv "$tmp" "$settings"
            echo "✓ Set USE_BUILTIN_RIPGREP=0 in $settings (jq)"
            return 0
        fi
        rm -f "$tmp"
    fi

    if { [ "$engine" = "python3" ] || [ "$engine" = "auto" ]; } && command -v python3 >/dev/null 2>&1; then
        if python3 - "$settings" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
    if not isinstance(d, dict): d = {}
except Exception:
    d = {}
if not isinstance(d.get("env"), dict):
    d["env"] = {}
d["env"]["USE_BUILTIN_RIPGREP"] = "0"
with open(p, "w") as f:
    json.dump(d, f, indent=2); f.write("\n")
PY
        then
            echo "✓ Set USE_BUILTIN_RIPGREP=0 in $settings (python3)"
            return 0
        fi
    fi

    echo "⚠️  Could not edit $settings (need jq or python3). Add manually:"
    echo '      "env": { "USE_BUILTIN_RIPGREP": "0" }'
    return 1
}

# Internal/convenience entrypoint: run ONLY the settings merge (no root, no
# install). Used by tests; also handy to re-apply the Claude config standalone.
#   ./install.sh --merge-claude-config [path]   (default: ~/.claude/settings.json)
if [ "${1:-}" = "--merge-claude-config" ]; then
    merge_claude_setting "${2:-$HOME/.claude/settings.json}"
    exit $?
fi

echo "🪶 smart-rg installer"
echo ""

# Flags:
#   --with-grep         also symlink `grep` -> shim (advanced; shadows system grep)
#   --no-claude-config  don't touch ~/.claude/settings.json
WITH_GREP=0
CONFIGURE_CLAUDE=1
for arg in "$@"; do
  case "$arg" in
    --with-grep) WITH_GREP=1 ;;
    --no-claude-config) CONFIGURE_CLAUDE=0 ;;
    -h|--help)
      echo "Usage: sudo ./install.sh [--with-grep] [--no-claude-config]"
      echo "  --with-grep             also intercept 'grep' (shadows system grep; off by default)"
      echo "  --no-claude-config      leave ~/.claude/settings.json untouched"
      echo "  --merge-claude-config [path]   (no root) only set USE_BUILTIN_RIPGREP=0 and exit"
      exit 0 ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
    echo "❌ Must run as root (writes to /usr/local/bin): sudo ./install.sh"
    exit 1
fi

# sudo sets $HOME to root's home — resolve the REAL invoking user instead.
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(eval echo "~$TARGET_USER")"

# --- locate or build the binary ---
if [ -f "./target/release/smart-rg" ]; then
    BIN="./target/release/smart-rg"
else
    echo "Building from source (cargo build --release)..."
    cargo build --release
    BIN="./target/release/smart-rg"
fi
echo "✓ Binary: $BIN"

# --- install + symlink ---
cp "$BIN" /usr/local/bin/smart-rg
ln -sf /usr/local/bin/smart-rg /usr/local/bin/rg
echo "✓ Installed: /usr/local/bin/smart-rg  (rg -> smart-rg)"

if [ "$WITH_GREP" -eq 1 ]; then
    ln -sf /usr/local/bin/smart-rg /usr/local/bin/grep
    echo "⚠️  grep -> smart-rg  (system grep shadowed everywhere; undo: rm /usr/local/bin/grep)"
fi

# --- configure Claude Code (it uses a BUNDLED rg unless USE_BUILTIN_RIPGREP=0) ---
if [ "$CONFIGURE_CLAUDE" -eq 1 ]; then
    merge_claude_setting "$TARGET_HOME/.claude/settings.json" || true
    chown -R "$TARGET_USER" "$TARGET_HOME/.claude" 2>/dev/null || true
fi

# --- verify PATH actually resolves to the shim ---
echo ""
echo "Verifying..."
RG_RESOLVED="$(command -v rg 2>/dev/null || echo 'NOT FOUND')"
echo "  rg → $RG_RESOLVED"
if [ "$RG_RESOLVED" != "/usr/local/bin/rg" ]; then
    echo "  ⚠️  PATH puts another rg first. For interception, /usr/local/bin must come"
    echo "      before it (e.g. Homebrew's /opt/homebrew/bin). Check: echo \$PATH"
fi

echo ""
echo "✅ smart-rg is ready."
echo "   See savings:  smart-rg stats"
echo "   HTML report:  smart-rg report -o report.html --open"
