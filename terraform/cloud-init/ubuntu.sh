#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://objectstorage.us-phoenix-1.oraclecloud.com/p/ryJWdnkQSeI4ruDo9Jh77saOd5XTmORuzjv1k7GmxegExdR4atsUW2y4n7GWjkwq/n/hpc_limited_availability/b/oke_node_repo/o/ubuntu stable main'

apt install -y oci-oke-node-all=1.27.2*

oke bootstrap --manage-gpu-services