# Private Kubernetes Platform on Proxmox

Plataforma Kubernetes privada y reproducible sobre Proxmox VE, construida con OpenTofu, Ansible, RKE2, Rancher, Flux CD, Argo CD y kube-prometheus-stack.

El proyecto cubre el ciclo completo:

```text
Proxmox VE
    ↓
OpenTofu
    ↓
VMs + cloud-init + red privada
    ↓
Ansible
    ↓
RKE2
    ↓
Kubernetes
    ↓
GitOps
    ↓
Storage + Observabilidad
```

## Estado

**Plataforma construida, operativa y validada.**

Última validación global: **11 de septiembre de 2026**.

### Componentes principales

| Capa | Tecnología | Estado |
|---|---|---|
| Virtualización | Proxmox VE 9.2.11 | Operativa |
| IaC | OpenTofu 1.12.6 | Implementado |
| Provider | `bpg/proxmox` 0.112.0 | Implementado |
| Configuración | cloud-init | Validada |
| Automatización | Ansible | Validada |
| Kubernetes | RKE2 v1.36.4+rke2r1 | 4/4 nodos Ready |
| CNI | Canal | Operativo |
| GitOps | Flux CD | Operativo |
| GitOps comparativo | Argo CD | Operativo |
| Storage | Rancher Local Path Provisioner | Operativo |
| Monitoring | Prometheus | Ready / Healthy |
| Dashboards | Grafana | Healthy |

## Topología RKE2

| Nodo | Rol | IP | vCPU | RAM | Disco |
|---|---|---:|---:|---:|---:|
| `rke2-cp01` | control-plane + etcd | `10.20.0.11` | 2 | 4 GiB | 30 GiB |
| `rke2-cp02` | control-plane + etcd | `10.20.0.12` | 2 | 4 GiB | 30 GiB |
| `rke2-cp03` | control-plane + etcd | `10.20.0.13` | 2 | 4 GiB | 30 GiB |
| `rke2-worker01` | worker | `10.20.0.21` | 4 | 6 GiB | 50 GiB |

Sistema operativo: Debian 13.

## Red

La plataforma utiliza dos bridges:

- `vmbr0`: gestión y salida externa.
- `vmbr1`: red privada `10.20.0.0/24` para RKE2.

El host Proxmox proporciona routing y NAT para la red privada.

La persistencia completa de red, forwarding, NAT y conectividad fue validada mediante reinicio del host.

## Infrastructure as Code

El repositorio utiliza un módulo reutilizable:

```text
modules/proxmox-vm/
```

El módulo encapsula:

- clonación completa desde template;
- CPU y memoria;
- disco;
- bridge;
- cloud-init;
- usuario y SSH key;
- IPv4 y gateway;
- DNS;
- QEMU Guest Agent;
- outputs de VM, IP y MAC.

Template base:

```text
Debian 13 cloud-init — VMID 9000
```

## Ansible

Playbooks principales:

```text
ansible/playbooks/
├── baseline.yml
├── rke2-prereqs.yml
├── rke2-bootstrap.yml
├── rke2-servers.yml
├── rke2-agents.yml
└── validate.yml
```

Ansible automatiza:

- baseline Linux;
- paquetes;
- módulos kernel;
- sysctl;
- eliminación de swap;
- bootstrap del primer servidor RKE2;
- unión de servidores adicionales;
- unión del worker.

El token de RKE2 no se almacena estáticamente en el repositorio.

## Kubernetes

El clúster fue validado funcionalmente, no solo mediante estado `Ready`.

La validación incluye:

- scheduling;
- DNS interno;
- comunicación HTTP entre workloads;
- ejecución real de aplicaciones.

Manifiesto:

```text
kubernetes/validation/functional-test.yml
```

## GitOps

### Flux CD

Flux sincroniza:

```text
./clusters/proxmox-lab
```

desde la rama:

```text
main
```

con pruning habilitado.

La estructura separa:

```text
apps/
infrastructure/
flux-system/
```

Flux administra actualmente:

