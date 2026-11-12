# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

variable "install_kube_fledged" {
  type        = bool
  default     = false
  description = "Install kube-fledged and GPU image caches, independently of OCI HPC OKE Utils."
}

variable "kube_fledged_chart_version" {
  type        = string
  default     = "v0.11.0"
  description = "Pinned upstream kube-fledged Helm chart version."
}

variable "kube_fledged_refresh_frequency" {
  type        = string
  default     = "15m"
  description = "Positive cache refresh interval (Go duration). Refresh retries failed pulls and populates new nodes."
  validation {
    condition     = can(regex("^([0-9]+(h|m|s))+$", var.kube_fledged_refresh_frequency)) && can(regex("[1-9]", var.kube_fledged_refresh_frequency))
    error_message = "Use a positive duration such as 15m or 1h30m; refresh must remain enabled."
  }
}

variable "kube_fledged_pull_deadline" {
  type        = string
  default     = "30m"
  description = "Maximum wait for image pulls (Go duration); allow enough time for large GPU images."
  validation {
    condition     = can(regex("^([0-9]+(h|m|s))+$", var.kube_fledged_pull_deadline)) && can(regex("[1-9]", var.kube_fledged_pull_deadline))
    error_message = "Use a positive duration such as 30m."
  }
}

variable "kube_fledged_image_pull_policy" {
  type        = string
  default     = "IfNotPresent"
  description = "Image pull policy for cache creation and refresh. Prefer immutable image tags or digests."
  validation {
    condition     = contains(["IfNotPresent", "Always"], var.kube_fledged_image_pull_policy)
    error_message = "Image pull policy must be IfNotPresent or Always."
  }
}

variable "kube_fledged_image_pull_secrets" {
  type        = list(string)
  default     = []
  description = "Names of existing registry secrets in kube-fledged, used by the controller and cache Jobs. Secret contents are not managed by this stack."
  validation {
    condition     = alltrue([for name in var.kube_fledged_image_pull_secrets : length(name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", name))])
    error_message = "Registry secret names must be valid Kubernetes DNS subdomain names."
  }
}

variable "kube_fledged_image_groups" {
  type = map(object({
    nodeSelector = map(string)
    images       = list(string)
  }))
  default     = null
  description = "Replacement cache groups. Null uses the bundled NVIDIA NCCL/AMD RCCL defaults; an empty images list disables a group. Each active group requires an explicit node selector."
  validation {
    condition = var.kube_fledged_image_groups == null ? true : alltrue([
      for name, group in var.kube_fledged_image_groups :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name)) && length(name) <= 43 &&
      (length(group.images) == 0 || length(group.nodeSelector) > 0) &&
      alltrue([for image in group.images : trimspace(image) != ""])
    ])
    error_message = "Group names must be DNS labels of at most 43 characters; active groups need a node selector and nonempty image references."
  }
}

locals {
  # Preserve existing tfvars while replacing the old DaemonSets completely.
  kube_fledged_enabled             = var.install_kube_fledged || var.install_image_prepuller
  kube_fledged_controller_defaults = yamldecode(file("${path.module}/files/kube-fledged/values.yaml"))
  kube_fledged_controller_values = merge(local.kube_fledged_controller_defaults, {
    args = merge(local.kube_fledged_controller_defaults.args, {
      controllerImageCacheRefreshFrequency = var.kube_fledged_refresh_frequency
      controllerImagePullDeadlineDuration  = var.kube_fledged_pull_deadline
      controllerImagePullPolicy            = var.kube_fledged_image_pull_policy
    })
    imagePullSecrets = [for name in var.kube_fledged_image_pull_secrets : { name = name }]
  })
  kube_fledged_cache_defaults = yamldecode(file("${path.module}/files/kube-fledged/imagecaches.yaml"))
  kube_fledged_cache_values = {
    groups           = var.kube_fledged_image_groups == null ? local.kube_fledged_cache_defaults.groups : var.kube_fledged_image_groups
    imagePullSecrets = [for name in var.kube_fledged_image_pull_secrets : { name = name }]
  }
}
