#!/usr/bin/env -S uv --quiet run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "oci==2.159.0"
# ]
# ///
"""
Update the cloud-init and/or kubernetes version on an OKE nodepool, RDMA cluster
(Cluster Network / GPU Memory Cluster), or Compute Cluster instance configuration.

Mode 1 - nodepool (default):
    Updates an OKE nodepool's cloud-init and/or kubernetes version via the
    Container Engine API. Uses the same cloud-init handling approach as the BVR
    script (docs/files/bvr-script.py).

Mode 2 - instance-config:
    Creates a copy of an existing instance configuration with an updated
    cloud-init, then attaches it to the specified Cluster Network,
    Compute GPU Memory Cluster, or Compute Cluster instance pool(s).

Usage:
    # Nodepool mode
    python update-oke-nodepool-cloud-init.py \\
        --mode nodepool \\
        --nodepool-id ocid1.nodepool.oc1... \\
        --desired-k8s-version v1.33.1

    # Instance-config mode (Cluster Network)
    python update-oke-nodepool-cloud-init.py \\
        --mode instance-config \\
        --cluster-network-id ocid1.clusternetwork.oc1... \\
        --desired-k8s-version v1.33.1

    # Instance-config mode (GPU Memory Cluster)
    python update-oke-nodepool-cloud-init.py \\
        --mode instance-config \\
        --gpu-memory-cluster-id ocid1.computegpumemorycluster.oc1... \\
        --cloud-init-file ./new-cloud-init.sh

    # Instance-config mode (Compute Cluster)
    python update-oke-nodepool-cloud-init.py \\
        --mode instance-config \\
        --compute-cluster-id ocid1.computecluster.oc1... \\
        --desired-k8s-version v1.33.1
"""

import argparse
import base64
import copy
import gzip
import io
import logging
import os
import re
import sys
import traceback

import oci
import oci.util
from oci.auth.signers import InstancePrincipalsSecurityTokenSigner
from oci.signer import Signer
from oci.container_engine import ContainerEngineClient
from oci.core import ComputeClient, ComputeManagementClient

logger = logging.getLogger(__name__)


def setup_logging(level):
    logger.setLevel(level)
    formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    console_handler = logging.StreamHandler(sys.stderr)
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)


def _get_delegation_token():
    try:
        with open("/etc/oci/delegation_token") as f:
            return f.read()
    except Exception:
        logger.error(f"Failed to get delegation token:\n{traceback.format_exc()}")
        return None


def _init_oci_clients(auth, region, oci_config_file, oci_config_profile):
    """
    Initialize OCI clients (ContainerEngine, Compute, ComputeManagement)
    using the same auth modes as the BVR script.
    """
    config = None
    signer = None

    if auth == "config_file":
        config = oci.config.from_file(file_location=oci_config_file, profile_name=oci_config_profile)
        if region:
            config["region"] = region
        signer = Signer(
            tenancy=config.get("tenancy"),
            user=config.get("user"),
            fingerprint=config.get("fingerprint"),
            private_key_file_location=config.get("key_file"),
            pass_phrase=oci.config.get_config_value_or_default(config, "pass_phrase"),
            private_key_content=config.get("key_content"),
        )
        ce_client = ContainerEngineClient(config)
        compute_client = ComputeClient(config)
        compute_mgmt_client = ComputeManagementClient(config)
    elif auth == "instance_principal":
        if not region:
            logger.error("Region must be specified when using instance_principal auth.")
            sys.exit(1)
        signer = InstancePrincipalsSecurityTokenSigner()
        config = {"region": region}
        ce_client = ContainerEngineClient(config=config, signer=signer)
        compute_client = ComputeClient(config=config, signer=signer)
        compute_mgmt_client = ComputeManagementClient(config=config, signer=signer)
    elif auth == "cloud_shell":
        signer = oci.auth.signers.InstancePrincipalsDelegationTokenSigner(
            delegation_token=_get_delegation_token()
        )
        config = {
            "signer": signer,
            "region": os.environ.get("OCI_REGION", region or ""),
        }
        ce_client = ContainerEngineClient(config=config, signer=signer)
        compute_client = ComputeClient(config=config, signer=signer)
        compute_mgmt_client = ComputeManagementClient(config=config, signer=signer)
    else:
        logger.error(f"Unknown auth mode: {auth}")
        sys.exit(1)

    return ce_client, compute_client, compute_mgmt_client


