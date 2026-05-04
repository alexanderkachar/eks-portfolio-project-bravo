#!/bin/bash

set -euo pipefail

cd /opt/actions-runner

MODE="$${1:-register}"
REPO_URL="https://github.com/${github_owner}/${github_repo}"
RUNNERS_API="https://api.github.com/repos/${github_owner}/${github_repo}/actions/runners"
RUNNER_NAME="${runner_name}"
RUNNER_LABELS="${runner_labels}"

PAT=$(aws ssm get-parameter \
  --name "${pat_ssm_parameter_name}" \
  --with-decryption \
  --query Parameter.Value \
  --output text)

request_token() {
  local endpoint="$1"

  curl -fsS -X POST \
    -H "Authorization: token $PAT" \
    -H "Accept: application/vnd.github+json" \
    "$RUNNERS_API/$endpoint" \
    | jq -er .token
}

remove_local_runner() {
  if [[ -f .runner || -f .credentials ]]; then
    local remove_token
    remove_token="$(request_token remove-token)"
    ./config.sh remove --token "$remove_token" || true
  fi
}

case "$MODE" in
  register)
    remove_local_runner

    REG_TOKEN="$(request_token registration-token)"

    ./config.sh \
      --url "$REPO_URL" \
      --token "$REG_TOKEN" \
      --name "$RUNNER_NAME" \
      --labels "$RUNNER_LABELS" \
      --unattended \
      --ephemeral \
      --replace
    ;;

  unregister)
    remove_local_runner
    ;;

  *)
    echo "Usage: $0 [register|unregister]" >&2
    exit 2
    ;;
esac
