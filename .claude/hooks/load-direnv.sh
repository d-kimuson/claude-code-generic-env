#!/usr/bin/env bash
#
# SessionStart / CwdChanged hook: apply the direnv environment to Claude Code's Bash tool.

set -euo pipefail

# On SessionStart, stdout is added to the session context, so logs go to stderr only.
log() {
  echo "[load-direnv] $*" >&2
}

if [[ -z "${CLAUDE_ENV_FILE:-}" ]]; then
  log "CLAUDE_ENV_FILE is not set; skip"
  exit 0
fi

if ! command -v direnv >/dev/null 2>&1; then
  log "direnv is not installed; skip"
  exit 0
fi

# Prefer cwd from the hook input (stdin JSON); fall back to CLAUDE_PROJECT_DIR, then the hook process cwd
input="$(cat || true)"
target_dir=""
if command -v jq >/dev/null 2>&1; then
  target_dir="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)"
fi
target_dir="${target_dir:-${CLAUDE_PROJECT_DIR:-$PWD}}"

cd "$target_dir"

# Replace via a temp file so a mid-way failure never leaves CLAUDE_ENV_FILE half-written
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

# Claude Code sources CLAUDE_ENV_FILE before each Bash command. Overwrite (not append)
# on every cwd change, so moving to a directory without .envrc empties it and the
# environment reverts.
if direnv export bash >"$tmp_file"; then
  mv "$tmp_file" "$CLAUDE_ENV_FILE"
  log "exported direnv environment for $target_dir"
else
  # e.g. .envrc is not allowed. Empty the file so no stale environment remains
  : >"$CLAUDE_ENV_FILE"
  log "direnv export failed for $target_dir (run \`direnv allow\` if .envrc is blocked)"
fi
