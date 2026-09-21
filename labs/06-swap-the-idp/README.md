# Lab 06 - Replace Dex's static user with a real IdP

**Tier:** 1+
**Status:** stub

Out of the box, tier 1 authenticates `user@example.com` / `12341234` from a
static bcrypt hash in a ConfigMap. Replace that with a real OIDC connector
(Entra ID, Okta, Keycloak in a sidecar cluster, or GitHub).

Then answer: when a user logs in, which component mints the identity the
Profile controller trusts, and what header carries it to the workload?
Lab 03 question 2 is the setup for this one.