# ---------------------------------------------------------------------------
# Cloud-init helpers (mirroring the BVR script approach)
# ---------------------------------------------------------------------------

def check_if_base64_encoded(cloud_init):
    try:
        return base64.b64encode(base64.b64decode(cloud_init)).decode("utf-8") == cloud_init
    except Exception:
        return False


def decode_cloud_init(cloud_init):
    """Decode a potentially base64-encoded and gzip-compressed cloud-init string."""
    if check_if_base64_encoded(cloud_init):
        logger.debug("Cloud-init is base64 encoded, decoding...")
        decoded = base64.standard_b64decode(cloud_init)
    else:
        logger.debug("Cloud-init is not base64 encoded.")
        decoded = cloud_init.encode("utf-8") if isinstance(cloud_init, str) else cloud_init

    try:
        fileobj = io.BytesIO(decoded)
        with gzip.GzipFile(fileobj=fileobj) as gz:
            decompressed = gz.read()
        logger.debug("Cloud-init was gzip compressed, decompressed successfully.")
        return decompressed.decode("utf-8")
    except gzip.BadGzipFile:
        logger.debug("Cloud-init is not gzip compressed.")
        return decoded.decode("utf-8") if isinstance(decoded, bytes) else decoded


def encode_cloud_init(cloud_init_str):
    """Gzip compress and base64-encode a cloud-init string."""
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        gz.write(cloud_init_str.encode("utf-8"))
    buf.seek(0)
    encoded = base64.standard_b64encode(buf.read())
    buf.close()
    return encoded.decode("utf-8")


# ---------------------------------------------------------------------------
# K8s version replacement helpers (same regexes as BVR script)
# ---------------------------------------------------------------------------

def replace_k8s_version_in_cloud_init(cloud_init_data, desired_version):
    """Apply the same k8s version replacement regexes used in the BVR script."""
    if not desired_version.lower().startswith("v1"):
        logger.error("Invalid Kubernetes version format. Must start with 'v1'.")
        sys.exit(1)

    # 1. Replace quoted full version strings like 'v1.33.1'
    cloud_init_data = re.sub(
        r"'v\d\.\d{2}\.\d{1,2}'",
        f"'{desired_version}'",
        cloud_init_data,
    )

    # 2. Replace oci-oke-node-all- prefix pattern (without leading 'v')
    cloud_init_data = re.sub(
        r"(oci-oke-node-all-)\d\.\d{2}\.\d{1,2}(\D)",
        rf"\g<1>{desired_version[1:]}\g<2>",
        cloud_init_data,
    )

    # 3. Replace kubernetes- package pattern (major.minor only)
    cloud_init_data = re.sub(
        r"(\Wkubernetes-)\d{1}\.\d{2}(\W)",
        rf'\g<1>{".".join(desired_version[1:].split(".")[0:2])}\g<2>',
        cloud_init_data,
    )

    return cloud_init_data


# ---------------------------------------------------------------------------
# Nodepool helpers
# ---------------------------------------------------------------------------

def get_nodepool(client, nodepool_id):
    """Fetch the current nodepool configuration."""
    logger.info(f"Fetching nodepool {nodepool_id}...")
    response = client.get_node_pool(node_pool_id=nodepool_id)
    return response.data


def extract_cloud_init_from_nodepool(nodepool):
    """Extract the cloud-init (user_data) from the nodepool's node_metadata."""
    node_metadata = nodepool.node_metadata or {}
    user_data = node_metadata.get("user_data")
    if not user_data:
        logger.warning("No user_data found in node_metadata.")
        return None
    return user_data


