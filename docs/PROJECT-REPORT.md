# Private Kubernetes Platform on Proxmox — Informe técnico completo

## 1. Resumen ejecutivo

`proxmox-rke2-platform` es una plataforma de infraestructura reproducible sobre Proxmox VE que recorre de extremo a extremo el ciclo de vida de una pequeña plataforma Kubernetes gestionada como código.

El proyecto evolucionó desde una fase inicial de aprovisionamiento de máquinas virtuales con OpenTofu hasta una plataforma RKE2 multi-nodo que integra:

- Infrastructure as Code con OpenTofu.
- Módulo reutilizable para máquinas virtuales Proxmox.
- Cloud-init y QEMU Guest Agent.
- Red privada, routing y NAT.
- Automatización Linux mediante Ansible.
- RKE2 con tres control planes y un worker.
- Validación funcional de Kubernetes.
- GitOps con Flux CD.
- Comparación práctica con Argo CD.
- Almacenamiento dinámico local.
- Prometheus y Grafana gestionados declarativamente.
- Dimensionamiento según recursos reales.
- Integración con el hardening de RKE2.
- Gestión segura y rotación del token de registro.
- Documentación y validación de cada fase.

El objetivo no es acumular tecnologías, sino construir una plataforma coherente, reproducible, observable y técnicamente defendible.

---

## 2. Objetivos

Los objetivos principales son:

1. Gestionar infraestructura Proxmox mediante Infrastructure as Code.
2. Reducir al mínimo la configuración manual de máquinas virtuales.
3. Construir componentes reutilizables con OpenTofu.
4. Automatizar preparación Linux mediante Ansible.
5. Desplegar un clúster RKE2 reproducible.
6. Validar Kubernetes mediante pruebas funcionales reales.
7. Adoptar GitOps como modelo operativo.
8. Comparar Flux CD y Argo CD sobre workloads reales.
9. Añadir almacenamiento persistente adecuado al tamaño dla plataforma.
10. Incorporar observabilidad sin sobredimensionar el entorno.
11. Mantener el hardening de RKE2.
12. Mantener secretos, credenciales y estados locales fuera de Git.
13. Documentar decisiones, limitaciones y resultados.

---

## 3. Arquitectura general

```text
GitHub
  |
  +-- OpenTofu
  |     |
  |     +-- Proxmox VE API
  |            |
  |            +-- Debian 13 cloud-init template
  |                    |
  |                    +-- rke2-cp01
  |                    +-- rke2-cp02
  |                    +-- rke2-cp03
  |                    +-- rke2-worker01
  |
  +-- Ansible
  |     |
  |     +-- Linux prerequisites
  |     +-- RKE2 bootstrap
  |     +-- RKE2 server join
  |     +-- RKE2 agent join
  |
  +-- Flux CD
  |     |
  |     +-- flux-demo
  |     +-- Local Path Provisioner
  |     +-- kube-prometheus-stack
  |
  +-- Argo CD
        |
        +-- argocd-demo
```

Separación conceptual:

```text
Proxmox VE
    ↓
OpenTofu
    ↓
VMs + red + cloud-init
    ↓
Ansible
    ↓
Linux + RKE2
    ↓
Kubernetes
    ↓
GitOps
    ↓
Servicios de plataforma
    ↓
Observabilidad
```

Cada herramienta mantiene una responsabilidad concreta:

- OpenTofu aprovisiona infraestructura.
- cloud-init realiza configuración inicial de las VMs.
- Ansible prepara Linux e instala RKE2.
- Kubernetes ejecuta workloads.
- Flux administra infraestructura y aplicaciones declarativas.
- Argo CD se utiliza como implementación GitOps comparativa.
- Prometheus y Grafana proporcionan observabilidad.

---

## 4. Infraestructura base

### 4.1 Proxmox VE

Versión validada:

```text
Proxmox VE 9.2.11
```

Provider utilizado:

```text
bpg/proxmox 0.112.0
```

### 4.2 OpenTofu

Versión:

```text
OpenTofu 1.12.6
```

Restricción del proyecto:

