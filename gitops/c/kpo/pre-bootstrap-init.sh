#!/usr/bin/env bash
# KPO still invokes /etc/oke/oke-install.sh with the Oracle Linux argument
# contract. Ubuntu OKE images provide /usr/bin/oke bootstrap with different
# flag names, so create a small compatibility wrapper.

set -o errexit
set -o nounset
set -o pipefail

install -d -m 0755 /etc/oke
cat >/etc/oke/oke-install.sh <<'EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

apiserver_host=""
apiserver_port="6443"
ca=""
kubelet_extra_args=""

while (($#)); do
  case "$1" in
    --apiserver-endpoint)
      endpoint="${2:-}"
      if [[ -z "${endpoint}" ]]; then
        echo "missing value for --apiserver-endpoint" >&2
        exit 2
      fi
      if [[ "${endpoint}" =~ ^\[(.*)\]:(.*)$ ]]; then
        apiserver_host="${BASH_REMATCH[1]}"
        apiserver_port="${BASH_REMATCH[2]}"
      elif [[ "${endpoint}" == *:* && "${endpoint}" != *","* ]]; then
        apiserver_host="${endpoint%:*}"
        apiserver_port="${endpoint##*:}"
      else
        apiserver_host="${endpoint}"
      fi
      shift 2
      ;;
    --kubelet-ca-cert)
      ca="${2:-}"
      shift 2
      ;;
    --kubelet-extra-args)
      kubelet_extra_args="${2:-}"
      shift 2
      ;;
    *)
      echo "unsupported argument: $1" >&2
      exit 2
      ;;
  esac
done

exec /usr/bin/oke bootstrap \
  --apiserver-host "${apiserver_host}" \
  --apiserver-port "${apiserver_port}" \
  --ca "${ca}" \
  --kubelet-extra-args "${kubelet_extra_args}"
EOF
chmod 0755 /etc/oke/oke-install.sh
