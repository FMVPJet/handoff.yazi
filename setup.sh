#!/bin/bash
# Handoff.yazi post-installation setup guide

set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAZI_CONFIG="$HOME/.config/yazi"
KEYMAP_FILE="$YAZI_CONFIG/keymap.toml"

echo "🚀 Handoff.yazi Setup"
echo "===================="
echo

# Check dependencies
echo "📋 Checking dependencies..."
MISSING=()
for cmd in swift ssh rsync fzf zsh; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "⚠️  Missing dependencies: ${MISSING[*]}"
    echo "   Install with: brew install ${MISSING[*]}"
    echo
else
    echo "✅ All dependencies found"
    echo
fi

# Keymap setup
echo "⌨️  Setting up key bindings..."
if [ -f "$KEYMAP_FILE" ]; then
    if grep -q "plugin handoff" "$KEYMAP_FILE" 2>/dev/null; then
        echo "✅ Key bindings already configured"
    else
        echo "📝 To add key bindings, run:"
        echo "   cat \"$PLUGIN_DIR/keymap.toml\" >> \"$KEYMAP_FILE\""
        echo
        read -p "   Add them now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cat "$PLUGIN_DIR/keymap.toml" >> "$KEYMAP_FILE"
            echo "✅ Key bindings added"
        fi
    fi
else
    echo "⚠️  Keymap file not found: $KEYMAP_FILE"
    echo "   Create it first, then run:"
    echo "   cat \"$PLUGIN_DIR/keymap.toml\" >> \"$KEYMAP_FILE\""
fi
echo

# Config customization
echo "⚙️  Configuration:"
echo "   Edit share apps: $PLUGIN_DIR/config.lua"
echo "   Advanced options: cache_dir, archive_dir, timeouts, etc."
echo

# Usage hint
echo "🎯 Usage:"
echo "   Press \\ in Yazi, then:"
echo "     c - Copy       z - Archive    x - Extract"
echo "     s - Share      r - Remote     o - Open"
echo
echo "📖 Full docs: $PLUGIN_DIR/README.md"
echo
echo "✨ Setup complete! Restart Yazi to use the new bindings."
