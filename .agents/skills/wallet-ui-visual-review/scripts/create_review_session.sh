#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  create_review_session.sh --target <PR URL|PR number|branch|commit>
    [--base <ref>] [--repo-root <path>] [--session-root <path>] [--dry-run]

Patch files and uncommitted working-tree targets are intentionally unsupported.
EOF
}

target=""
base_ref=""
repo_root="."
session_root=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      target="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      base_ref="$2"
      shift 2
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      repo_root="$2"
      shift 2
      ;;
    --session-root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      session_root="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -n "$target" ]] || { echo "error: --target is required" >&2; exit 2; }
[[ "$target" != -* ]] || { echo "error: target cannot begin with '-'" >&2; exit 2; }

case "$target" in
  working-tree|working_tree|dirty|uncommitted|.)
    echo "error: uncommitted working-tree targets are not supported; create a commit or branch" >&2
    exit 2
    ;;
  *.patch|*.diff)
    echo "error: patch-file targets are not supported; create a commit or branch" >&2
    exit 2
    ;;
esac

if [[ -f "$target" ]]; then
  echo "error: file targets are not supported; create a commit or branch" >&2
  exit 2
fi

repo_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
target_kind="commit"
pr_number=""
base_name=""
reported_head_sha=""

default_base() {
  local symbolic=""
  symbolic="$(git -C "$repo_root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$symbolic" ]]; then
    printf '%s\n' "$symbolic"
  elif git -C "$repo_root" show-ref --verify --quiet refs/heads/main; then
    printf '%s\n' "main"
  elif git -C "$repo_root" show-ref --verify --quiet refs/heads/master; then
    printf '%s\n' "master"
  else
    echo "error: cannot infer a default base; pass --base" >&2
    return 1
  fi
}

resolve_ref() {
  local ref="$1"
  local resolved=""

  resolved="$(git -C "$repo_root" rev-parse --verify "${ref}^{commit}" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return
  fi

  if git -C "$repo_root" check-ref-format --branch "$ref" >/dev/null 2>&1; then
    git -C "$repo_root" fetch origin \
      "+refs/heads/${ref}:refs/remotes/origin/${ref}" >/dev/null
    git -C "$repo_root" rev-parse --verify "refs/remotes/origin/${ref}^{commit}"
    return
  fi

  echo "error: cannot resolve ref: $ref" >&2
  return 1
}

if [[ "$target" =~ ^[0-9]+$ ]]; then
  target_kind="pr"
  pr_number="${BASH_REMATCH[0]}"
elif [[ "$target" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)/?$ ]]; then
  target_kind="pr"
  pr_number="${BASH_REMATCH[3]}"
  requested_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  command -v gh >/dev/null 2>&1 || { echo "error: gh is required for PR targets" >&2; exit 1; }
  current_repo="$(cd "$repo_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
  if [[ "$(printf '%s' "$requested_repo" | tr '[:upper:]' '[:lower:]')" != \
        "$(printf '%s' "$current_repo" | tr '[:upper:]' '[:lower:]')" ]]; then
    echo "error: PR URL targets $requested_repo but this checkout is $current_repo" >&2
    exit 2
  fi
fi

if [[ "$target_kind" == "pr" ]]; then
  command -v gh >/dev/null 2>&1 || { echo "error: gh is required for PR targets" >&2; exit 1; }
  repo_slug="$(cd "$repo_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
  pr_data="$(cd "$repo_root" && gh pr view "$pr_number" --repo "$repo_slug" \
    --json baseRefName,headRefOid \
    --jq '"\(.baseRefName) \(.headRefOid)"')"
  read -r base_name reported_head_sha <<<"$pr_data"
  [[ -z "$base_ref" || "$base_ref" == "$base_name" ]] || {
    echo "error: --base $base_ref conflicts with PR base $base_name" >&2
    exit 2
  }

  head_ref="refs/wallet-ui-review/pull/${pr_number}/head"
  git -C "$repo_root" fetch origin "+pull/${pr_number}/head:${head_ref}" >/dev/null
  git -C "$repo_root" fetch origin \
    "+refs/heads/${base_name}:refs/remotes/origin/${base_name}" >/dev/null
  after_sha="$(git -C "$repo_root" rev-parse --verify "${head_ref}^{commit}")"

  if [[ "$after_sha" != "$reported_head_sha" ]]; then
    latest_reported_head="$(cd "$repo_root" && gh pr view "$pr_number" \
      --repo "$repo_slug" --json headRefOid --jq .headRefOid)"
    if [[ "$after_sha" != "$latest_reported_head" ]]; then
      echo "error: PR head changed while resolving; rerun for a consistent target" >&2
      exit 1
    fi
  fi
  base_sha="$(git -C "$repo_root" rev-parse --verify "refs/remotes/origin/${base_name}^{commit}")"
