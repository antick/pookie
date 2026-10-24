#!/usr/bin/env bash
# Policy emits only shell-quoted, repository-owned constants.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
policy_shell=$(python3 "$root/scripts/release/policy.py" shell) || {
  echo 'Unable to load release policy.' >&2
  return 1
}
eval "$policy_shell"
unset policy_shell
release_fail() { echo "$*" >&2; exit 1; }
