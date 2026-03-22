region           = "us-ashburn-1"
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaawxdcmyu3bxuemm3yfj7jojapxsm6dmyx6s344bn6zsqb2ebznoyq"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaa3p3kstuy3pkr4kj4ehgadfcnw3ivqz53xzd6i7r3hkkkddzd7u3a"
ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIwZXnHrnvtAvP8wfgQBLZ9tGnBKCGxd0beP3POUhWER+jXE/N/nfMeg8arLITO6ravSCS18TUgZbcYQHSFBFjppzvPb7dcG0S1asoYI5WDDtjeL7BAYC6E/zw49o4qmJpLmp7ZjBT5/AHmk2NE1yIy2dz6y1HnHeW68Ah2o41sZuBeHsFF3+sMh0d2Mrlm88kG/3jUoZAi5loio/exMzJjN0RbE0V5KM6PJbdwspbSO0BS3cONZjAayP0dCf0YiymgsSj3Wrwx6y/b9V2tD5xBs0irjKbOwRW41DmHZxp55KjHjvhnoydMJ3dmfIvKJRxG61WkV28mzN/fhRHTPC/ opastirm@opastirm-mac"

# Bastion Service (the thing being tested)
create_oci_bastion_service = true
create_bastion             = false
create_operator            = false

# Public endpoint so Helm provider can reach the cluster from local machine
# Bastion service still connects to the private endpoint for testing
control_plane_is_public = true

# Operational pool
worker_ops_ad              = "jLaG:US-ASHBURN-AD-1"
worker_ops_image_custom_id = "ocid1.image.oc1.iad.aaaaaaaa7fglgziye2d6tfn6pjutgxdn4azfpexcupao5bwun6jpgqhg73nq"
worker_ops_pool_size       = 3

# Disable optional components for a lean test deploy
create_lustre = false
create_fss    = false

install_monitoring                                  = false
install_node_problem_detector_kube_prometheus_stack = false
install_grafana                                     = false
install_grafana_dashboards                          = false
install_nvidia_dcgm_exporter                        = false
install_mpi_operator                                = false
install_oci_hpc_oke_utils                           = false
install_kueue                                       = false
setup_alerting                                      = false