def build_update_details(nodepool, new_cloud_init_encoded, desired_k8s_version, new_cloud_init_file):
    """
    Build an UpdateNodePoolDetails object that preserves the existing nodepool
    configuration and only changes:
      - cloud-init (node_metadata.user_data)
      - kubernetes_version (if specified)
    """
    # Preserve existing node_metadata and update user_data
    updated_node_metadata = dict(nodepool.node_metadata or {})
    updated_node_metadata["user_data"] = new_cloud_init_encoded
    if desired_k8s_version:
        updated_node_metadata["oke-k8s-version"] = desired_k8s_version

    # Preserve existing node_source_details
    existing_source = nodepool.node_source_details
    if existing_source:
        source_type = getattr(existing_source, "source_type", "IMAGE")
        if source_type == "IMAGE":
            node_source_details = oci.container_engine.models.NodeSourceViaImageDetails(
                source_type="IMAGE",
                image_id=existing_source.image_id,
                boot_volume_size_in_gbs=getattr(existing_source, "boot_volume_size_in_gbs", None),
            )
        else:
            node_source_details = existing_source
    else:
        node_source_details = None

    # Preserve existing node_config_details
    existing_config = nodepool.node_config_details
    if existing_config:
        placement_configs = []
        for pc in (existing_config.placement_configs or []):
            placement_configs.append(
                oci.container_engine.models.NodePoolPlacementConfigDetails(
                    availability_domain=pc.availability_domain,
                    subnet_id=pc.subnet_id,
                    capacity_reservation_id=getattr(pc, "capacity_reservation_id", None),
                    fault_domains=getattr(pc, "fault_domains", None),
                    preemptible_node_config=getattr(pc, "preemptible_node_config", None),
                )
            )

        node_config_details = oci.container_engine.models.UpdateNodePoolNodeConfigDetails(
            size=existing_config.size,
            nsg_ids=getattr(existing_config, "nsg_ids", None),
            kms_key_id=getattr(existing_config, "kms_key_id", None),
            is_pv_encryption_in_transit_enabled=getattr(existing_config, "is_pv_encryption_in_transit_enabled", None),
            freeform_tags=getattr(existing_config, "freeform_tags", None),
            defined_tags=getattr(existing_config, "defined_tags", None),
            placement_configs=placement_configs,
            node_pool_pod_network_option_details=getattr(existing_config, "node_pool_pod_network_option_details", None),
        )
    else:
        node_config_details = None

    # Build the update details
    update_kwargs = {
        "name": nodepool.name,
        "node_metadata": updated_node_metadata,
    }

    if desired_k8s_version:
        update_kwargs["kubernetes_version"] = desired_k8s_version

    if node_source_details:
        update_kwargs["node_source_details"] = node_source_details

    if node_config_details:
        update_kwargs["node_config_details"] = node_config_details

    # Preserve other fields if present. subnet_ids and quantity_per_subnet are
    # legacy placement fields and are mutually exclusive with node_config_details.
    preserved_attrs = [
        "ssh_public_key", "node_shape", "freeform_tags", "defined_tags",
        "initial_node_labels", "node_eviction_node_pool_settings",
        "node_pool_cycling_details", "secondary_vnics", "network_launch_type",
    ]
    if not node_config_details:
        preserved_attrs.extend(["quantity_per_subnet", "subnet_ids"])

    for attr in preserved_attrs:
        val = getattr(nodepool, attr, None)
        if val is not None:
            update_kwargs[attr] = val

    # Preserve node_shape_config
    existing_shape_config = getattr(nodepool, "node_shape_config", None)
    if existing_shape_config:
        update_kwargs["node_shape_config"] = oci.container_engine.models.UpdateNodeShapeConfigDetails(
            ocpus=getattr(existing_shape_config, "ocpus", None),
            memory_in_gbs=getattr(existing_shape_config, "memory_in_gbs", None),
        )

    return oci.container_engine.models.UpdateNodePoolDetails(**update_kwargs)


def update_nodepool(client, nodepool_id, update_details):
    """Issue the update_node_pool API call."""
    logger.info(f"Updating nodepool {nodepool_id}...")
    response = client.update_node_pool(
        node_pool_id=nodepool_id,
        update_node_pool_details=update_details,
    )
    return response


# ---------------------------------------------------------------------------
# Instance-config mode helpers (RDMA and Compute clusters)
# ---------------------------------------------------------------------------

