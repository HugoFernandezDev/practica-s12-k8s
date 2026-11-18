# Bitácora Técnica de Troubleshooting y Hardening de Seguridad (S12 | AP9)

**Namespace:** `practica-s12`  
**Arquitectura:** Microservicio Web Cloud (`app-deployment`) + Servicio interno de Base de Datos (`db-deployment` / `db-service`) en Kubernetes con endurecimiento (`SecurityContext` non-root).

---

## Resumen Ejecutivo de Fallas Identificadas y Resueltas

| Escenario | Categoría | Síntoma en Clúster | Causa Raíz | Solución Aplicada |
| :--- | :--- | :--- | :--- | :--- |
| **Escenario A** | Configuración (`ConfigMap`/`Secret`) | Pod en estado `Error` / `CrashLoopBackOff` (`RESTARTS > 0`) | Variable `INVALID_CONFIG_MODE=CRASH` y clave errónea `DB_PASS_KEY` referenciando `DB_USER` en lugar de inyectar correctamente `security-configmap` y `db-secret` | Eliminación de la variable inválida e inyección completa vía `envFrom` (`security-configmap` + `db-secret`) |
| **Escenario B** | Red y Conectividad Interna | Log `[NET ERROR] Connection refused al intentar conectar con db-service:5499` | El contenedor intentaba conectar al puerto `5499` mientras `db-service` (`ClusterIP`) expone el puerto `5432` | Sincronización de `DB_HOST=db-service` y `DB_PORT=5432` desde `security-configmap` y despliegue del servicio ClusterIP en puerto `5432` |
| **Escenario C** | Sondas de Salud (`Probes`) | Eventos `Warning Unhealthy`: `Liveness/Readiness probe failed` en `:9090/healthz-wrong` | Las sondas `livenessProbe` y `readinessProbe` apuntaban a rutas (`/healthz-wrong`, `/readyz-wrong`) y puerto (`9090`) inexistentes | Corrección hacia `GET /healthz` y `GET /readyz` en el puerto real del contenedor (`8080`) |

---

## Escenario A — Falla de Configuración (`CrashLoopBackOff`)

### 1. Síntoma observado
Al listar los Pods tras aplicar el manifiesto defectuoso (`k8s/broken/03-app-deployment-broken.yaml`):
```bash
kubectl get pods -n practica-s12
```
El Pod `app-deployment-*` entra en estado `Error` y posteriormente `CrashLoopBackOff` con reinicios crecientes (`READY 0/1`).

### 2. Comandos de diagnóstico
```bash
kubectl logs <pod-app> -n practica-s12
kubectl describe pod <pod-app> -n practica-s12
```
Salida de diagnóstico en logs:
```text
[FATAL CONFIG ERROR] Error de inyeccion en ConfigMap/Secret: Variable critica DB_PASS_KEY invalida (INVALID_CONFIG_MODE=CRASH)
```

### 3. Causa raíz
En `k8s/broken/03-app-deployment-broken.yaml`, se introdujo `INVALID_CONFIG_MODE: "CRASH"` y se mapeó erróneamente `DB_PASS_KEY` apuntando a la clave `DB_USER` del Secret, omitiendo la variable requerida `DB_PASS`.

### 4. Solución aplicada (Antes vs. Después)

**Antes (`k8s/broken/03-app-deployment-broken.yaml`):**
```yaml
env:
  - name: INVALID_CONFIG_MODE
    value: "CRASH"
  - name: DB_PASS_KEY
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: DB_USER
```

**Después (`k8s/03-app-deployment.yaml`):**
```yaml
envFrom:
  - configMapRef:
      name: security-configmap
  - secretRef:
      name: db-secret
```

---

## Escenario B — Falla de Red y Conectividad Interna

### 1. Síntoma observado
El backend no logra establecer conexión TCP contra el servicio interno `db-service` dentro del namespace `practica-s12`.

### 2. Comandos de diagnóstico
```bash
kubectl logs <pod-app> -n practica-s12
kubectl get svc,endpoints -n practica-s12
```
Salida observada en los logs:
```text
[NET ERROR] Connection refused al intentar conectar con db-service:5499 (Puerto interno incorrecto)
```

### 3. Causa raíz
El manifiesto defectuoso sobrescribió `DB_PORT` con `"5499"`, pero el Service `db-service` (`ClusterIP`) atiende en el puerto `5432`. Al intentar conectar a `db-service:5499`, el kernel devuelve `Connection refused`.

### 4. Solución aplicada (Antes vs. Después)

**Antes:**
```yaml
- name: DB_PORT
  value: "5499"
```

**Después (`k8s/01-security-configmap.yaml` + `k8s/03-app-deployment.yaml`):**
```yaml
# En security-configmap:
DB_HOST: "db-service"
DB_PORT: "5432"
```
Tras corregir el puerto mediante `security-configmap` y `db-service` en `5432`, el backend registra:
```text
[OK] Conectado a base de datos interna db-service:5432/cloud_security_db en <latencia> ms.
```

---

## Escenario C — Falla de Sondas de Salud (`Liveness` y `Readiness`)

### 1. Síntoma observado
Kubelet marca el contenedor como no saludable (`0/1`) y emite eventos `Warning Unhealthy` hasta reiniciar el contenedor.

### 2. Comandos de diagnóstico
```bash
kubectl describe pod <pod-app> -n practica-s12
```
Eventos observados:
```text
Warning  Unhealthy  kubelet  Readiness probe failed: Get "http://<pod-ip>:9090/readyz-wrong": dial tcp <pod-ip>:9090: connect: connection refused
Warning  Unhealthy  kubelet  Liveness probe failed: Get "http://<pod-ip>:9090/healthz-wrong": dial tcp <pod-ip>:9090: connect: connection refused
```

### 3. Causa raíz
Las sondas `livenessProbe` y `readinessProbe` consultaban rutas inexistentes (`/healthz-wrong`, `/readyz-wrong`) en el puerto equivocado (`9090`), cuando la aplicación escucha en el puerto `8080` y expone `/healthz` y `/readyz`.

### 4. Solución aplicada (Antes vs. Después)

**Antes:**
```yaml
livenessProbe:
  httpGet:
    path: /healthz-wrong
    port: 9090
readinessProbe:
  httpGet:
    path: /readyz-wrong
    port: 9090
```

**Después (`k8s/03-app-deployment.yaml`):**
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /readyz
    port: 8080
  initialDelaySeconds: 3
  periodSeconds: 5
```

---

## Directivas de Hardening de Seguridad Implementadas

Aplicadas tanto a nivel de **Pod** como de **Contenedor** en `k8s/03-app-deployment.yaml`:
- `runAsNonRoot: true`: prohíbe explícitamente la ejecución como `root` (UID 0).
- `runAsUser: 10001` y `runAsGroup: 10001` (`fsGroup: 10001`): fuerza un UID/GID sin privilegios.
- `readOnlyRootFilesystem: true`: convierte en solo lectura todo el sistema de archivos raíz del contenedor, montando únicamente un volumen temporal `emptyDir` en `/tmp`.
- `allowPrivilegeEscalation: false` y `capabilities.drop: ["ALL"]`: bloquea escalación de privilegios y elimina todas las capacidades POSIX del kernel.
