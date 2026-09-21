# Lab 02 - What is actually running your pipeline

**Tier:** 0+
**Time:** 45-60 min
**You will learn:** that Kubeflow Pipelines is a UI and an API over Argo
Workflows, and that "a pipeline" is a CRD instance reconciled by a
controller - the same pattern behind every operator you will ever deploy.

---

## The task

Submit the pipeline in `pipeline.py`, then ignore the UI completely and
watch what happens in the cluster.

### 1. Compile it without a cluster

The KFP SDK can execute pipelines locally, with no Kubernetes at all. This
is how you should iterate on component code - a 3-second loop instead of a
3-minute one.

```bash
make sh
cd labs/02-argo-underneath
python3 pipeline.py --local      # runs in-process, no cluster
python3 pipeline.py --compile    # writes out/pipeline.yaml
```

Read `out/pipeline.yaml`. It is not Argo YAML - it is KFP's IR. Note that
it describes a DAG, not pods.

### 2. Submit it and watch the translation

```bash
python3 pipeline.py --submit
```

Now, in another toolbox shell:

```bash
kubectl -n kubeflow get workflows -w
kubectl -n kubeflow get pods -w
```

Questions for `ANSWERS.md`:

1. `kubectl api-resources | grep -i argo` - what CRDs did KFP install, and
   which controller Deployment watches them?
2. Pick your Workflow: `kubectl -n kubeflow get wf <name> -o yaml`. Where in
   that object does the controller record progress? Why is that on the
   *object* and not in a database?
3. Each step's pod has more than one container. Name them and say what the
   extra ones do. (`kubectl -n kubeflow get pod <step-pod> -o jsonpath='{.spec.containers[*].name}'`)
4. Kill the workflow controller mid-run:
   ```bash
   kubectl -n kubeflow scale deploy/workflow-controller --replicas=0
   ```
   Do the already-running step pods die? Does the workflow advance? Scale it
   back to 1 - what happens then, and what does that tell you about how
   controllers recover state?
5. Run the *same* pipeline again unchanged. Time it. Why was it faster, and
   where is that cache stored? (`kubectl -n kubeflow get pods | grep cache`)

Question 4 is the important one. The answer - pods keep running, progress
stalls, then the controller re-reads the world from the API server and
carries on - is the reconcile loop, and it is why Kubernetes controllers
are safe to restart and your cron job is not.

## Done when

`bash verify.sh` passes: at least one Workflow has completed, and your
`ANSWERS.md` covers questions 1-4.