def get_instance_config_from_cluster_network(cluster_network_id, compute_mgmt_client):
    """Get the instance configuration from a Cluster Network's instance pools."""
    cn = compute_mgmt_client.get_cluster_network(cluster_network_id).data
    instance_pools = cn.instance_pools
    if not instance_pools:
        logger.error(f"No instance pools found in Cluster Network {cluster_network_id}.")
        sys.exit(1)

    # Use the first instance pool's instance config (they should all be the same)
    instance_pool = compute_mgmt_client.get_instance_pool(instance_pools[0].id).data
    instance_config_id = instance_pool.instance_configuration_id
    logger.info(f"Cluster Network '{cn.display_name}' uses instance config {instance_config_id}")
    return instance_config_id


def get_instance_config_from_gpu_memory_cluster(gpu_memory_cluster_id, compute_client, compute_mgmt_client):
    """Get the instance configuration from a GPU Memory Cluster."""
    gmc = compute_client.get_compute_gpu_memory_cluster(gpu_memory_cluster_id).data
    instance_config_id = gmc.instance_configuration_id
    logger.info(f"GPU Memory Cluster '{gmc.display_name}' uses instance config {instance_config_id}")
    return instance_config_id


def get_instance_pools_for_compute_cluster(compute_cluster_id, compute_client, compute_mgmt_client):
    """Find instance pools whose placement configuration targets a Compute Cluster."""
    compute_cluster = compute_client.get_compute_cluster(compute_cluster_id).data
    response = oci.pagination.list_call_get_all_results(
        compute_mgmt_client.list_instance_pools,
        compute_cluster.compartment_id,
    )

    matching_pools = []
    for instance_pool in response.data:
        for placement in (instance_pool.placement_configurations or []):
            if getattr(placement, "compute_cluster_id", None) == compute_cluster_id:
                matching_pools.append(instance_pool)
                break

    if not matching_pools:
        logger.error(f"No instance pools found for Compute Cluster {compute_cluster_id}.")
        sys.exit(1)

    logger.info(
        f"Compute Cluster '{compute_cluster.display_name}' has {len(matching_pools)} matching instance pool(s)."
    )
    return matching_pools


def get_instance_config_from_compute_cluster(compute_cluster_id, compute_client, compute_mgmt_client):
    """Get the instance configuration from a Compute Cluster's instance pools."""
    instance_pools = get_instance_pools_for_compute_cluster(
        compute_cluster_id, compute_client, compute_mgmt_client
    )
    instance_config_ids = {pool.instance_configuration_id for pool in instance_pools}
    if len(instance_config_ids) > 1:
        logger.error(
            "Compute Cluster instance pools use multiple instance configurations: "
            f"{', '.join(sorted(instance_config_ids))}. Update them separately."
        )
        sys.exit(1)

    instance_config_id = next(iter(instance_config_ids))
    logger.info(f"Compute Cluster {compute_cluster_id} uses instance config {instance_config_id}")
    return instance_config_id


def get_instance_config_details(instance_config_id, compute_mgmt_client):
    """Retrieve the full instance configuration details."""
    response = compute_mgmt_client.get_instance_configuration(instance_config_id)
    return response.data


def create_instance_config_with_new_cloud_init(src_config, new_cloud_init_encoded, desired_k8s_version, new_instance_config_name, compute_mgmt_client):
    """
    Create a new instance configuration by copying the source and only changing
    the cloud-init (user_data) in the launch metadata.
    """
    new_instance_details = copy.deepcopy(src_config.instance_details)
    launch = new_instance_details.launch_details
    new_metadata = dict(launch.metadata or {})
    new_metadata["user_data"] = new_cloud_init_encoded
    if desired_k8s_version:
        new_metadata["oke-k8s-version"] = desired_k8s_version
    launch.metadata = new_metadata

    config_name = new_instance_config_name or f"{src_config.display_name}-updated"
    logger.info(f"Creating new instance configuration '{config_name}'...")

    new_config_details = oci.core.models.CreateInstanceConfigurationDetails(
        compartment_id=src_config.compartment_id,
        display_name=config_name,
        instance_details=new_instance_details,
        defined_tags=src_config.defined_tags,
        freeform_tags=src_config.freeform_tags,
    )

    response = compute_mgmt_client.create_instance_configuration(new_config_details)
    return response.data


