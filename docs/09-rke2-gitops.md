# Fase 9 — RKE2 y GitOps

## 1. Objetivo

La Fase 9 tiene como objetivo construir y validar una plataforma Kubernetes multinodo sobre Proxmox y establecer Git como fuente declarativa de estado para las cargas desplegadas mediante GitOps.

La fase incorpora:

- RKE2 multinodo.
- Control plane altamente disponible.
- etcd distribuido.
- Worker dedicado.
- CNI Canal.
- Validación funcional de Kubernetes.
- Flux CD.
- Argo CD.
- GitHub como fuente GitOps.
- Reconciliación automática del estado deseado.
- Comparación práctica entre Flux CD y Argo CD.

El objetivo no es únicamente instalar componentes, sino demostrar mediante pruebas reales que la infraestructura y las aplicaciones convergen hacia el estado declarado en Git.

## 2. Arquitectura

La red privada utilizada por la plataforma es 10.20.0.0/24.

Arquitectura Kubernetes:

GitHub
  |
  +-------------------+
  |                   |
Flux               Argo CD
  |                   |
  +---------+---------+
            |
     RKE2 Kubernetes
            |
  +---------+---------+---------+
  |                   |         |
rke2-cp01          rke2-cp02  rke2-cp03
10.20.0.11         10.20.0.12 10.20.0.13
control-plane      control-plane control-plane
etcd               etcd        etcd
            |
      rke2-worker01
       10.20.0.21
          worker

Todos los nodos utilizan Debian GNU/Linux 13 (trixie).

## 3. Plataforma RKE2

### 3.1 Versión

RKE2: v1.36.4+rke2r1

Container runtime: containerd 2.3.4-k3s1.36

Kernel: 6.12.107+deb13-cloud-amd64

La versión de RKE2 está fijada explícitamente para garantizar la reproducibilidad del despliegue.

### 3.2 Nodos

| Nodo | Dirección | Función |
|---|---|---|
| rke2-cp01 | 10.20.0.11 | Control plane + etcd |
| rke2-cp02 | 10.20.0.12 | Control plane + etcd |
| rke2-cp03 | 10.20.0.13 | Control plane + etcd |
| rke2-worker01 | 10.20.0.21 | Worker |

El clúster dispone de tres miembros etcd y tres nodos de control, proporcionando alta disponibilidad del plano de control y del almacenamiento distribuido de estado de Kubernetes.

## 4. Automatización con Ansible

La instalación de RKE2 está automatizada mediante Ansible.

Inventario:

ansible/inventory/rke2.ini

Variables:

ansible/inventory/group_vars/rke2_cluster.yml

Configuración principal:

rke2_version: "v1.36.4+rke2r1"
rke2_registration_address: "10.20.0.11"

Playbooks:

ansible/playbooks/rke2-bootstrap.yml
ansible/playbooks/rke2-servers.yml
ansible/playbooks/rke2-agents.yml

El proceso permite:

1. Inicializar el primer servidor RKE2.
2. Obtener automáticamente el node-token desde rke2-cp01.
3. Incorporar rke2-cp02 y rke2-cp03.
4. Incorporar workers.
5. Instalar y habilitar rke2-server o rke2-agent.
6. Mantener la versión de RKE2 fijada.
7. Reejecutar los playbooks de forma idempotente.

La idempotencia fue validada mediante una segunda ejecución de los playbooks sin producir cambios no deseados.

Commit de la automatización:

5fc9a48 feat: automate RKE2 cluster deployment

## 5. Validación del clúster

Estado validado:

rke2-cp01      Ready
rke2-cp02      Ready
rke2-cp03      Ready
rke2-worker01  Ready

Todos los nodos ejecutan:

v1.36.4+rke2r1

El CNI Canal fue validado:

rke2-canal  2/2 Running

Esto confirma que el clúster dispone de una red Kubernetes funcional.

## 6. Validación funcional de Kubernetes

Se creó un workload específico:

kubernetes/validation/functional-test.yml

Configuración:

namespace: lab-validation
deployment: echo-server
replicas: 2
service: echo-server

Se utilizó un cliente temporal basado en:

curlimages/curl

### DNS interno

Se comprobó:

echo-server.lab-validation.svc.cluster.local -> 10.43.100.168