```text
>= 1.12.0
```

### 4.3 Provider Proxmox

Configuración actual:

```text
https://127.0.0.1:8006/
```

con:

```text
insecure = true
```

Esta decisión pertenece exclusivamente a la plataforma. OpenTofu se ejecuta desde el propio host Proxmox y accede a la API local.

No debe interpretarse como patrón recomendado de producción. En producción sería preferible:

- validar TLS correctamente;
- usar certificados confiables;
- ejecutar IaC desde un nodo de automatización separado;
- gestionar credenciales mediante un secret store;
- minimizar el acoplamiento entre host de virtualización y sistema de automatización.

---

## 5. Red dla plataforma

El entorno utiliza dos bridges de Proxmox.

### 5.1 `vmbr0`

Red de gestión y salida externa.

```text
Proxmox: 192.168.137.2/24
Gateway: 192.168.137.1
```

El gateway corresponde al entorno Windows ICS utilizado por la plataforma.

### 5.2 `vmbr1`

Red privada dedicada a RKE2:

```text
10.20.0.0/24
```

Dirección del host Proxmox:

```text
10.20.0.1
```

No existe una interfaz física asociada a `vmbr1`.

### 5.3 Routing

IPv4 forwarding se mantiene habilitado de forma persistente mediante:

```text
/etc/sysctl.d/99-proxmox-lab-routing.conf
```

con:

```text
net.ipv4.ip_forward=1
```

### 5.4 NAT

La red privada sale al exterior mediante NAT sobre `vmbr0`.

```text
10.20.0.0/24
      ↓
  MASQUERADE
      ↓
    vmbr0
      ↓
red externa
```

La persistencia de bridge, forwarding, NAT y conectividad fue validada mediante un reinicio completo del host Proxmox.

---

## 6. Template Debian y cloud-init

Las VMs parten de un template Debian 13:

```text
VMID 9000
```

El template incorpora `qemu-guest-agent`.

Cloud-init configura:

- usuario `automation`;
- clave SSH pública;
- IPv4;
- gateway;
- DNS;
- dominio de búsqueda.

QEMU Guest Agent permite además recuperar desde Proxmox información como:

- direcciones IPv4;
- direcciones MAC;
- estado del guest.

---

## 7. OpenTofu y módulo reutilizable

El módulo principal reside en:

```text
modules/proxmox-vm/
```

Encapsula la creación de máquinas virtuales Proxmox.

Parámetros principales:

- `name`;
- `node_name`;
- `vm_id`;
- `clone_vm_id`;
- `cpu_cores`;
- `memory_mb`;
- `disk_size_gb`;
- `datastore_id`;
- `bridge`;
- `username`;
- `ssh_public_key`;
- `ipv4_address`;
- `ipv4_gateway`;
- `dns_servers`;
- `dns_domain`;
- `started`.

Esto evita duplicar bloques completos de recursos para cada nodo.

### 7.1 Clonación

Las VMs se generan mediante clonación completa:

```hcl
clone {
  vm_id = var.clone_vm_id
  full  = true
}
```

### 7.2 CPU

Se utiliza:

```text
type = host
```

para exponer las capacidades reales del procesador al guest.

### 7.3 Disco

El disco raíz utiliza:

```text
scsi0
```

sobre:

```text
local-lvm
```

### 7.4 QEMU Guest Agent

El módulo habilita:

```text
agent.enabled = true
```

y espera una dirección IPv4 reportada por el guest.

### 7.5 Outputs

El módulo expone:

- VM ID;
- direcciones IPv4;
- direcciones MAC.

---

## 8. Topología RKE2

| Nodo | Rol | IP | vCPU | RAM | Disco |
|---|---|---:|---:|---:|---:|
| `rke2-cp01` | control-plane + etcd | `10.20.0.11` | 2 | 4 GiB | 30 GiB |
| `rke2-cp02` | control-plane + etcd | `10.20.0.12` | 2 | 4 GiB | 30 GiB |
| `rke2-cp03` | control-plane + etcd | `10.20.0.13` | 2 | 4 GiB | 30 GiB |
| `rke2-worker01` | worker | `10.20.0.21` | 4 | 6 GiB | 50 GiB |

