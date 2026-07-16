# gcvx

A thin Google Cloud Vertex AI execution wrapper for Claude Code, plus a
Claude Code plugin that delegates work to the Vertex-backed agent over the
Agent Client Protocol (ACP).

`gcvx` does not reimplement anything Claude Code, the Claude Agent SDK, ACP,
[`acpx`](https://www.npmjs.com/package/acpx), or
[`claude-agent-acp`](https://www.npmjs.com/package/@agentclientprotocol/claude-agent-acp)
already provide. It only selects the provider (Vertex AI) and a default
model via environment variables, then hands off to the real tools. The whole
runtime is one wrapper script, one plugin companion script, and three command
Markdown files.

## Command surface

```text
gcvx init          # initial local setup
gcvx doctor        # read-only diagnostics (no model requests)
gcvx claude [...]  # ordinary Claude Code CLI, backed by Vertex AI
gcvx claude-acp    # ACP agent (claude-agent-acp), backed by Vertex AI
```

Claude Code plugin commands:

```text
/gcvx:rescue              delegate investigation / fixing / implementation
/gcvx:review              read-only review of the working tree or branch
/gcvx:adversarial-review  challenge design direction and assumptions
```

The default model is `fable`, but it is configuration, not part of any
command name.

## Architecture

Direct interactive use:

```text
gcvx claude
  └── Vertex environment wrapper
        └── ordinary claude CLI
              └── Google Cloud Vertex AI
```

Plugin delegation (ACP is used only at the plugin-to-agent boundary):

```text
Claude Code parent session
  └── /gcvx:rescue | /gcvx:review | /gcvx:adversarial-review
        └── plugin/scripts/gcvx-companion
              └── acpx --agent "gcvx claude-acp"
                    └── claude-agent-acp (Claude Agent SDK)
                          └── Google Cloud Vertex AI
```

## Installation

Dependencies:

```sh
npm install -g @anthropic-ai/claude-code
npm install -g @agentclientprotocol/claude-agent-acp
npm install -g acpx
# and the gcloud CLI: https://cloud.google.com/sdk/docs/install
```

Install gcvx:

```sh
scripts/install.sh          # preserves existing files; --force overwrites
gcvx init
gcvx doctor
```

This installs `~/.local/bin/gcvx`, a reference config example, and the
plugin at `~/.local/share/gcvx/plugin`. Shell profiles are never modified.

Load the plugin in Claude Code:

```sh
claude --plugin-dir ~/.local/share/gcvx/plugin
```

During development, point `--plugin-dir` at the `plugin/` directory of this
repository instead.

## Configuration

`gcvx init` creates `~/.config/gcvx/config` (never overwriting an existing
file). It is plain shell, sourced by the wrapper:

```sh
GCVX_GCP_PROJECT_ID="example-project"   # required
GCVX_GCP_REGION="global"                # default: global
GCVX_CLAUDE_MODEL="fable"               # default: fable

# Optional binary overrides:
#GCVX_CLAUDE_BIN="claude"
#GCVX_CLAUDE_ACP_BIN="claude-agent-acp"
#GCVX_ACPX_BIN="acpx"
```

Google Cloud authentication uses Application Default Credentials:

```sh
gcloud auth application-default login
```

## Usage

`gcvx claude` is a transparent wrapper — every ordinary Claude Code option
and positional argument passes through unchanged, and stdin/stdout/stderr,
the working directory, signals, and the exit status are preserved:

```sh
gcvx claude
gcvx claude -p "Review this implementation"
gcvx claude --resume
gcvx claude --permission-mode plan
gcvx claude --model opus     # overrides the configured default
```

The wrapper sets only `CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_PROJECT_ID`,
`CLOUD_ML_REGION`, and `ANTHROPIC_MODEL` in the launched process. Your
ordinary `claude` login and global settings are untouched, so subscription
and Vertex use coexist.

Plugin commands:

```text
/gcvx:rescue investigate why the integration tests fail
/gcvx:rescue --background fix the race condition with the smallest safe patch
/gcvx:review
/gcvx:review --base main
/gcvx:adversarial-review challenge the authentication boundary
```

`rescue` is write-capable by default (`acpx --approve-all`). The review
commands run read-only (`--approve-reads` with non-read permissions denied)
and never apply fixes. `--background` uses Claude Code's native background
execution; there is no gcvx job manager.

## Tests

```sh
tests/test.sh
```

The suite uses fake executables and makes no network or model requests. It
covers argument passthrough, stdio/cwd/exit-status preservation, the Vertex
environment, ACP stdout purity, init/doctor behaviour, companion prompt
selection, permission posture per mode, and shell-injection safety of task
text.

## Design constraints

- No Python package, daemon, database, custom job manager, session store, or
  generic backend framework.
- The single extension seam is ACP: replacing the agent later means changing
  the companion's agent command (`gcvx claude-acp`) and prompts only.
- `gcvx claude-acp` never writes wrapper output to stdout; ACP owns it.

## Deferred (see plan §24)

- ACP session resume through `/gcvx:rescue` (`--resume` / `--fresh`).
- Per-invocation model/effort flags for the plugin commands.
- Version-pinning `claude-agent-acp`.
- `/gcvx:status` / `/gcvx:result` / `/gcvx:cancel` job commands — only if
  native background execution proves insufficient.
- A separate read-only advisor command.
- Reverse invocation (a Vertex session launching a subscription-authenticated
  `claude`); the wrapper already keeps this possible by touching only its own
  child process environment.
