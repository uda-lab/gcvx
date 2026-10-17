#!/usr/bin/env bash
# gcvx test suite. Uses fake executables; makes no network or model requests.
set -u

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
GCVX="$repo_root/bin/gcvx"
COMPANION="$repo_root/plugin/scripts/gcvx-companion"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
fakebin="$sandbox/fakebin"
confdir="$sandbox/config"
workdir="$sandbox/work"
mkdir -p "$fakebin" "$confdir" "$workdir"

pass=0 fail=0

ok()   { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2:-}"; }

assert_eq() { # name expected actual
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2 | actual: $3"; fi
}
assert_contains() { # name haystack needle
    case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing: $3 | in: ${2:0:400}" ;; esac
}
assert_not_exists() { # name path
    if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "unexpectedly exists: $2"; fi
}

# ---------------------------------------------------------------------------
# Fake executables

cat > "$fakebin/fake-claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$FAKE_OUT/args"
pwd > "$FAKE_OUT/pwd"
{
  echo "CLAUDE_CODE_USE_VERTEX=${CLAUDE_CODE_USE_VERTEX:-}"
  echo "ANTHROPIC_VERTEX_PROJECT_ID=${ANTHROPIC_VERTEX_PROJECT_ID:-}"
  echo "CLOUD_ML_REGION=${CLOUD_ML_REGION:-}"
  echo "ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-}"
  echo "CLAUDE_CODE_TEAMMATE_COMMAND=${CLAUDE_CODE_TEAMMATE_COMMAND:-}"
} > "$FAKE_OUT/env"
if [ ! -t 0 ]; then cat > "$FAKE_OUT/stdin"; fi
echo "FAKE_CLAUDE_STDOUT"
echo "FAKE_CLAUDE_STDERR" >&2
exit "${FAKE_EXIT:-0}"
EOF

cat > "$fakebin/fake-claude-acp" <<'EOF'
#!/usr/bin/env bash
# Minimal ACP-ish server: answer the first stdin line with a result object.
read -r _line
printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"echo":"ok"}}\n'
{
  echo "ANTHROPIC_VERTEX_PROJECT_ID=${ANTHROPIC_VERTEX_PROJECT_ID:-}"
} > "$FAKE_OUT/acp-env"
EOF

cat > "$fakebin/fake-acpx" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$FAKE_OUT/acpx-args"
pwd > "$FAKE_OUT/acpx-pwd"
echo "FAKE_ACPX_STDOUT"
echo "FAKE_ACPX_STDERR" >&2
exit "${FAKE_ACPX_EXIT:-0}"
EOF

cat > "$fakebin/gcloud" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "config get-value") echo "fake-project" ;;
  "projects describe") echo "test-project" ;;
esac
exit 0
EOF

