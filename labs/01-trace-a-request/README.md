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
4. Which node is the pod on? If it is a worker and the NodePort is mapped
   on the control-plane, how does the traffic still arrive?

Question 4 is the one worth the time. The answer is kube-proxy, and
understanding it is most of Kubernetes networking.

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
