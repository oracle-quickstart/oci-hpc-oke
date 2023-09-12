#!/bin/bash

# Get the API server endpoint & the CA cert from IMDS
OKE_APISERVER_ENDPOINT=$(curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ | jq -r '.metadata."apiserver_host"')
OKE_KUBELET_CA_CERT=$(curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ | jq -r '.metadata."cluster_ca_cert"')

# Adjust boot volume size        
sudo dd iflag=direct if=/dev/oracleoci/oraclevda of=/dev/null count=1
echo "1" | sudo tee /sys/class/block/`readlink /dev/oracleoci/oraclevda | cut -d'/' -f 2`/device/resca
sudo /usr/libexec/oci-growfs -y

timedatectl set-timezone $${worker_timezone}

# Initialize OKE
# Do not remove the "oci.oraclecloud.com/oci-rdma-health-check" taint. It's used to wait until the RDMA network is configured on the node. The daemonset that you will deploy with the insructions will remove the taint when network is ready. 

bash /etc/oke/oke-install.sh \
  --apiserver-endpoint $OKE_APISERVER_ENDPOINT \
  --kubelet-ca-cert $OKE_KUBELET_CA_CERT \
  --kubelet-extra-args "--register-with-taints=oci.oraclecloud.com/oci-rdma-health-check:NoSchedule"

touch /var/log/oke.done