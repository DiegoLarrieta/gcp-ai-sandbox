# Etapa 2: seguridad

| Recurso | Detalle |
|---|---|
| Cloud KMS | keyring `ai-sandbox-us-central1` en el proyecto security con llaves `storage`, `bigquery`, `aiplatform` y `compute`, rotación de 90 días y protegidas contra borrado |
| Permisos CMEK | agentes de Storage, BigQuery, Vertex AI y Compute de ai-platform y ai-data |
| Secret Manager | contenedor `huggingface-token`, el valor lo carga una persona |
| VPC Service Controls | perímetro `ai_sandbox` sobre ai-platform y ai-data, sin reglas de salida (ADR-0007) |

`admin_members` debe incluir a quien opera la plataforma, por ejemplo `["user:diego@empresa.com"]`. Con `dry_run = true` el perímetro solo registra.
