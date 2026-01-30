#!/usr/bin/env -S uv --quiet run --script
# /// script
# requires-python = "==3.12"
# dependencies = [
#   "kubernetes==33.1.0",
#   "oci==2.159.0"
# ]
# ///
import argparse, base64, gzip, io, json, logging, re, sys, traceback
import concurrent.futures

from kubernetes import client as kubernetes_client
from kubernetes import config as kubernetes_config
from kubernetes import watch as kubernetes_watch

import oci
from oci.core import ComputeClient, BlockstorageClient
from oci.auth.signers import InstancePrincipalsSecurityTokenSigner
from oci.signer import Signer

logger = logging.getLogger(__name__)

class BootVolumeReplacer:
    # BVR will try to use the "DEFAULT" profile in the ~/.oci/config file and
    # the default kubeconfig file at ~/.kube/config. You can override these defaults by passing a custom auth argument.
    def __init__(self, 
                compartment_id,
                nodes,
                cloud_init_file="",
                image_ocid="",
                cloud_init_change_functions=[],
                parallelism=1,
                bv_size=0,
                remove_previous_boot_volume=False,
                node_metadata={},
                interactive=False,
                timeout_seconds=600,
                region="",
                auth="config_file",
                kubeconfig="~/.kube/config",
                oci_config_file="~/.oci/config",
                oci_config_profile="DEFAULT",
                ssh_authorized_keys="",
                **kwargs
        ):
        
        try:
            logger.debug(f"Attempting to use {kubeconfig} kubeconfig file.")
            self.kubeconfig = kubernetes_config.load_kube_config(config_file=kubeconfig)
        except Exception as e:
            logger.error(f"Invalid kubeconfig file:\n{traceback.format_exc()}")
            sys.exit(1)
        
        try:
            if auth == "config_file":
                logger.debug(f"Attempting to use {oci_config_file} OCI config file.")
                self.oci_config = oci.config.from_file(file_location=oci_config_file, profile_name=oci_config_profile)
                if region:
                    self.oci_config["region"] = region

                self.oci_signer = Signer(
                    tenancy=self.oci_config.get("tenancy"),
                    user=self.oci_config.get("user"),
                    fingerprint=self.oci_config.get("fingerprint"),
                    private_key_file_location=self.oci_config.get("key_file"),
                    pass_phrase=oci.config.get_config_value_or_default(self.oci_config, "pass_phrase"),
                    private_key_content=self.oci_config.get("key_content")
                )

        except Exception as e:
            logger.error(f"Failed to load OCI config:\n{traceback.format_exc()}")
            sys.exit(1)

        try:
            if auth == "instance_principal":
                logger.debug(f"Attempting to use instance_principal signer.")
                self.oci_signer = InstancePrincipalsSecurityTokenSigner()
        
                if not region:
                    logger.error("Region must be specified when using instance_principal signer.")
                    sys.exit(1)
                else:
                    self.oci_config = {
                        "region": region,
                    }
                
        except Exception as e:
            logger.error(f"Failed to initialize the Instance Principal signer:\n{traceback.format_exc()}")
            sys.exit(1)

        self.compartment_id = compartment_id
        self.interactive = interactive
        self.nodes = nodes
        self.cloud_init_file = cloud_init_file
        self.cloud_init_change_functions = cloud_init_change_functions
        self.parallelism = parallelism
        self.image_ocid = image_ocid
        self.bv_size = bv_size
        self.node_metadata = node_metadata
        self.remove_previous_boot_volume = remove_previous_boot_volume
        self.timeout_seconds = timeout_seconds
        self.ssh_authorized_keys = ssh_authorized_keys

    def _get_k8s_node_details(self, node):
        api_instance = kubernetes_client.CoreV1Api()
        try:
            k8s_node_details = api_instance.read_node(name=node)
        except Exception as exc:
            # logger.error(f"Failed to fetch Kubernetes node details for {node}: {exc}")
            return None
        return k8s_node_details

    def get_node_details(self, node):
        
        ##  Fetch the OCI instance details based on Kubernetes node name.
        k8s_node_details = self._get_k8s_node_details(node)
        
        is_k8s_node = False
        if k8s_node_details:
            is_k8s_node = True
            instance_display_name = k8s_node_details.metadata.labels.get('displayName', k8s_node_details.metadata.labels.get('hostname', ""))

            core_client = ComputeClient(config = self.oci_config, signer = self.oci_signer)
            list_instances_response = core_client.list_instances(
                compartment_id=self.compartment_id,
                display_name=instance_display_name,
                lifecycle_state="RUNNING")
            
            if len(list_instances_response.data) == 0:
                logger.error(f"No running instance found with display name {instance_display_name} in compartment {self.compartment_id} corresponding to the Kubernetes node {node} in state 'Running'.")
                return None, is_k8s_node
            else:
                logger.info(f"Identified instance {list_instances_response.data[0].id} for the kubernetes node {node}.")
                response = input(f"Continue BVR for node {node}? [y/n]: \n") if self.interactive else "y"
                if response.lower() != "y":
                    return False, is_k8s_node
                return list_instances_response.data[0], is_k8s_node
        else:
            if node.startswith("ocid1.instance"):
                core_client = ComputeClient(config = self.oci_config, signer = self.oci_signer)
                get_instances_response = core_client.get_instance(
                    instance_id=node)
                return get_instances_response.data, is_k8s_node
        logger.error(f"Failed to fetch instance details for {node}.")
        return None, is_k8s_node


    def check_image_compatibility(self, image_id, shape_name):
        core_client = ComputeClient(config = self.oci_config, signer = self.oci_signer)
        get_image_shape_compatibility_entries_response = core_client.list_image_shape_compatibility_entries(
            image_id=image_id,
        )
        supported_shapes = [entry.shape for entry in get_image_shape_compatibility_entries_response.data]
        if shape_name in supported_shapes:
            return True
        return False


    def get_existing_boot_volume_size(self, compartment_ocid, instance_id, ad):
        # Get the instance current boot volume size
        core_client = ComputeClient(config = self.oci_config, signer = self.oci_signer)
        list_boot_volume_attachments_response = core_client.list_boot_volume_attachments(
            availability_domain=ad,
            compartment_id=compartment_ocid,
            instance_id=instance_id,
            )
        boot_volume_id = list_boot_volume_attachments_response.data[0].boot_volume_id
        core_client = BlockstorageClient(config = self.oci_config, signer = self.oci_signer)

        get_boot_volume_response = core_client.get_boot_volume(
            boot_volume_id=boot_volume_id)
        logger.debug(f"Current boot volume size for instance with id {instance_id} is {get_boot_volume_response.data.size_in_gbs}.")
        return get_boot_volume_response.data.size_in_gbs


    def cordon_and_drain_node(self, kubernetes_node):
        # Cordon and Drain the node
        api_instance = kubernetes_client.CoreV1Api()
        body = {
            "spec": {
                "unschedulable": True,
            },
        }
        api_instance.patch_node(kubernetes_node, body)
        logger.info(f"Cordoned node: {kubernetes_node}.")

        logger.info(f"Starting to drain the node: {kubernetes_node}.")
        pods = api_instance.list_pod_for_all_namespaces(field_selector=f"spec.nodeName={kubernetes_node}").items
        for pod in pods:
            if pod.metadata.owner_references:
                for owner in pod.metadata.owner_references:
                    if owner.kind == "DaemonSet":
                        break
                else:
                    # Not a DaemonSet
                    self.evict_pod(api_instance, pod, kubernetes_node)
            else:
                # Static pod or mirror pod
                continue
        return True
    

    def delete_node(self, kubernetes_node):
        # Delete the node from Kubernetes
        try:
            api_instance = kubernetes_client.CoreV1Api()
            api_instance.delete_node(kubernetes_node)
            return True
        except Exception as e:
            raise Exception(f"Failed to delete node {kubernetes_node}:\n{traceback.format_exc()}")


    def evict_pod(self, policy_v1, pod, kubernetes_node):
        eviction = kubernetes_client.V1Eviction(
            metadata=kubernetes_client.V1ObjectMeta(name=pod.metadata.name, namespace=pod.metadata.namespace),
            delete_options=kubernetes_client.V1DeleteOptions(grace_period_seconds=60)
        )

        try:
            logger.info(f"Eviction initiated for pod {pod.metadata.name} with a grace period of 60 seconds. Waiting for pod to terminate.")
            policy_v1.create_namespaced_pod_eviction(
                name=pod.metadata.name,
                namespace=pod.metadata.namespace,
                body=eviction
            )
        except kubernetes_client.ApiException as e:
            raise Exception(f"Failed to remove pod {pod.metadata.name} in namespace {pod.metadata.namespace} from the node {kubernetes_node}:\n{traceback.format_exc()}")

    def _check_if_base64_encoded(self, cloud_init):
        try:
            return base64.b64encode(base64.b64decode(cloud_init)).decode('utf-8') == cloud_init
        except Exception:
            return False

    def _decode_cloud_init(self, cloud_init, k8s_node=""):
        cloud_init_decoded = base64.standard_b64decode(cloud_init)
        cloud_init_zip = None

        try:    
            cloud_init_fileobj = io.BytesIO(cloud_init_decoded)
            cloud_init_zip = gzip.GzipFile(fileobj=cloud_init_fileobj)
            decoded_cloud_init = cloud_init_zip.read()
        except gzip.BadGzipFile:
            if k8s_node:
                logger.debug(f"Cloud-init for node {k8s_node} is not gzip compressed.")
            decoded_cloud_init = cloud_init_decoded
        finally:
            if cloud_init_zip:
                cloud_init_zip.close()

        return decoded_cloud_init.decode('utf-8')


    def _encode_cloud_init(self, cloud_init):
        
        new_cloud_init_zip_fileobj = io.BytesIO()
        new_cloud_init_zip = gzip.GzipFile(fileobj=new_cloud_init_zip_fileobj, mode='wb')
        new_cloud_init_zip.write(cloud_init.encode('utf-8'))
        new_cloud_init_zip.close()
        new_cloud_init_zip_fileobj.seek(0)
        new_cloud_init_encoded = base64.standard_b64encode(new_cloud_init_zip_fileobj.read())
        new_cloud_init_zip_fileobj.close()
        return new_cloud_init_encoded

    def generate_new_cloud_init(self, k8s_node, initial_cloud_init, cloud_init_change_functions):
        # Modifying the base64 gziped cloud-init. Generated from the OKE TF module.

        if self._check_if_base64_encoded(initial_cloud_init):
            logger.debug(f"cloud-init for node {k8s_node} is base64 encoded.")
            cloud_init_data_string = self._decode_cloud_init(initial_cloud_init, k8s_node)
        else:
            logger.debug(f"cloud-init for node {k8s_node} is not base64 encoded.")
            cloud_init_data_string = initial_cloud_init
        
        logger.debug(f"Cloud-init data for node {k8s_node} before changes:\n{cloud_init_data_string}")
        
        # Modify the cloud-init data using the functions provided by the user
        for func in cloud_init_change_functions:
            cloud_init_data_string = func(cloud_init_data_string)

        logger.debug(f"Cloud-init data for node {k8s_node} after changes:\n{cloud_init_data_string}")
        if logger.getEffectiveLevel() == logging.DEBUG:
            response = input(f"Continue upgrade of node {k8s_node}? [y/n]: \n") if self.interactive else "y"
            if response.lower() != "y":
                logger.info("BVR cancelled.")
                return None

        return self._encode_cloud_init(cloud_init_data_string)


    def replace_bv(self, instance_ocid, image_ocid, new_metadata, bv_size_in_gbs, remove_bv):
        # Issue replace Instance BV replacement call with:
        # - new boot volume size
        # - new image
        # - new metadata
        # - flag to preserve the current boot volume 
        core_client = ComputeClient(config = self.oci_config, signer = self.oci_signer)
        if bv_size_in_gbs < 50:
            bv_size_in_gbs = 50
        update_instance_response = core_client.update_instance(
            instance_id=instance_ocid,
            update_instance_details=oci.core.models.UpdateInstanceDetails(
                metadata=new_metadata,
                source_details=oci.core.models.UpdateInstanceSourceViaImageDetails(
                    source_type="image",
                    image_id=image_ocid,
                    is_preserve_boot_volume_enabled=not remove_bv,
                    boot_volume_size_in_gbs=bv_size_in_gbs
                )
            )
        )
        if update_instance_response.status not in [200, 202]:
            raise Exception(f"Failed to request boot_volume_replace on instance {instance_ocid}: {update_instance_response.status} | {update_instance_response.data}.")
        get_instance_response = core_client.get_instance(instance_ocid)
        oci.wait_until(core_client, get_instance_response, 'lifecycle_state', 'STOPPING', succeed_on_not_found=False)
        return True
    

    def wait_for_completion(self, k8s_node, timeout_seconds=600):
        # Method to wait for the completion of the boot volume replacement process
        # wait for the node to join the Kubernetes cluster.
        api_instance = kubernetes_client.CoreV1Api()
        w = kubernetes_watch.Watch()
        
        try:
            for event in w.stream(api_instance.list_node, timeout_seconds=timeout_seconds):
                node = event['object']
                if node.metadata.name == k8s_node:
                    for condition in node.status.conditions:
                        if condition.type == 'Ready' and condition.status == 'True':
                            logger.info(f"Node {k8s_node} is ready.")
                            w.stop()
                            return True
                        
            logger.error(f"The node has not rejoined the cluster in {timeout_seconds} seconds.")
            return False
        except Exception as e:
            raise Exception(f"Failed to wait for node {k8s_node}:\n{traceback.format_exc()}")


    def upgrade_node(self, k8s_node):
        ## Method that brings together all the steps to replace the boot volume on a self managed instance.
        # Fetching the instance details
        instance_details, is_k8s_node = self.get_node_details(k8s_node)
        if instance_details is None:
            raise Exception(f"Failed to identify the instance details for node {k8s_node}")
        if instance_details is False:
            return False, None
        
        # Check if the image is compatible with the shape of the node
        if self.image_ocid:
            shape_is_compatible = self.check_image_compatibility(self.image_ocid, instance_details.shape)
            if not shape_is_compatible:
                raise Exception(f"The image {self.image_ocid} is not compatible with the shape {instance_details.shape}.")
        
        # Establish the cloud-init
        if self.cloud_init_file:
            try:
                with open(self.cloud_init_file, 'r') as file:
                    cloud_init_data = file.read()
                    new_cloud_init = self._encode_cloud_init(cloud_init_data)
            except Exception as e:
                raise Exception(f"Failed to read cloud-init file {self.cloud_init_file}: {traceback.format_exc()}")
        elif len(self.cloud_init_change_functions):
            existing_cloud_init = instance_details.metadata['user_data']
            new_cloud_init = self.generate_new_cloud_init(k8s_node, existing_cloud_init, self.cloud_init_change_functions)
            if new_cloud_init is None:
                return False, None
        else:
            logger.debug(f'Cloud-init was not changed.')
            new_cloud_init = instance_details.metadata['user_data']
        
        new_metadata = instance_details.metadata
        if self.node_metadata:
            new_metadata.update(self.node_metadata)
        
        if isinstance(new_cloud_init, bytes):
            new_metadata['user_data'] = new_cloud_init.decode('utf-8')
        else:
            new_metadata['user_data'] = new_cloud_init

        if self.ssh_authorized_keys:
            new_metadata['ssh_authorized_keys'] = self.ssh_authorized_keys
        
        if is_k8s_node:
            cordon_and_drain_result = self.cordon_and_drain_node(k8s_node)
            if cordon_and_drain_result:
                logger.info(f"Successfuly drained the node {k8s_node}.")
            
            delete_node_result = self.delete_node(k8s_node)
            if delete_node_result:
                logger.info(f'Successfuly deleted the node {k8s_node} from the Kubernetes cluster.')
            else:
                logger.error(f"Failed to delete the node {k8s_node} from the Kubernetes cluster.")
                return None, False
        
        if self.bv_size:
            new_bv_size = self.bv_size
        else:
            new_bv_size = self.get_existing_boot_volume_size(self.compartment_id, instance_details.id, instance_details.availability_domain)
        
        if self.image_ocid:
            new_image_ocid = self.image_ocid
        else:
            new_image_ocid = instance_details.source_details.image_id
        
        bvr_result = self.replace_bv(
            instance_details.id, 
            new_image_ocid,
            new_metadata,
            new_bv_size,
            self.remove_previous_boot_volume)
        
        if bvr_result:
            if self.ssh_authorized_keys:
                logger.info(f"The SSH authorized keys have been updated for node {k8s_node}.")
            logger.info(f'The command to replace the boot volume on instance {instance_details.id} has been accepted.')

        logger.info(f"Waiting {self.timeout_seconds} seconds for node {k8s_node} to be ready...")

        if is_k8s_node:
            wait_for_completion_result = self.wait_for_completion(k8s_node, self.timeout_seconds)
            if wait_for_completion_result:
                logger.info(f'The boot volume replacement for instance {instance_details.id} has been completed successfully.')
                result = True
            else:
                logger.error(f'The boot volume replacement for instance {instance_details.id} failed.')
                result = False
        else:
            result = True
        return result, instance_details.metadata['user_data'] != new_cloud_init
        

    def execute_upgrade_nodes(self):
        any_cloud_init_updated = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.parallelism) as executor:
            
            # Start the load operations and mark each future with its URL
            bvr_replace_futures = {executor.submit(self.upgrade_node, node): node for node in self.nodes}
            for future in concurrent.futures.as_completed(bvr_replace_futures):
                node = bvr_replace_futures[future]
                try:
                    status, node_cloud_init_updated = future.result()
                except Exception as exc:
                    logger.error(f'The upgrade of node {node} generated an exception:\n{traceback.format_exc()}')
                    sys.exit(1)
                else:
                    if status:
                        logger.info(f"Successfuly executed Boot Volume Replacement for node {node}.")
                        any_cloud_init_updated.append(node_cloud_init_updated)
                    else:
                        logger.error(f"Failed to execute Volume Replacement for node {node}.")
                    
        if any(any_cloud_init_updated):
            logger.info(f"Don't forget to update the terraform code to reflect the operations executed.")


