# gcp-ai-sandbox

Datacenter virtual en Google Cloud diseñado como **sandbox de IA**: un entorno aislado donde los equipos experimentan con modelos generativos, entrenan y ajustan modelos propios y prototipan aplicaciones, sin riesgo para producción ni para datos sensibles. Todo se despliega con Terraform.

## Estado del proyecto

| Sprint | Fechas | Hito | Estado |
|---|---|---|---|
| 1. Descubrimiento y bases | 28 sep al 9 oct | Diseño y pipeline aprobados | En curso |
| 2. Seguridad y red | 12 al 23 oct | Perímetro y red validados | Pendiente |
| 3. Datos y cómputo | 26 oct al 6 nov | Primer trabajo en GPU | Pendiente |
| 4. Servicios de IA | 9 al 20 nov | Piloto RAG funcionando | Pendiente |
| 5. Costos y entrega | 23 nov al 3 dic | Acta de aceptación firmada | Pendiente |

El Sprint 1 se valida **sin cuenta de GCP**: todo el código se prueba con `terraform test` y `mock_provider` (ver [ADR-0005](docs/adr/0005-pruebas-con-mocks.md)). El primer despliegue real ocurre al iniciar el Sprint 2.

## Estructura

```
gcp-ai-sandbox/
├── modules/                 # Módulos reutilizables (se llenan a partir del Sprint 2)
├── stages/
│   ├── 0-bootstrap/         # Proyecto semilla, estado remoto, cuentas del pipeline, WIF
│   ├── 1-org/               # Carpetas, org policies, logging, SCC
│   ├── 2-security/          # KMS, Secret Manager, VPC-SC
│   ├── 3-networks/          # Hub, spokes, DNS, VPN, PSC
│   ├── 4-ai-platform/       # Datos, Vertex AI compartido, GKE GPU, guardrails
│   └── 5-sandboxes/         # Un proyecto por equipo a partir de teams/*.yaml
├── policies/                # Políticas como código (Conftest / OPA)
├── docs/                    # Casos de uso, plan de IPs, convenciones, ADR
└── .github/workflows/       # Pipeline CI/CD
```

## Requisitos locales

| Herramienta | Versión |
|---|---|
| Terraform | 1.9 o superior (mocks requieren 1.7+) |
| tflint | 0.54+ |
| checkov | 3.x |
| conftest | 0.56+ |
| infracost | 0.10+ |

## Cómo correr las validaciones en tu máquina

```bash
# Formato
terraform fmt -check -recursive

# Validación y pruebas de una etapa (sin credenciales)
cd stages/0-bootstrap
terraform init -backend=false
terraform validate
terraform test

# Políticas sobre los sandboxes
conftest verify -p policies
conftest test stages/5-sandboxes/teams -p policies/sandbox
```

## Cómo pedir un sandbox

1. Copia `stages/5-sandboxes/teams/analitica.yaml` con el nombre de tu equipo.
2. Llena presupuesto, fecha de expiración, cuotas de GPU y datos que necesitas.
3. Abre un PR. El pipeline valida las políticas y publica la estimación de costo.
4. Tu líder de equipo aprueba y, al hacer merge, se crea el proyecto.

Las reglas que se validan están en [policies/sandbox/sandbox.rego](policies/sandbox/sandbox.rego).

## Documentación

- [Casos de uso](docs/casos-de-uso.md)
- [Plan de direccionamiento IP](docs/plan-ip.md)
- [Convenciones de nombres y etiquetas](docs/convenciones.md)
- [Registro de decisiones (ADR)](docs/adr/)
