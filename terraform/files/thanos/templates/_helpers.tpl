{{- define "thanos.labels" -}}
app.kubernetes.io/part-of: thanos
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "thanos.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}
