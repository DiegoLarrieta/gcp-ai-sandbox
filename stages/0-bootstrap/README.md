# Etapa 0: bootstrap

Crea lo mínimo para que el pipeline pueda desplegar todo lo demás.

| Recurso | Para qué |
|---|---|
| Carpeta `bootstrap` | Aísla el proyecto semilla del resto |
| Proyecto `<prefix>-seed-<sufijo>` | Aloja estado, llaves e identidades del pipeline |
| Llave KMS `tfstate` | CMEK del estado, rotación cada 90 días |
| Bucket `<prefix>-tfstate-<sufijo>` | Estado remoto con versionado y acceso público bloqueado |
| Cuentas `sa-<etapa>` | Una por etapa, sin Owner ni Editor |
| Workload Identity Pool `github` | El pipeline se autentica sin llaves, solo desde este repo |

## Probar sin cuenta de GCP

```bash
terraform init -backend=false
terraform test
```

Las pruebas usan `mock_provider` y no llaman a ninguna API (ver ADR-0005).

## Primer despliegue real (inicio del Sprint 2)

Requiere un usuario con Organization Admin y Billing Admin.

```bash
gcloud auth application-default login
cp terraform.tfvars.example terraform.tfvars   # llena valores reales
terraform init
terraform apply
```

Después:

1. Descomenta el bloque `backend "gcs"` de `versions.tf` con el valor de `tfstate_bucket`.
2. `terraform init -migrate-state`.
3. En GitHub, guarda como variables del repo `WIF_PROVIDER` (output `wif_provider`) y el correo de cada etapa del output `stage_service_accounts`.
