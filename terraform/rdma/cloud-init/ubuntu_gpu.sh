#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://idv4srl8nzr8.objectstorage.us-phoenix-1.oci.customer-oci.com/p/XBJ8n3MAcnlyAfSATU_4jYu4W-cB2TzqXtS8WOJk6XaGOROphH2OFlsSH_2aEabJ/n/idv4srl8nzr8/b/oke_node_repo/o/ubuntu stable main'

apt install -y oci-oke-node-all=1.27.2*

oke bootstrap
