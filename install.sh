#!/bin/bash
set -e

echo "🪶 smart-rg installer"
echo ""

# --with-grep also symlinks `grep` -> shim. OFF by default because it shadows
# the system `grep` for EVERY process, and the shim speaks ripgrep's flags, not
# classic grep's — that can break scripts/tools that rely on real grep.
WITH_GREP=0
for arg in "$@"; do
  case "$arg" in
    --with-grep) WITH_GREP=1 ;;
    -h|--help)
      echo "Usage: sudo ./install.sh [--with-grep]"
      echo "  --with-grep   also intercept 'grep' (advanced; see warning in README)"
      exit 0 ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
    echo "❌ Must run as root (writes to /usr/local/bin): sudo ./install.sh"
    exit 1
fi

# --- locate or build the binary ---
if [ -f "./target/release/smart-rg" ]; then
    BIN="./target/release/smart-rg"
else
    echo "Building from source (cargo build --release)..."
    cargo build --release
    BIN="./target/release/smart-rg"
fi
echo "✓ Binary: $BIN"

# --- install ---
cp "$BIN" /usr/local/bin/smart-rg
ln -sf /usr/local/bin/smart-rg /usr/local/bin/rg
echo "✓ Installed: /usr/local/bin/smart-rg  (rg -> smart-rg)"

if [ "$WITH_GREP" -eq 1 ]; then
    ln -sf /usr/local/bin/smart-rg /usr/local/bin/grep
    echo "⚠️  grep -> smart-rg  (system grep is now shadowed everywhere; remove with: rm /usr/local/bin/grep)"
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

# --- Claude Code hint (it uses a VENDORED rg unless told otherwise) ---
if [ -f "$HOME/.claude/settings.json" ] && grep -q "USE_BUILTIN_RIPGREP" "$HOME/.claude/settings.json" 2>/dev/null; then
    echo "✓ Claude Code: USE_BUILTIN_RIPGREP already set"
else
    echo ""
    echo "⚠️  Claude Code uses its OWN bundled ripgrep by default — add this to"
    echo "    ~/.claude/settings.json so it uses the shim on your PATH:"
    echo '      "env": { "USE_BUILTIN_RIPGREP": "0" }'
fi

echo ""
echo "✅ smart-rg is ready."
echo "   See savings:  smart-rg stats"
echo "   HTML report:  smart-rg report -o report.html --open"
