#!/usr/bin/env bash
# Install or update the approval-explainer Vibe plugin on this machine.
# Idempotent: safe to re-run. Requires python3 on PATH.
set -euo pipefail

die() { echo "install: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"

VH="${VIBE_HOME:-$HOME/.vibe}"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$VH/plugins/approval-explainer"

# 1. Copy the package into VIBE_HOME (no-op when already installed in place).
if [ "$SRC" != "$DEST" ]; then
  mkdir -p "$DEST"
  cp -R "$SRC/." "$DEST/"
fi
[ -f "$DEST/scripts/explain.py" ] || die "missing $DEST/scripts/explain.py"

# 2. Activate the hook. Plugin-declared hooks (ai.mistral.vibe/hooks.toml)
#    are parsed but not bound by the unified harness in current Vibe
#    releases, so a user-level entry is what actually runs. The entry needs
#    a literal absolute path: the hook command may run without VIBE_HOME
#    exported, and ~ is not expanded for non-interactive sh in all setups.
mkdir -p "$VH"
HOOKS="$VH/hooks.toml"
touch "$HOOKS"

python3 - "$HOOKS" "$DEST" <<'PY'
import re
import sys

hooks_path, dest = sys.argv[1], sys.argv[2]
with open(hooks_path, encoding="utf-8") as fh:
    text = fh.read()

# Drop any previous explain-approval block, keep everything else verbatim.
parts = re.split(r"(?m)^\[\[hooks\]\]\s*$", text)
preamble, blocks = parts[0], parts[1:]
kept = [
    b
    for b in blocks
    if re.search(r"""(?m)^\s*name\s*=\s*["']explain-approval["']""", b) is None
]

block = (
    '\n[[hooks]]\nname = "explain-approval"\ntype = "pre_tool"\n'
    f'match = "bash"\ncommand = "python3 {dest}/scripts/explain.py"\n'
    "timeout = 20.0\n"
    'description = "Explain what the tool call does, with no conversation context"\n'
)

new = preamble.rstrip("\n")
for b in kept:
    new += "\n[[hooks]]" + b.rstrip("\n") + "\n"
new += block

with open(hooks_path, "w", encoding="utf-8") as fh:
    fh.write(new)
PY

# 3. Verify: script imports, gate behaves, and the hook runs end to end on a
#    provably safe command (which the gate skips, so no API call is spent).
python3 - "$DEST" <<'PY'
import sys

sys.path.insert(0, sys.argv[1] + "/scripts")
import explain

assert explain.is_likely_auto_approved("ls -la | head")
assert explain.is_likely_auto_approved("git status && git diff")
assert not explain.is_likely_auto_approved("rm -rf /tmp/x")
assert not explain.is_likely_auto_approved("git push origin main")
print("gate ok")
PY

printf '{"tool_name":"file_system.bash","tool_input":{"command":"ls -la"}}' \
  | python3 "$DEST/scripts/explain.py" \
  || die "hook script failed on a safe payload"

cat <<EOF
Installed approval-explainer into $DEST
Hook activated in $HOOKS
Restart Vibe for the hook to bind (/reload is not enough).
EOF