### Comunicación HTTP

Se validó:

curl http://echo-server

con respuesta:

rke2-lab-ok

También se validó el FQDN completo:

curl http://echo-server.lab-validation.svc.cluster.local

con respuesta:

rke2-lab-ok

La prueba demuestra:

- scheduling de workloads;
- funcionamiento del Deployment;
- réplicas;
- Service ClusterIP;
- DNS interno;
- comunicación entre pods y servicios;
- conectividad HTTP.

Commit:

1ea328a test: add Kubernetes functional validation workload

## 7. Flux CD

Flux CD fue instalado y configurado mediante bootstrap contra GitHub.

Versión:

Flux v2.9.5

Repositorio:

jgonzalezguevara/proxmox-rke2-platform

Branch:

main

Ruta GitOps:

clusters/proxmox-lab

Namespace:

flux-system

### 7.1 Estructura

Bootstrap:

clusters/proxmox-lab/flux-system/
  gotk-components.yaml
  gotk-sync.yaml
  kustomization.yaml

Kustomization principal:

clusters/proxmox-lab/kustomization.yaml

Recursos:

resources:
  - flux-system
  - apps/flux-demo

Aplicación:

clusters/proxmox-lab/apps/flux-demo/
  namespace.yaml
  deployment.yaml
  service.yaml
  kustomization.yaml

### 7.2 Aplicación Flux

namespace: flux-demo
deployment: flux-demo
service: flux-demo
image: hashicorp/http-echo:1.0

Respuesta:

deployed-by-flux

La aplicación demuestra que Flux puede tomar el estado declarado desde Git y aplicarlo automáticamente al clúster.

## 8. Argo CD

Argo CD también fue desplegado en el mismo clúster para realizar una comparación práctica con Flux CD.

Namespace:

argocd

CRDs principales:

applications.argoproj.io
applicationsets.argoproj.io
appprojects.argoproj.io

Durante la instalación se produjo un problema al utilizar client-side apply con el manifest oficial debido al tamaño de una anotación del CRD applicationsets.argoproj.io.

Se resolvió mediante:

kubectl apply --server-side --force-conflicts

Los componentes principales de Argo CD quedaron posteriormente en estado Running.

### 8.1 Aplicación Argo CD

Application:

argocd-demo

Manifest:

argocd/applications/argocd-demo.yaml

Aplicación:

argocd/apps/argocd-demo/
  deployment.yaml
  service.yaml
  kustomization.yaml

Configuración:

source:
https://github.com/jgonzalezguevara/proxmox-rke2-platform.git

targetRevision:
main

path:
argocd/apps/argocd-demo

destination:
https://kubernetes.default.svc

namespace:
argocd-demo

Sincronización:

automated
prune: true
selfHeal: true

Estado validado:

Synced
Healthy

Respuesta:

deployed-by-argocd

## 9. Estructura GitOps

El repositorio contiene actualmente dos modelos GitOps independientes:

clusters/
  proxmox-lab/
    flux-system/
      gotk-components.yaml
      gotk-sync.yaml
      kustomization.yaml
    apps/
      flux-demo/
        namespace.yaml
        deployment.yaml
        service.yaml
        kustomization.yaml
    kustomization.yaml

argocd/
  applications/
    argocd-demo.yaml
  apps/
    argocd-demo/
      deployment.yaml
      service.yaml
      kustomization.yaml

Cada herramienta gestiona una aplicación independiente, evitando que Flux CD y Argo CD compitan por los mismos recursos Kubernetes.

## 10. Prueba real de reconciliación

La validación principal de la fase consistió en realizar un cambio exclusivamente mediante Git.

No se utilizó kubectl apply para actualizar ninguna de las dos aplicaciones.

Se modificó el número de réplicas:

Flux:
2 -> 3

Argo CD:
2 -> 3

El cambio se publicó mediante:

5f4cdc6 test: compare Flux and Argo CD reconciliation

Ambos controladores detectaron el nuevo estado declarado en Git y convergieron automáticamente.

### Flux

Flux detectó:

main@sha1:5f4cdc6e

La aplicación quedó en:

flux-demo
3 replicas

### Argo CD

Argo CD detectó:

5f4cdc6ecd4c088b821e90bcb45667bcdf446dcc

La aplicación quedó en:

argocd-demo
3 replicas

Ambos estados permanecieron estables durante varios minutos.

La prueba demuestra que Git fue utilizado realmente como fuente de verdad para ambas aplicaciones.

## 11. Comparación práctica: Flux CD vs Argo CD

| Aspecto | Flux CD | Argo CD |
|---|---|---|
| Fuente Git | GitHub | GitHub |
| Reconciliación automática | Sí | Sí |
| Detección de cambios Git | Sí | Sí |
| Estado observado | Reconciliado | Synced / Healthy |
| Auto-healing | Reconciliación declarativa | selfHeal: true |
| Prune | Declarativo mediante configuración | prune: true |
| Modelo de gestión | Recursos Kubernetes y controladores Flux | Modelo centrado en Applications |
| Interfaz web | No es el elemento central | Uno de sus puntos fuertes |
| Integración Kubernetes | Muy nativa | Muy completa |
| Modelo de aplicación | Kustomizations / recursos Flux | Application / recursos Argo |
| Observabilidad | CLI y recursos Kubernetes | CLI, UI y recursos Kubernetes |

La prueba no permite concluir que una herramienta sea universalmente mejor que la otra. Sí demuestra que ambas son capaces de implementar un modelo GitOps funcional y autónomo.

## 12. Consideraciones arquitectónicas

La coexistencia de Flux CD y Argo CD en esta plataforma tiene una finalidad de evaluación comparativa.

No se recomienda desplegar simultáneamente dos controladores GitOps sobre los mismos recursos productivos sin una razón concreta, ya que ambos podrían intentar reconciliar el mismo estado y generar conflictos.

En esta plataforma cada herramienta dispone de una aplicación independiente:

Flux CD -> flux-demo
Argo CD -> argocd-demo

Esto permite estudiar ambas implementaciones sin introducir competición por los mismos recursos.

La fase también evidencia la separación de responsabilidades entre IaC, configuración y GitOps:

OpenTofu
  |
  +--> infraestructura Proxmox

Ansible
  |
  +--> configuración y bootstrap RKE2

Git
  |
  +--> estado deseado de aplicaciones Kubernetes

Flux / Argo CD
  |
  +--> reconciliación continua

Cada herramienta tiene una responsabilidad distinta dentro de la plataforma.

## 13. Resultado de la fase

La Fase 9 queda funcionalmente validada.

Se ha demostrado:

1. Clúster RKE2 multinodo.
2. Tres nodos de control.
3. Tres miembros etcd.
4. Worker dedicado.
5. CNI Canal operativo.
6. Kubernetes funcional.
7. DNS interno.
8. Services ClusterIP.
9. Flux CD operativo.
10. Argo CD operativo.
11. GitHub como fuente GitOps.
12. Reconciliación automática.
13. Detección de cambios mediante Git.
14. Convergencia automática del estado deseado.
15. Comparación práctica de Flux CD y Argo CD.

La evidencia principal es que un cambio realizado mediante Git, sin ejecutar kubectl apply sobre las aplicaciones, provocó que ambos sistemas detectaran el nuevo estado y actualizaran automáticamente sus respectivos workloads.

## 14. Conclusión técnica

La plataforma construida en esta fase demuestra un flujo completo desde la infraestructura hasta la gestión declarativa de aplicaciones:

Proxmox
  |
OpenTofu
  |
VMs
  |
Ansible
  |
RKE2
  |
Kubernetes
  |
GitHub
  |
+----------------+
|                |
Flux           Argo CD
|                |
+-------+--------+
        |
   Kubernetes
   workloads

La plataforma deja de ser únicamente una colección de máquinas virtuales y pasa a representar una plataforma reproducible con separación de responsabilidades:

- OpenTofu gestiona infraestructura.
- Ansible automatiza la configuración y bootstrap.
- RKE2 proporciona Kubernetes.
- Git mantiene el estado declarativo.
- Flux CD y Argo CD realizan reconciliación continua.

La experiencia práctica obtenida permite además comparar dos implementaciones reales de GitOps sobre la misma plataforma y bajo las mismas condiciones.

## Estado

FASE 9 — COMPLETADA Y VALIDADA
