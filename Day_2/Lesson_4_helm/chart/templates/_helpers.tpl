{{/* Generate basic labels */}}
{{- define "my-first-chart.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
managed-by: {{ .Release.Service }}
teaching-tool: "helm"
{{- end -}}
