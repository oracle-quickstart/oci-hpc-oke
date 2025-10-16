#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    echo "Cannot detect OS: /etc/os-release missing"
    exit 1
fi

version_ge() {
    local v1="$1"
    local v2="$2"

    [[ -n "$v1" ]] || return 1
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | tail -n1)" == "$v1" ]]
}

# Fix for CRI-O short name mode not being disabled for Kubernetes versions >= 1.34
configure_crio_defaults() {
    local version="$1"

    if version_ge "$version" "v1.34"; then
        echo "Configuring CRI-O defaults for Kubernetes version $version"
        mkdir -p /etc/crio/crio.conf.d
        cat >/etc/crio/crio.conf.d/11-default.conf <<'EOF'
[crio.image]
short_name_mode = "disabled"
EOF
    fi
}

# Disable nvidia-imex.service for GB200 and GB300 shapes for Dynamic Resource Allocation (DRA) compatibility
SHAPE=$(curl -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/shape 2>/dev/null) || true
if [[ -z "$SHAPE" ]]; then
    echo "Warning: Unable to fetch instance shape from metadata service, skipping nvidia-imex check" >&2
elif [[ "$SHAPE" == BM.GPU.GB200* ]] || [[ "$SHAPE" == BM.GPU.GB300* ]]; then
    echo "Disabling nvidia-imex.service for shape: $SHAPE"
    if systemctl list-unit-files | grep -q nvidia-imex.service; then
        systemctl disable --now nvidia-imex.service && systemctl mask nvidia-imex.service
    else
        echo "nvidia-imex.service not found, skipping"
    fi
fi

case "$ID" in
    ubuntu)
        echo "Detected Ubuntu"
        if command -v oke >/dev/null 2>&1; then
            echo "[Ubuntu] oke binary already present, running bootstrap only"
            kubernetes_version="${1-}"
            configure_crio_defaults "$kubernetes_version"
            oke bootstrap
        else
            echo "[Ubuntu] oke binary not found, installing package"
            kubernetes_version="${1-}"
            oke_package_version="${kubernetes_version:1}"
            oke_package_repo_version="${oke_package_version:0:4}"
            oke_package_name="oci-oke-node-all-$oke_package_version"
            oke_package_repo="https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-$VERSION_CODENAME/kubernetes-$oke_package_repo_version"

            tee /etc/apt/sources.list.d/oke-node-client.sources > /dev/null <<EOF
Enabled: yes
Types: deb
URIs: $oke_package_repo
Suites: stable
Components: main
Trusted: yes
EOF
            # Wait for apt lock and install the package
            while fuser /var/{lib/{dpkg/{lock,lock-frontend},apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
                echo "Waiting for dpkg/apt lock"
                sleep 1
            done

            apt-get -y update
            apt-get -y install "$oke_package_name"

            echo "[Ubuntu] Running bootstrap"
            configure_crio_defaults "$kubernetes_version"
            oke bootstrap
        fi
        ;;
    ol)
        echo "Detected Oracle Linux"
        if command -v oke >/dev/null 2>&1; then
            echo "[Oracle Linux] oke binary already present, running bootstrap only"
            kubernetes_version="${1-}"
            configure_crio_defaults "$kubernetes_version"
            oke bootstrap
        else
            echo "[Oracle Linux] oke binary not found, fetching init script"
            curl --fail -H "Authorization: Bearer Oracle" \
                 -L0 http://169.254.169.254/opc/v2/instance/metadata/oke_init_script \
            | base64 --decode >/var/run/oke-init.sh

            echo "[Oracle Linux] Running init script"
            kubernetes_version="${1-}"
            configure_crio_defaults "$kubernetes_version"
            bash /var/run/oke-init.sh
        fi
        ;;
    *)
        echo "Unsupported OS: $ID"
        exit 1
        ;;
esac

echo "OKE setup completed successfully."