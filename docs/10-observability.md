# Fase 10 — Observabilidad

## 1. Objetivo

La Fase 10 tiene como objetivo incorporar una capa de observabilidad persistente al clúster RKE2 construido en la fase anterior.

La fase incorpora:

- almacenamiento dinámico local para Kubernetes;
- Rancher Local Path Provisioner;
- Prometheus;
- Grafana;
- Prometheus Operator;
- kube-state-metrics;
- node-exporter;
- persistencia de métricas y configuración;
- despliegue declarativo mediante Flux CD;
- validación funcional mediante las APIs HTTP;
- validación real de targets Prometheus;
- adaptación de kube-prometheus-stack al modelo de seguridad de RKE2;
- dimensionamiento específico para los recursos disponibles en la plataforma.

El objetivo no es únicamente instalar herramientas de monitorización, sino construir una solución coherente con la arquitectura dla plataforma, validar que recopila métricas reales y evitar introducir falsa alta disponibilidad o componentes innecesarios.

## 2. Arquitectura

La arquitectura de observabilidad queda integrada en la plataforma existente:

GitHub
  |
Flux CD
  |
  +--> Local Path Provisioner
  |
  +--> kube-prometheus-stack
          |
          +--> Prometheus
          +--> Grafana
          +--> Prometheus Operator
          +--> kube-state-metrics
          +--> node-exporter

Los componentes centrales de observabilidad se ejecutan sobre:

rke2-worker01
10.20.0.21

node-exporter se ejecuta en los cuatro nodos del clúster para proporcionar métricas del sistema operativo:

- rke2-cp01
- rke2-cp02
- rke2-cp03
- rke2-worker01

Esta distribución evita cargar innecesariamente los nodos de control, que disponen de menos memoria que el worker.

## 3. Decisión de almacenamiento

El clúster no disponía inicialmente de ninguna StorageClass.

Para esta plataforma se descartó introducir almacenamiento distribuido como Longhorn o Ceph.

La infraestructura dispone de un único worker, por lo que desplegar almacenamiento distribuido no proporcionaría alta disponibilidad real y añadiría complejidad y consumo de recursos sin aportar una mejora arquitectónica efectiva.

Se seleccionó:

Rancher Local Path Provisioner v0.0.37

StorageClass:

local-path

Provisioner:

rancher.io/local-path

VolumeBindingMode:

WaitForFirstConsumer

ReclaimPolicy:

Delete

Commit:

50c4930 feat: add worker-local dynamic storage provisioner

## 4. Local Path Provisioner

La configuración está declarada en:

clusters/proxmox-lab/infrastructure/local-path-provisioner/

Estructura:

upstream.yaml
patch-deployment.yaml
patch-config.yaml
kustomization.yaml

El provisioner está restringido mediante nodeSelector a:

kubernetes.io/hostname: rke2-worker01

El almacenamiento local se crea bajo:

/opt/local-path-provisioner

La configuración nodePathMap únicamente permite utilizar:

rke2-worker01

Esto hace explícito que el almacenamiento de esta fase es local al worker y no proporciona alta disponibilidad.

### 4.1 Validación funcional

Se realizó una prueba completa del ciclo de vida de un volumen mediante un PVC y un pod temporales.

Se validó:

1. creación del PVC;
2. aprovisionamiento dinámico del PV;
3. estado Bound;
4. scheduling del pod sobre rke2-worker01;
5. escritura de datos;
6. lectura correcta de los datos;
7. creación del directorio correspondiente en el host;
8. eliminación del PVC;
9. eliminación automática del PV;
10. limpieza del directorio local.

Contenido utilizado para validar escritura y lectura:

local-path-ok

La prueba confirmó que el almacenamiento dinámico funciona correctamente de extremo a extremo.

## 5. Gestión GitOps

La infraestructura Kubernetes de esta fase está gestionada exclusivamente mediante Flux CD.

La estructura principal es:

clusters/proxmox-lab/
  infrastructure/
    local-path-provisioner/
    monitoring/