def attach_instance_config_to_cluster_network(cluster_network_id, new_instance_config_id, compute_mgmt_client):
    """Update all instance pools in a Cluster Network to use the new instance config."""
    cn = compute_mgmt_client.get_cluster_network(cluster_network_id).data
    for ip_summary in cn.instance_pools:
        instance_pool = compute_mgmt_client.get_instance_pool(ip_summary.id).data
        compute_mgmt_client.update_instance_pool(
            instance_pool_id=instance_pool.id,
            update_instance_pool_details=oci.core.models.UpdateInstancePoolDetails(
                instance_configuration_id=new_instance_config_id,
            ),
        )
        logger.info(f"Updated instance pool {instance_pool.id} in Cluster Network {cluster_network_id} with new instance config {new_instance_config_id}")


def attach_instance_config_to_gpu_memory_cluster(gpu_memory_cluster_id, new_instance_config_id, compute_client):
    """Update a GPU Memory Cluster to use the new instance config."""
    compute_client.update_compute_gpu_memory_cluster(
        gpu_memory_cluster_id=gpu_memory_cluster_id,
        update_compute_gpu_memory_cluster_details=oci.core.models.UpdateComputeGpuMemoryClusterDetails(
            instance_configuration_id=new_instance_config_id,
        ),
    )
    logger.info(f"Updated GPU Memory Cluster {gpu_memory_cluster_id} with new instance config {new_instance_config_id}")


def attach_instance_config_to_compute_cluster(compute_cluster_id, new_instance_config_id, compute_client, compute_mgmt_client):
    """Update all matching Compute Cluster instance pools to use the new instance config."""
    instance_pools = get_instance_pools_for_compute_cluster(
        compute_cluster_id, compute_client, compute_mgmt_client
    )
    for instance_pool in instance_pools:
        compute_mgmt_client.update_instance_pool(
            instance_pool_id=instance_pool.id,
            update_instance_pool_details=oci.core.models.UpdateInstancePoolDetails(
                instance_configuration_id=new_instance_config_id,
            ),
        )
        logger.info(f"Updated instance pool {instance_pool.id} in Compute Cluster {compute_cluster_id} with new instance config {new_instance_config_id}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Update cloud-init and/or kubernetes version on an OKE nodepool, RDMA cluster, or Compute Cluster instance configuration."
    )
    parser.add_argument(
        "--mode", required=False, default="nodepool",
        choices=["nodepool", "instance-config"],
        help="Operation mode. 'nodepool' updates an OKE nodepool; 'instance-config' copies an instance config with new cloud-init and attaches it to a Cluster Network, GPU Memory Cluster, or Compute Cluster. Default: nodepool",
    )

    # Nodepool mode arguments
    parser.add_argument(
        "--nodepool-id", required=False, default="",
        help="[nodepool mode] OCID of the OKE nodepool to update.",
    )

    # Instance-config mode arguments
    parser.add_argument(
        "--cluster-network-id", required=False, default="",
        help="[instance-config mode] OCID of the Cluster Network (RDMA). The script will find the instance config from its instance pools.",
    )
    parser.add_argument(
        "--gpu-memory-cluster-id", required=False, default="",
        help="[instance-config mode] OCID of the Compute GPU Memory Cluster.",
    )
    parser.add_argument(
        "--compute-cluster-id", required=False, default="",
        help="[instance-config mode] OCID of the Compute Cluster. The script will find instance pools whose placement configuration targets it.",
    )
    parser.add_argument(
        "--new-instance-config-name", required=False, default="",
        help="[instance-config mode] Name for the new instance configuration. Default: <original>-updated",
    )

    # Common arguments
    parser.add_argument(
        "--desired-k8s-version", required=False, default="",
        help="Desired Kubernetes version (e.g. v1.33.1). Replaces version references in cloud-init, updates nodepool kubernetes_version in nodepool mode, and updates oke-k8s-version metadata when present.",
    )
    parser.add_argument(
        "--cloud-init-file", required=False, default="",
        help="Path to a new cloud-init file to use. If not provided, the existing cloud-init is decoded, modified (if --desired-k8s-version is set), and re-encoded.",
    )
    parser.add_argument(
        "--oci-config-file", required=False, default="~/.oci/config",
        help="Path to the OCI config file. Default: ~/.oci/config",
    )
    parser.add_argument(
        "--oci-config-profile", required=False, default="DEFAULT",
        help="OCI config profile to use. Default: DEFAULT",
    )
    parser.add_argument(
        "--auth", required=False, default="config_file",
        choices=["config_file", "instance_principal", "cloud_shell"],
        help="OCI authentication method. Default: config_file",
    )
    parser.add_argument(
        "--region", required=False, default="",
        help="OCI region. Required when using --auth instance_principal.",
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="Enable debug logging.",
    )
    args = parser.parse_args()

    if args.debug:
        setup_logging(logging.DEBUG)
    else:
        setup_logging(logging.INFO)

    if not args.desired_k8s_version and not args.cloud_init_file:
        logger.error("At least one of --desired-k8s-version or --cloud-init-file must be specified.")
        sys.exit(1)

    # Initialize all OCI clients
    ce_client, compute_client, compute_mgmt_client = _init_oci_clients(
        args.auth, args.region, args.oci_config_file, args.oci_config_profile
    )

    if args.mode == "nodepool":
        _run_nodepool_mode(args, ce_client)
    else:
        _run_instance_config_mode(args, compute_client, compute_mgmt_client)


