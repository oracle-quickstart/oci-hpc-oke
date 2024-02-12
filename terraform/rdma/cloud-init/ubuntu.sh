#!/bin/bash

# Add OKE repo & install the package
add-apt-repository -y 'deb [trusted=yes] https://objectstorage.ap-osaka-1.oraclecloud.com/p/LtN5W_61bXynNHZ4J9G2dRkDiC3MWPn7vQcE4GznMJwqqZDqjAmehHuogYUld5ht/n/hpc_limited_availability/b/oke_node_repo/o/ubuntu stable main'

apt install -y oci-oke-node-all=1.27.2*

systemctl enable --no-block --now oke