El Kustomization principal incluye:

resources:
  - flux-system
  - infrastructure
  - apps/flux-demo

Y la infraestructura incluye:

resources:
  - local-path-provisioner
  - monitoring

Flux es el único controlador GitOps responsable de estos componentes.

Argo CD permanece disponible en la plataforma para la comparación realizada durante la Fase 9, pero no gestiona los recursos de observabilidad ni almacenamiento.

Esta separación evita que dos controladores GitOps intenten reconciliar los mismos objetos Kubernetes.

## 6. Stack de observabilidad

Se seleccionó:

kube-prometheus-stack

Chart:

89.2.4

El despliegue incluye:

- Prometheus;
- Grafana;
- Prometheus Operator;
- kube-state-metrics;
- node-exporter.

Alertmanager permanece deshabilitado inicialmente.

No se configura Ingress en esta fase.

Commit inicial:

7625cb8 feat: add GitOps observability stack

## 7. Dimensionamiento

La plataforma dispone de recursos limitados, especialmente en los nodos de control.

Por este motivo los componentes centrales se concentran en rke2-worker01.

### Prometheus

Configuración:

replicas: 1
retention: 3d
retentionSize: 6GB

Recursos:

requests:
  cpu: 150m
  memory: 512Mi

limits:
  memory: 1Gi

Persistencia:

StorageClass: local-path
PVC: 8Gi
AccessMode: ReadWriteOnce

### Grafana

Recursos:

requests:
  cpu: 50m
  memory: 128Mi

limits:
  memory: 384Mi

Persistencia:

StorageClass: local-path
PVC: 2Gi
AccessMode: ReadWriteOnce

Durante la validación inicial Grafana consumía aproximadamente 253 MiB con un límite configurado inicialmente en 256 MiB.

Aunque no se produjeron reinicios ni eventos OOMKilled, el margen disponible era insuficiente.

El límite se incrementó preventivamente a:

384Mi

Commit:

99ee402 fix: increase Grafana memory headroom

### Otros componentes

También se ejecutan sobre rke2-worker01:

- Prometheus Operator;
- kube-state-metrics.

node-exporter se mantiene distribuido por todos los nodos, ya que su finalidad es precisamente recopilar métricas de cada sistema.

## 8. Persistencia

Se validaron dos PVC persistentes principales.

Prometheus:

8Gi
RWO
local-path

Grafana:

2Gi
RWO
local-path

Ambos quedaron en estado:

Bound

Los PV utilizan:

ReclaimPolicy: Delete

La persistencia está asociada al worker rke2-worker01.

Esta arquitectura es adecuada para la plataforma, pero no debe interpretarse como almacenamiento altamente disponible.

La pérdida permanente del worker implicaría la pérdida de los datos locales almacenados en estos volúmenes si no existe una copia externa.

## 9. Instalación mediante Flux y Helm

El repositorio Helm utilizado es:

prometheus-community

La instalación se realiza mediante:

HelmRepository
HelmRelease

Namespace:

monitoring

Durante la primera instalación los componentes Kubernetes comenzaron a desplegarse correctamente, pero Helm agotó su timeout mientras Grafana todavía estaba inicializando.

La causa no fue un error de configuración.

La descarga de algunas imágenes fue considerablemente lenta. La imagen de Grafana necesitó aproximadamente diez minutos para descargarse.

Una vez finalizadas las descargas:

- Grafana quedó Running;
- Prometheus quedó Running;
- los sidecars de Grafana quedaron Ready;
- no se observaron reinicios.

Para permitir instalaciones válidas en entornos con descargas lentas se configuró:

timeout: 15m

Commit:

3118406 fix: increase observability Helm timeout

Tras la reconciliación de Flux:

HelmRelease:
Ready: True

Helm upgrade:
Succeeded

## 10. Validación funcional de Prometheus

La validación no se limitó al estado Running de los pods.

