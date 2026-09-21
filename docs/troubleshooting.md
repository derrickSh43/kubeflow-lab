# When it breaks

Run `make doctor` first. It catches most of this before you waste an hour.

## `make up` dies at "Starting control-plane"

Symptom: kind creates the node container, generates certificates, writes
the static pod manifests — then hundreds of lines of

```
round_trippers.go:632] "Response" verb="POST" url="https://.../clusterrolebindings?timeout=10s" status="" milliseconds=0
```

ending in `context deadline exceeded`.

Cause: **cgroup v1**. Kubernetes 1.36 does not run on it. The API server
never starts, so every request kubeadm makes returns an empty status until
it gives up.

The real message is the *first* line of the output, hundreds of lines
earlier:

```
cgroup v1 is deprecated in Kubernetes and will not be supported in a
future kind release, please upgrade to cgroup v2
```

Fix: [wsl2-setup.md §2](wsl2-setup.md). Short version — add
`kernelCommandLine = cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1`
to `.wslconfig`, `wsl --shutdown`, and confirm with
`docker info --format '{{.CgroupVersion}}'`.

`make doctor` checks this now and blocks on v1.

## "The connection to the server localhost:8080 was refused"

You are running `make` inside the toolbox container. Type `exit` and run it
from your host shell.

That message is kubectl's behaviour when it finds **no kubeconfig at all** -
it falls back to a compiled-in default of `localhost:8080`. It is almost
never a dead cluster.

Why it happens: `make` inside the toolbox spawns a nested toolbox container
and passes `-v /work:/work -v /work/.state:/state`. Volume paths are
resolved by the Docker daemon on the *host*, where `/work` does not exist,
so Docker creates empty directories and mounts those. No kubeconfig, hence
the fallback.

`scripts/lib.sh` now refuses to run inside the toolbox and says so. If you
still see the raw error, rebuild the image: `exit`, then `make tools`.

## Warnings that are fine

`make status` shows warnings during and shortly after an install. These
four are expected. Anything else, read carefully.

**`proxy-agent ... violates PodSecurity "baseline:latest": host namespaces
(hostNetwork=true)`**

Permanent, and harmless. `proxy-agent` is Google's inverting-proxy agent —
it exposes the KFP UI through a Google-managed URL and depends on the GCP
metadata server. Useless on a local cluster; it would crash even if it
could start. It cannot start, because the `kubeflow` namespace enforces
PodSecurity `baseline` and the pod wants `hostNetwork: true`.

Admission control is doing its job. `up.sh` scales the deployment to zero
so it stops shouting. If you see it, you are on a cluster created before
that was added:

```bash
kubectl -n kubeflow scale deploy/proxy-agent --replicas=0
```

**`MountVolume.SetUp failed for volume "webhook-tls-certs": secret
"webhook-server-tls" not found`**

A startup race. `cache-deployer` generates that secret as a Job, and
`cache-server` is scheduled before it finishes. Resolves itself in a few
minutes. If it is still there after ten:

```bash
kubectl -n kubeflow get jobs
kubectl -n kubeflow logs job/cache-deployer-deployment
```

**`coredns ... Readiness probe failed: connection refused`**, in the first
couple of minutes — CoreDNS answering probes before it is listening.
Transient.

**`kube-apiserver ... Liveness probe failed: statuscode: 500`**, during
the install — the API server is busy admitting hundreds of objects at
once and briefly fails its own probe. Transient *unless* it repeats after
things settle, or the pod's restart count climbs:

```bash
kubectl -n kube-system get pod -l component=kube-apiserver
```

A rising `RESTARTS` column there means real pressure — usually memory.

## The install never converges

`up.sh` retries 25 times. If it exhausts that:

```bash
make status          # shows only the pods that are NOT healthy
```

Then, in order of likelihood:

| Symptom | Usual cause |
|---|---|
| Pods `Pending`, events say `Insufficient memory` | WSL2 memory cap - see docs/wsl2-setup.md |
| `ImagePullBackOff` on many pods | slow pull, or out of disk. `docker system df` |
| Controllers `CrashLoopBackOff` after ~20 min | inotify limits - see docs/wsl2-setup.md |
| `no matches for kind ...` forever | a CRD genuinely failed; `kubectl get crd \| wc -l` |
| Everything Pending, nodes `NotReady` | kind node died. `docker logs kubeflow-lab-control-plane` |

## `kubectl` from the toolbox hangs

The toolbox needs the `kind` docker network. If the cluster was created but
the network is gone:

```bash
docker network inspect kind | head
make down && make up
```

## The UI does not load on localhost:8080

The NodePort patch is the load-bearing bit. Check it:

```bash
make sh
kubectl -n kubeflow get svc ml-pipeline-ui -o jsonpath='{.spec.type}{" "}{.spec.ports[0].nodePort}'   # tier 0
kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.type}{" "}{.spec.ports[*].nodePort}'  # tier 1+
```

Want `NodePort 30080`. If it is `ClusterIP`, re-run `make up` (idempotent)
or fall back to `make forward`.

At tier 1+ also confirm the gateway pod is up - a `Pending`
istio-ingressgateway is usually the memory cap again.

## Login loop at tier 1+

You log in and land back on the login page. Almost always oauth2-proxy or
Dex not ready yet:

```bash
kubectl -n auth get pods
kubectl -n oauth2-proxy get pods
kubectl -n auth logs deploy/dex --tail=50
```

Give it ten minutes after `make up` says it is done. The message is
accurate about the manifests having converged, not about every pod being
ready.

## It is slow and my laptop is unusable

Expected at tier 1+. Things that help, in order:

1. Raise `memory=` in `.wslconfig` and `wsl --shutdown`.
2. `make pause` between sessions - frees the memory back to Windows and
   keeps your cluster state. `make down` also frees it but destroys the
   cluster.
3. Work at tier 0 unless the lab needs more. Tier 0 boots in minutes.
4. Move the repo off `/mnt/d` into the WSL filesystem.

## Starting over

```bash
make down     # delete the cluster, keep cached images (fast rebuild)
make nuke     # delete the cluster AND the images (slow rebuild, clean slate)
```

`make nuke` is the right answer more often than you would think. Nothing in
`.state/` is precious - it is all regenerated.
