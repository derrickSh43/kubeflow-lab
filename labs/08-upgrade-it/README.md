# Lab 08 - Upgrade it

**Tier:** 1+
**Status:** stub

Bump `KUBEFLOW_VERSION` in `VERSIONS` on a branch. Re-run `make up` against
the *existing* cluster rather than a fresh one. Find out what breaks.

26.03.1's release notes flag breaking dashboard changes, so there is a real
landmine waiting. This is the most realistic lab in the repo: nobody pays
you to install Kubeflow once, they pay you to still have it working two
releases later.

Record: what broke, how you found out, and whether you could have known in
advance from the release notes alone.
