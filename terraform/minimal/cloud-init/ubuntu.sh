#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.29 stable main'

while fuser /var/{lib/{dpkg/{lock,lock-frontend},apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
   echo "Waiting for dpkg/apt lock"
   sleep 1
done

apt update
apt install -y oci-oke-node-all*

oke bootstrap
