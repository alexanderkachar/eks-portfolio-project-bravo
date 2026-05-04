#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/sync-github-actions-vars.sh [options]

Reads terraform output "github_actions_variables" and creates/updates the
matching GitHub Actions repository variables.

Options:
  --pat TOKEN             GitHub PAT to use. If omitted, the script prompts.
  --owner OWNER           GitHub owner. Defaults to github_owner in terraform.tfvars.
  --repo REPO             GitHub repo. Defaults to github_repo in terraform.tfvars.
  --terraform-dir DIR     Terraform environment dir. Default: terraform/environments/dev.
  --dry-run               Print the variables that would be synced, but do not call GitHub.
  -h, --help              Show this help.

The PAT needs permission to manage repository Actions variables.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

tfvars_value() {
  local key="$1"
  local file="$2"

  [[ -f "$file" ]] || return 0

  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

github_remote_owner_repo() {
  local remote

  remote="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$remote" ]] || return 0

  case "$remote" in
    git@github.com:*)
      remote="${remote#git@github.com:}"
      ;;
    https://github.com/*)
      remote="${remote#https://github.com/}"
      ;;
    *)
      return 0
      ;;
  esac

  remote="${remote%.git}"
  [[ "$remote" == */* ]] || return 0
  printf '%s\n' "$remote"
}

github_api() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local output_file="$4"

  if [[ -n "$body" ]]; then
    curl -sS -o "$output_file" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer $github_pat" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url" \
      -d "$body"
  else
    curl -sS -o "$output_file" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer $github_pat" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  fi
}

root="$(repo_root)"
terraform_dir="$root/terraform/environments/dev"
github_owner=""
github_repo=""
github_pat="${GITHUB_PAT:-}"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pat)
      [[ $# -ge 2 ]] || die "--pat requires a value"
      github_pat="$2"
      shift 2
      ;;
    --owner)
      [[ $# -ge 2 ]] || die "--owner requires a value"
      github_owner="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      github_repo="$2"
      shift 2
      ;;
    --terraform-dir)
      [[ $# -ge 2 ]] || die "--terraform-dir requires a value"
      terraform_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_command curl
require_command jq
require_command terraform

[[ -d "$terraform_dir" ]] || die "Terraform dir not found: $terraform_dir"

tfvars_file="$terraform_dir/terraform.tfvars"
github_owner="${github_owner:-$(tfvars_value github_owner "$tfvars_file")}"
github_repo="${github_repo:-$(tfvars_value github_repo "$tfvars_file")}"

if [[ -z "$github_owner" || -z "$github_repo" ]]; then
  remote_owner_repo="$(github_remote_owner_repo)"
  if [[ -n "$remote_owner_repo" ]]; then
    github_owner="${github_owner:-${remote_owner_repo%%/*}}"
    github_repo="${github_repo:-${remote_owner_repo#*/}}"
  fi
fi

[[ -n "$github_owner" ]] || die "GitHub owner not found. Pass --owner or set github_owner in terraform.tfvars."
[[ -n "$github_repo" ]] || die "GitHub repo not found. Pass --repo or set github_repo in terraform.tfvars."

if [[ "$dry_run" == false && -z "$github_pat" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "GitHub PAT: " github_pat
    echo
  else
    die "GitHub PAT not provided. Pass --pat TOKEN or set GITHUB_PAT."
  fi
fi

variables_json="$(terraform -chdir="$terraform_dir" output -json github_actions_variables)"
[[ "$(jq -r 'type' <<<"$variables_json")" == "object" ]] || die "Terraform output github_actions_variables must be an object."

echo "Repository: $github_owner/$github_repo"
echo "Terraform:  $terraform_dir"

if [[ "$dry_run" == true ]]; then
  echo "Dry run: would sync these GitHub Actions variables:"
  jq -r 'to_entries[] | "  \(.key)=\(.value)"' <<<"$variables_json"
  exit 0
fi

tmp_response="$(mktemp)"
trap 'rm -f "$tmp_response"' EXIT

while IFS= read -r encoded; do
  variable="$(base64 -d <<<"$encoded")"
  name="$(jq -r '.key' <<<"$variable")"
  value="$(jq -r '.value' <<<"$variable")"
  body="$(jq -n --arg name "$name" --arg value "$value" '{name: $name, value: $value}')"

  url="https://api.github.com/repos/$github_owner/$github_repo/actions/variables/$name"
  status="$(github_api PATCH "$url" "$body" "$tmp_response")"

  if [[ "$status" == "404" ]]; then
    url="https://api.github.com/repos/$github_owner/$github_repo/actions/variables"
    status="$(github_api POST "$url" "$body" "$tmp_response")"
  fi

  if [[ "$status" != "201" && "$status" != "204" ]]; then
    echo "GitHub API response:" >&2
    sed -n '1,120p' "$tmp_response" >&2
    die "Failed to sync $name. HTTP status: $status"
  fi

  echo "Synced $name"
done < <(jq -r 'to_entries[] | @base64' <<<"$variables_json")

echo "Done."
