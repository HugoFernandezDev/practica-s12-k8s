# Práctica S12 | AP9: Despliegue Cloud, Seguridad y Troubleshooting en Kubernetes

Implementación de una arquitectura distribuida en Kubernetes aislada en el namespace **`practica-s12`**, aplicando **Hardening de Seguridad** (`SecurityContext` non-root, UID `10001`, `readOnlyRootFilesystem: true`, `Secrets` Base64), sondas de salud **Liveness / Readiness** y resolución documentada de **3 escenarios de falla críticos (Troubleshooting)**.

---

## 📁 Estructura del Repositorio

```text
/
├── k8s/
│   ├── 00-namespace.yaml                 # Namespace aislado: practica-s12
│   ├── 01-security-configmap.yaml        # ConfigMap con variables de entorno y puerto interno DB
│   ├── 02-db-secret.yaml                 # Secret (Opaque) con credenciales codificadas en Base64
│   ├── 03-app-deployment.yaml            # Deployments hardened (app-deployment + db-deployment/db-service)
│   ├── 04-app-service.yaml               # Service NodePort (30092) / compatible con AWS ELB LoadBalancer
│   └── broken/
│       └── 03-app-deployment-broken.yaml # Escenario "Antes" con las 3 fallas introducidas
├── scripts/
│   ├── diagnose.sh                       # Script Bash de diagnóstico y alternancia broken/fix
│   └── diagnose.ps1                      # Script PowerShell de diagnóstico y alternancia broken/fix
├── docs/
│   └── troubleshooting-log.md            # Bitácora técnica detallada de los 3 escenarios (Antes vs. Después)
└── README.md
```

---

## 🛡️ Arquitectura y Hardening de Seguridad

```text
+-----------------------------------------------------------------------------------+
|                        CLÚSTER KUBERNETES (Namespace: practica-s12)               |
|                                                                                   |
|  [security-configmap] ----+                 +----> [app-deployment] (2 réplicas)  |
|  (APP_PORT=8080, DB_PORT) |---> envFrom --->|      UID: 10001 (runAsNonRoot:true) |
|  [db-secret (Base64)] ----+                 |      readOnlyRootFilesystem: true   |
|                                             |      Liveness:  GET /healthz:8080   |
|                                             |      Readiness: GET /readyz:8080    |
|                                             +------------------+------------------+
|                                                                | TCP :5432        |
|  [app-service] NodePort :30092 (ELB en AWS EKS)                v                  |
|  Redirige tráfico HTTP externo -> :8080        [db-service] ClusterIP :5432       |
|                                                                |                  |
|                                                [db-deployment] UID: 10001         |
+-----------------------------------------------------------------------------------+
```

### Directivas de Seguridad (`SecurityContext`)
En [`k8s/03-app-deployment.yaml`](k8s/03-app-deployment.yaml):
- `runAsNonRoot: true`: impide iniciar contenedores con usuario `root`.
- `runAsUser: 10001` / `runAsGroup: 10001` / `fsGroup: 10001`: ejecuta los procesos con un UID no privilegiado.
- `readOnlyRootFilesystem: true`: protege el sistema de archivos raíz contra escrituras maliciosas (montando `emptyDir` en `/tmp`).
- `allowPrivilegeEscalation: false` + `capabilities.drop: ["ALL"]`: principio de mínimo privilegio.

---

## 🔧 Escenarios de Troubleshooting Cubiertos

1. **Escenario A — Falla de Configuración (`CrashLoopBackOff`):** Mala inyección de variables (`INVALID_CONFIG_MODE=CRASH` y clave incorrecta en `Secret`). Corregido con inyección limpia vía `envFrom`.
2. **Escenario B — Falla de Red/Conectividad:** `DB_PORT` configurado en `5499` en lugar del puerto interno `5432` expuesto por `db-service`.
3. **Escenario C — Falla de Sondas de Salud:** `livenessProbe` y `readinessProbe` apuntando a `/healthz-wrong:9090` en lugar de `/healthz:8080` y `/readyz:8080`.

Consulta la bitácora completa en [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md).

---

## 🚀 Despliegue y Validación

### 1. Reproducir estado con fallas ("Antes")
```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-security-configmap.yaml
kubectl apply -f k8s/02-db-secret.yaml
kubectl apply -f k8s/broken/03-app-deployment-broken.yaml
kubectl get pods -n practica-s12
```

### 2. Aplicar despliegue Hardened y corregido ("Después")
```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-security-configmap.yaml
kubectl apply -f k8s/02-db-secret.yaml
kubectl apply -f k8s/03-app-deployment.yaml
kubectl apply -f k8s/04-app-service.yaml
kubectl get pods -n practica-s12 -o wide
```

### 3. Comandos de Verificación y Auditoría
```bash
# 1. Verificación de estado Running y Ready (2/2 + 1/1)
kubectl get pods -n practica-s12

# 2. Validación de usuario non-root (UID 10001)
kubectl exec -it <pod-app> -n practica-s12 -- id

# 3. Revisión de logs y eventos
kubectl logs <pod-app> -n practica-s12
kubectl describe pod <pod-app> -n practica-s12

# 4. Script automatizado de diagnóstico
./scripts/diagnose.sh
```

> **Nota para AWS EKS / EC2:** Para exposición con AWS ELB cambia `type: NodePort` a `type: LoadBalancer` en [`k8s/04-app-service.yaml`](k8s/04-app-service.yaml), o mantén `NodePort` abriendo el puerto `TCP 30092` en el **Security Group** de tu VPC en AWS.