def _run_nodepool_mode(args, ce_client):
    """Execute the nodepool update flow."""
    if not args.nodepool_id:
        logger.error("--nodepool-id is required in nodepool mode.")
        sys.exit(1)

    # Step 1: Fetch existing nodepool configuration
    nodepool = get_nodepool(ce_client, args.nodepool_id)
    logger.info(f"Nodepool name: {nodepool.name}")
    logger.info(f"Current kubernetes version: {nodepool.kubernetes_version}")

    # Step 2: Determine the new cloud-init
    if args.cloud_init_file:
        logger.info(f"Using cloud-init from file: {args.cloud_init_file}")
        with open(args.cloud_init_file, "r") as f:
            cloud_init_str = f.read()
        if args.desired_k8s_version:
            logger.info(f"Applying k8s version replacements ({args.desired_k8s_version}) to cloud-init file content...")
            cloud_init_str = replace_k8s_version_in_cloud_init(cloud_init_str, args.desired_k8s_version)
        new_cloud_init_encoded = encode_cloud_init(cloud_init_str)
    else:
        existing_cloud_init = extract_cloud_init_from_nodepool(nodepool)
        if not existing_cloud_init:
            logger.error("No existing cloud-init found in nodepool and no --cloud-init-file provided.")
            sys.exit(1)

        logger.info("Decoding existing cloud-init...")
        cloud_init_str = decode_cloud_init(existing_cloud_init)
        logger.debug(f"Decoded cloud-init ({len(cloud_init_str)} chars):\n{cloud_init_str[:500]}...")

        if args.desired_k8s_version:
            logger.info(f"Applying k8s version replacements ({args.desired_k8s_version}) to existing cloud-init...")
            cloud_init_str = replace_k8s_version_in_cloud_init(cloud_init_str, args.desired_k8s_version)

        new_cloud_init_encoded = encode_cloud_init(cloud_init_str)

    # Step 3: Build the update details
    k8s_version = args.desired_k8s_version if args.desired_k8s_version else nodepool.kubernetes_version
    update_details = build_update_details(nodepool, new_cloud_init_encoded, args.desired_k8s_version or None, args.cloud_init_file)

    logger.info("Update details built successfully.")
    logger.info(f"  Kubernetes version: {k8s_version}")
    logger.info(f"  Cloud-init encoded length: {len(new_cloud_init_encoded)} chars")

    # Step 4: Confirm and apply
    response = input("Apply the update to the nodepool? [y/n]: ")
    if response.lower() != "y":
        logger.info("Update cancelled by user.")
        sys.exit(0)

    update_response = update_nodepool(ce_client, args.nodepool_id, update_details)
    logger.info(f"Update request accepted. Status: {update_response.status}")
    logger.info(f"Work Request ID: {update_response.headers.get('opc-work-request-id', 'N/A')}")


