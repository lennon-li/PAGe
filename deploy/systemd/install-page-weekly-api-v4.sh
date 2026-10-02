#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./deploy/systemd/install-page-weekly-api-v4.sh check   /path/to/weekly-api-v4.env
  sudo ./deploy/systemd/install-page-weekly-api-v4.sh install /path/to/weekly-api-v4.env

The env file must define the variables from page-weekly-api-v4.env.example.
`check` performs production-host validation without changing systemd.
`install` performs the same validation, builds a content-addressed API deployment,
installs/starts the API service, and leaves the weekly timer disabled.
EOF
}

[[ $# -eq 2 ]] || { usage >&2; exit 64; }
MODE=$1
ENV_FILE=$2
[[ "$MODE" == check || "$MODE" == install ]] || { usage >&2; exit 64; }
[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 77; }
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || { echo "env file must be a regular non-symlink file" >&2; exit 78; }
[[ $(stat -c '%u' "$ENV_FILE") -eq 0 ]] || { echo "env file must be root-owned" >&2; exit 78; }
[[ -z $(find "$ENV_FILE" -maxdepth 0 -perm /022 -print -quit) ]] || { echo "env file must not be group/world writable" >&2; exit 78; }

# Root-owned deployment configuration is trusted input for this installer.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required=(
  PAGE_API_BIND_HOST PAGE_API_PORT PAGE_API_TOKEN_FILE PAGE_RELEASE_DIR
  PAGE_ARTIFACT_MOUNT PAGE_ARTIFACT_FS_TYPE PAGE_ARTIFACT_MOUNT_SOURCE
  PAGE_JOB_ROOT PAGE_OUTPUT_ROOT PAGE_SOURCE_MODE PAGE_SEASON PAGE_RSCRIPT
  PAGE_MAX_RUNTIME_SECONDS
)
for k in "${required[@]}"; do
  [[ -n "${!k:-}" ]] || { echo "missing required variable: $k" >&2; exit 78; }
done

[[ "$PAGE_API_BIND_HOST" == 127.0.0.1 || "$PAGE_API_BIND_HOST" == ::1 ]] || { echo "API bind host must be loopback" >&2; exit 78; }
[[ "$PAGE_SEASON" == 2026-27 ]] || { echo "PAGE_SEASON must be 2026-27" >&2; exit 78; }
[[ "$PAGE_SOURCE_MODE" =~ ^(auto|orvt|olis)$ ]] || { echo "invalid PAGE_SOURCE_MODE" >&2; exit 78; }
[[ "$PAGE_ARTIFACT_FS_TYPE" == nfs || "$PAGE_ARTIFACT_FS_TYPE" == nfs4 ]] || { echo "artifact fs must be nfs/nfs4" >&2; exit 78; }

REPO_ROOT=${PAGE_REPO_ROOT:-/opt/page/PAGe-m1-v2}
DEPLOYMENT_ROOT=${PAGE_API_DEPLOYMENT_ROOT:-$PAGE_ARTIFACT_MOUNT/api-deployments}
SERVICE_USER=${PAGE_SERVICE_USER:-page}
SERVICE_GROUP=${PAGE_SERVICE_GROUP:-page}
SYSTEMD_UNIT=/etc/systemd/system/page-weekly-api-v4.service
SYSTEMD_ENV=/etc/page/weekly-api-v4.env
PREFLIGHT_RESULT=/run/page-weekly-api-v4-preflight.json
EXPECTED_RELEASE=5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b

[[ -d "$REPO_ROOT" ]] || { echo "repo root missing: $REPO_ROOT" >&2; exit 78; }
[[ -x "$PAGE_RSCRIPT" && ! -L "$PAGE_RSCRIPT" ]] || { echo "PAGE_RSCRIPT must be executable regular binary" >&2; exit 78; }
[[ -d "$PAGE_RELEASE_DIR" && "$(basename "$PAGE_RELEASE_DIR")" == "$EXPECTED_RELEASE" ]] || { echo "release dir must be canonical release $EXPECTED_RELEASE" >&2; exit 78; }
getent passwd "$SERVICE_USER" >/dev/null || { echo "service user missing: $SERVICE_USER" >&2; exit 78; }
getent group "$SERVICE_GROUP" >/dev/null || { echo "service group missing: $SERVICE_GROUP" >&2; exit 78; }
[[ -f "$PAGE_API_TOKEN_FILE" && ! -L "$PAGE_API_TOKEN_FILE" ]] || { echo "token file missing/non-regular" >&2; exit 78; }
[[ $(stat -c '%a' "$PAGE_API_TOKEN_FILE") =~ ^(400|440|600|640)$ ]] || { echo "token file permissions too broad" >&2; exit 78; }

for p in "$PAGE_ARTIFACT_MOUNT" "$PAGE_JOB_ROOT" "$PAGE_OUTPUT_ROOT" "$DEPLOYMENT_ROOT"; do
  mkdir -p "$p"
done

actual_fstype=$(findmnt -n -o FSTYPE --target "$PAGE_ARTIFACT_MOUNT")
actual_source=$(findmnt -n -o SOURCE --target "$PAGE_ARTIFACT_MOUNT")
[[ "$actual_fstype" == "$PAGE_ARTIFACT_FS_TYPE" ]] || { echo "artifact fs type mismatch: expected $PAGE_ARTIFACT_FS_TYPE got $actual_fstype" >&2; exit 78; }
[[ "$actual_source" == "$PAGE_ARTIFACT_MOUNT_SOURCE" ]] || { echo "artifact mount source mismatch: expected $PAGE_ARTIFACT_MOUNT_SOURCE got $actual_source" >&2; exit 78; }

case "$PAGE_SOURCE_MODE" in
  olis)
    [[ -n "${PAGE_OLIS_FALLBACK:-}" && -f "$PAGE_OLIS_FALLBACK" && ! -L "$PAGE_OLIS_FALLBACK" ]] || { echo "OLIS source missing/non-regular" >&2; exit 78; }
    ;;
  auto)
    if [[ -n "${PAGE_OLIS_FALLBACK:-}" ]]; then
      [[ -f "$PAGE_OLIS_FALLBACK" && ! -L "$PAGE_OLIS_FALLBACK" ]] || { echo "configured OLIS fallback missing/non-regular" >&2; exit 78; }
    fi
    ;;