- `flux-demo`;
- Local Path Provisioner;
- kube-prometheus-stack.

### Argo CD

Argo CD se utiliza como implementación GitOps comparativa.

La aplicación:

```text
argocd-demo
```

utiliza:

- sync automático;
- `prune`;
- `selfHeal`;
- creación automática del namespace.

Flux y Argo CD no compiten por los mismos recursos.

## Storage

Se utiliza Rancher Local Path Provisioner v0.0.37.

StorageClass:

```text
local-path
```

Configuración:

```text
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

El almacenamiento está restringido al worker:

```text
rke2-worker01
```

Ruta:

```text
/opt/local-path-provisioner
```

La solución es intencionadamente local y no HA.

El ciclo completo PVC/PV/escritura/lectura/eliminación fue validado.

## Observabilidad

Stack:

```text
kube-prometheus-stack 89.2.4
```

Componentes:

- Prometheus;
- Grafana;
- Prometheus Operator;
- kube-state-metrics;
- node-exporter.

Prometheus:

```text
retention: 3d
retentionSize: 6GB
storage: 8Gi
```

Grafana:

```text
storage: 2Gi
memory limit: 384Mi
```

Los componentes pesados se fijan al worker.

## Hardening RKE2

Los endpoints locales de:

- etcd;
- kube-controller-manager;
- kube-scheduler;

se mantuvieron sin exponer.

En lugar de debilitar RKE2 para satisfacer Prometheus, el chart de observabilidad se adaptó al modelo de seguridad del clúster.

Resultado final: todos los targets configurados de Prometheus quedaron `UP`.

## Seguridad

No se versionan:

```text
.tofu/
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
```

La ausencia de estos artefactos en Git fue verificada.

El token de registro RKE2 fue rotado de forma controlada tras aparecer accidentalmente en una salida interactiva.

Orden de reinicio durante la rotación:

```text
rke2-cp02
→ rke2-cp03
→ rke2-cp01
→ rke2-worker01
```

Tras la rotación, los cuatro nodos permanecieron `Ready`.

## Estructura del repositorio

```text
proxmox-rke2-platform/
├── ansible/
├── argocd/
├── clusters/
│   └── proxmox-lab/
├── docs/
│   ├── 09-rke2-gitops.md
│   ├── 10-observability.md
│   └── PROJECT-REPORT.md
├── kubernetes/
├── modules/
│   └── proxmox-vm/
├── data.tf
├── provider.tf
├── rke2.tf
├── versions.tf
├── vm.tf
└── README.md
```

## Documentación

- `docs/09-rke2-gitops.md` — despliegue RKE2, validación Kubernetes y GitOps.
- `docs/10-observability.md` — storage, Prometheus, Grafana, dimensionamiento y hardening.
- `docs/PROJECT-REPORT.md` — informe técnico global y exhaustivo del proyecto.

## Decisiones arquitectónicas

El proyecto prioriza:

- IaC sobre configuración manual;
- módulos reutilizables;
- separación de responsabilidades;
- versiones fijadas;
- secretos fuera de Git;
- propietario GitOps único;
- almacenamiento honesto respecto a sus limitaciones;
- observabilidad dimensionada;
- seguridad por encima de dashboards perfectos;
- validación funcional antes de añadir nuevas capas.

## Limitaciones conocidas

- un único host Proxmox físico;
- un único worker;
- almacenamiento local no HA;
- recursos de memoria limitados;
- API Proxmox local con TLS no validado;
- credenciales OpenTofu cargadas externamente;
- sin balanceador externo/VIP del control plane;
- sin almacenamiento distribuido;
- sin Alertmanager productivo;
- sin disaster recovery multi-host.

Estas limitaciones son explícitas y forman parte del alcance y las decisiones arquitectónicas de la plataforma.

## Informe completo

Para la descripción técnica exhaustiva:

```text
docs/PROJECT-REPORT.md
```

El informe recoge arquitectura, IaC, Ansible, RKE2, GitOps, almacenamiento, observabilidad, seguridad, validaciones, decisiones y limitaciones.
