# SecurityPolicy Change Playbook

## Policy changes

The encrypted policy files in `kubernetes/apps/network/envoy-gateway/app/` hold the
OIDC client IDs and email allowlists. `oauth-policy.sops.yaml` contains the admin/users
lists; `oauth-policy-internal.sops.yaml` contains the internal list.

1. With the age key available, run `sops edit <policy-file>`.
2. Change only the intended lowercase email values under
   `spec.authorization.rules[0].principal.jwt.claims[0].values`.
3. Include admin emails in the users list when required.
4. Keep the file encrypted. Do not redirect decrypted policies into persistent files.
5. Run `task lint`, `task dev:auth:test`, and `task dev:validate`.
6. Use the branch testing workflow, including `task dev:stop` when finished.

Public settings in `oauth-hardening.yaml`, the Kustomize audience replacements, and
`oauth-verified-email.yaml` enforce authentication independently of encrypted scalar
values. Default deny, the email allowlist, and verified-email enforcement are all required.
Do not add a string `email_verified` claim matcher: Google emits a boolean, which the
pinned Gateway cannot match with native string claim authorization.

Route-level SecurityPolicies can replace Gateway-level authentication. Review any new
policy or exception carefully. The only public exceptions are the exact `denied` and
`logged-out` rules on `oauth-pages`; callback and logout remain protected.

## Revocation

1. Remove the affected email from **every applicable list**, commit, push, and wait for
   the Envoy application to sync.
2. Verify SecurityPolicy status has `Accepted=True` and check the next request using an
   existing session. Authorization runs on requests; an existing session must not retain
   access after the updated policy reaches the data plane.
3. Check active WebSockets/streams separately. They were authorized when opened and can
   survive policy updates. Restart the affected **data-plane** Deployment to close them:

```bash
kubectl get deployment -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-oauth-admin
kubectl rollout restart deployment -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-oauth-admin
```

Use the users/internal owning-Gateway label when those groups are affected. Restarts use
normal draining (`180s` is configured), so do not promise instantaneous stream termination.
Verify the removed user's old connection has actually closed.

Restarting the `envoy-gateway` controller does **not** invalidate browser cookies. Envoy
stores sessions in cookies, signed with the persisted `envoy-oidc-hmac` Secret. Global
cookie invalidation requires a planned rotation of that Secret, understanding chart
ownership and the impact on every OAuth group, followed by verification with an existing
test session. Neither controller nor data-plane restarts alone rotate that key.
Google and application credentials, native app sessions, and Tailscale grants must also
be revoked when relevant; removing a Google allowlist entry does not revoke those paths.

## Rollback

Revert the policy commit, push, and verify reconciliation and access behavior. A rollback
can restore revoked access, so review allowlist changes before reverting.

For the host-cookie migration, keep Google's old callback registrations until validation
is complete. See [Authentication](AUTHENTICATION.md) for the rollout checklist.