else
  after_sha="$(resolve_ref "$target")"
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/${target}" || \
     git -C "$repo_root" show-ref --verify --quiet "refs/remotes/${target}" || \
     git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/${target}"; then
    target_kind="branch"
  fi
  base_name="${base_ref:-$(default_base)}"
  base_sha="$(resolve_ref "$base_name")"
fi

before_sha="$(git -C "$repo_root" merge-base "$base_sha" "$after_sha")"
[[ -n "$before_sha" ]] || {
  echo "error: no merge-base found between $base_name and $target" >&2
  exit 1
}
[[ "$before_sha" != "$after_sha" ]] || {
  echo "error: target resolves to its merge-base; there is no committed comparison" >&2
  exit 2
}

source_dirty=false
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  source_dirty=true
fi

emit_json() {
  python3 - "$@" <<'PY'
import json
import sys

(
    output,
    target_kind,
    target_input,
    base_name,
    before_sha,
    after_sha,
    pr_number,
    source_dirty,
    session_dir,
    before_worktree,
    after_worktree,
    artifact_dir,
) = sys.argv[1:]

data = {
    "schema_version": 1,
    "target_kind": target_kind,
    "target_input": target_input,
    "base_name": base_name,
    "before_sha": before_sha,
    "after_sha": after_sha,
    "pr_number": int(pr_number) if pr_number else None,
    "source_checkout_dirty": source_dirty == "true",
    "session_dir": session_dir or None,
    "before_worktree": before_worktree or None,
    "after_worktree": after_worktree or None,
    "artifact_dir": artifact_dir or None,
}

text = json.dumps(data, indent=2, sort_keys=True) + "\n"
if output == "-":
    sys.stdout.write(text)
else:
    with open(output, "w", encoding="utf-8") as handle:
        handle.write(text)
PY
}

if [[ "$dry_run" -eq 1 ]]; then
  emit_json "-" "$target_kind" "$target" "$base_name" "$before_sha" "$after_sha" \
    "$pr_number" "$source_dirty" "" "" "" ""
  exit 0
fi

if [[ -n "$session_root" ]]; then
  mkdir -p "$session_root"
  session_dir="$(mktemp -d "${session_root%/}/wallet-ui-review.XXXXXX")"
else
  session_dir="$(mktemp -d "${TMPDIR:-/tmp}/wallet-ui-review.XXXXXX")"
fi

before_worktree="$session_dir/before"
after_worktree="$session_dir/after"
artifact_dir="$session_dir/artifacts"
mkdir -p "$artifact_dir" "$session_dir/derived-data"

before_registered=0
after_registered=0
setup_complete=0
cleanup_failed_setup() {
  local status=$?
  if [[ "$status" -ne 0 && "$setup_complete" -eq 0 ]]; then
    set +e
    if [[ "$after_registered" -eq 1 ]]; then
      git -C "$repo_root" worktree remove --force "$after_worktree" >/dev/null 2>&1
    fi
    if [[ "$before_registered" -eq 1 ]]; then
      git -C "$repo_root" worktree remove --force "$before_worktree" >/dev/null 2>&1
    fi
  fi
}
trap cleanup_failed_setup EXIT

git -C "$repo_root" worktree add --detach "$before_worktree" "$before_sha" >/dev/null
before_registered=1
git -C "$repo_root" worktree add --detach "$after_worktree" "$after_sha" >/dev/null
after_registered=1

for worktree in "$before_worktree" "$after_worktree"; do
  if [[ -f "$repo_root/android/local.properties" && \
        ! -e "$worktree/android/local.properties" ]]; then
    ln -s "$repo_root/android/local.properties" "$worktree/android/local.properties"
  fi
done

session_json="$session_dir/session.json"
emit_json "$session_json" "$target_kind" "$target" "$base_name" "$before_sha" \
  "$after_sha" "$pr_number" "$source_dirty" "$session_dir" "$before_worktree" \
  "$after_worktree" "$artifact_dir"
setup_complete=1

printf 'SESSION_DIR=%s\n' "$session_dir"
printf 'SESSION_JSON=%s\n' "$session_json"
printf 'BEFORE_WORKTREE=%s\n' "$before_worktree"
printf 'AFTER_WORKTREE=%s\n' "$after_worktree"
printf 'ARTIFACT_DIR=%s\n' "$artifact_dir"
printf 'BEFORE_SHA=%s\n' "$before_sha"
printf 'AFTER_SHA=%s\n' "$after_sha"
printf 'TARGET_KIND=%s\n' "$target_kind"
if [[ -n "$pr_number" ]]; then
  printf 'PR_NUMBER=%s\n' "$pr_number"
fi
