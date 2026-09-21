# When it breaks

Run `make doctor` first. It catches most of this before you waste an hour.

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
2. `make down` between sessions - `make up` reuses the image cache and is
   much faster the second time.
3. Work at tier 0 unless the lab needs more. Tier 0 boots in minutes.
4. Move the repo off `/mnt/d` into the WSL filesystem.

## Starting over

```bash
make down     # delete the cluster, keep cached images (fast rebuild)
make nuke     # delete the cluster AND the images (slow rebuild, clean slate)
```

`make nuke` is the right answer more often than you would think. Nothing in
`.state/` is precious - it is all regenerated.
