#!/usr/bin/env bash
# Borra todo el laboratorio al terminar el reto: bash scripts/borrar-lab.sh <project_id>
# Las llaves KMS no se pueden borrar en GCP; se destruyen sus versiones.
set -euo pipefail
PROJECT=${1:?falta project_id}
export PATH="$HOME/bin:$PATH"
cd "$(dirname "$0")/../labs/proyecto"
terraform init -input=false -reconfigure -backend-config="bucket=${PROJECT}-tfstate" >/dev/null
for k in storage compute; do
  terraform state rm "google_kms_crypto_key.key[\"$k\"]" >/dev/null 2>&1 || true
  gcloud kms keys versions destroy 1 --key="$k" --keyring=ai-sandbox-us-central1 --location=us-central1 --project="$PROJECT" --quiet >/dev/null 2>&1 || true
done
terraform destroy -input=false -auto-approve -var "project_id=$PROJECT"
echo "Listo. Para borrar el proyecto completo: gcloud projects delete $PROJECT"