Sistema operativo:

```text
Debian GNU/Linux 13 (trixie)
```

Kernel observado durante la validación final:

```text
6.12.107+deb13-cloud-amd64
```

RKE2:

```text
v1.36.4+rke2r1
```

Runtime:

```text
containerd 2.3.4-k3s1.36
```

---

## 9. Ansible

La automatización reside en:

```text
ansible/
```

Estructura:

```text
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.ini
│   ├── rke2.ini
│   └── group_vars/
│       └── rke2_cluster.yml
└── playbooks/
    ├── baseline.yml
    ├── rke2-prereqs.yml
    ├── rke2-bootstrap.yml
    ├── rke2-servers.yml
    ├── rke2-agents.yml
    └── validate.yml
```

### 9.1 Baseline Linux

`baseline.yml` automatiza:

- actualización de metadata APT;
- instalación de paquetes base;
- configuración de timezone.

Esta fase permitió validar comunicación SSH, privilege escalation y repetibilidad antes de desplegar Kubernetes.

### 9.2 Preparación para RKE2

`rke2-prereqs.yml` prepara todos los nodos:

- paquetes necesarios;
- módulos `overlay` y `br_netfilter`;
- carga persistente de módulos;
- sysctl requeridos por Kubernetes;
- desactivación inmediata de swap;
- eliminación persistente de swap de `/etc/fstab`.

Se mantiene una separación clara entre preparación del sistema operativo e instalación de Kubernetes.

---

## 10. Instalación RKE2

La versión está fijada explícitamente:

```text
v1.36.4+rke2r1
```

Esto aporta reproducibilidad, control de cambios y capacidad de reconstrucción.

### 10.1 Bootstrap inicial

`rke2-cp01` se inicializa mediante:

```text
ansible/playbooks/rke2-bootstrap.yml
```

El playbook:

1. crea el directorio de configuración;
2. genera la configuración inicial;
3. comprueba si RKE2 ya está instalado;
4. descarga el instalador;
5. instala RKE2 server;
6. habilita e inicia el servicio.

### 10.2 Servidores adicionales

`rke2-cp02` y `rke2-cp03` se incorporan mediante:

```text
ansible/playbooks/rke2-servers.yml
```

El playbook:

1. obtiene el token desde `rke2-cp01`;
2. lo mantiene como dato de ejecución;
3. configura los nodos adicionales;
4. instala la versión fijada;
5. activa RKE2 server.

El token no se almacena de forma estática en Git.

### 10.3 Worker

`rke2-worker01` se incorpora mediante:

```text
ansible/playbooks/rke2-agents.yml
```

La estrategia es equivalente:

1. lectura dinámica del token desde el primer servidor;
2. transferencia durante la ejecución;
3. generación de configuración;
4. instalación del agente;
5. activación de `rke2-agent`.

---

## 11. Estado final RKE2

La validación final confirmó:

```text
rke2-cp01       Ready    control-plane,etcd
rke2-cp02       Ready    control-plane,etcd
rke2-cp03       Ready    control-plane,etcd
rke2-worker01   Ready
```

Los cuatro nodos ejecutaban:

```text
v1.36.4+rke2r1
```

### 11.1 Alta disponibilidad del control plane

Los tres control planes ejecutan:

- kube-apiserver;
- kube-controller-manager;
- kube-scheduler;
- etcd.

Esto proporciona quorum etcd y un control plane multi-nodo real.

Debe distinguirse entre HA lógica del clúster y HA física completa: todas las VMs siguen dependiendo del mismo host Proxmox físico.

---

## 12. CNI y servicios de sistema

RKE2 utiliza Canal como CNI.

Durante la validación final estaban operativos:

- Canal;
- CoreDNS;
- Metrics Server;
- Traefik;
- snapshot controller;
- kube-proxy;
- cloud-controller-manager;
- etcd;
- kube-apiserver;
- kube-controller-manager;
- kube-scheduler.

---

## 13. Validación funcional Kubernetes

