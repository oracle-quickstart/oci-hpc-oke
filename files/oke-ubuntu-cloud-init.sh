#!/bin/bash
set -x

source /etc/os-release

kubernetes_version=$1
oke_package_version="${kubernetes_version:1}"
oke_package_repo_version="${oke_package_version:0:4}"
oke_package_name="oci-oke-node-all-$oke_package_version"
oke_package_repo="https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-$VERSION_CODENAME/kubernetes-$oke_package_repo_version"

# Add OKE Ubuntu package repo
tee /etc/apt/sources.list.d/oke-node-client.sources <<EOF
Enabled: yes
Types: deb
URIs: https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-$VERSION_CODENAME/kubernetes-$oke_package_repo_version
Suites: stable
Components: main
Trusted: yes
EOF

# Wait for apt lock and install the package
while fuser /var/{lib/{dpkg/{lock,lock-frontend},apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
   echo "Waiting for dpkg/apt lock"
   sleep 1
done

for f in /etc/apt/sources.list.d/*nvidia*; do
  [ -f "$f" ] && mv "$f" "${f}.bak"
done

apt-get -y update && apt-get -y install $oke_package_name

# OKE bootstrap
oke bootstrap
