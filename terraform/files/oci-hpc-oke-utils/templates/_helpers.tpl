{{- define "oci-hpc-oke-utils.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "oci-hpc-oke-utils.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "oci-hpc-oke-utils.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Content-addressed name for the RDMA PF reconciler script ConfigMap. The
ConfigMap is immutable, so script changes produce a new name and roll the
DaemonSet instead of mutating executable content in place.
*/}}
{{- define "oci-hpc-oke-utils.rdmaPfReconcilerScriptName" -}}
{{- $hash := printf "%s%s%s%s" (.Files.Get "files/rdma-pf-reconciler/rdma-pf-reconciler.sh") (.Files.Get "files/rdma-pf-reconciler/reconcile-auth.sh") (.Files.Get "files/rdma-pf-reconciler/restore-host-routes.sh") (.Files.Get "files/rdma-pf-reconciler/restore-host-routes-monitor.sh") | sha256sum | trunc 8 -}}
{{- printf "%s-rdma-pf-reconciler-%s" (include "oci-hpc-oke-utils.fullname" .) $hash -}}
{{- end -}}
