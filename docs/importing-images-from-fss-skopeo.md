# Importing Container Images from OCI File Storage Service Using Skopeo

When working with large container images in OKE, downloading images from a registry to multiple nodes can be time-consuming and bandwidth-intensive. This guide demonstrates how to use OCI File Storage Service (FSS) with `skopeo` to efficiently distribute container images across worker nodes by storing images in a shared filesystem.

## Benefits

- **Reduced bandwidth usage**: Download images once, distribute to all nodes via high-speed FSS
- **Faster deployment**: Nodes can copy images from FSS instead of pulling from remote registries
- **Cost savings**: Minimize data transfer costs from container registries
- **Offline capability**: Images remain available even if the registry is temporarily unavailable

## Prerequisites

- OKE cluster with worker nodes
- OCI File Storage Service file system created
- SSH access to worker nodes
- Sufficient FSS storage capacity for your container images

## Procedure

### Step 1: Create an FSS File System

Create a File Storage Service file system in your compartment. For detailed instructions, see [Creating File Systems](https://docs.oracle.com/en-us/iaas/Content/File/Tasks/create-file-system.htm#top).

### Step 2: Mount the FSS File System to Worker Nodes

Mount the FSS file system to your worker nodes. For detailed instructions, see [Mounting File Systems](https://docs.oracle.com/en-us/iaas/Content/File/Tasks/mountingunixstyleos.htm#mountingFS).

> [!NOTE]  
> This guide assumes you mounted FSS to `/mnt/share`. You can select different throughput levels for your mount target based on your performance requirements: 1 Gbps, 20 Gbps, 40 Gbps, or 80 Gbps.

### Step 3: Install Skopeo and Create Image Directory

On one of your worker nodes, install `skopeo` and create a directory for storing container images:

```sh
apt update
apt install -y skopeo
mkdir -p /mnt/share/images
```

> [!NOTE]
> For Oracle Linux, use `yum install -y skopeo` instead of `apt install -y skopeo`.

### Step 4: Copy an Image from a Registry to FSS

Use `skopeo` to copy a container image from a registry to the FSS shared folder. This example uses Docker Hub, but you can use any registry, including private registries:

```sh
skopeo copy docker://busybox:latest dir:/mnt/share/images/busybox
```

**Example output:**

```
Getting image source signatures
Copying blob 2fce1e0cdfc5 done
Copying config 6fd955f66c done
Writing manifest to image destination
Storing signatures
```

The image is now stored in the FSS shared folder and accessible from all worker nodes that have the FSS file system mounted.

### Step 5: Import the Image on Other Worker Nodes

On any worker node with the FSS file system mounted, import the image from FSS to the local container storage:

```sh
skopeo copy dir:/mnt/share/images/busybox containers-storage:busybox:latest
```

### Step 6: Verify the Image Import

Verify that the image has been successfully imported to the node's container runtime:

```sh
crictl images
```

**Example output:**

```
IMAGE                                                               TAG                 IMAGE ID            SIZE
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-cloud-provider-oci   <none>              8310661879155       582MB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-flannel              <none>              8bbca5abb5f3e       308MB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-kube-proxy           <none>              c4f3122c5b070       1.28GB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-pause                <none>              e105b7466686e       146MB
ap-melbourne-1.ocir.io/axoxdievda5j/oke-public-proxymux-cli         <none>              14330458a37d2       197MB
docker.io/library/busybox                                           latest              6fd955f66c231       4.5MB
```

The image is now available on the worker node and can be used by pods running on that node.

## Working with Private Registries

When copying images from private registries that require authentication, you can provide credentials to `skopeo`:

### Using a Credentials File

```sh
skopeo copy --src-creds=username:password docker://registry.example.com/myapp:v1.0 dir:/mnt/share/images/myapp
```

### Using Docker Config

If you have already authenticated with `docker login`, skopeo can use the same credentials:

```sh
skopeo copy --authfile ~/.docker/config.json docker://registry.example.com/myapp:v1.0 dir:/mnt/share/images/myapp
```

### Copying from OCI Registry (OCIR)

For Oracle Cloud Infrastructure Registry:

```sh
skopeo copy --src-creds=<tenancy-namespace>/<username>:<auth-token> \
  docker://<region-key>.ocir.io/<tenancy-namespace>/<repo-name>:<tag> \
  dir:/mnt/share/images/<image-name>
```