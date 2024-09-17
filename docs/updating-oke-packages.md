# Updating the OKE packages
To update the OKE packages in your cluster deployed using the OCI Resource Manager stack, you will need to edit the Terraform state of your deployment.

## 1. Download the stack state file
1. Go to your deployment stack by following **Menu > Developer Services > Resource Manager > Stacks** in the web console.

2. Click on the name of your stack. In the **Stack details** page, click **More actions** and **Download Terraform state**.

![Download Terraform state](../images/download_terraform_state.png)

## 2. Open the downloaded Terraform state file with your favorite code editor
The state file is a JSON file. You will update the cloud init in the state, which adds the Ubuntu repo for OKE packages.

1. Search for `[trusted=yes]` in the state file. Depending on how many worker pools you have, you will have multiple results.

2. In the line that starts with `"content"` that you found by searching for `[trusted=yes]`, change the old repo that starts with `https` to the new repos. The old link will have `hpc_limited_availability` in it.
  
   Example of the old repo: `https://objectstorage.us-phoenix-1.oraclecloud.com/../n/hpc_limited_availability/b/oke_node_repo`

   The new repos:

   - Kubernetes 1.27 - https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.27
   - Kubernetes 1.28 - https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.28
   - Kubernetes 1.29 - https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.29
   
> [!IMPORTANT]  
> Make sure you use the Kubernetes version that matches your existing OKE cluster.

The first part of `content` should look like below:
```
"content": "\"apt\":\n  \"sources\":\n    \"oke-node\":\n      \"source\": \"deb [trusted=yes] https://odx-oke.objectstorage.us-sanjose-1.oci.customer-oci.com/n/odx-oke/b/okn-repositories/o/prod/ubuntu-jammy/kubernetes-1.29\n        stable main\ ....
```

## 3. Import the updated state file to your stack
In the **Stack details** page. click **More actions** and **Import state**. Choose the state file you edited in the previous step, and click **Import**. This will create an Import state job. Once the job is succeeded, the new nodes you deploy in your cluster will use the correct OKE packages.
