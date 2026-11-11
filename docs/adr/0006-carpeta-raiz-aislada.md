# ADR-0006: Carpeta raíz aislada dentro de una organización existente

- Estado: Aceptado
- Fecha: 2026-11-10
- Reemplaza en parte: ADR-0001 (dónde cuelgan las carpetas) y ADR-0004 (nivel de los roles)

## Contexto

La organización de GCP disponible (rubro.ai) ya tiene otros proyectos. Las org policies, los permisos y el perímetro de VPC Service Controls del reto no deben afectarlos.

## Decisión

- Todo el reto cuelga de una carpeta `gcp-ai-sandbox` directamente bajo la organización. Las carpetas `bootstrap`, `common` y `ai-sandbox` del ADR-0001 quedan dentro de ella.
- Los roles de las cuentas de servicio de cada etapa se dan sobre esa carpeta, no sobre la organización.
- Única excepción: `roles/orgpolicy.policyAdmin` para `sa-org`, porque Google solo permite asignarlo a nivel organización. El código de la etapa 1 solo escribe políticas con `parent` en la carpeta raíz o sus hijas, y las pruebas lo verifican.
- VPC Service Controls usa una política de Access Context Manager con alcance (scoped policy) limitada a la carpeta raíz. La crea el bootstrap y su administración se delega a `sa-security` sobre esa política únicamente.

## Consecuencias

- Borrar la carpeta `gcp-ai-sandbox` elimina el reto completo sin tocar el resto de la organización.
- Quien aplica el bootstrap necesita, además de Organization Admin, el rol Access Context Manager Admin a nivel organización (solo para crear la política con alcance).
- El riesgo del rol de org policies a nivel organización se acota con revisión obligatoria de PR y con las pruebas de la etapa 1.
