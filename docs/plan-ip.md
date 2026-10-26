# Plan de direccionamiento IP

Todas las subredes son privadas (sin IP públicas) y usan Private Google Access. Los rangos se eligen para no chocar con on-premises ni entre sí, y para que cada sandbox nuevo reciba su bloque sin coordinación manual.

## Resumen de bloques

| Bloque | Uso | Notas |
|---|---|---|
| `10.0.0.0/16` | Plataforma común y compartida (us-central1) | Hub, ai-platform, ai-data, PSC, PSA |
| `10.10.0.0/16` | Sandboxes en us-central1 | Un `/22` por equipo, hasta 64 sandboxes |
| `10.20.0.0/16` | Sandboxes y capacidad GPU en us-east4 | Región alterna, misma lógica |
| `10.255.0.0/24` | Planos de control de GKE privados | Un `/28` por clúster, hasta 16 |
| `100.64.0.0/10` | Rangos secundarios de GKE (pods y servicios) | Espacio CGNAT, no se anuncia a on-premises |
| `172.16.0.0/12` | Reservado para on-premises | **Supuesto**, confirmar con el cliente |
| `169.254.0.0/24` | Sesiones BGP de HA VPN | Un `/30` por túnel |

## Plataforma común (`10.0.0.0/16`)

| Subred | CIDR | Proyecto | Región |
|---|---|---|---|
| hub-usc1 | `10.0.0.0/24` | net-hub | us-central1 |
| hub-use4 | `10.0.1.0/24` | net-hub | us-east4 |
| psc-endpoints | `10.0.8.0/24` | net-hub | us-central1 |
| ai-platform-gke | `10.0.16.0/20` | ai-platform | us-central1 |
| ai-data-dataflow | `10.0.32.0/20` | ai-data | us-central1 |
| psa-alloydb-cloudsql | `10.0.64.0/20` | net-hub (Private Service Access) | us-central1 |

Rangos secundarios del clúster compartido de GKE en ai-platform:

| Rango | CIDR |
|---|---|
| pods | `100.64.0.0/14` |
| servicios | `100.68.0.0/20` |

## Sandboxes (`10.10.0.0/16`)

Cada sandbox recibe un índice `n` (0 a 63) asignado en su YAML de equipo y deriva sus rangos con `cidrsubnet`:

| Rango | Fórmula | Ejemplo para n = 0 (analitica) | n = 1 |
|---|---|---|---|
| Subred primaria | `cidrsubnet("10.10.0.0/16", 6, n)` | `10.10.0.0/22` | `10.10.4.0/22` |
| Pods de GKE | `cidrsubnet("100.80.0.0/12", 6, n)` | `100.80.0.0/18` | `100.80.64.0/18` |
| Servicios de GKE | `cidrsubnet("100.96.0.0/16", 8, n)` | `100.96.0.0/24` | `100.96.1.0/24` |

Un `/22` da 1,020 direcciones utilizables: suficiente para Workbench, nodos de GKE con GPU y conectores de Cloud Run de un equipo.

## Conectividad híbrida

- Dos túneles HA VPN desde net-hub hacia on-premises, con BGP en `169.254.0.0/30` y `169.254.0.4/30`.
- Se anuncian a on-premises solo `10.0.0.0/16` y `10.10.0.0/16`. Los rangos de pods (`100.64.0.0/10`) no se anuncian.
- Firewall jerárquico: los sandboxes no tienen rutas hacia proyectos productivos.

## Decisiones abiertas

- Confirmar el rango real de on-premises con el cliente antes del Sprint 2.
- Si se necesitan más de 64 sandboxes por región, usar `10.11.0.0/16` con la misma fórmula.
