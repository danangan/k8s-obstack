{{/*
Node placement (nodeSelector / tolerations / affinity) for the central components:
Prometheus, Loki, Tempo, Grafana and the cluster collector. Render inside a pod spec with
  {{- include "obstack.placement" . | nindent 6 }}
*/}}
{{- define "obstack.placement" -}}
{{- with .Values.placement.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.placement.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.placement.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
PersistentVolumeClaim for a component's data, when <component>.persistence.enabled.
  {{ include "obstack.pvc" (dict "root" $ "name" "prometheus" "persistence" .Values.prometheus.persistence) }}
*/}}
{{- define "obstack.pvc" -}}
{{- if .persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .name }}-data
  namespace: {{ .root.Values.namespace.name }}
  annotations:
    # Keep the claim, and so the volume and its data, on `helm uninstall`.
    helm.sh/resource-policy: keep
spec:
  accessModes: [ReadWriteOnce]
  {{- with (.persistence.storageClassName | default .root.Values.storage.className) }}
  storageClassName: {{ . }}
  {{- end }}
  resources:
    requests:
      storage: {{ .persistence.size }}
{{- end }}
{{- end }}

{{/*
The `data` volume for a component: its PVC when persistence is enabled, otherwise an emptyDir.
  {{- include "obstack.dataVolume" (dict "name" "prometheus" "persistence" .Values.prometheus.persistence) | nindent 8 }}
*/}}
{{- define "obstack.dataVolume" -}}
- name: data
{{- if .persistence.enabled }}
  persistentVolumeClaim:
    claimName: {{ .name }}-data
{{- else }}
  emptyDir: {}
{{- end }}
{{- end }}