Se utilizó port-forward temporal contra el Service de Prometheus y se consultaron sus endpoints HTTP.

Endpoint:

/-/ready

Respuesta:

Prometheus Server is Ready.

Endpoint:

/-/healthy

Respuesta:

Prometheus Server is Healthy.

Esto confirma que el servidor Prometheus estaba funcional y preparado para atender consultas.

El port-forward utilizado durante las pruebas fue temporal y se eliminó después de cada validación.

## 11. Validación funcional de Grafana

Grafana se validó mediante:

/api/health

Respuesta:

database: ok
version: 13.2.1

Esto confirmó:

- servicio HTTP funcional;
- base de datos accesible;
- proceso Grafana operativo.

La prueba se realizó mediante port-forward temporal sin exponer Grafana externamente.

## 12. Validación de targets Prometheus

Se consultó directamente:

/api/v1/targets

La primera validación mostró correctamente operativos:

apiserver: 3
coredns: 2
Grafana: 1
Prometheus Operator: 1
Prometheus: 2
kube-state-metrics: 1
kubelet: 12
node-exporter: 4

Sin embargo aparecieron nueve targets DOWN:

kube-controller-manager: 3
kube-scheduler: 3
kube-etcd: 3

Todos fallaban con:

connection refused

## 13. Integración con el hardening de RKE2

La investigación de los nueve targets DOWN confirmó que no se trataba de un fallo de Prometheus.

En los nodos de control RKE2 se comprobó:

etcd:
127.0.0.1:2381

kube-scheduler:
127.0.0.1:10259

kube-controller-manager:
127.0.0.1:10257

Por tanto, estos endpoints no estaban disponibles mediante las direcciones 10.20.0.x utilizadas por los ServiceMonitors estándar de kube-prometheus-stack.

La configuración de RKE2 no contenía overrides para modificar este comportamiento.

Se decidió explícitamente no abrir estos endpoints sobre las interfaces de red únicamente para satisfacer los valores predeterminados del chart.

La prioridad arquitectónica fue conservar el modelo endurecido de RKE2.

Se deshabilitaron en kube-prometheus-stack:

kubeControllerManager
kubeScheduler
kubeEtcd

También se deshabilitaron las reglas asociadas que dependían de estas métricas:

etcd
kubeControllerManager
kubeSchedulerAlerting
kubeSchedulerRecording

Commit:

af1d20e fix: align monitoring with RKE2 hardened endpoints

Esta decisión evita modificar la superficie de exposición del control plane únicamente para obtener targets Prometheus en estado UP.

## 14. Estado final de targets

Tras la reconciliación del cambio mediante Flux se volvió a consultar la API de Prometheus.

Resultado:

apiserver: up=3 down=0
coredns: up=2 down=0
kube-prometheus-stack-grafana: up=1 down=0
kube-prometheus-stack-operator: up=1 down=0
kube-prometheus-stack-prometheus: up=2 down=0
kube-state-metrics: up=1 down=0
kubelet: up=12 down=0
node-exporter: up=4 down=0

Todos los targets configurados quedaron operativos.

La ausencia de controller-manager, scheduler y etcd es intencionada y responde a la decisión de conservar el hardening de RKE2.

## 15. Consumo de recursos

Durante la validación final se observaron aproximadamente los siguientes consumos.

### Nodos

rke2-cp01:
2890 MiB
73 %

rke2-cp02:
2933 MiB
74 %

rke2-cp03:
2610 MiB
66 %

rke2-worker01:
3585 MiB
60 %

### Componentes principales

Prometheus:

aproximadamente 612 MiB
13m CPU

Grafana:

aproximadamente 262 MiB
8m CPU

kube-state-metrics:

aproximadamente 36 MiB

Prometheus Operator:

aproximadamente 27 MiB

node-exporter:

aproximadamente 15-18 MiB por nodo

El worker mantiene margen suficiente para el stack actual.

Los nodos de control presentan un uso de memoria relativamente elevado debido principalmente a la propia plataforma RKE2, razón adicional para evitar colocar sobre ellos los componentes centrales de observabilidad.