El proyecto no considera suficiente validar únicamente `kubectl get nodes`.

Se añadió:

```text
kubernetes/validation/functional-test.yml
```

La validación comprobó:

- scheduling;
- ejecución de pods;
- DNS interno;
- comunicación entre workloads;
- conectividad HTTP.

El objetivo fue distinguir entre “API Kubernetes disponible” y “clúster realmente funcional para ejecutar workloads”.

---

## 14. GitOps

La plataforma utiliza dos implementaciones GitOps:

- Flux CD;
- Argo CD.

No se utilizan para competir sobre los mismos recursos. La comparación se realizó mediante workloads separados.

---

## 15. Flux CD

Flux se encuentra bootstrappeado contra:

```text
ssh://git@github.com/jgonzalezguevara/proxmox-rke2-platform
```

Branch:

```text
main
```

Path:

```text
./clusters/proxmox-lab
```

El `GitRepository` consulta Git cada minuto y la Kustomization utiliza:

```text
prune: true
```

### 15.1 Estructura Flux

```text
clusters/proxmox-lab/
├── flux-system/
├── infrastructure/
└── apps/
    └── flux-demo/
```

Infraestructura:

```text
clusters/proxmox-lab/infrastructure/
├── local-path-provisioner/
└── monitoring/
```

Esto separa aplicaciones e infraestructura de plataforma.

### 15.2 Flux demo

La aplicación `flux-demo` permitió verificar reconciliación real desde Git y no solo la presencia de los controladores.

---

## 16. Argo CD

Argo CD se instaló para comparar su modelo operativo con Flux.

Aplicación:

```text
argocd-demo
```

Manifiesto:

```text
argocd/applications/argocd-demo.yaml
```

Repositorio:

```text
https://github.com/jgonzalezguevara/proxmox-rke2-platform.git
```

Path:

```text
argocd/apps/argocd-demo
```

Namespace:

```text
argocd-demo
```

La Application utiliza:

```yaml
automated:
  prune: true
  selfHeal: true
```

y:

```yaml
CreateNamespace=true
```

Se validaron sincronización automática, autocorrección de drift y pruning.

---

## 17. Comparación Flux vs Argo CD

### Flux

Encaja especialmente bien con:

- Kustomize;
- Helm;
- recursos Kubernetes declarativos;
- composición GitOps orientada a plataforma.

### Argo CD

Destaca por:

- modelo centrado en `Application`;
- visibilidad clara del estado de sincronización;
- experiencia gráfica;
- enfoque application-centric.

### Decisión

Los componentes de infraestructura posteriores quedaron bajo un único propietario:

```text
Flux
```

Argo CD se conserva como implementación comparativa independiente.

Esto evita reconciliación concurrente sobre los mismos recursos.

---

## 18. Almacenamiento dinámico

El clúster no disponía inicialmente de StorageClass.

Se evaluó el contexto real:

- un único worker;
- recursos limitados;
- ausencia de necesidad de almacenamiento distribuido;
- imposibilidad de aportar HA real con un solo worker.

Por ello no se introdujeron Longhorn, Ceph u otras soluciones distribuidas.

---

## 19. Local Path Provisioner

Se eligió:

```text
Rancher Local Path Provisioner v0.0.37
```

Gestionado mediante Flux.

StorageClass:

```text
local-path
```

Provisioner:

```text
rancher.io/local-path
```

Reclaim policy:

```text
Delete
```

Binding mode:

```text
WaitForFirstConsumer
```

### 19.1 Placement

El provisioner se restringió a:

```text
rke2-worker01
```

Ruta local:

```text
/opt/local-path-provisioner
```

Esto evita colocar persistencia de aplicaciones sobre los control planes.

### 19.2 Validación funcional

Se comprobó el ciclo completo:

1. creación de PVC;
2. binding dinámico;
3. scheduling sobre worker;
4. escritura;
5. lectura;
6. creación de la ruta en el host;
7. eliminación del PVC;
8. eliminación del PV;
9. eliminación del path asociado.

Resultado:

```text
local-path-ok
```

