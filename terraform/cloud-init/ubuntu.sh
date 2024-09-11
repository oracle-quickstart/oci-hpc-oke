#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.29 stable main'

apt install -y oci-oke-node-all=1.29.1*

oke bootstrap --manage-gpu-services
