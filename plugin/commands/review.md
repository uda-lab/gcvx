---
description: Read-only code review of the working tree or branch by the Vertex-backed Claude agent
argument-hint: "[--base <ref>] [--background]"
allowed-tools: ["Bash"]
---

Run a read-only review of the current repository state through the
Vertex-backed Claude agent over ACP.

User arguments: $ARGUMENTS

## Steps

1. Parse the arguments:
   - `--base <ref>` (or `--base=<ref>`): review changes relative to that ref.
   - `--background`: run the companion as a background Bash command
     (`run_in_background`) and report back when it completes.
   - No other arguments are supported; if something else was passed, tell the
     user and stop.
2. Run the companion from the current working directory:

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/gcvx-companion" review [--base <ref>]
   ```

3. Present the reviewer's findings to the user directly.

## Rules

- Review only. Do not apply fixes, and do not let this command modify the
  repository. If the user wants fixes applied afterwards, that is a separate
  step they must ask for.
- Do not run your own parallel review; the delegated agent's findings are the
  deliverable.
- If the companion fails (non-zero exit), show the error output and suggest
  running `gcvx doctor`.
