#!/usr/bin/env bash
# Preflight. Run this before `make up` and before filing any bug report.
#
# Everything here exists because it has burned somebody. The WSL2 memory
# cap and the inotify limits in particular fail *silently* - the cluster
# comes up, then pods die twenty minutes in with no obvious cause.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions
validate_tier

PROBLEMS=0
ADVISORY=0
bad()  { fail "$*"; PROBLEMS=$((PROBLEMS+1)); }
soft() { warn "$*"; ADVISORY=$((ADVISORY+1)); }

printf '\n%skubeflow-lab doctor%s   tier %s - %s\n' "$C_BLD" "$C_OFF" "$TIER" "$(tier_name)"

# --- Docker ----------------------------------------------------------------
step "Docker"
if ! command -v docker >/dev/null 2>&1; then
  bad "docker CLI not found on PATH"
elif ! docker info >/dev/null 2>&1; then
  bad "docker CLI found but the daemon is not reachable (is Docker Desktop running?)"
else
  ok "daemon reachable - $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

  # Memory the *engine* can actually use. On WSL2 this is the WSL VM's
  # allocation, not your physical RAM, and it defaults to a fraction of it.
  MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  MEM_GB=$(( MEM_BYTES / 1024 / 1024 / 1024 ))
  NEED_RAM=$(tier_ram_gb)
  if (( MEM_GB == 0 )); then
    soft "could not read Docker memory allocation"
  elif (( MEM_GB < NEED_RAM )); then
    bad "Docker can use ${MEM_GB}GB; tier $TIER needs ~${NEED_RAM}GB. See docs/wsl2-setup.md"
  else
    ok "Docker memory: ${MEM_GB}GB (tier $TIER wants ~${NEED_RAM}GB)"
  fi

  CPUS=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 0)
  NEED_CPU=$([[ "$TIER" == "0" ]] && echo 2 || echo 6)
  if (( CPUS < NEED_CPU )); then
    bad "Docker sees ${CPUS} CPUs; tier $TIER wants >= ${NEED_CPU}"
  else
    ok "Docker CPUs: ${CPUS}"
  fi

  # Kubeflow's own manifests quote ~65GB of storage for a full install.
  ROOTDIR=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)
  if AVAIL_GB=$(df -BG --output=avail "$ROOTDIR" 2>/dev/null | tail -1 | tr -dc '0-9'); then
    NEED_DISK=$(tier_disk_gb)
    if [[ -n "$AVAIL_GB" ]] && (( AVAIL_GB < NEED_DISK )); then
      bad "Docker storage has ${AVAIL_GB}GB free; tier $TIER wants ~${NEED_DISK}GB"
    else
      ok "Docker storage free: ${AVAIL_GB:-?}GB"
    fi
  else
    soft "could not measure free space at $ROOTDIR"
  fi
fi

# --- WSL2 ------------------------------------------------------------------
step "Platform"
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  ok "running under WSL2"
  WSLCFG="/mnt/c/Users/${WSL_USER:-$USER}/.wslconfig"
  if [[ -f "$WSLCFG" ]]; then
    ok ".wslconfig found at $WSLCFG"
    grep -qiE '^\s*memory\s*=' "$WSLCFG" \
      || soft ".wslconfig has no [wsl2] memory= line - WSL will take a default share of RAM"
  else
    soft "no .wslconfig found. Tier 1+ almost certainly needs one - see docs/wsl2-setup.md"
  fi
  # WSL2 defaults are low enough to break Kubeflow's many file watchers.
  # Symptom without this: controllers restart-loop with cryptic watch errors.
  for knob in max_user_instances:512 max_user_watches:524288; do
    key="${knob%%:*}"; want="${knob##*:}"
    have=$(cat "/proc/sys/fs/inotify/$key" 2>/dev/null || echo 0)
    if (( have < want )); then
      bad "fs.inotify.$key is $have, needs >= $want  (see docs/wsl2-setup.md)"
    else
      ok "fs.inotify.$key = $have"
    fi
  done
else
  ok "native Linux / macOS host"
  for knob in max_user_instances:512 max_user_watches:524288; do
    key="${knob%%:*}"; want="${knob##*:}"
    have=$(cat "/proc/sys/fs/inotify/$key" 2>/dev/null || echo 999999)
    (( have < want )) && soft "fs.inotify.$key is $have, consider raising to $want"
  done
fi

# --- Toolbox ---------------------------------------------------------------
step "Toolbox"
if toolbox_exists; then
  ok "$TOOLBOX_IMAGE present"
else
  soft "$TOOLBOX_IMAGE not built yet - 'make up' will build it (a few minutes)"
fi

# --- Pins ------------------------------------------------------------------
step "Pinned versions"
info "kubeflow        $KUBEFLOW_VERSION"
info "kfp standalone  $KFP_STANDALONE_VERSION"
info "kind            $KIND_VERSION"
info "node image      ${KIND_NODE_IMAGE%%@*}"
[[ -f "$ROOT/VERSIONS.lock" ]] \
  && ok "VERSIONS.lock present - tool versions are frozen" \
  || soft "no VERSIONS.lock - run 'make freeze' before sharing this repo"

# --- Existing cluster ------------------------------------------------------
step "Cluster"
if cluster_exists; then
  ok "kind cluster '$CLUSTER_NAME' already exists (make down to remove)"
else
  info "no cluster yet"
fi

# --- Verdict ---------------------------------------------------------------
echo
if (( PROBLEMS > 0 )); then
  printf '%s%d blocking problem(s)%s, %d advisory. Fix the red lines before `make up`.\n\n' \
    "$C_RED" "$PROBLEMS" "$C_OFF" "$ADVISORY"
  exit 1
fi
printf '%sReady%s for tier %s - %s. %d advisory note(s).\n\n' \
  "$C_GRN" "$C_OFF" "$TIER" "$(tier_name)" "$ADVISORY"
