---
description: Challenge the implementation direction, assumptions, and trade-offs via the Vertex-backed Claude agent
argument-hint: "[--base <ref>] [focus]"
allowed-tools: ["Bash"]
---

Run a read-only adversarial review through the Vertex-backed Claude agent
over ACP. Unlike `/gcvx:review`, this challenges the design direction,
assumptions, trade-offs, and failure modes rather than only finding code
defects.

User arguments: $ARGUMENTS

## Steps

1. Parse the arguments:
   - `--base <ref>` (or `--base=<ref>`): scope the review to changes relative
     to that ref.
   - `--background`: run the companion as a background Bash command
     (`run_in_background`) and report back when it completes.
   - Any remaining text is the focus (e.g. "challenge the authentication
     boundary"). Preserve it verbatim.
2. Run the companion from the current working directory, passing the focus as
   arguments (never interpolated into a shell string):

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/gcvx-companion" adversarial-review [--base <ref>] [focus text]
   ```

3. Return the agent's critique to the user directly.

## Rules

- Read-only. Do not apply fixes or modify the repository.
- Do not soften or counter the critique with your own defense of the code;
  the adversarial perspective is the deliverable.
- If the companion fails (non-zero exit), show the error output and suggest
  running `gcvx doctor`.
