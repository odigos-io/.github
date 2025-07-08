{{/*
Expand the name of the chart.
*/}}
{{- define "odigos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "odigos.fullname" -}}
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
{{- define "odigos.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "odigos.labels" -}}
helm.sh/chart: {{ include "odigos.chart" . }}
{{ include "odigos.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "odigos.selectorLabels" -}}
app.kubernetes.io/name: {{ include "odigos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "odigos.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "odigos.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Convert Kubernetes memory limit to GOMEMLIMIT value
Handles memory units: Ki, Mi, Gi, Ti, Pi, Ei (binary) and K, M, G, T, P, E (decimal)
Returns empty string if parsing fails or value is 0
*/}}
{{- define "odigos.gomemlimitFromLimits" -}}
{{- $memory := . -}}
{{- if $memory -}}
  {{- /* Use improved regex to match valid decimal numbers */ -}}
  {{- $pattern := "^([0-9]+(?:\\.[0-9]+)?)([KMGTPE]i?)?$" -}}
  {{- if regexMatch $pattern $memory -}}
    {{- $matches := regexFindSubmatch $pattern $memory -}}
    {{- $number := index $matches 1 -}}
    {{- $unit := index $matches 2 -}}
    {{- /* Only proceed if we have a valid number and it's not zero */ -}}
    {{- if and $number (ne $number "0") (ne $number "0.0") -}}
      {{- $bytes := 0 -}}
      {{- $numFloat := float64 $number -}}
      {{- /* Handle different memory units */ -}}
      {{- if eq $unit "Ki" -}}
        {{- $bytes = mul $numFloat 1024 -}}
      {{- else if eq $unit "Mi" -}}
        {{- $bytes = mul $numFloat 1048576 -}}
      {{- else if eq $unit "Gi" -}}
        {{- $bytes = mul $numFloat 1073741824 -}}
      {{- else if eq $unit "Ti" -}}
        {{- $bytes = mul $numFloat 1099511627776 -}}
      {{- else if eq $unit "Pi" -}}
        {{- $bytes = mul $numFloat 1125899906842624 -}}
      {{- else if eq $unit "Ei" -}}
        {{- $bytes = mul $numFloat 1152921504606846976 -}}
      {{- else if eq $unit "K" -}}
        {{- $bytes = mul $numFloat 1000 -}}
      {{- else if eq $unit "M" -}}
        {{- $bytes = mul $numFloat 1000000 -}}
      {{- else if eq $unit "G" -}}
        {{- $bytes = mul $numFloat 1000000000 -}}
      {{- else if eq $unit "T" -}}
        {{- $bytes = mul $numFloat 1000000000000 -}}
      {{- else if eq $unit "P" -}}
        {{- $bytes = mul $numFloat 1000000000000000 -}}
      {{- else if eq $unit "E" -}}
        {{- $bytes = mul $numFloat 1000000000000000000 -}}
      {{- else -}}
        {{- /* No unit means bytes */ -}}
        {{- $bytes = $numFloat -}}
      {{- end -}}
      {{- /* Convert to string and remove decimal places for integer result */ -}}
      {{- $bytes | int64 -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}