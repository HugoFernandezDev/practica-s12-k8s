#!/usr/bin/env bash
# ==============================================================================
# Script de Diagnóstico y Troubleshooting Kubernetes - Práctica S12 | AP9
# Automatiza la inspección de Pods, Logs, Events, SecurityContext y Red Interna.
# Uso:
#   ./scripts/diagnose.sh           -> Ejecuta diagnóstico completo
#   ./scripts/diagnose.sh broken    -> Despliega escenario con 3 fallas ("Antes")
#   ./scripts/diagnose.sh fix       -> Despliega escenario corregido ("Después")
# ==============================================================================
set -euo pipefail

NS="practica-s12"
MODE="${1:-status}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$MODE" = "broken" ]; then
  echo ">>> [1/2] Aplicando entorno base (Namespace, ConfigMap, Secret)..."
  kubectl apply -f "${ROOT_DIR}/k8s/00-namespace.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/01-security-configmap.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/02-db-secret.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/04-app-service.yaml"
  echo ">>> [2/2] Desplegando manifiesto CON FALLAS (Escenarios A, B y C)..."
  kubectl apply -f "${ROOT_DIR}/k8s/broken/03-app-deployment-broken.yaml"
  echo ">>> Espera ~15-20s para observar CrashLoopBackOff / Unhealthy y ejecuta: $0"
  exit 0
elif [ "$MODE" = "fix" ]; then
  echo ">>> Aplicando manifiestos CORREGIDOS con Hardening..."
  kubectl apply -f "${ROOT_DIR}/k8s/00-namespace.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/01-security-configmap.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/02-db-secret.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/03-app-deployment.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/04-app-service.yaml"
  kubectl rollout status deployment/db-deployment -n "${NS}" --timeout=90s
  kubectl rollout status deployment/app-deployment -n "${NS}" --timeout=90s
fi

echo "=============================================================================="
echo " 1. ESTADO DE PODS, SERVICIOS Y CONFIGURACIÓN (NAMESPACE: ${NS})"
echo "=============================================================================="
kubectl get pods,svc,configmaps,secrets -n "${NS}" -o wide

APP_POD=$(kubectl get pods -n "${NS}" -l app=cloud-sec-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "${APP_POD}" ]; then
  echo "No se encontraron Pods con etiqueta app=cloud-sec-app en ${NS}."
  exit 1
fi

echo ""
echo "=============================================================================="
echo " 2. DESCRIPCIÓN Y EVENTOS DEL POD (${APP_POD})"
echo "=============================================================================="
kubectl describe pod "${APP_POD}" -n "${NS}" | tail -n 35

echo ""
echo "=============================================================================="
echo " 3. LOGS DEL CONTENEDOR (${APP_POD})"
echo "=============================================================================="
kubectl logs "${APP_POD}" -n "${NS}" --tail=30 || true

echo ""
echo "=============================================================================="
echo " 4. VALIDACIÓN DE CONTEXTO DE SEGURIDAD (NON-ROOT UID 10001 & READ-ONLY FS)"
echo "=============================================================================="
kubectl exec "${APP_POD}" -n "${NS}" -- id || true
kubectl exec "${APP_POD}" -n "${NS}" -- sh -c 'touch /test-ro 2>&1 || true'

echo ""
echo "=============================================================================="
echo " 5. PRUEBA INTERNA DE CONECTIVIDAD HTTP Y SONDAS DE SALUD"
echo "=============================================================================="
kubectl exec "${APP_POD}" -n "${NS}" -- python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/api/status').read().decode())" || true
