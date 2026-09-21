#!/usr/bin/env bash
# Stop and start the cluster without destroying it.
#
# kind "nodes" are Docker containers. Stopping them ends every process
# inside while leaving all the disk-backed state alone: pipeline runs,
# Workflows, the MySQL database, artifacts. Resuming takes under a minute,
# against 3-5 minutes for `make down && make up` - which also wipes all of
# the above.
#
# What this does NOT do, on Windows, is hand memory back to Windows.
# Stopping containers frees memory inside the WSL2 VM, but the VM keeps
# what it has already claimed. Only WSL returns it, and only if
# autoMemoryReclaim is configured - see the note printed after a pause.
#
# Use pause/resume between sessions. Use down/up when you want a clean slate
# or when a resume comes back unhealthy.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions

# kind labels every node container it creates. More reliable than matching
# on the name, which changes with the node role and count.
nodes_of_cluster() {
  docker ps -a \
    --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME" \
    --format '{{.Names}}'
}

NODES=$(nodes_of_cluster)
[[ -n "$NODES" ]] || die "no cluster '$CLUSTER_NAME'. run: make up TIER=$TIER"

case "${1:-stop}" in
  stop)
    step "Pausing cluster '$CLUSTER_NAME'"
    # shellcheck disable=SC2086
    docker stop $NODES >/dev/null
    for n in $NODES; do ok "stopped $n"; done
    cat <<TXT

  Cluster state is intact on disk - runs, database, artifacts, all of it.
  Come back with:  make resume

TXT

    # On Windows, stopping containers does not return memory to Windows.
    # Say so, rather than letting people watch Task Manager and conclude
    # the pause did nothing.
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
      cat <<'TXT'
  On WSL2, the processes are gone but the VM keeps the memory it claimed.
  To actually give it back to Windows:

    1. drop the page cache here (instant, safe):
         sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

    2. or, for all of it, from PowerShell - NOT from inside WSL:
         wsl --shutdown
       Stopped containers survive this. Start Docker Desktop again later
       and `make resume` picks up exactly where you left off.

  If memory never comes back on its own, autoMemoryReclaim is probably in
  the wrong section of .wslconfig. It belongs under [experimental], not
  [wsl2], and should be dropCache - see docs/wsl2-setup.md.

TXT
    fi
    ;;

  start)
    step "Resuming cluster '$CLUSTER_NAME'"
    # shellcheck disable=SC2086
    docker start $NODES >/dev/null
    for n in $NODES; do ok "started $n"; done

    step "Waiting for the API server"
    if retry_until 24 5 kc get --raw /readyz >/dev/null 2>&1; then
      ok "API server responding"
    else
      fail "API server did not come back after 2 minutes"
      cat <<TXT

  A resume can fail if the cluster sat for days - certificates and leases
  have timing assumptions that a long pause breaks. This is recoverable
  but not worth debugging in a lab:

      make down && make up TIER=$TIER

  Images are cached, so that is 3-5 minutes and you lose only cluster
  state - your notes and answers are files on disk and are untouched.

TXT
      exit 1
    fi

    step "Waiting for nodes"
    retry_until 24 5 kc wait --for=condition=Ready nodes --all --timeout=10s >/dev/null 2>&1 \
      && ok "nodes Ready" \
      || warn "nodes still settling - give it another minute, then: make status"

    cat <<TXT

  Back up. Pods take a minute or two to re-settle after a pause.

      make status            confirm everything is Running
      http://localhost:8080  the UI, on the same port as before

TXT
    ;;

  *) die "unknown: ${1:-} (stop|start)" ;;
esac
