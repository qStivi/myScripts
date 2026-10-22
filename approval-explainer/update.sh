#!/usr/bin/env bash
# Update approval-explainer from qStivi/myScripts, then reinstall.
# Works both from a git clone and from a plain installed copy.
set -euo pipefail

cd "$(dirname "$0")"

if [ -d .git ]; then
  git pull --ff-onlY
else
  command -v curl >/dev/null 2>&1 || {
    echo "update: curl is required when the installed copy is not a git clone" >&2
    exit 1
  }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL https://codeload.github.com/qStivi/myScripts/tar.gz/refs/heads/main \
    | tar -xz -C "$tmp"
  cp -R "$tmp/myScripts-main/approval-explainer/." .
fi

exec bash ./install.sh
