#!/usr/bin/env python3
"""Context-free approval explainer.

Reads a Vibe pre_tool hook payload from stdin, asks a small model to explain
what the tool call does, and prints a structured hook response on stdout.

Deliberately uses ONLY tool_name and tool_input from the payload -- the
transcript path, session id, and any conversation context are ignored, so the
explaining model sees the call the same way the approving user does.

Fails open: on any error, prints nothing and exits 0 (pass-through, no warning).
"""

import json
import os
import re
import shlex
import shutil
import ssl
import subprocess
import sys
import urllib.request

MAX_INPUT_CHARS = 8000
MAX_OUTPUT_TOKENS = 120

SYSTEM_PROMPT = (
    "You review a single tool call made by a coding agent. You have no other "
    "context: no conversation, no files, no task description. In one or two "
    "plain sentences, explain what this tool call will do. If you notice "
    "anything notable -- reading credentials or secrets, sending data to the "
    "network, destructive operations, privilege changes -- say so explicitly "
    "and concretely. Be neutral and factual; do not moralize, do not prefix "
    "with your own name. Reply with the explanation only."
)

# --- Will-this-prompt gate --------------------------------------------------
# The pre_tool payload carries no permission state, and in smart-approve mode
# an LLM classifier decides per call whether to prompt -- so "will the user be
# asked" cannot be known exactly at hook time. What we can do is skip commands
# that are provably read-only and free of risky patterns: those are exactly the
# calls the classifier auto-runs, where the explanation would be computed and
# thrown away. Anything else still gets explained, so a surprise prompt keeps
# its note at the cost of an occasional wasted call.

SAFE_COMMANDS = frozenset({
    "basename", "cat", "cd", "comm", "cut", "date", "diff", "dirname", "du",
    "echo", "file", "find", "fmt", "fold", "grep", "head", "join", "less",
    "ls", "md5sum", "more", "nl", "od", "paste", "pwd", "readlink", "rg",
    "sha1sum", "sha256sum", "shasum", "sort", "stat", "strings", "tac",
    "tail", "tr", "tree", "uniq", "wc", "which", "whoami",
})

SAFE_GIT_SUBCOMMANDS = frozenset({
    "branch", "diff", "log", "rev-parse", "show", "status",
})

FIND_EXEC_PREDICATES = {"-exec", "-execdir", "-ok", "-okdir"}

RISKY_PATTERN = re.compile(
    r"(?:"
    r"[<>]{1,2}\s*\S"         # redirections: > f, >> f, < f, 2>&1
    r"|\$\("                  # command substitution
    r"|`"              # backtick substitution
    r"|\.env\b|\.ssh\b|\.aws\b|\.gnupg\b|keychain"
    r"|id_rsa|id_ed25519"
    r"|secret|credential|token|passwd|shadow"
    r")",
    re.IGNORECASE,
)


def _split_segments(command: str) -> list[str]:
    parts = re.split(r"&&|\|\||;|\||\n", command)
    return [p.strip() for p in parts if p.strip()]


def _segment_is_safe(segment: str, safe: frozenset) -> bool:
    try:
        tokens = shlex.split(segment)
    except ValueError:
        tokens = segment.split()
    while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
        tokens = tokens[1:]
    if not tokens:
        return True
    head = tokens[0]
    if head == "git":
        return len(tokens) > 1 and tokens[1] in SAFE_GIT_SUBCOMMANDS
    if head == "find":
        return not any(t in FIND_EXEC_PREDICATES for t in tokens)
    return head in safe


def is_likely_auto_approved(command: str) -> bool:
    gate = os.environ.get("EXPLAIN_GATE", "").strip().lower()
    if gate in {"off", "0", "false"}:
        return False
    extra = os.environ.get("EXPLAIN_SAFE_COMMANDS", "")
    safe = SAFE_COMMANDS | {c.strip() for c in extra.split(",") if c.strip()}
    if RISKY_PATTERN.search(command):
        return False
    return all(_segment_is_safe(seg, safe) for seg in _split_segments(command))


def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + "\n...[truncated]"


def resolve_api_key() -> str:
    key = os.environ.get("EXPLAIN_API_KEY") or os.environ.get("MISTRAL_API_KEY")
    if key:
        return key
    # Vibe's own browser-sign-in storage: macOS keychain service "ai.mistral.vibe".
    if sys.platform == "darwin" and shutil.which("security"):
        try:
            out = subprocess.run(
                ["security", "find-generic-password", "-s", "ai.mistral.vibe", "-w"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if out.returncode == 0:
                return out.stdout.strip()
        except Exception:
            pass
    return ""


def _ssl_context() -> ssl.SSLContext:
    # Some interpreters (notably Apple's /usr/bin/python3) ship without a usable
    # CA bundle, so resolve one explicitly instead of trusting the defaults.
    candidates: list[str] = []
    env_bundle = os.environ.get("SSL_CERT_FILE")
    if env_bundle:
        candidates.append(env_bundle)
    try:
        import certifi

        candidates.append(certifi.where())
    except Exception:
        pass
    candidates += ["/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt"]
    for path in candidates:
        if path and path and os.path.isfile(path):
            try:
                return ssl.create_default_context(cafile=path)
            except Exception:
                continue
    return ssl.create_default_context()


def explain(tool_name: str, tool_input: dict) -> str:
    api_key = resolve_api_key()
    model = os.environ.get("EXPLAIN_MODEL", "mistral-small-latest")
    api_base = os.environ.get("EXPLAIN_API_BASE", "https://api.mistral.ai/v1")

    user_content = (
        "Tool: "
        + tool_name
        + "\nArguments (JSON): "
        + truncate(json.dumps(tool_input, ensure_ascii=False), MAX_INPUT_CHARS)
    )

    body = json.dumps(
        {
            "model": model,
            "temperature": 0.2,
            "max_tokens": MAX_OUTPUT_TOKENS,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
        }
    ).encode()

    req = urllib.request.Request(
        api_base.rstrip("/") + "/chat/completions",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + api_key,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15, context=_ssl_context()) as resp:
        data = json.load(resp)
    return data["choices"][0]["message"]["content"].strip()


def main() -> None:
    try:
        payload = json.load(sys.stdin)
        tool_name = payload.get("tool_name") or ""
        tool_input = payload.get("tool_input") or {}
        if not tool_name:
            return
        command = str(tool_input.get("command") or "")
        if command and is_likely_auto_approved(command):
            return
        explanation = explain(tool_name, tool_input)
        if not explanation:
            _debug("empty explanation")
            return
        print(
            json.dumps({"decision": "allow", "system_message": explanation},
                       ensure_ascii=False)
        )
    except Exception as exc:
        # Fail open: empty stdout + exit 0 = pass-through, no UI warning.
        _debug(f"{type(exc).__name__}: {exc}")


def _debug(message: str) -> None:
    try:
        with open("/tmp/vibe-explain-hook.log", "a") as fh:
            fh.write(message + "\n")
    except Exception:
        pass


if __name__ == "__main__":
    main()