esac

cd "$REPO_ROOT"

build_args=(
  "--deployment-root=$DEPLOYMENT_ROOT"
  "--artifact-mount=$PAGE_ARTIFACT_MOUNT"
  "--artifact-fs-type=$PAGE_ARTIFACT_FS_TYPE"
  "--artifact-mount-source=$PAGE_ARTIFACT_MOUNT_SOURCE"
  "--job-root=$PAGE_JOB_ROOT"
  "--output-root=$PAGE_OUTPUT_ROOT"
  "--source-mode=$PAGE_SOURCE_MODE"
  "--season=$PAGE_SEASON"
  "--bind-host=$PAGE_API_BIND_HOST"
  "--port=$PAGE_API_PORT"
  "--rscript=$PAGE_RSCRIPT"
  "--forecast-release-dir=$PAGE_RELEASE_DIR"
  "--max-runtime-seconds=$PAGE_MAX_RUNTIME_SECONDS"
  "--mode=production"
)
if [[ -n "${PAGE_OLIS_FALLBACK:-}" ]]; then
  build_args+=("--olis-fallback=$PAGE_OLIS_FALLBACK")
fi

build_out=$($PAGE_RSCRIPT --vanilla scripts/build_v3_weekly_api_deployment_v4.R "${build_args[@]}")
printf '%s\n' "$build_out"
DEPLOYMENT_ID=$(awk -F': ' '$1=="deployment_id"{print $2}' <<<"$build_out")
DEPLOYMENT_DIR=$(awk -F': ' '$1=="deployment_dir"{print $2}' <<<"$build_out")
[[ "$DEPLOYMENT_ID" =~ ^[0-9a-f]{64}$ && -d "$DEPLOYMENT_DIR" ]] || { echo "deployment builder did not return valid identity" >&2; exit 70; }

