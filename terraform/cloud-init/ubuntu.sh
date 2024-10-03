#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.29 stable main'

while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
    echo "Waiting for other apt instances to exit"
    # Sleep to avoid pegging a CPU core while polling this lock
    sleep 1
done

apt update
apt install -y oci-oke-node-all*

# TEMPORARY REQUIREMENT: Edit registries.conf to add unqualified registries
cat <<EOF > /etc/containers/registries.conf
unqualified-search-registries = ["container-registry.oracle.com", "docker.io"]
short-name-mode = "permissive"
EOF

oke bootstrap --manage-gpu-services
