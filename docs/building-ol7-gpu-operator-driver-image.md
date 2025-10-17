# Building the Oracle Linux 7 GPU driver in a container for Nvidia GPU Operator

## IMPORTANT NOTES

- You will need a node that is running an Oracle Linux 7 image with the Red Hat Compatible Kernel (RHCK) with Docker installed. You can find the instructions to change the kernel from UEK to RHCK [here](https://github.com/OguzPastirmaci/misc/blob/master/change-ol-kernel-to-rhck.md).

- You will need a Docker repository to push your image to (OCIR, Docker Hub, etc.)

- When deploying your GPU worker nodes on OKE, you will need an image that is an Oracle Linux 7 image with the Red Hat Compatible Kernel (RHCK). You can find the instructions to change the kernel from UEK to RHCK [here](https://github.com/OguzPastirmaci/misc/blob/master/change-ol-kernel-to-rhck.md). Oracle Linux 8 or Ubuntu will not work with the below instructions.


### Clone the Nvidia driver repository

```
git clone https://gitlab.com/nvidia/container-images/driver.git

cd driver/centos7
```

### Save the following content as ol7_latest.repo in driver/centos7 directory

```
[ol7_latest]
name=Oracle Linux $releasever Latest ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL7/latest/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
```

### Create the OL7 RPM key in driver/centos7 directory
```
curl -s https://yum.oracle.com/RPM-GPG-KEY-oracle-ol7 -o RPM-GPG-KEY-oracle
```

So the final content of driver/centos7 directory will be

```
-rw-rw-r-- 1 opc opc  3106 Aug  4 18:11 Dockerfile
-rw-rw-r-- 1 opc opc     0 Aug  4 17:28 empty
-rwxrwxr-x 1 opc opc  1839 Aug  4 17:28 install.sh
-rwxrwxr-x 1 opc opc 21100 Aug  4 17:28 nvidia-driver
-rw-rw-r-- 1 opc opc   203 Aug  8 20:37 ol7_latest.repo
-rw-rw-r-- 1 opc opc   210 Aug  4 17:28 README.md
-rw-rw-r-- 1 opc opc  1011 Aug  8 20:37 RPM-GPG-KEY-oracle
```

### Edit the Dockerfile in driver/centos7 directory
Open the Dockerfile and add the following lines after `ADD install.sh /tmp/`

```
ADD ol7_latest.repo /etc/yum.repos.d/
ADD RPM-GPG-KEY-oracle /etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
```

### Build and push the custom image
Make sure you choose a compatible GPU driver and CUDA pair. More info [here.](https://docs.nvidia.com/deploy/cuda-compatibility/)


```
DRIVER_VERSION=
CUDA_VERSION=

docker build . -t <yourrepository name>/driver:$DRIVER_VERSION-ol7.9 --build-arg DRIVER_VERSION=$DRIVER_VERSION --build-arg CUDA_VERSION=$CUDA_VERSION --build-arg TARGETARCH=amd64
```

#### Important note:
You can use any registry (e.g. `oguzpastirmaci` above is on Docker Hub), but the repository name needs to be `driver` in above command. Otherwise GPU Operator won't be able to find the correct image.

Example:

```
DRIVER_VERSION=510.85.02
CUDA_VERSION=11.7.1

docker build . -t oguzpastirmaci/driver:$DRIVER_VERSION-ol7.9 --build-arg DRIVER_VERSION=$DRIVER_VERSION --build-arg CUDA_VERSION=$CUDA_VERSION --build-arg TARGETARCH=amd64
```

Then push the image to your image repository.

Example:

```
docker push oguzpastirmaci/driver:510.85.02-ol7.9
```