$PAGE_RSCRIPT --vanilla 2026/run_page_weekly_api_preflight_v4.R \
  "--deployment-dir=$DEPLOYMENT_DIR" \
  "--repo-root=$REPO_ROOT" \
  "--release-dir=$PAGE_RELEASE_DIR" \
  "--expected-release-id=$EXPECTED_RELEASE" \
  "--result-path=$PREFLIGHT_RESULT"

grep -q '"ok":true' "$PREFLIGHT_RESULT" || { echo "preflight failed" >&2; exit 70; }

echo "production preflight PASS deployment_id=$DEPLOYMENT_ID"

if [[ "$MODE" == check ]]; then
  echo "check-only mode: no systemd files changed"
  exit 0
fi

install -d -m 0750 -o root -g "$SERVICE_GROUP" /etc/page
TMP_ENV=$(mktemp)
trap 'rm -f "$TMP_ENV"' EXIT
awk '!/^PAGE_API_DEPLOYMENT_DIR=/' "$ENV_FILE" > "$TMP_ENV"
printf 'PAGE_API_DEPLOYMENT_DIR=%s\n' "$DEPLOYMENT_DIR" >> "$TMP_ENV"
install -m 0640 -o root -g "$SERVICE_GROUP" "$TMP_ENV" "$SYSTEMD_ENV"

TMP_UNIT=$(mktemp)
trap 'rm -f "$TMP_ENV" "$TMP_UNIT"' EXIT
sed \
  -e "s|^User=.*|User=$SERVICE_USER|" \
  -e "s|^Group=.*|Group=$SERVICE_GROUP|" \
  -e "s|^WorkingDirectory=.*|WorkingDirectory=$REPO_ROOT|" \
  -e "s|^EnvironmentFile=.*|EnvironmentFile=$SYSTEMD_ENV|" \
  -e "s|^ExecStart=.*|ExecStart=$PAGE_RSCRIPT --vanilla 2026/run_page_weekly_api_v4.R|" \
  -e "s|^ReadOnlyPaths=.*|ReadOnlyPaths=$REPO_ROOT $PAGE_RELEASE_DIR${PAGE_OLIS_FALLBACK:+ $PAGE_OLIS_FALLBACK}|" \
  -e "s|^# ReadWritePaths=.*|ReadWritePaths=$PAGE_JOB_ROOT $PAGE_OUTPUT_ROOT|" \
  deploy/systemd/page-weekly-api-v4.service > "$TMP_UNIT"
install -m 0644 -o root -g root "$TMP_UNIT" "$SYSTEMD_UNIT"

systemctl daemon-reload
systemctl disable --now page-weekly-trigger.timer 2>/dev/null || true
systemctl enable --now page-weekly-api-v4.service
systemctl --no-pager --full status page-weekly-api-v4.service

if ! curl --fail --silent --show-error "http://$PAGE_API_BIND_HOST:$PAGE_API_PORT/v1/health" >/tmp/page-weekly-api-v4-health.json || \
   ! curl --fail --silent --show-error "http://$PAGE_API_BIND_HOST:$PAGE_API_PORT/v1/readiness" >/tmp/page-weekly-api-v4-readiness.json; then
  echo "API v4 health/readiness failed; rolling service back to disabled/stopped" >&2
  systemctl disable --now page-weekly-api-v4.service || true
  exit 70
fi
cat /tmp/page-weekly-api-v4-health.json; echo
cat /tmp/page-weekly-api-v4-readiness.json; echo

echo "API v4 installed and started. Weekly timer remains disabled."
echo "Next: perform one reviewed real weekF12+ trigger and idempotent retry before enabling the timer."
