---
description: Delegate investigation, fixing, or implementation work to the Vertex-backed Claude agent
argument-hint: "[--background] <task>"
allowed-tools: ["Bash"]
---

Delegate the user's task to the Vertex-backed Claude agent over ACP. The
delegated agent does the work; you relay it.

User arguments: $ARGUMENTS

## Steps

1. Separate control flags from the task text:
   - If the arguments start with `--background`, remove that flag and run the
     companion as a background Bash command (`run_in_background`), then tell
     the user the delegation is running and how you will report back when it
     completes.
   - `--wait` (or no flag) means foreground execution: remove the flag if
     present and wait for the result.
   - Everything else is the task text. Forward it with minimal rewriting.
2. If no task text remains, ask the user what to delegate and stop.
3. Run the companion from the current working directory, passing the task as
   arguments (never interpolated into a shell string):

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/gcvx-companion" rescue <task text>
   ```

4. Return the delegated agent's output to the user faithfully. Summarize long
   output, but do not add an independent solution of your own, and do not
   redo or second-guess the delegated work.

## Rules

- Do not inspect or modify the repository yourself before delegating, unless
  it is strictly required to phrase the task.
- The delegation is write-capable by default; the delegated agent may modify
  files in this repository. If the user asked for read-only work, say so
  explicitly in the forwarded task text.
- If the companion fails (non-zero exit), show the error output and suggest
  running `gcvx doctor`.
