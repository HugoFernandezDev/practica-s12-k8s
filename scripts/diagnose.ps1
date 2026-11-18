# ==============================================================================
# Script de Diagnóstico y Troubleshooting Kubernetes (PowerShell) - Práctica S12
# Uso:
#   .\scripts\diagnose.ps1              -> Ejecuta diagnóstico completo
#   .\scripts\diagnose.ps1 -Mode broken -> Despliega escenario con las 3 fallas
#   .\scripts\diagnose.ps1 -Mode fix    -> Despliega solución Hardened corregida
# ==============================================================================
param(
    [ValidateSet("status", "broken", "fix")]
    [string]$Mode = "status"
)

$ErrorActionPreference = "Continue"
$Namespace = "practica-s12"
$RootDir = Split-Path -Parent $PSScriptRoot

if ($Mode -eq "broken") {
    Write-Host ">>> [1/2] Aplicando entorno base (Namespace, ConfigMap, Secret, Service)..." -ForegroundColor Yellow
    kubectl apply -f "$RootDir\k8s\00-namespace.yaml"
    kubectl apply -f "$RootDir\k8s\01-security-configmap.yaml"
    kubectl apply -f "$RootDir\k8s\02-db-secret.yaml"
    kubectl apply -f "$RootDir\k8s\04-app-service.yaml"
    Write-Host ">>> [2/2] Desplegando escenario CON FALLAS (Escenarios A, B y C)..." -ForegroundColor Red
    kubectl apply -f "$RootDir\k8s\broken\03-app-deployment-broken.yaml"
    Write-Host ">>> Espera ~15-20s para observar CrashLoopBackOff y ejecuta .\scripts\diagnose.ps1" -ForegroundColor Cyan
    exit 0
}

if ($Mode -eq "fix") {
    Write-Host ">>> Aplicando manifiestos CORREGIDOS con Hardening de Seguridad..." -ForegroundColor Green
    kubectl apply -f "$RootDir\k8s\00-namespace.yaml"
    kubectl apply -f "$RootDir\k8s\01-security-configmap.yaml"
    kubectl apply -f "$RootDir\k8s\02-db-secret.yaml"
    kubectl apply -f "$RootDir\k8s\03-app-deployment.yaml"
    kubectl apply -f "$RootDir\k8s\04-app-service.yaml"
    kubectl rollout status deployment/db-deployment -n $Namespace --timeout=90s
    kubectl rollout status deployment/app-deployment -n $Namespace --timeout=90s
}

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 1. ESTADO DE PODS, SERVICIOS, CONFIGMAP Y SECRET (NAMESPACE: $Namespace)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
kubectl get pods,svc,configmaps,secrets -n $Namespace -o wide

$AppPod = kubectl get pods -n $Namespace -l app=cloud-sec-app -o jsonpath="{.items[0].metadata.name}" 2>$null
if (-not $AppPod) {
    Write-Host "No se encontraron Pods con etiqueta app=cloud-sec-app en $Namespace." -ForegroundColor Red
    exit 1
}

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 2. DESCRIPCIÓN Y EVENTOS DEL POD ($AppPod)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
kubectl describe pod $AppPod -n $Namespace | Select-Object -Last 35

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 3. LOGS DEL CONTENEDOR ($AppPod)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
kubectl logs $AppPod -n $Namespace --tail=30

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 4. VALIDACIÓN DEL CONTEXTO DE SEGURIDAD (UID 10001 NON-ROOT & READONLY ROOTFS)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
kubectl exec $AppPod -n $Namespace -- id
kubectl exec $AppPod -n $Namespace -- sh -c "touch /test-ro 2>&1 || true"

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host " 5. PRUEBA DE ENDPOINTS HTTP INTERNOS (/healthz, /readyz, /api/status)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
kubectl exec $AppPod -n $Namespace -- python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/api/status').read().decode())"
