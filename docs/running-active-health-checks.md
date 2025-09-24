# Running Active Health Checks (preview)

> [!NOTE]  
> This is a preview feature. We are actively adding more tests.

This readme contains the manifests required to run the NCCL-tests active health checks on GPU nodes using Volcano. It includes a smart applier Kubernetes CronJob that only schedules tests on idle nodes that were not already tested in the last 24 hours (configurable).

## Node selection logic

When the CronJob runs, the applier script performs the following steps:

1. **Enumerate GPU nodes**: Look for nodes that have the `nvidia.com/gpu=true` label.
2. **Check current usage:** It sums the GPU requests across running pods on each node. Only nodes with zero GPU usage are considered idle.
3. **Exclude recently tested nodes:** If a node is labeled `oke.oraclecloud.com/active-health-checks-nccl-tests-last-run` within the last 24 hours, it is skipped.
4. **Require at least two nodes:** Both worker nodes must be available. If fewer than two nodes remain, the job exits gracefully.
5. **Shape detection:** The selected node’s `node.kubernetes.io/instance-type` label determines which ConfigMap manifest to apply.
6. **Job creation:** A Volcano `Job` is created with a launcher (`mpimaster`) and workers (`mpiworker`). The launcher waits for SSH connectivity to the workers before running the NCCL test.
7. **Label updates:** After the run, nodes are labeled with the latest result and timestamp.

If all nodes are excluded (either busy or already tested), the job exits without creating a Volcano job, logging the reason.

## Usage
The manifest assumes there's a namespace called `monitoring`. If you want to deploy to another namespace, edit the manifest accordingly.

1. **Apply manifests**
   ```bash
   kubectl apply -f https://github.com/oracle-quickstart/oci-hpc-oke/tree/main/manifests/active-health-checks/active-health-checks-nccl-tests.yaml
   ```

2. **Run ad-hoc test**
   ```bash
   kubectl create job -n monitoring --from=cronjob/active-health-checks-nccl-tests-applier test-$(date +%s)
   
   kubectl logs -n monitoring job/test-<timestamp>
   ```

3. **Watch Volcano job**
   ```bash
   kubectl get pods -n monitoring -l volcano.sh/job-name=<job-name>
   
   kubectl logs -n monitoring <launcher-pod>
   ```

4. **Clean up**
   ```bash
   kubectl delete job -n monitoring -l job-name
   
   kubectl delete cronjob active-health-checks-nccl-tests-applier -n monitoring
   ```