### 19.3 Limitación

El almacenamiento es worker-local y no HA.

Si se pierde permanentemente el worker, se pierde también el almacenamiento local asociado.

Esta limitación es explícita e intencionada.

---

## 20. Observabilidad

La plataforma utiliza:

```text
kube-prometheus-stack 89.2.4
```

gestionado mediante Flux Helm Controller.

Componentes principales:

- Prometheus Operator;
- Prometheus;
- Grafana;
- kube-state-metrics;
- node-exporter.

Alertmanager permanece deshabilitado en esta fase.

---

## 21. Placement de observabilidad

Los componentes pesados se ejecutan sobre:

```text
rke2-worker01
```

mediante `nodeSelector`.

Se aplica a:

- Prometheus;
- Grafana;
- kube-state-metrics;
- Prometheus Operator.

Node Exporter se ejecuta en todos los nodos.

---

## 22. Prometheus

Configuración principal:

```text
replicas: 1
retention: 3d
retentionSize: 6GB
```

Recursos:

```text
requests:
  cpu: 150m
  memory: 512Mi

limits:
  memory: 1Gi
```

Persistencia:

```text
8 GiB
```

StorageClass:

```text
local-path
```

---

## 23. Grafana

Recursos:

```text
requests:
  cpu: 50m
  memory: 128Mi

limits:
  memory: 384Mi
```

Persistencia:

```text
2 GiB
```

StorageClass:

```text
local-path
```

No se expone mediante Ingress en esta fase.

### 23.1 Ajuste de memoria

El límite inicial era 256 MiB.

Durante mediciones reales Grafana consumió aproximadamente 253 MiB.

Aunque no hubo OOMKills ni reinicios, el margen era demasiado pequeño, por lo que se elevó el límite a:

```text
384 MiB
```

La decisión se basó en consumo real observado.

---

## 24. HelmRelease y timeout

La instalación inicial del stack superó el timeout por defecto debido a descargas lentas de imágenes.

Los pods finalmente arrancaron correctamente.

Se amplió el timeout de HelmRelease a:

```text
15 minutos
```

La corrección distinguió entre un fallo real del workload y una instalación que simplemente necesitaba más tiempo.

---

## 25. Validación de Prometheus

Se validaron directamente:

```text
/-/ready
/-/healthy
```

Resultado:

```text
Prometheus Server is Ready.
Prometheus Server is Healthy.
```

---

## 26. Validación de Grafana

La API:

```text
/api/health
```

respondió correctamente.

Se observó:

```text
database: ok
version: 13.2.1
```

---

## 27. Targets Prometheus y hardening RKE2

La primera instalación mostró como `DOWN`:

- kube-controller-manager;
- kube-scheduler;
- etcd.

La investigación confirmó que RKE2 mantenía esos endpoints vinculados a localhost:

```text
127.0.0.1:2381   etcd metrics
127.0.0.1:10257  kube-controller-manager
127.0.0.1:10259  kube-scheduler
```

Se decidió mantener el hardening de RKE2 y adaptar la observabilidad, en lugar de abrir interfaces sensibles únicamente para eliminar targets `DOWN`.

Se deshabilitaron en el chart:

- scraping de etcd;
- scraping de kube-controller-manager;
- scraping de kube-scheduler;
- reglas dependientes de esos endpoints.

Tras el cambio, todos los targets configurados quedaron saludables:

```text
apiserver
coredns
grafana
operator
prometheus
kube-state-metrics
kubelet
node-exporter
```

con:

```text
down=0
```

---

## 28. Consumo observado

Durante la fase de observabilidad se observaron aproximadamente:

```text
rke2-cp01       ~2.9 GiB
rke2-cp02       ~2.9 GiB
rke2-cp03       ~2.6 GiB
rke2-worker01   ~3.6 GiB
```

El entorno está deliberadamente ajustado a recursos modestos.

Esto obliga a priorizar arquitectura y dimensionamiento sobre el despliegue indiscriminado de herramientas.

---

## 29. Seguridad de secretos

El repositorio excluye explícitamente:

