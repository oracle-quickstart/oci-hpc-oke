### Running GPU & RDMA health checks with Node Problem Detector
You can deploy the [Node Problem Detector](https://github.com/kubernetes/node-problem-detector) with OKE GPU & RDMA health checks to get a quick overview of possible issues with your nodes.

#### Currently available health checks
Please note depending on the shape and its configuration, some health checks will not run. For example, if you have an RDMA capable node that is not deployed in a [Cluster Network](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managingclusternetworks.htm#top), RDMA checks will not run.

| Name             	| Description                                                  	|
|------------------	|--------------------------------------------------------------	|
| GpuCount         	| Checks if the node has the expected number of GPUs available 	|
| GpuEcc           	| Checks for GPU ECC errors                                    	|
| GpuRowRemap      	| Checks for GPU Row Remapping Errors                          	|
| GpuBus           	| Checks if any GPU has fallen off the bus                     	|
| RdmaLink         	| Checks if RDMA links are up                                  	|
| RdmaLinkFlapping 	| Checks if there's any RDMA links that are flapping           	|
| RdmaWpaAuth      	| Checks if all RDMA interfaces are authenticated              	|
| RdmaRttcc        	| Checks if RTTCC is disabled on the RDMA interfaces           	|
| OcaVersion       	| Checks if node has the correct Oracle Cloud Agent version    	|

#### Deployment
You can deploy using the Node Problem Detector Helm chart. The health check scripts are created as a `ConfigMap`, so please make sure you use the `values.yaml` in the link below.

```
helm install gpu-rdma-node-problem-detector oci://ghcr.io/deliveryhero/helm-charts/node-problem-detector --version 2.3.15 \
    -f https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/node-problem-detector/values.yaml
```

#### Checking if any nodes report errors
After you deploy the Helm chart, wait for about 5 minutes to give health checks some time to run. By default, the tests will run every 5 minutes. You can edit `values.yaml` to change the frequency.

You can see new conditions are added to each GPU shape when you run `kubectl describe node <NODE NAME>`. Example output below is redacted for a cleaner look.

```
Conditions:     
                                                                                                                                                                                                                  
    Type                    Status    Reason                        Message   
    ----                    ------    ------                        -------                  
    RdmaLinkFlapping        False     RdmaLinkFlappingHasNoIssues   No flapping RDMA links                    
    OcaVersion              False     OcaVersionHasNoIssues         OCA version is up to date   
    GpuRowRemap             False     GpuRowRemapHasNoIssues        No Row Remapping issues detected with GPUs
    RdmaWpaAuth             False     RdmaWpaAuthHasNoIssues        All RDMA links are authenticated          
    RdmaRttcc               False     RdmaRttccHasNoIssues          RTCCC is disabled on all RDMA interfaces  
    GpuEcc                  False     GpuEccHasNoIssues             No ECC issues detected with GPUs          
    GpuBus                  False     GpuBusHasNoIssues             No GPU Bus issues detected with GPUs      
    GpuCount                True      GpuCountHasIssues             Node has missing GPU(s)                   
    RdmaLink                False     RdmaLinkHasNoIssues           All RDMA links are up                     
```

You can also run the following command to get a list of all nodes that report a problem.

```sh
kubectl get nodes -o json | jq -r '.items[]
| select (.metadata.labels."nvidia.com/gpu" == "true" or .metadata.labels."amd.com/gpu" == "true")
| { name: .metadata.name, ocid: .spec.providerID, serial: .metadata.labels["oci.oraclecloud.com/host.serial_number"], error: .status.conditions[]
| select(.reason | test("^(Gpu|Rdma|Oca).*HasIssues$")) | .message }
| "\(.name)\t\(.ocid)\t\(.serial)\t\(.error)"'
```

Example output that lists the node name, OCID, serial, and the error:
```
10.140.30.89    ocid1.instance.oc1.ap-melbourne-1.anww...   2210xcr0bv  Node has missing GPU(s)
```
