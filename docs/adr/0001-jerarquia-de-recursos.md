# ADR-0001: Jerarquía de recursos

- Estado: Aceptado
- Fecha: 2026-10-26

## Contexto

El sandbox necesita aislarse de producción, compartir servicios de IA entre equipos y crear un proyecto por equipo bajo demanda. Las políticas de organización, los permisos y el perímetro de VPC Service Controls se aplican por carpeta y por proyecto.

## Decisión

Tres carpetas bajo la organización:

| Carpeta | Proyectos | Para qué |
|---|---|---|
| `bootstrap` | `<empresa>-seed-<sufijo>` | Estado de Terraform, cuentas del pipeline, Workload Identity Federation |
| `common` | `net-hub`, `logging`, `security` | Red compartida, logs centralizados, KMS y SCC |
| `ai-sandbox` | `ai-platform`, `ai-data`, `aisbx-<equipo>` | Servicios de IA compartidos, lago de datos y un proyecto por equipo |

La carpeta `bootstrap` la crea la etapa 0; `common` y `ai-sandbox` la etapa 1.

## Consecuencias

- Las org policies de regiones permitidas, CMEK obligatorio y modelos permitidos se aplican una vez en `ai-sandbox` y las heredan todos los sandboxes.
- El perímetro VPC-SC envuelve solo `ai-platform`, `ai-data` y los sandboxes.
- Borrar un sandbox es borrar un proyecto: no hay recursos compartidos que limpiar.
- Requiere una organización de GCP real (Cloud Identity o Workspace); no funciona con una cuenta de Gmail sin organización.
