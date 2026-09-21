# Lab 01 - Trace a request

**Tier:** 0+
**Time:** 30-45 min
**You will learn:** how a browser request actually reaches a Kubeflow pod,
and how to read that path out of a live cluster instead of a diagram.

---

## Why this one is first

Every Kubeflow problem you will ever be paged for looks like "the UI is
down". Almost none of them are the UI. They are DNS, or the gateway, or a
sidecar that did not inject, or a Service with no endpoints. If you can
walk the path from `localhost:8080` to a running container without
guessing, you can debug the other 90% of this platform.

## The task

Open <http://localhost:8080>. Then, **using only `kubectl`**, write down
every hop between your browser and the process that rendered that page.

For each hop, record: the object kind, its name, its namespace, and the
one field that decides where traffic goes next.

### Tier 0 path (4 hops)

Start here:

```bash
make sh

kubectl -n kubeflow get svc ml-pipeline-ui -o yaml
kubectl -n kubeflow get endpointslices -l kubernetes.io/service-name=ml-pipeline-ui
kubectl -n kubeflow get pod -l app=ml-pipeline-ui -o wide
```

Questions to answer in `ANSWERS.md`:

1. kind maps host `8080` to container port `30080` on the control-plane
   node. Which file in this repo says so, and which field?
2. `ml-pipeline-ui` is a NodePort Service. What are its `port`,
   `targetPort` and `nodePort`, and which one does the *pod* listen on?
3. Delete nothing, but answer: if the EndpointSlice were empty, what would
   `curl localhost:8080` return, and why is that different from the pod
   being gone?
4. Which node is the pod on? Tier 0 has exactly one node, so the answer is
   "the control-plane" and that looks like the end of it. It isn't. The
   real question is **why a NodePort works at all**, and you can watch the
   machinery on a single node.

   Find out who is responsible, and how it is doing the job:

   ```bash
   kubectl -n kube-system get ds kube-proxy -o wide
   kubectl -n kube-system get cm kube-proxy -o yaml | grep -i 'mode:'
   ```

   Then read the rules it actually wrote. From the toolbox, which has the
   Docker socket:

   ```bash
   # if mode is iptables (or blank, which means iptables)
   docker exec kubeflow-lab-control-plane iptables-save -t nat | grep 30080

   # if mode is nftables
   docker exec kubeflow-lab-control-plane nft list ruleset | grep -B2 -A6 30080
   ```

   Answer: what does that rule do to a packet arriving on port 30080, and
   what address does it rewrite the destination to? Compare that address
   to the EndpointSlice output from earlier. They should match, and if you
   see why they must match, you have the whole idea.

   Then one more, which decides the answer above:

   ```bash
   kubectl -n kubeflow get svc ml-pipeline-ui -o jsonpath='{.spec.externalTrafficPolicy}'
   ```

Question 4 is the one worth the time. kube-proxy runs as a DaemonSet on
**every** node and writes those rules on every node — which is why a
NodePort answers on nodes that run none of the pods. When the pod is
elsewhere, the packet takes a second hop across the pod network, and gets
SNAT'd so the reply comes back the same way. That SNAT is why the pod sees
a node IP as the client rather than the real caller, and why
`externalTrafficPolicy: Local` exists.

You cannot observe that second hop at tier 0 — one node, nothing to hop
to. Reason it through now from the rules in front of you, then come back
and confirm it at tier 1, where there are three nodes and you can cordon
one mid-request.

### Tier 1 path (7+ hops)

Same exercise, much longer chain:

```bash
kubectl -n istio-system get svc istio-ingressgateway -o yaml
kubectl -n istio-system get gateway,virtualservice -A
kubectl -n kubeflow get virtualservice centraldashboard -o yaml
kubectl -n kubeflow get pod -l app=centraldashboard -o jsonpath='{.items[0].spec.containers[*].name}'
```

Extra questions:

5. The dashboard pod has **two** containers. What is the second one and who
   put it there? (Hint: `kubectl get ns kubeflow -o jsonpath='{.metadata.labels}'`)
6. Before you see the dashboard you get bounced to a login page. Trace that
   redirect: which VirtualService, which service, which namespace?
7. `istioctl` is not installed. Get the gateway's effective routes anyway:
   ```bash
   kubectl -n istio-system exec deploy/istio-ingressgateway -- \
     curl -s localhost:15000/config_dump | head -100
   ```
   What is port 15000 and why does every meshed pod have it?

## Done when

`bash verify.sh` passes, and `ANSWERS.md` exists with your answers to at
least questions 1-4.
