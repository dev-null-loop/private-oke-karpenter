#!/usr/bin/env bash
# Karpenter Provider OCI OKE bootstrap compatibility shim.
#
# Export OKE bootstrap metadata into the environment before Oracle's
# standard OKE worker bootstrap entrypoint runs.

set -o errexit
set -o nounset
set -o pipefail

MD_URL="http://169.254.169.254/opc/v2/instance/metadata"
AUTH_HDR="Authorization: Bearer Oracle"

fetch_md() {
  local key="$1"
  curl -sfL -H "${AUTH_HDR}" --connect-timeout 2 --max-time 5 "${MD_URL}/${key}" 2>/dev/null || true
}

CLUSTER_DNS="$(fetch_md kubedns_svc_ip)"
KUBELET_EXTRA_ARGS="$(fetch_md kubelet-extra-args)"
APISERVER_ENDPOINT="$(fetch_md apiserver_host)"
KUBELET_CA_CERT="$(fetch_md cluster_ca_cert)"

# OKE bootstrap expects the control-plane host without the Kubernetes API port.
if [[ "${APISERVER_ENDPOINT}" =~ ^\[(.*)\](:[0-9]+)?$ ]]; then
  APISERVER_ENDPOINT="${BASH_REMATCH[1]}"
elif [[ "${APISERVER_ENDPOINT}" == *:* ]]; then
  APISERVER_ENDPOINT="${APISERVER_ENDPOINT%%:*}"
fi

[ -n "${CLUSTER_DNS}" ] && export CLUSTER_DNS
[ -n "${KUBELET_EXTRA_ARGS}" ] && export KUBELET_EXTRA_ARGS
[ -n "${APISERVER_ENDPOINT}" ] && export APISERVER_ENDPOINT
[ -n "${KUBELET_CA_CERT}" ] && export KUBELET_CA_CERT
