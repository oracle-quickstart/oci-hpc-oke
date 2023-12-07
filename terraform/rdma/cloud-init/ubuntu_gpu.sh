#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://objectstorage.us-phoenix-1.oraclecloud.com/p/ryJWdnkQSeI4ruDo9Jh77saOd5XTmORuzjv1k7GmxegExdR4atsUW2y4n7GWjkwq/n/hpc_limited_availability/b/oke_node_repo/o/ubuntu stable main'

apt install -y jq oci-oke-node-all=1.27.2*

# Initialize OKE
OKE_APISERVER_ENDPOINT=$(curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ | jq -r '.metadata."apiserver_host"')
OKE_KUBELET_CA_CERT=$(curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ | jq -r '.metadata."cluster_ca_cert"')

oke bootstrap --apiserver-host $OKE_APISERVER_ENDPOINT --ca $OKE_KUBELET_CA_CERT --num-vfs 1