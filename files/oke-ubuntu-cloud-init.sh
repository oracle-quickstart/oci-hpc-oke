#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else
    echo "Cannot detect OS: /etc/os-release missing"
    exit 1
fi

# Disable nvidia-imex.service for GB200 and GB300 shapes for Dynamic Resource Allocation (DRA) compatibility
SHAPE=$(curl -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/shape)
if [[ "$SHAPE" == BM.GPU.GB200* ]] || [[ "$SHAPE" == BM.GPU.GB300* ]]; then
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
            echo "[Ubuntu] oke binary already present → running bootstrap only"
            oke bootstrap
        else
            echo "[Ubuntu] oke binary not found → installing package"
            kubernetes_version="$1"
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
            oke bootstrap
        fi
        ;;
    ol)
        echo "Detected Oracle Linux"
        if command -v oke >/dev/null 2>&1; then
            echo "[Oracle Linux] oke binary already present → running bootstrap only"
            oke bootstrap
        else
            echo "[Oracle Linux] oke binary not found, fetching init script"
            curl --fail -H "Authorization: Bearer Oracle" \
                 -L0 http://169.254.169.254/opc/v2/instance/metadata/oke_init_script \
            | base64 --decode >/var/run/oke-init.sh

            echo "[Oracle Linux] Running init script"
            bash /var/run/oke-init.sh
        fi
        ;;
    *)
        echo "Unsupported OS: $ID"
        exit 1
        ;;
esac

echo "OKE setup completed successfully."
