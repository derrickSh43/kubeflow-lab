# shellcheck shell=bash
# Shared helpers. Source this, do not execute it.

set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="$ROOT/.state"
mkdir -p "$STATE_DIR"

# --- pretty ----------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_DIM=$'\033[2m';  C_OFF=$'\033[0m'; C_BLD=$'\033[1m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_OFF=''; C_BLD=''
fi

ok()    { printf '  %s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_YEL" "$C_OFF" "$*"; }
fail()  { printf '  %s✘%s %s\n' "$C_RED" "$C_OFF" "$*"; }
info()  { printf '  %s·%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLU" "$C_OFF" "$C_BLD" "$*" "$C_OFF"; }
die()   { fail "$*"; exit 1; }

# --- versions --------------------------------------------------------------
# VERSIONS holds the pins. VERSIONS.lock, if present, wins (written by
# `make freeze`) so a team shares byte-identical tooling.
load_versions() {
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$ROOT/VERSIONS"
  [[ -f "$ROOT/VERSIONS.lock" ]] && source "$ROOT/VERSIONS.lock"
  set +a
}

# --- tier ------------------------------------------------------------------
TIER="${TIER:-0}"

tier_ram_gb()  { case "$TIER" in 0) echo 6  ;; 1) echo 14 ;; 2) echo 20 ;; esac; }
tier_disk_gb() { case "$TIER" in 0) echo 25 ;; 1) echo 55 ;; 2) echo 75 ;; esac; }
tier_name()    { case "$TIER" in
                   0) echo "Pipelines standalone" ;;
                   1) echo "Community Distribution (no serving)" ;;
                   2) echo "Community Distribution (full)" ;;
                 esac; }

validate_tier() {
  case "$TIER" in 0|1|2) ;; *) die "TIER must be 0, 1 or 2 (got '$TIER')" ;; esac
}

# --- the toolbox -----------------------------------------------------------
# Every CLI lives in one pinned image. Nobody installs kubectl, kustomize,
# kind or helm on their laptop - that is the whole point. The container gets:
#   - the docker socket, so `kind` can create sibling containers
#   - the `kind` docker network, so kubectl can reach the API server directly
#   - /state, where the kubeconfig lives
TOOLBOX_IMAGE="kubeflow-lab/toolbox:local"

toolbox_exists() { docker image inspect "$TOOLBOX_IMAGE" >/dev/null 2>&1; }

require_toolbox() {
  toolbox_exists || die "Toolbox image missing. Run: make tools"
}

# Network to attach to. Before the cluster exists there is no `kind` network,
# so we fall back to the default bridge for cluster-creation calls.
toolbox_net() {
  docker network inspect kind >/dev/null 2>&1 && echo "kind" || echo "bridge"
}

_toolbox_run() {
  local tty_flag="$1"; shift
  local extra=()
  # shellcheck disable=SC2206
  [[ -n "${TOOLBOX_PORTS:-}" ]] && extra=($TOOLBOX_PORTS)
  docker run --rm $tty_flag \
    --network "$(toolbox_net)" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$ROOT:/work" -w /work \
    -v "$STATE_DIR:/state" \
    -e KUBECONFIG=/state/kubeconfig \
    -e CLUSTER_NAME="$CLUSTER_NAME" \
    "${extra[@]}" \
    "$TOOLBOX_IMAGE" "$@"
}

tb()      { require_toolbox; _toolbox_run "-i" "$@"; }
tb_tty()  { require_toolbox; _toolbox_run "-it" "$@"; }

kc()  { tb kubectl "$@"; }
kz()  { tb kustomize "$@"; }
kind_() { tb kind "$@"; }

cluster_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${CLUSTER_NAME}-control-plane$"
}

# Retry a command until it succeeds or we run out of patience.
# The Kubeflow install genuinely needs this: CRDs race their consumers, so
# the first few applies are EXPECTED to fail. This is not a workaround,
# it is the documented upstream install procedure.
retry_until() {
  local tries="$1"; shift
  local delay="$1"; shift
  local n=1
  until "$@"; do
    if (( n >= tries )); then
      return 1
    fi
    warn "attempt $n/$tries failed, retrying in ${delay}s ..."
    sleep "$delay"
    ((n++))
  done
  return 0
}
