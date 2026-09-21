#!/usr/bin/env python3
"""A deliberately boring pipeline.

There is no model here. The point is to produce a DAG with a fan-out, a
join, and an artifact hand-off, so you have something real to watch the
Argo controller reconcile.

    python3 pipeline.py --local      # no cluster at all
    python3 pipeline.py --compile    # -> out/pipeline.yaml
    python3 pipeline.py --submit     # -> a Workflow in the cluster
"""
import argparse
import os
import sys

from kfp import dsl, compiler, local

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


@dsl.component(base_image="python:3.11-slim")
def make_rows(n: int, rows: dsl.Output[dsl.Dataset]):
    """Write n rows. Stands in for 'ingest'."""
    with open(rows.path, "w") as f:
        for i in range(n):
            f.write(f"{i},{i * i}\n")
    print(f"wrote {n} rows to {rows.path}")


@dsl.component(base_image="python:3.11-slim")
def summarize(rows: dsl.Input[dsl.Dataset], column: int) -> float:
    """Read the artifact the previous step produced. Fans out."""
    total = 0.0
    count = 0
    with open(rows.path) as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) > column:
                total += float(parts[column])
                count += 1
    mean = total / count if count else 0.0
    print(f"column {column}: n={count} mean={mean}")
    return mean


@dsl.component(base_image="python:3.11-slim")
def join(a: float, b: float) -> str:
    """The join step. Exists so the DAG is not a straight line."""
    msg = f"col0_mean={a:.2f} col1_mean={b:.2f}"
    print(msg)
    return msg


@dsl.pipeline(
    name="lab02-dag",
    description="Fan-out/join DAG for watching the Argo controller work.",
)
def lab02(n: int = 200):
    src = make_rows(n=n)
    # Two parallel steps over the same artifact -> a real fan-out in the DAG.
    left = summarize(rows=src.outputs["rows"], column=0)
    right = summarize(rows=src.outputs["rows"], column=1)
    join(a=left.output, b=right.output)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--local", action="store_true", help="run in-process, no cluster")
    g.add_argument("--compile", action="store_true", help="write out/pipeline.yaml")
    g.add_argument("--submit", action="store_true", help="submit to the cluster")
    ap.add_argument("--host", default=os.environ.get("KFP_HOST", "http://ml-pipeline-ui.kubeflow"))
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)

    if args.local:
        # SubprocessRunner needs no container runtime. DockerRunner is closer
        # to the real thing if you have one handy.
        local.init(runner=local.SubprocessRunner(use_venv=True), pipeline_root=OUT)
        lab02(n=200)
        print("\nlocal run finished. No Kubernetes was involved.")
        return

    target = os.path.join(OUT, "pipeline.yaml")
    compiler.Compiler().compile(pipeline_func=lab02, package_path=target)
    print(f"compiled -> {target}")

    if args.submit:
        from kfp.client import Client

        client = Client(host=args.host)
        run = client.create_run_from_pipeline_package(
            target, arguments={"n": 200}, enable_caching=True
        )
        print(f"submitted run {run.run_id}")
        print("now watch:  kubectl -n kubeflow get workflows -w")


if __name__ == "__main__":
    sys.exit(main())
