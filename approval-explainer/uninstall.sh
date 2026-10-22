#!/usr/bin/env bash
# Deactivate the approval-explainer hook. Files stay in place unless --purge.
set -euo pipefail

VH="\${VIBE_HOME:-$HOME/.vibe}"
DEST="$VH/plugins/approval-explainer"
HOOKS="$VH/hooks.toml"

if [ -f "$HOOKS" ]; then
  python3 - "$HOOKS" <<'PY'
import re
import sys

hooks_path = sys.argv[1]
with open(hooks_path, encoding="utf-8") as fh:
    text = fh.read()

parts = re.split(r"(?m)^\[\[hooks\]\]\s*$", text)
preamble, blocks = parts[0], parts[1:]
kept = [
    b
    for b in blocks
    if re.search(r"""(?m)^\s*name\s*=\s*["']explain-approval["']""", b) is None
]

new = preamble.rstrip("\n")
for b in kept:
    new += "\n[[hooks]]" + b.rstrip("\n") + "\n"

with open(hooks_path, "w", encoding="utf-8") as fh:
    fh.write(new)
PY
  echo "Hook removed from $HOOKS"
else
  echo "No $HOOKS found; nothing to deactivate."
fi

if [ "\${1:-}" = "--purge" ]; then
  rm -rf "$DEST"
  echo "Removed $DEST"
else
  echo "Files kept at $DEST (rerun install.sh to re-enable, or pass --purge to delete)"
fi
