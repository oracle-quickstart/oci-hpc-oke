# Importing images from OCI File Storage Service (FSS) to OKE nodes instead of downloading them from a registry

### 1. Create an FSS File System
https://docs.oracle.com/en-us/iaas/Content/File/Tasks/create-file-system.htm#top

### 2. Mount the FSS File System to your worker nodes
https://docs.oracle.com/en-us/iaas/Content/File/Tasks/mountingunixstyleos.htm#mountingFS

> [!NOTE]  
> This guide assumes you mounted FSS to `/mnt/share`. You can select different throughput levels for your mount target. Select the one that would give you enough performance: 1 Gbps, 20 Gbps, 40 Gbps, 80 Gbps.


### 3. Install `skopeo` in your worker nodes and create a dir under /mnt/share (we'll use /mnt/share/images as the example)
```
apt update
apt install -y skopeo
mkdir -p /mnt/share/images
```
### 4. Using `skopeo`, copy the image from a registry to the FSS shared folder
We'll use the Docker registry, but any registry including private ones can be used.

```
skopeo copy docker://busybox:latest dir:/mnt/share/images/busybox

Getting image source signatures
Copying blob 2fce1e0cdfc5 done
Copying config 6fd955f66c done
Writing manifest to image destination
Storing signatures
```

### Now the image is pulled to the FSS shared folder. You can import/copy it to any other worker node.

```
skopeo copy dir:/mnt/share/images/busybox containers-storage:busybox:latest
```

Check that the image is imported. On your worker node:
```
crictl images

IMAGE                                                               TAG                 IMAGE ID            SIZE
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-cloud-provider-oci   <none>              8310661879155       582MB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-flannel              <none>              8bbca5abb5f3e       308MB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-kube-proxy           <none>              c4f3122c5b070       1.28GB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-pause                <none>              e105b7466686e       146MB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-proxymux-cli         <none>              14330458a37d2       197MB
docker.io/library/busybox                                           latest              6fd955f66c231       4.5MB
```