def _run_instance_config_mode(args, compute_client, compute_mgmt_client):
    """Execute the instance-config update flow for RDMA or Compute clusters."""
    if not args.cluster_network_id and not args.gpu_memory_cluster_id and not args.compute_cluster_id:
        logger.error("In instance-config mode, at least one of --cluster-network-id, --gpu-memory-cluster-id, or --compute-cluster-id must be specified.")
        sys.exit(1)

    # Step 1: Resolve the source instance configuration from the cluster
    instance_config_ids = []
    if args.cluster_network_id:
        instance_config_ids.append(
            get_instance_config_from_cluster_network(args.cluster_network_id, compute_mgmt_client)
        )
    if args.gpu_memory_cluster_id:
        instance_config_ids.append(
            get_instance_config_from_gpu_memory_cluster(args.gpu_memory_cluster_id, compute_client, compute_mgmt_client)
        )
    if args.compute_cluster_id:
        instance_config_ids.append(
            get_instance_config_from_compute_cluster(args.compute_cluster_id, compute_client, compute_mgmt_client)
        )

    unique_instance_config_ids = set(instance_config_ids)
    if len(unique_instance_config_ids) > 1:
        logger.error(
            "Selected targets use different source instance configurations: "
            f"{', '.join(sorted(unique_instance_config_ids))}. Update them separately."
        )
        sys.exit(1)
    instance_config_id = instance_config_ids[0]

    # Step 2: Fetch the instance configuration details
    src_config = get_instance_config_details(instance_config_id, compute_mgmt_client)
    logger.info(f"Source instance config: {src_config.display_name} ({src_config.id})")

    # Step 3: Extract and modify the cloud-init
    launch = src_config.instance_details.launch_details
    existing_cloud_init = (launch.metadata or {}).get("user_data")

    if args.cloud_init_file:
        logger.info(f"Using cloud-init from file: {args.cloud_init_file}")
        with open(args.cloud_init_file, "r") as f:
            cloud_init_str = f.read()
        if args.desired_k8s_version:
            logger.info(f"Applying k8s version replacements ({args.desired_k8s_version}) to cloud-init file content...")
            cloud_init_str = replace_k8s_version_in_cloud_init(cloud_init_str, args.desired_k8s_version)
    elif existing_cloud_init:
        logger.info("Decoding existing cloud-init from instance config...")
        cloud_init_str = decode_cloud_init(existing_cloud_init)
        logger.debug(f"Decoded cloud-init ({len(cloud_init_str)} chars):\n{cloud_init_str[:500]}...")

        if args.desired_k8s_version:
            logger.info(f"Applying k8s version replacements ({args.desired_k8s_version}) to existing cloud-init...")
            cloud_init_str = replace_k8s_version_in_cloud_init(cloud_init_str, args.desired_k8s_version)
    else:
        logger.error("No existing cloud-init found in instance config and no --cloud-init-file provided.")
        sys.exit(1)

    new_cloud_init_encoded = encode_cloud_init(cloud_init_str)

    # Step 4: Create the new instance configuration
    new_config = create_instance_config_with_new_cloud_init(
        src_config, new_cloud_init_encoded, args.desired_k8s_version or None, args.new_instance_config_name, compute_mgmt_client
    )
    logger.info(f"New instance configuration created: {new_config.display_name} ({new_config.id})")

    # Step 5: Attach the new instance config to the cluster(s)
    response = input("Attach the new instance configuration to the cluster? [y/n]: ")
    if response.lower() != "y":
        logger.info(f"Attachment cancelled. The new instance config {new_config.id} was created but not attached.")
        sys.exit(0)

    if args.cluster_network_id:
        attach_instance_config_to_cluster_network(
            args.cluster_network_id, new_config.id, compute_mgmt_client
        )
        logger.info(f"Cluster Network {args.cluster_network_id} updated. New nodes will use instance config {new_config.id}.")

    if args.gpu_memory_cluster_id:
        attach_instance_config_to_gpu_memory_cluster(
            args.gpu_memory_cluster_id, new_config.id, compute_client
        )
        logger.info(f"GPU Memory Cluster {args.gpu_memory_cluster_id} updated. New nodes will use instance config {new_config.id}.")

    if args.compute_cluster_id:
        attach_instance_config_to_compute_cluster(
            args.compute_cluster_id, new_config.id, compute_client, compute_mgmt_client
        )
        logger.info(f"Compute Cluster {args.compute_cluster_id} updated. New nodes will use instance config {new_config.id}.")


if __name__ == "__main__":
    main()
