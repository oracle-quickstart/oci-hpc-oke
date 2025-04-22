# Building the NCCL tests container

You can change the values of the variables based on the version combination you want to have in your image.

```
docker build -t nccl-tests \
--build-arg PYTORCH_IMAGE_TAG=25.03-py3 \
--build-arg NCCL_VERSION=2.26.2-1 \
--build-arg NCCL_TESTS_VERSION=2.14.1 \
--pull .
```