def setup_logging(level):
    ## Setting up logging
    logger.setLevel(level)

    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    console_handler = logging.StreamHandler(sys.stderr)
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)

    # logger.addHandler(file_handler)
    logger.addHandler(console_handler)


if __name__ == "__main__": 

    ## Argument parsing
    def to_bool(argument):
        if argument == 'false':
            return False
        return True
    
    parser = argparse.ArgumentParser()
    
    parser.add_argument("-c", "--compartment-id", help="Kubernetes cluster compartment OCID.", required=True)
    parser.add_argument("--interactive", help="Enable interactive execution of the script.", action='store_true')
    parser.add_argument("--cloud-init-file", help="File with new node cloud-init. If not provided, the existing node cloud-init is used.", nargs="?", default="")
    parser.add_argument("--image-ocid", help="New image OCID to use for the BV. If not provided, the current node image is used.", nargs="?", default="")
    parser.add_argument("--ssh_authorized_keys", help="New SSH public key(s) to be configured on the node.", nargs="?", default="")
    parser.add_argument("-p", "--parallelism", help="How many nodes to upgrade in parallel. Not recommended to enable at the same time with --interactive.", type=int, default=1)
    parser.add_argument("--bv-size", help="Size of the new boot volume in GB. If not set, the size of the existing boot volume will be used.", type=int, default=0)
    parser.add_argument("--remove-previous-boot-volume", help="Remove the existing boot volume after the upgrade. By default, the existing boot volume is preserved.", action='store_true')
    parser.add_argument("--node-metadata", help="Metadata to add to the new node.", nargs="?", default="{}", type=json.loads)
    parser.add_argument("--desired-k8s-version", help="Desired K8s version to upgrade to. Works only with the nodes created using the standard OCI OKE TF Modules. The version should start with v. Eg. v1.33.1", required=False, default="")
    parser.add_argument("--timeout-seconds", help="Timeout in seconds for nodes to boot after BVR and join the Kubernetes cluster.", type=int, default=900)
    parser.add_argument("--kubeconfig", help="Override the path to the kubeconfig file. Default is '~/.kube/config'", required=False, default="~/.kube/config")
    parser.add_argument("--oci-config-file", help="Override the path to the oci_config file. Default is '~/.oci/config'", required=False, default="~/.oci/config")
    parser.add_argument("--oci-config-profile", help="oci config profile to use. Default is 'DEFAULT'", required=False, default="DEFAULT")
    parser.add_argument("--region", help="The region to target. Required when using auth='instance_principal'", required=False)
    parser.add_argument("--auth", help="Change the OCI signer.", required=False, default="config_file", choices=['config_file', 'instance_principal'])
    parser.add_argument("nodes", help="Name of the Kubernetes node(s) for which to execute BVR.", nargs="+")
    parser.add_argument("--debug", help="Enable debug logging.", action='store_true')
    
    args = parser.parse_args()

    if args.debug:
        setup_logging(logging.DEBUG)
    else:
        setup_logging(logging.INFO)

    logger.info("Application starting.")

    # Functions to update the cloud-init metadata (by default specific for ubuntu images)
    cloud_init_change_functions = []
    
    # This is an exemple for the expected functions for cloud_init_change_functions
    # cloud_init_change_functions.append(lambda cloud_init_data: cloud_init_data.replace(
    #     "https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/refs/heads/main/files/oke-nvme-raid.sh",
    #     "https://raw.githubusercontent.com/OguzPastirmaci/misc/refs/heads/master/oke-nvme-provisioner/oke-nvme-bvr.sh")
    # )
    node_metadata = args.node_metadata
    
    if args.desired_k8s_version:
        if args.desired_k8s_version.lower().startswith("v1"):
            cloud_init_change_functions.append(lambda cloud_init_data: re.sub(r"'v\d\.\d{2}\.\d{1,2}'", rf"'{args.desired_k8s_version}'", cloud_init_data))
            cloud_init_change_functions.append(lambda cloud_init_data: re.sub(r'(oci-oke-node-all-)\d\.\d{2}\.\d{1,2}(\D)', rf"\g<1>{args.desired_k8s_version[1:]}\g<2>", cloud_init_data))
            cloud_init_change_functions.append(lambda cloud_init_data: re.sub(r'(\Wkubernetes-)\d{1}\.\d{2}(\W)', rf'\g<1>{".".join(args.desired_k8s_version[1:].split(".")[0:2])}\g<2>', cloud_init_data))
            node_metadata.update({"oke-k8s-version": args.desired_k8s_version})
        else:
            logger.error("Invalid Kubernetes version format. Please use a version starting with 'v1'.")
            sys.exit(1)

    bvr = BootVolumeReplacer(**args.__dict__, cloud_init_change_functions=cloud_init_change_functions)
    bvr.execute_upgrade_nodes()
    
    logger.info("Node BVR process completed.")
    sys.exit(0)
