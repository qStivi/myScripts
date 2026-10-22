# approval-explainer

A [Mistral Vibe](https://docs.mistral.ai/vibe/code/overview) plugin that adds a
short, plain-language explanation to every tool-approval prompt: what the call
does, and whether it touches anything notable (credentials, network, destructive
operations, privilege changes).

The explaining model sees only the tool name and arguments — no conversation,
files, or task context — so it judges the call the way the approving user sees
it and cannot be steered by the agent it reviews. It never allows or denies
anything; the normal approval flow is unchanged. Any failure is fail-open: no
note, never a blocked tool.

## How it works

- A \`pre_tool\` hook on \`bash\` calls the script \`scripts/explain.py\`.
- The script asks a small model (default \`mistral-small-latest\`) for a one or
  two sentence explanation and returns it as a \`system_message\` UI note.
- **Prompt gate**: the pre_tool payload carries no permission state, and in
  smart-approve mode an LLM classifier decides per call whether to prompt — so
  "will the user be asked" is unknowable at hook time. The script instead skips
  commands that are provably read-only and free of risky markers (\`ls\`,
  \`grep\`, \`git status/log/diff\`, plain \`find\`, ... — the exact calls smart
  approve auto-runs). Everything else gets explained. Result: no API cost and
  no 2–4 s delay on the routine flood of commands, notes whenever something
  is plausibly worth approving.

## Install (per machine)

\`\`\`bash
git clone https://github.com/qStivi/myScripts.git
myScripts/approval-explainer/install.sh
\`\`\`

Then restart Vibe (hook bindings are compiled at session start; \`/reload\` is
not enough). You can delete the \`myScripts\` clone afterwards — \`update.sh\`
re-fetches on its own.

\`install.sh\` is idempotent and also works when \`$VIBE_HOME\` is set to
somewhere other than \`~/.vibe\`. It copies the package into
\`$VIBE_HOME/plugins/approval-explainer/\` first.

## Update

\`\`\`bash
~/.vibe/plugins/approval-explainer/update.sh   # fetch latest from myScripts + reinstall
\`\`\`

## Uninstall

\`\`\`bash
~/.vibe/plugins/approval-explainer/uninstall.sh            # deactivate
~/.vibe/plugins/approval-explainer/uninstall.sh --purge    # deactivate + delete
\`\`\`

## Configuration (env, e.g. in \`$VIBE_HOME/.env\`)

| Variable | Default | Effect |
|---|---|---|
| \`EXPLAIN_MODEL\` | \`mistral-small-latest\` | Explaining model. |
| \`EXPLAIN_API_BASE\` | \`https://api.mistral.ai/v1\` | API endpoint. |
| \`EXPLAIN_API_KEY\` / \`MISTRAL_API_KEY\` | — | API key; on macOS also read from Vibe's keychain entry (\`ai.mistral.vibe\`). |
| \`EXPLAIN_GATE\` | on | \`off\`/\`0\`/\`false\` disables the safe-command gate and explains every call. |
| \`EXPLAIN_SAFE_COMMANDS\` | — | Comma-separated extra command names the gate treats as safe (e.g. \`sed,python3,strings\`). |

## Cost

One small-model call per explained approval: typically a few hundredths of a
cent. The gate makes that cost — and the 2–4 s latency — apply only to calls
that are plausibly prompt-worthy, instead of every single command.

## Trade-offs of the gate

- If the smart-approve classifier prompts on something the gate deemed safe,
  the prompt appears without a note (soft miss).
- If the classifier auto-runs something the gate deemed risky, one call is
  wasted. Both should be rare.
