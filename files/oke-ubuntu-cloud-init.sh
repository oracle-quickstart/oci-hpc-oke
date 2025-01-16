#!/bin/bash
set -x

distrib_codename=$(lsb_release -c -s)
kubernetes_version=$1
oke_package_version="${kubernetes_version:1}"
oke_package_repo_version="${oke_package_version:0:4}"
oke_package_name="oci-oke-node-all-$oke_package_version"
oke_package_repo="https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-$distrib_codename/kubernetes-$oke_package_repo_version"

# Add OKE Ubuntu package repo
add-apt-repository -y "deb [trusted=yes] $oke_package_repo stable main"

# Wait for apt lock and install the package
while fuser /var/{lib/{dpkg/{lock,lock-frontend},apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
   echo "Waiting for dpkg/apt lock"
   sleep 1
done

apt-get -y update

apt-get -y install $oke_package_name

# OKE bootstrap
oke bootstrap
