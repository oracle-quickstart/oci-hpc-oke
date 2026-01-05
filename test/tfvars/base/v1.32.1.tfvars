# Required inputs for core provisioning (API key auth).
# Replace values with your tenancy/compartment/user details.

home_region          = "us-ashburn-1"
region               = "us-ashburn-1"
tenancy_ocid           = "ocid1.tenancy.oc1..aaaaaaaawxdcmyu3bxuemm3yfj7jojapxsm6dmyx6s344bn6zsqb2ebznoyq"
compartment_ocid       = "ocid1.compartment.oc1..aaaaaaaa3p3kstuy3pkr4kj4ehgadfcnw3ivqz53xzd6i7r3hkkkddzd7u3a"
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIwZXnHrnvtAvP8wfgQBLZ9tGnBKCGxd0beP3POUhWER+jXE/N/nfMeg8arLITO6ravSCS18TUgZbcYQHSFBFjppzvPb7dcG0S1asoYI5WDDtjeL7BAYC6E/zw49o4qmJpLmp7ZjBT5/AHmk2NE1yIy2dz6y1HnHeW68Ah2o41sZuBeHsFF3+sMh0d2Mrlm88kG/3jUoZAi5loio/exMzJjN0RbE0V5KM6PJbdwspbSO0BS3cONZjAayP0dCf0YiymgsSj3Wrwx6y/b9V2tD5xBs0irjKbOwRW41DmHZxp55KjHjvhnoydMJ3dmfIvKJRxG61WkV28mzN/fhRHTPC/ opastirm@opastirm-mac"

# Cluster
kubernetes_version = "v1.32.1"

# Operational pool
worker_ops_ad              = "jLaG:US-ASHBURN-AD-1"
worker_ops_image_custom_id = "ocid1.image.oc1.iad.aaaaaaaax67s2hyjfqporivczf2g6mdoyeilvhxv3lnnr5xhfdiydzympaoq"
worker_ops_pool_size       = 1

# # GPU pool
# worker_gpu_enabled   = true
# worker_gpu_ad        = "jLaG:US-ASHBURN-AD-1"
# worker_gpu_shape     = "VM.GPU.A10.1"
# worker_gpu_pool_size = 1
# worker_gpu_image_custom_id  = "ocid1.image.oc1.iad.aaaaaaaah6izjpzcgln36zqr2dulad4uh5ty4kybyicy4ztbc3d35dzzb4na"