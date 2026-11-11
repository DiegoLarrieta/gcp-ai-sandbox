# Etapa 1: organización

Dentro de la carpeta raíz `gcp-ai-sandbox`:

| Recurso | Detalle |
|---|---|
| Carpetas | `common` y `ai-sandbox` |
| Proyectos base | `logging`, `security`, `net-hub` (en common); `ai-platform`, `ai-data` (en ai-sandbox) |
| Org policies en la raíz | regiones us-central1 y us-east4, sin IP públicas, sin llaves de cuentas de servicio, sin red default, OS Login, acceso uniforme y sin acceso público en buckets |
| Org policies en ai-sandbox | CMEK obligatorio en Storage, BigQuery y Vertex AI, solo con llaves del proyecto security |
| Auditoría | Data Access en toda la carpeta y sink al bucket `audit-logs` del proyecto logging |

```bash
terraform init -backend-config="bucket=<tfstate_bucket>"
terraform apply -var tfstate_bucket=<tfstate_bucket> -var prefix=<prefix> -var billing_account=<billing>
```
