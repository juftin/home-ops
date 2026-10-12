#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-$(yq -r '.kubernetesVersion | sub("^v"; "")' "${ROOT_DIR}/talos/talenv.yaml")}"

# Check built-in API groups only. Custom resources need separately maintained schemas,
# and placeholder values cannot validate the semantics of encrypted policies.
# CRD definitions are skipped because the standard registry has no schema for them.
# Missing schemas for built-in resources are errors, not silently skipped.
yq eval '
    (.apiVersion | split("/") | .[0]) as $group |
    select($group == "v1" or
        $group == "apps" or $group == "autoscaling" or $group == "batch" or $group == "policy" or
        $group == "admissionregistration.k8s.io" or $group == "apiextensions.k8s.io" or
        $group == "apiregistration.k8s.io" or $group == "authentication.k8s.io" or
        $group == "authorization.k8s.io" or $group == "certificates.k8s.io" or
        $group == "coordination.k8s.io" or $group == "discovery.k8s.io" or
        $group == "events.k8s.io" or $group == "flowcontrol.apiserver.k8s.io" or
        $group == "networking.k8s.io" or $group == "node.k8s.io" or
        $group == "rbac.authorization.k8s.io" or $group == "resource.k8s.io" or
        $group == "scheduling.k8s.io" or $group == "storage.k8s.io")
' - | kubeconform -strict -summary -skip CustomResourceDefinition -kubernetes-version "${KUBERNETES_VERSION}"
