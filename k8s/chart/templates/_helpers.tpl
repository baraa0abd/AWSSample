{{- define "app.name" -}}
{{ .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "app.labels" -}}
{{ include "app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "app.image" -}}
{{- $tag := required "image.tag is required (git SHA or semver)" .Values.image.tag -}}
{{- if eq $tag "latest" }}{{ fail "image.tag must not be 'latest': deploy an immutable tag" }}{{ end -}}
{{ required "image.repository is required" .Values.image.repository }}:{{ $tag }}
{{- end }}
