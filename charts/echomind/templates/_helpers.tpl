{{/*
Expand the name of the chart.
*/}}
{{- define "echomind.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "echomind.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "echomind.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "echomind.labels" -}}
helm.sh/chart: {{ include "echomind.chart" . }}
{{ include "echomind.selectorLabels" . }}
{{- if .Values.image.tag }}
app.kubernetes.io/version: {{ include "echomind.imageTag" . | trunc 63 | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "echomind.selectorLabels" -}}
app.kubernetes.io/name: {{ include "echomind.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "echomind.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "echomind.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The image tag is required: every release maps to exactly one git commit.
*/}}
{{- define "echomind.imageTag" -}}
{{- required "image.tag is required: deploy a CI-built image by its full git commit SHA" .Values.image.tag -}}
{{- end }}

{{/*
Labels for the n8n pods and for the Postgres pods. The component label keeps
the two selectors apart.
*/}}
{{- define "echomind.n8n.selectorLabels" -}}
{{ include "echomind.selectorLabels" . }}
app.kubernetes.io/component: n8n
{{- end }}

{{- define "echomind.postgres.selectorLabels" -}}
{{ include "echomind.selectorLabels" . }}
app.kubernetes.io/component: database
{{- end }}

{{- define "echomind.postgres.host" -}}
{{- printf "%s-postgres" (include "echomind.fullname" .) -}}
{{- end }}

{{- define "echomind.dbSecretName" -}}
{{- printf "%s-db" (include "echomind.fullname" .) -}}
{{- end }}

{{- define "echomind.encryptionKeySecretName" -}}
{{- printf "%s-encryption-key" (include "echomind.fullname" .) -}}
{{- end }}

{{- define "echomind.restrictedSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}
