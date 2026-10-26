# Convenciones

## Nombres

Formato general: `<empresa>-aisbx-<equipo>-<recurso>`, todo en minúsculas, separado por guiones.

| Recurso | Formato | Ejemplo |
|---|---|---|
| Proyecto de sandbox | `<empresa>-aisbx-<equipo>` | `acme-aisbx-analitica` |
| Proyecto de plataforma | `<empresa>-<función>` | `acme-ai-platform`, `acme-net-hub` |
| Proyecto semilla | `<empresa>-seed-<sufijo>` | `acme-seed-3f9a` |
| Bucket | `<empresa>-<uso>-<sufijo>` | `acme-tfstate-3f9a` |
| Cuenta de servicio de etapa | `sa-<etapa>` | `sa-networks` |
| Llave KMS | `<uso>` dentro del keyring `<uso>-<región>` | `tfstate` en `tfstate-us-central1` |

Límites de GCP a tener en cuenta: ID de proyecto de 6 a 30 caracteres, cuenta de servicio de 6 a 30, bucket de 3 a 63 y único global.

## Etiquetas obligatorias

Todos los recursos que aceptan etiquetas llevan estas cinco. El pipeline rechaza sandboxes que no las puedan generar.

| Etiqueta | Valor | Ejemplo |
|---|---|---|
| `team` | Equipo dueño | `analitica` |
| `owner` | Grupo dueño, con `@` y `.` cambiados por `-` | `gcp-ai-analitica-empresa-com` |
| `cost_center` | Centro de costos | `cc-1042` |
| `expires` | Fecha de expiración `AAAA-MM-DD`; `never` solo en la base | `2027-03-31` |
| `managed_by` | Siempre `terraform` | `terraform` |

## Estado remoto

- Un solo bucket con versionado y CMEK, creado por `0-bootstrap`.
- Prefijo por etapa: `stages/<etapa>/`.
- Prefijo por sandbox: `sandboxes/<equipo>/`.

## Código

- Versiones fijadas de Terraform y proveedores; `.terraform.lock.hcl` versionado.
- Recursos que solo existen en `google-beta` se declaran con `provider = google-beta` de forma explícita.
- Sin secretos en el código; el pipeline se autentica con Workload Identity Federation.
- Módulos externos (Cloud Foundation Fabric, terraform-google-modules) solo con versión fijada.
- Cada etapa tiene su carpeta `tests/` con pruebas de `terraform test`.
