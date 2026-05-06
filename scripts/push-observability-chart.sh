#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/push-observability-chart.sh [options]

Packages charts/observability, builds Helm dependencies, and pushes the chart
to Amazon ECR as an OCI artifact.

Options:
  --chart-dir DIR       Chart directory. Default: charts/observability.
  --repository NAME     ECR repository for the chart. Defaults to
                        OBSERVABILITY_HELM_CHART_ECR_REPOSITORY or observability.
                        The repository must end with the chart name.
  --region REGION       AWS region. Defaults to AWS_REGION or us-east-1.
  --version VERSION     Package version. Defaults to <chart-version>-<timestamp>.
  --app-version VERSION App version. Defaults to the chart appVersion.
  --registry REGISTRY   ECR registry. Defaults to the current AWS account registry.
  -h, --help            Show this help.

Examples:
  scripts/push-observability-chart.sh
  scripts/push-observability-chart.sh --repository observability --version 0.1.0-1
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

ensure_helm_repositories() {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
  helm repo add grafana https://grafana.github.io/helm-charts --force-update
  helm repo update prometheus-community grafana
}

root="$(repo_root)"
chart_dir="$root/charts/observability"
repository="${OBSERVABILITY_HELM_CHART_ECR_REPOSITORY:-observability}"
region="${AWS_REGION:-us-east-1}"
version=""
app_version=""
registry=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart-dir)
      [[ $# -ge 2 ]] || die "--chart-dir requires a value"
      chart_dir="$2"
      shift 2
      ;;
    --repository)
      [[ $# -ge 2 ]] || die "--repository requires a value"
      repository="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "--region requires a value"
      region="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || die "--version requires a value"
      version="$2"
      shift 2
      ;;
    --app-version)
      [[ $# -ge 2 ]] || die "--app-version requires a value"
      app_version="$2"
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
require_command helm

[[ -d "$chart_dir" ]] || die "Chart dir not found: $chart_dir"

chart_metadata="$(helm show chart "$chart_dir")"
chart_name="$(awk -F': ' '$1 == "name" {print $2}' <<<"$chart_metadata")"
base_version="$(awk -F': ' '$1 == "version" {print $2}' <<<"$chart_metadata")"
default_app_version="$(awk -F': ' '$1 == "appVersion" {gsub(/^"|"$/, "", $2); print $2}' <<<"$chart_metadata")"

[[ -n "$chart_name" ]] || die "Unable to read chart name from $chart_dir"
[[ -n "$base_version" ]] || die "Unable to read chart version from $chart_dir"

version="${version:-${base_version}-$(date -u +%Y%m%d%H%M%S)}"
app_version="${app_version:-$default_app_version}"

if [[ "${repository##*/}" != "$chart_name" ]]; then
  die "--repository must end with chart name '$chart_name'"
fi

if [[ -z "$registry" ]]; then
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  registry="${account_id}.dkr.ecr.${region}.amazonaws.com"
fi

if [[ "$repository" == "$chart_name" ]]; then
  push_target="oci://${registry}"
else
  push_target="oci://${registry}/${repository%/$chart_name}"
fi

package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT

echo "Chart:      $chart_dir"
echo "Version:    $version"
echo "Repository: $registry/$repository"

ensure_helm_repositories
helm dependency build "$chart_dir"

aws ecr get-login-password --region "$region" \
  | helm registry login --username AWS --password-stdin "$registry"

package_args=(
  "$chart_dir"
  --destination "$package_dir"
  --version "$version"
)

if [[ -n "$app_version" ]]; then
  package_args+=(--app-version "$app_version")
fi

package_path="$(helm package "${package_args[@]}" | awk '{print $NF}')"
helm push "$package_path" "$push_target"

echo "Pushed: oci://$registry/$repository:$version"