```text
.tofu/
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
crash.log
crash.*.log
```

La comprobación mediante `git ls-files` confirmó que:

- `.terraform/`;
- `terraform.tfstate`;
- `terraform.tfstate.backup`;
- `*.tfvars`;

no están versionados.

---

## 30. Estado OpenTofu y credenciales

Las credenciales Proxmox se mantienen fuera del repositorio.

Durante el desarrollo se validó repetidamente la idempotencia de OpenTofu.

En la comprobación final del 11 de septiembre de 2026 se intentó:

```text
tofu plan -detailed-exitcode
```

pero la shell no tenía cargadas credenciales de Proxmox.

Resultado:

```text
plan-exit-code=1
```

Causa:

```text
must provide either username and password, an API token, or a ticket
```

Esta ejecución:

- no detectó drift;
- no produjo cambios;
- no representa un fallo del estado de infraestructura;
- confirma que las credenciales no están embebidas en el código del provider.

La validación de idempotencia realizada durante las fases anteriores sigue siendo la referencia funcional.

---

## 31. Rotación del token RKE2

Durante una sesión de diagnóstico el token de registro del clúster apareció accidentalmente en salida interactiva.

Aunque nunca fue almacenado en Git, se trató como credencial comprometida.

### 31.1 Pre-check

Antes de rotar se verificó:

- cuatro nodos `Ready`;
- versión RKE2;
- disponibilidad de `rke2 token rotate`;
- permisos del token;
- ubicación de referencias;
- ausencia del secreto en Git.

### 31.2 Rotación

Se ejecutó:

```text
rke2 token rotate
```

sobre el primer servidor.

El nuevo token no se imprimió en la salida.

Para validar consistencia se utilizaron hashes parciales SHA-256.

### 31.3 Propagación

El nuevo token se actualizó en:

```text
rke2-cp02
rke2-cp03
rke2-worker01
```

Los tres mostraron el mismo hash del nuevo secreto.

### 31.4 Reinicio controlado

Los nodos se reiniciaron secuencialmente:

```text
rke2-cp02
   ↓
rke2-cp03
   ↓
rke2-cp01
   ↓
rke2-worker01
```

Después de cada servidor se comprobó que volvía a `Ready` antes de continuar.

### 31.5 Resultado final

Al finalizar:

```text
rke2-cp01       Ready
rke2-cp02       Ready
rke2-cp03       Ready
rke2-worker01   Ready
```

El servicio del worker estaba `active`.

La rotación se considera completada y validada.

---

## 32. Estado final de workloads

Tras las últimas operaciones de seguridad se verificaron operativos:

### RKE2

- etcd en los tres control planes;
- kube-apiserver;
- kube-controller-manager;
- kube-scheduler;
- kube-proxy;
- Canal;
- CoreDNS;
- Metrics Server;
- Traefik.

### GitOps

- Flux source-controller;
- Flux kustomize-controller;
- Flux helm-controller;
- Flux notification-controller;
- Argo CD application controller;
- Argo CD server;
- Argo CD repo server;
- Argo CD ApplicationSet controller;
- Argo CD notifications controller;
- Argo CD Dex;
- Redis.

### Storage

- Local Path Provisioner.

### Observabilidad

- Grafana;
- Prometheus;
- Prometheus Operator;
- kube-state-metrics;
- cuatro node-exporters.

---

## 33. Git como fuente de verdad

El repositorio contiene:

- OpenTofu;
- Ansible;
- manifiestos Kubernetes;
- Flux;
- Argo CD;
- almacenamiento;
- observabilidad;
- documentación.

No se versionan:

- secretos;
- tokens;
- estado local OpenTofu;
- credenciales Proxmox;
- artefactos generados localmente.

---

## 34. Historial técnico

Hitos principales:

