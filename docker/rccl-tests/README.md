# Building the RCCL tests container

You can change the values of the variables based on the version combination you want to have in your image.

```
docker build -t rccl-tests \
--build-arg="ROCM_IMAGE_NAME=rocm/dev-ubuntu-22.04" \
--build-arg="ROCM_IMAGE_TAG=6.3.2" \
--build-arg="GPU_TARGETS=gfx942" \
--pull .
```