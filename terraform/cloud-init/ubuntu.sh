#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y ''deb [trusted=yes] https://objectstorage.us-ashburn-1.oraclecloud.com/p/1_NbjfnPPmyyklGibGM-qEpujw9jEpWSLa9mXEIUFCFYqqHdUh5cFAWbj870h-g0/n/hpc_limited_availability/b/oke_node_packages/o/1.29.1/ubuntu stable main'

apt install -y oci-oke-node-all=1.29.1*

oke bootstrap --manage-gpu-services