```text
bc11625 feat: establish Proxmox OpenTofu lab baseline
6c20e39 refactor: add reusable Proxmox VM module
87982b8 feat: add idempotent Ansible Linux baseline
7048053 feat: support configurable VM IPv4 settings
b4b4bac feat: add private lab network and configurable DNS
f146829 feat: provision RKE2 lab nodes
1f06791 feat: prepare RKE2 nodes with Ansible
5fc9a48 feat: automate RKE2 cluster deployment
1ea328a test: add Kubernetes functional validation workload
b43c406 Add Flux v2.9.5 component manifests
8bfa867 Add Flux sync manifests
e2ac7a3 feat: deploy demo application with Flux GitOps
f7a1ec0 fix: structure Flux cluster kustomization
4542f78 feat: add Argo CD demo application
5f4cdc6 test: compare Flux and Argo CD reconciliation
47f076f docs: document RKE2 and GitOps phase
50c4930 feat: add worker-local dynamic storage provisioner
7625cb8 feat: add GitOps observability stack
3118406 fix: increase observability Helm timeout
af1d20e fix: align monitoring with RKE2 hardened endpoints
99ee402 fix: increase Grafana memory headroom
0814fbc docs: document observability phase
```

El historial refleja un ciclo incremental:

```text
construir
→ validar
→ observar
→ corregir
→ documentar
```

---

## 35. Decisiones arquitectónicas principales

### IaC antes que configuración manual

La infraestructura se define desde código siempre que resulta razonable.

### Componentes reutilizables

La VM Proxmox se convirtió en módulo antes de escalar el número de nodos.

### Direccionamiento predecible

Los nodos RKE2 utilizan IPs fijas sobre la red privada.

### Separación de capas

OpenTofu no instala Kubernetes.

Ansible no aprovisiona VMs.

Flux no configura el sistema operativo.

Cada herramienta tiene una responsabilidad concreta.

### Versiones controladas

RKE2 y kube-prometheus-stack se fijan explícitamente.

### Secretos fuera de Git

Los tokens se obtienen durante ejecución o desde mecanismos externos.

### GitOps con propietario único

Flux administra los componentes de plataforma posteriores.

Argo CD se mantiene como comparación independiente.

### Storage honesto

Un único worker no se presenta como almacenamiento HA.

### Observabilidad dimensionada

Prometheus y Grafana se ajustan al hardware disponible.

### Seguridad antes que dashboards

No se debilita el hardening de RKE2 simplemente para eliminar targets `DOWN`.

---

## 36. Elementos deliberadamente no implementados

La plataforma no pretende incluir todas las tecnologías posibles.

No se ha añadido:

- almacenamiento distribuido HA;
- múltiples workers;
- balanceador externo dedicado para la API;
- VIP de control plane;
- Ingress público para Grafana;
- Alertmanager productivo;
- almacenamiento remoto para Prometheus;
- external secrets;
- Vault;
- NetworkPolicies avanzadas;
- backup remoto de etcd;
- disaster recovery entre varios hosts físicos;
- CI de infraestructura;
- múltiples entornos;
- autoscaling.

Estas ausencias representan posibles evoluciones, no carencias ocultas.

---

## 37. Limitaciones

### Único hipervisor físico

Los control planes son HA a nivel Kubernetes/etcd, pero comparten dominio de fallo físico.

### Un único worker

No existe HA real para workloads dependientes del worker.

### Storage local

Los PVC dependen de `rke2-worker01`.

### Recursos limitados

Los control planes disponen de 4 GiB y el worker de 6 GiB.

### API Proxmox local con TLS no verificado

Aceptable para el contexto aislado dla plataforma, no patrón de producción.

### Credenciales OpenTofu externas

Deben cargarse antes de ejecutar operaciones contra Proxmox.

---

## 38. Qué demuestra el proyecto

### Infrastructure as Code

- OpenTofu;
- providers;
- módulos;
- state;
- recursos parametrizados;
- outputs;
- cloud-init.

### Virtualización

- Proxmox VE;
- templates;
- clonación;
- bridges;
- QEMU Guest Agent;
- NAT;
- routing.

### Automatización

- Ansible;
- inventories;
- variables;
- privilege escalation;
- playbooks;
- instalación reproducible.

### Linux

- networking;
- systemd;
- kernel modules;
- sysctl;
- swap;
- SSH;
- paquetes.

### Kubernetes

