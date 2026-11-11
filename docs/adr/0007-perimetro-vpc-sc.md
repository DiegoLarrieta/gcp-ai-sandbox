# ADR-0007: Perímetro de VPC Service Controls

- Estado: Aceptado
- Fecha: 2026-11-10

## Contexto

El reto exige que copiar datos de Storage, BigQuery o Vertex AI fuera de los proyectos autorizados falle y quede registrado.

## Decisión

- Un perímetro regular `ai_sandbox` que envuelve los proyectos `ai-platform` y `ai-data` (y los sandboxes en el Sprint 5).
- Servicios restringidos: Storage, BigQuery, Vertex AI, Notebooks, Artifact Registry, GKE, Secret Manager y DLP. Desde dentro de las VPC solo se alcanzan servicios restringidos (`RESTRICTED-SERVICES`).
- Cloud KMS no se restringe: las llaves CMEK viven en el proyecto `security`, fuera del perímetro, para separar a quien custodia las llaves de quien usa los datos.
- Una sola regla de entrada: las cuentas del pipeline y los administradores (`admin_members`) pueden operar dentro del perímetro desde cualquier origen.
- Ninguna regla de salida. Cualquier movimiento de datos hacia un proyecto fuera del perímetro se rechaza.
- `dry_run = true` permite activar el perímetro en modo simulación para revisar violaciones antes de bloquear.
- Las violaciones quedan en los audit logs de política del proyecto y en el bucket central `audit-logs` (etapa 1).

## Consecuencias

- Un administrador puede leer los datos, pero no puede copiarlos a otro proyecto: la prueba del criterio de aceptación se hace con su propia identidad.
- Cada servicio nuevo que se use dentro de los proyectos protegidos debe agregarse a `restricted_services` y validarse primero en `dry_run`.