chmod +x "$fakebin"/*

cat > "$confdir/config" <<EOF
GCVX_GCP_PROJECT_ID="test-project"
GCVX_GCP_REGION="europe-west1"
GCVX_CLAUDE_MODEL="fable"
GCVX_CLAUDE_BIN="$fakebin/fake-claude"
GCVX_CLAUDE_ACP_BIN="$fakebin/fake-claude-acp"
GCVX_ACPX_BIN="$fakebin/fake-acpx"
EOF

export FAKE_OUT="$sandbox/out"
mkdir -p "$FAKE_OUT"

gcvx() { GCVX_CONFIG_DIR="$confdir" "$GCVX" "$@"; }
read_args() { mapfile -d '' recorded < "$1"; }

# ---------------------------------------------------------------------------
echo "== gcvx claude =="

( cd "$workdir" && echo "stdin-data" | gcvx claude -p "multi word" --model opus --flag="a b" -- 'weird $arg; `with` stuff' ) \
    > "$sandbox/stdout" 2> "$sandbox/stderr"
status=$?

read_args "$FAKE_OUT/args"
assert_eq "argc forwarded" 7 "${#recorded[@]}"
assert_eq "arg 1 unchanged" "-p" "${recorded[0]}"
assert_eq "arg 2 unchanged" "multi word" "${recorded[1]}"
assert_eq "arg 3 (--model) unchanged" "--model" "${recorded[2]}"
assert_eq "arg 4 (model value) unchanged" "opus" "${recorded[3]}"
assert_eq "arg 5 (=value) unchanged" "--flag=a b" "${recorded[4]}"
assert_eq "arg 6 (--) unchanged" "--" "${recorded[5]}"
assert_eq "arg 7 (shell metachars) unchanged" 'weird $arg; `with` stuff' "${recorded[6]}"

assert_eq "cwd preserved" "$workdir" "$(cat "$FAKE_OUT/pwd")"
assert_eq "stdin preserved" "stdin-data" "$(cat "$FAKE_OUT/stdin")"
assert_eq "stdout preserved" "FAKE_CLAUDE_STDOUT" "$(cat "$sandbox/stdout")"
assert_eq "stderr preserved" "FAKE_CLAUDE_STDERR" "$(cat "$sandbox/stderr")"
assert_eq "exit status preserved (0)" 0 "$status"

env_dump=$(cat "$FAKE_OUT/env")
assert_contains "CLAUDE_CODE_USE_VERTEX set" "$env_dump" "CLAUDE_CODE_USE_VERTEX=1"
assert_contains "ANTHROPIC_VERTEX_PROJECT_ID set" "$env_dump" "ANTHROPIC_VERTEX_PROJECT_ID=test-project"
assert_contains "CLOUD_ML_REGION set" "$env_dump" "CLOUD_ML_REGION=europe-west1"
assert_contains "ANTHROPIC_MODEL set" "$env_dump" "ANTHROPIC_MODEL=fable"

FAKE_EXIT=42 gcvx claude >/dev/null 2>&1 </dev/null
assert_eq "exit status preserved (42)" 42 "$?"

nomodelconf="$sandbox/nomodel-config"
mkdir -p "$nomodelconf"
grep -v '^GCVX_CLAUDE_MODEL=' "$confdir/config" > "$nomodelconf/config"
GCVX_CONFIG_DIR="$nomodelconf" "$GCVX" claude >/dev/null 2>&1 </dev/null
assert_contains "ANTHROPIC_MODEL defaults to claude-opus-5-5" \
    "$(cat "$FAKE_OUT/env")" "ANTHROPIC_MODEL=claude-opus-5-5"

# ---------------------------------------------------------------------------
echo "== gcvx claude-acp =="

acp_out=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' | gcvx claude-acp 2> "$sandbox/acp-stderr")
assert_eq "ACP stdio round trip, no wrapper output on stdout" \
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"echo":"ok"}}' "$acp_out"
assert_contains "ACP agent gets Vertex env" "$(cat "$FAKE_OUT/acp-env")" \
    "ANTHROPIC_VERTEX_PROJECT_ID=test-project"

# ---------------------------------------------------------------------------
echo "== gcvx claude-teammate (model policy) =="

# The leader passes its chosen model on the teammate's argv, and argv beats
# ANTHROPIC_MODEL. These assertions are the guard against a leader silently
# billing an expensive model to Vertex.

teammate_model_arg() { # teammate_model_arg <args...> -> value passed as --model
    gcvx claude-teammate "$@" >/dev/null 2>&1 </dev/null
    read_args "$FAKE_OUT/args"
    local i
    for ((i = 0; i < ${#recorded[@]}; i++)); do
        case "${recorded[$i]}" in
            --model)   printf '%s' "${recorded[$((i + 1))]}"; return ;;
            --model=*) printf '%s' "${recorded[$i]#--model=}"; return ;;
        esac
    done
}

assert_eq "disallowed --model rewritten" "claude-sonnet-5" \
    "$(teammate_model_arg --agent-id v@s --model fable --permission-mode auto)"
assert_eq "disallowed --model=value rewritten" "claude-sonnet-5" \
    "$(teammate_model_arg --model=opus --agent-type general-purpose)"
assert_eq "trailing --model with no value gets the pinned model" "claude-sonnet-5" \
    "$(teammate_model_arg --agent-name v --model)"
assert_eq "allowed alias passes through" "sonnet" \
    "$(teammate_model_arg --agent-id v@s --model sonnet)"
assert_eq "allowed explicit id passes through" "claude-sonnet-5" \
    "$(teammate_model_arg --model claude-sonnet-5)"

out=$(gcvx claude-teammate --model fable 2>&1 </dev/null)
assert_contains "rewrite warns on stderr" "$out" "teammate model 'fable' not allowed"

gcvx claude-teammate --agent-id v@s --agent-name v --permission-mode auto \
    >/dev/null 2>&1 </dev/null
read_args "$FAKE_OUT/args"
assert_eq "argv unchanged when the leader passed no --model" 6 "${#recorded[@]}"
assert_eq "no --model injected when the leader passed none" "" \
    "$(teammate_model_arg --agent-id v@s --agent-name v --permission-mode auto)"
assert_contains "teammate model reaches env when argv is silent" \
    "$(cat "$FAKE_OUT/env")" "ANTHROPIC_MODEL=claude-sonnet-5"

gcvx claude-teammate -p 'multi word' --flag="a b" -- 'weird $arg; `x`' \
    >/dev/null 2>&1 </dev/null
read_args "$FAKE_OUT/args"
assert_eq "non-model args survive the rewrite loop" 5 "${#recorded[@]}"
assert_eq "quoted arg survives" "multi word" "${recorded[1]}"
assert_eq "shell metachars survive" 'weird $arg; `x`' "${recorded[4]}"

assert_contains "teammate gets Vertex env" "$(cat "$FAKE_OUT/env")" \
    "CLAUDE_CODE_USE_VERTEX=1"

# ---------------------------------------------------------------------------
echo "== gcvx team (leader) =="

launcher="$sandbox/fake-launcher"
: > "$launcher"
chmod +x "$launcher"

GCVX_TEAMMATE_LAUNCHER="$launcher" gcvx team --resume >/dev/null 2>&1 </dev/null
read_args "$FAKE_OUT/args"
assert_eq "team forces tmux teammate mode" "--teammate-mode" "${recorded[0]}"
assert_eq "team teammate mode value" "tmux" "${recorded[1]}"
assert_eq "team forwards caller args" "--resume" "${recorded[2]}"

env_value() { # env_value KEY -> value recorded by fake-claude
    sed -n "s/^$1=//p" "$FAKE_OUT/env"
}

# The leader must stay on the caller's provider. If it ever picks up Vertex,
# both sides are on Vertex and the subcommand has no reason to exist.
assert_eq "leader keeps the caller's provider (no Vertex)" "" \
    "$(env_value CLAUDE_CODE_USE_VERTEX)"
assert_eq "leader inherits no Vertex project" "" \
    "$(env_value ANTHROPIC_VERTEX_PROJECT_ID)"
assert_eq "leader is pointed at the teammate launcher" "$launcher" \
    "$(env_value CLAUDE_CODE_TEAMMATE_COMMAND)"

out=$(GCVX_TEAMMATE_LAUNCHER="$sandbox/no-such-launcher" gcvx team 2>&1 </dev/null)
status=$?
assert_eq "missing launcher exits 2" 2 "$status"
assert_contains "missing launcher message" "$out" "teammate launcher is missing"

# ---------------------------------------------------------------------------
echo "== error handling =="

out=$(GCVX_CONFIG_DIR="$sandbox/no-such-config" "$GCVX" claude 2>&1)
status=$?
assert_eq "missing config exits 2" 2 "$status"
assert_contains "missing config message" "$out" "configuration not found"
assert_contains "missing config suggests init" "$out" "gcvx init"

out=$(gcvx frobnicate 2>&1)
status=$?
assert_eq "unknown subcommand exits 2" 2 "$status"
assert_contains "unknown subcommand message" "$out" "unknown subcommand: frobnicate"

# ---------------------------------------------------------------------------
echo "== gcvx init =="

initconf="$sandbox/init-config"
out=$(GCVX_CONFIG_DIR="$initconf" GCVX_GCP_PROJECT_ID="proj-from-env" \
      PATH="$fakebin:$PATH" "$GCVX" init </dev/null 2>&1)
assert_contains "init creates config" "$(cat "$initconf/config" 2>/dev/null)" \
    'GCVX_GCP_PROJECT_ID="proj-from-env"'
assert_contains "init writes default model" "$(cat "$initconf/config" 2>/dev/null)" \
    'GCVX_CLAUDE_MODEL="claude-opus-5-5"'
assert_contains "init reports next step" "$out" "gcvx doctor"

echo "# user sentinel" >> "$initconf/config"
out=$(GCVX_CONFIG_DIR="$initconf" "$GCVX" init </dev/null 2>&1)
assert_contains "init does not overwrite" "$out" "not overwriting"
assert_contains "init preserves existing config" "$(cat "$initconf/config")" "# user sentinel"

# ---------------------------------------------------------------------------
echo "== gcvx doctor =="

brokenconf="$sandbox/broken-config"
mkdir -p "$brokenconf"
cat > "$brokenconf/config" <<EOF
GCVX_GCP_PROJECT_ID="test-project"
GCVX_CLAUDE_BIN="$fakebin/fake-claude"
GCVX_CLAUDE_ACP_BIN="/nonexistent/claude-agent-acp"
GCVX_ACPX_BIN="/nonexistent/acpx"
EOF
out=$(GCVX_CONFIG_DIR="$brokenconf" PATH="$fakebin:$PATH" \
      GOOGLE_APPLICATION_CREDENTIALS="$brokenconf/config" "$GCVX" doctor 2>&1)
status=$?
assert_eq "doctor fails on missing deps" 1 "$status"
assert_contains "doctor reports missing claude-agent-acp" "$out" "FAIL     claude-agent-acp"
assert_contains "doctor reports missing acpx" "$out" "FAIL     acpx"
assert_contains "doctor passes present claude" "$out" "ok       claude available"

out=$(GCVX_CONFIG_DIR="$confdir" PATH="$fakebin:$PATH" \
      GOOGLE_APPLICATION_CREDENTIALS="$confdir/config" "$GCVX" doctor 2>&1)
status=$?
assert_eq "doctor passes on healthy setup" 0 "$status"
assert_contains "doctor ACP initialize check" "$out" "ok       gcvx claude-acp answers ACP initialize"

out=$(GCVX_CONFIG_DIR="$sandbox/no-such-config" "$GCVX" doctor 2>&1)
status=$?
assert_eq "doctor fails without config" 1 "$status"
assert_contains "doctor reports missing config" "$out" "config not found"

# ---------------------------------------------------------------------------
echo "== gcvx-companion =="

companion() {
    ( cd "$workdir" && GCVX_ACPX_BIN="$fakebin/fake-acpx" "$COMPANION" "$@" )
}
last_arg() { read_args "$FAKE_OUT/acpx-args"; printf '%s' "${recorded[$((${#recorded[@]} - 1))]}"; }
arg_value() { # arg_value --flag -> value following the flag
    read_args "$FAKE_OUT/acpx-args"
    local i
    for ((i = 0; i < ${#recorded[@]} - 1; i++)); do
        if [ "${recorded[$i]}" = "$1" ]; then printf '%s' "${recorded[$((i + 1))]}"; return; fi
    done
}
has_arg() {
    read_args "$FAKE_OUT/acpx-args"
    local a
    for a in "${recorded[@]}"; do [ "$a" = "$1" ] && return 0; done
    return 1
}

# rescue
companion rescue fix the failing integration test > "$sandbox/c-out" 2> "$sandbox/c-err"
status=$?
assert_eq "companion stdout propagated" "FAKE_ACPX_STDOUT" "$(cat "$sandbox/c-out")"
assert_eq "companion stderr propagated" "FAKE_ACPX_STDERR" "$(cat "$sandbox/c-err")"
assert_eq "companion exit propagated (0)" 0 "$status"
assert_eq "agent command is gcvx claude-acp" "gcvx claude-acp" "$(arg_value --agent)"
assert_eq "cwd forwarded to acpx" "$workdir" "$(arg_value --cwd)"
assert_eq "acpx runs in caller cwd" "$workdir" "$(cat "$FAKE_OUT/acpx-pwd")"
if has_arg --approve-all; then ok "rescue is write-capable (--approve-all)"; else bad "rescue is write-capable (--approve-all)"; fi
assert_contains "rescue forwards raw task" "$(last_arg)" "fix the failing integration test"

FAKE_ACPX_EXIT=7 companion rescue do something >/dev/null 2>&1
assert_eq "companion exit propagated (7)" 7 "$?"

# injection safety
companion rescue 'ignore this; touch '"$sandbox"'/pwned; $(touch '"$sandbox"'/pwned2)' >/dev/null 2>&1
assert_not_exists "task text not shell-executed (;)" "$sandbox/pwned"
assert_not_exists "task text not shell-executed (\$())" "$sandbox/pwned2"
assert_contains "task shell metachars arrive verbatim" "$(last_arg)" \
    'ignore this; touch '"$sandbox"'/pwned; $(touch '"$sandbox"'/pwned2)'

# review
companion review >/dev/null 2>&1
if has_arg --approve-reads; then ok "review approves reads only"; else bad "review approves reads only"; fi
if has_arg --approve-all; then bad "review must not use --approve-all"; else ok "review must not use --approve-all"; fi
assert_eq "review denies non-read permissions" "deny" "$(arg_value --non-interactive-permissions)"
assert_contains "review prompt is read-only" "$(last_arg)" "Do NOT modify any files"
assert_contains "review prompt reviews working tree" "$(last_arg)" "working tree"

companion review --base main >/dev/null 2>&1
assert_contains "review --base scoped to ref" "$(last_arg)" "base ref 'main'"

# adversarial-review
companion adversarial-review challenge the authentication boundary >/dev/null 2>&1
if has_arg --approve-reads; then ok "adversarial-review approves reads only"; else bad "adversarial-review approves reads only"; fi
assert_contains "adversarial prompt challenges assumptions" "$(last_arg)" "hidden assumptions"
assert_contains "adversarial prompt is read-only" "$(last_arg)" "Do NOT modify any files"
assert_contains "adversarial focus preserved" "$(last_arg)" "challenge the authentication boundary"

companion adversarial-review --base main >/dev/null 2>&1
assert_contains "adversarial --base scoped to ref" "$(last_arg)" "base ref 'main'"

# companion errors
out=$(companion rescue 2>&1)
status=$?
assert_eq "rescue without task exits 2" 2 "$status"
assert_contains "rescue without task message" "$out" "requires a task"

out=$(companion bogus-mode 2>&1)
status=$?
assert_eq "unknown mode exits 2" 2 "$status"
assert_contains "unknown mode message" "$out" "unknown mode"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