## 16. Consideraciones arquitectónicas

La fase adopta deliberadamente varias decisiones conservadoras.

### Almacenamiento

Local Path Provisioner se utiliza porque existe un único worker.

No se pretende simular alta disponibilidad mediante herramientas de almacenamiento distribuido sin disponer de los nodos necesarios para proporcionarla realmente.

### Placement

Prometheus, Grafana, Prometheus Operator y kube-state-metrics se concentran en el worker.

node-exporter se distribuye en todos los nodos.

### Alta disponibilidad

Prometheus utiliza una única réplica.

Grafana utiliza una única réplica.

El almacenamiento es local.

Esto significa que la observabilidad no es altamente disponible.

La decisión es coherente con el tamaño y propósito dla plataforma.

### Seguridad

No se modificaron los endpoints locales del controller-manager, scheduler o etcd para adaptarlos a los defaults de kube-prometheus-stack.

Se adaptó la monitorización a RKE2 y no RKE2 a la monitorización.

### Exposición

Grafana y Prometheus no disponen de Ingress en esta fase.

Las validaciones se realizaron mediante port-forward temporal.

### GitOps

Flux es el único owner GitOps de la infraestructura de observabilidad y almacenamiento.

Argo CD no gestiona estos recursos.

## 17. Limitaciones conocidas

La solución actual presenta conscientemente las siguientes limitaciones:

1. almacenamiento local no-HA;
2. un único worker;
3. Prometheus con una sola réplica;
4. Grafana con una sola réplica;
5. Alertmanager deshabilitado;
6. controller-manager no scrapeado;
7. scheduler no scrapeado;
8. etcd no scrapeado;
9. ausencia de Ingress para las interfaces;
10. pérdida del worker implicaría indisponibilidad de la observabilidad y riesgo para los datos locales.

Estas limitaciones no están ocultas ni se presentan como características de alta disponibilidad.

Forman parte del diseño consciente dla plataforma y permiten mantener una arquitectura proporcional a los recursos disponibles.

## 18. Resultado de la fase

La Fase 10 queda funcionalmente validada.

Se ha demostrado:

1. aprovisionamiento dinámico de almacenamiento;
2. ciclo de vida completo de PVC y PV;
3. almacenamiento persistente para Prometheus;
4. almacenamiento persistente para Grafana;
5. despliegue de kube-prometheus-stack mediante Flux;
6. Prometheus operativo;
7. Grafana operativo;
8. Prometheus Operator operativo;
9. kube-state-metrics operativo;
10. node-exporter operativo en los cuatro nodos;
11. health checks HTTP reales;
12. scraping efectivo de métricas;
13. validación mediante la API de targets de Prometheus;
14. adaptación consciente al hardening de RKE2;
15. todos los targets configurados en estado UP;
16. dimensionamiento específico para la plataforma;
17. persistencia del estado mediante GitOps;
18. separación clara de ownership entre Flux y Argo CD.

## 19. Conclusión técnica

La plataforma dispone ahora de una capa de observabilidad integrada en el mismo modelo declarativo utilizado para gestionar el resto de la infraestructura Kubernetes.

El flujo queda:

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
Flux CD
  |
  +-----------------------+
  |                       |
Storage               Observability
  |                       |
Local Path          Prometheus
Provisioner         Grafana
                    kube-state-metrics
                    node-exporter

La fase demuestra no solo el despliegue de herramientas de monitorización, sino también decisiones de arquitectura relacionadas con capacidad, persistencia, seguridad, placement y ownership GitOps.

Especialmente relevante es la decisión de conservar el comportamiento endurecido de RKE2 en lugar de exponer endpoints del control plane únicamente para satisfacer los valores predeterminados de una herramienta externa.

La solución resultante es deliberadamente pequeña, reproducible y proporcional a la infraestructura disponible.

## Estado

FASE 10 — COMPLETADA Y VALIDADA
