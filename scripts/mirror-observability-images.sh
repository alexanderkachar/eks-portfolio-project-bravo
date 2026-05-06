#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/mirror-observability-images.sh [options]

Renders charts/observability, discovers public container images, and mirrors
them into Amazon ECR while preserving repository paths. Use the printed
global.imageRegistry Helm value when deploying the observability chart.

Options:
  --chart-dir DIR   Chart directory. Default: charts/observability.
  --region REGION   AWS region. Defaults to AWS_REGION or us-east-1.
  --registry REG    ECR registry. Defaults to the current AWS account registry.
  -h, --help        Show this help.

Examples:
  scripts/mirror-observability-images.sh
  helm upgrade --install observability oci://$REGISTRY/observability \
    --namespace observability --create-namespace \
    --set-string global.imageRegistry=$REGISTRY
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

repo_name_from_image() {
  local image_without_registry="$1"
  local repo_name

  repo_name="${image_without_registry%@*}"
  repo_name="${repo_name%:*}"
  printf '%s\n' "$repo_name"
}

tag_from_image() {
  local image_without_registry="$1"

  if [[ "$image_without_registry" == *@* || "$image_without_registry" != *:* ]]; then
    return 0
  fi

  printf '%s\n' "${image_without_registry##*:}"
}

root="$(repo_root)"
chart_dir="$root/charts/observability"
region="${AWS_REGION:-us-east-1}"
registry=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart-dir)
      [[ $# -ge 2 ]] || die "--chart-dir requires a value"
      chart_dir="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "--region requires a value"
      region="$2"
      shift 2
      ;;
    --registry)
      [[ $# -ge 2 ]] || die "--registry requires a value"
      registry="$2"
      shift 2
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

require_command aws
require_command docker
require_command helm
require_command rg

[[ -d "$chart_dir" ]] || die "Chart dir not found: $chart_dir"

if [[ -z "$registry" ]]; then
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  registry="${account_id}.dkr.ecr.${region}.amazonaws.com"
fi

manifest="$(mktemp)"
trap 'rm -f "$manifest"' EXIT

helm dependency build "$chart_dir"
helm template observability "$chart_dir" --namespace observability > "$manifest"

mapfile -t images < <(
  rg -o '(docker\.io|quay\.io|registry\.k8s\.io|ghcr\.io)/[^"'\'' ,)]+' "$manifest" \
    | sed 's/[),]$//' \
    | sort -u
)

[[ "${#images[@]}" -gt 0 ]] || die "No public images found in rendered chart."

aws ecr get-login-password --region "$region" \
  | docker login --username AWS --password-stdin "$registry"

for image in "${images[@]}"; do
  image_without_registry="${image#*/}"
  repo_name="$(repo_name_from_image "$image_without_registry")"
  image_tag="$(tag_from_image "$image_without_registry")"
  target_image="$registry/$image_without_registry"

  aws ecr describe-repositories \
    --region "$region" \
    --repository-names "$repo_name" >/dev/null \
    || die "ECR repository '$repo_name' does not exist. Run terraform apply first."

  if [[ -n "$image_tag" ]] && aws ecr describe-images \
    --region "$region" \
    --repository-name "$repo_name" \
    --image-ids imageTag="$image_tag" >/dev/null 2>&1; then
    echo "Already mirrored $target_image"
    continue
  fi

  echo "Mirroring $image -> $target_image"
  docker pull "$image"
  docker tag "$image" "$target_image"
  docker push "$target_image"
done

echo "Done. Deploy with: --set-string global.imageRegistry=$registry"