- RKE2;
- control plane;
- etcd;
- worker;
- CNI;
- Services;
- DNS;
- workloads;
- persistent volumes;
- StorageClasses.

### GitOps

- Flux CD;
- Argo CD;
- Kustomize;
- HelmRelease;
- pruning;
- self-healing;
- reconciliación.

### Observabilidad

- Prometheus;
- Grafana;
- kube-state-metrics;
- node-exporter;
- sizing;
- persistence;
- troubleshooting de targets.

### Seguridad

- secretos fuera de Git;
- hardening de RKE2;
- rotación de token;
- reinicio secuencial;
- validación post-cambio.

### Arquitectura

- separación de responsabilidades;
- decisiones explícitas;
- reconocimiento de limitaciones;
- evitar complejidad artificial;
- validación antes de expansión.

---

## 39. Estructura principal del repositorio

```text
proxmox-rke2-platform/
├── ansible/
│   ├── inventory/
│   └── playbooks/
├── argocd/
│   ├── applications/
│   └── apps/
├── clusters/
│   └── proxmox-lab/
│       ├── apps/
│       ├── flux-system/
│       └── infrastructure/
│           ├── local-path-provisioner/
│           └── monitoring/
├── docs/
│   ├── 09-rke2-gitops.md
│   ├── 10-observability.md
│   └── PROJECT-REPORT.md
├── kubernetes/
│   └── validation/
├── modules/
│   └── proxmox-vm/
├── data.tf
├── provider.tf
├── rke2.tf
├── versions.tf
├── vm.tf
└── README.md
```

---

## 40. Documentación adicional

Documentos específicos de las fases más extensas:

```text
docs/09-rke2-gitops.md
docs/10-observability.md
```

Este informe no los sustituye: proporciona una visión transversal de todo el proyecto.

---

## 41. Estado final

| Área | Estado |
|---|---|
| Proxmox / OpenTofu | Implementado |
| Módulo reutilizable VM | Implementado |
| Red privada y NAT | Validado |
| Cloud-init | Validado |
| Automatización Ansible | Validada |
| RKE2 | 4/4 nodos Ready |
| etcd | 3 miembros operativos |
| Kubernetes funcional | Validado |
| Flux CD | Operativo |
| Argo CD | Operativo |
| Reconciliación GitOps | Validada |
| Local Path Provisioner | Operativo |
| Ciclo de vida PVC | Validado |
| Prometheus | Ready / Healthy |
| Grafana | Healthy |
| Targets configurados Prometheus | UP |
| Persistencia Prometheus/Grafana | Operativa |
| Rotación token RKE2 | Completada y validada |
| Secretos versionados | No detectados |

---

## 42. Conclusión

`proxmox-rke2-platform` evolucionó desde un ejercicio de creación de máquinas virtuales hasta una plataforma reproducible que recorre las capas fundamentales de una infraestructura moderna:

```text
virtualización
→ IaC
→ automatización
→ Linux
→ Kubernetes
→ GitOps
→ almacenamiento
→ observabilidad
→ seguridad
```

El valor principal del proyecto no está en la cantidad de tecnologías instaladas, sino en cómo se incorporaron.

Cada fase implicó:

- observar el estado real;
- identificar la siguiente necesidad;
- implementar una solución proporcionada;
- validar funcionalmente el resultado;
- corregir problemas reales;
- documentar decisiones.

También se evitaron patrones engañosos:

- presentar storage local como HA;
- abrir endpoints endurecidos solo para satisfacer Prometheus;
- introducir componentes distribuidos sin recursos suficientes;
- guardar tokens o credenciales en Git;
- confundir una carga de validación GitOps con propiedad compartida de recursos.

El resultado es una plataforma de alcance controlado, pero representativo de tareas reales de Platform Engineering e Infrastructure Engineering:

- diseñar;
- automatizar;
- operar;
- diagnosticar;
- asegurar;
- documentar.

## Estado del proyecto

**PLATAFORMA CONSTRUIDA, OPERATIVA Y VALIDADA.**

Última validación operativa global:

**11 de septiembre de 2026.**
