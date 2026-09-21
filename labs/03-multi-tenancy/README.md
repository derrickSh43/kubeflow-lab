# Lab 03 - Prove the tenancy boundary

**Tier:** 1+
**Time:** 60-90 min
**You will learn:** how Kubeflow turns a namespace into a tenant, and -
more usefully - how to test an isolation claim instead of believing it.

---

## Why this is the highest-value lab here

If you do one lab from this repo, do this one. "Namespace per team" is the
single most common multi-tenancy design in Kubernetes, and Kubeflow's
Profile controller is a complete, readable implementation of it: it creates
the namespace, the RBAC, the quota, the service account, the Istio
AuthorizationPolicy and the object-storage credentials, all from one CR.

Whether that boundary actually holds is a question you should be able to
answer with evidence, for any platform you are asked to run.

## The task

### 1. Read the controller's output before you write anything

The install already made you a Profile. Look at what it produced:

```bash
make sh
kubectl get profiles
kubectl get profile kubeflow-user-example-com -o yaml
kubectl get ns kubeflow-user-example-com -o yaml
kubectl -n kubeflow-user-example-com get rolebindings,serviceaccounts,resourcequota,authorizationpolicies
```

Write down, in `ANSWERS.md`:

1. Which objects did the Profile controller create that you did *not* write?
2. What does the `AuthorizationPolicy` in that namespace actually say? Which
   header does it trust, and who sets that header?

Question 2 matters more than it looks. The answer explains why the mesh is
load-bearing for tenancy here, not decoration.

### 2. Make a second tenant

```bash
kubectl apply -f profile-team-b.yaml
kubectl get ns team-b -w
```

3. Diff the two namespaces. What differs besides the name?

### 3. Now try to break it

This is the part people skip. Do not skip it.

```bash
# a) cross-namespace read with team-b's service account
kubectl -n team-b create token default-editor > /tmp/tb.token

kubectl --token="$(cat /tmp/tb.token)" \
  -n kubeflow-user-example-com get pods
# expected: Forbidden. If it is not, stop and find out why.

# b) network path - can a pod in team-b reach the other tenant's services?
kubectl -n team-b run probe --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s -m 5 -o /dev/null -w '%{http_code}\n' \
  http://ml-pipeline-ui.kubeflow-user-example-com/

# c) object storage - the interesting one
# the secret name depends on which object store your build ships -
# find it first rather than trusting the name below
kubectl -n team-b get secret | grep -Ei 'artifact|minio|seaweed'

kubectl -n team-b get secret mlpipeline-minio-artifact -o jsonpath='{.data.accesskey}' | base64 -d
kubectl -n kubeflow-user-example-com get secret mlpipeline-minio-artifact -o jsonpath='{.data.accesskey}' | base64 -d
```

4. Did (a) fail? Good. Did (b) fail? Record the exact failure mode - was it
   RBAC, a NetworkPolicy, an Istio AuthorizationPolicy, or nothing at all?
5. **(c) is the one to think hard about.** Compare the two secrets. If both
   tenants hold the same object-store credentials, what exactly stops team-b from
   reading the other tenant's pipeline artifacts? Test your answer - do not
   assume it.

### 4. Write it up

6. In three sentences: if a colleague asked "is this multi-tenancy safe
   enough to put two customers on?", what would you say, and what would you
   want to change first?

Question 6 is the deliverable. Everything above is evidence-gathering for
it.

## Done when

`bash verify.sh` passes - `team-b` exists as a Profile-managed namespace
with the controller-created objects present - and `ANSWERS.md` covers
questions 1-6.

## Cleanup

```bash
kubectl delete -f profile-team-b.yaml   # the controller garbage-collects the namespace
```
