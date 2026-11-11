#!/usr/bin/env bash
# Despliegue completo del Sprint 2 desde Cloud Shell, con la sesión del admin.
#
#   bash scripts/desplegar-sprint2.sh <org_id> <billing_account> [prefix]
#
# Pasos: herramientas, permisos del admin, 0-bootstrap, migración del estado,
# etapas 1-org, 2-security y 3-networks (cada una con su propia cuenta de
# servicio), validación del hito y apagado del HA VPN.
set -euo pipefail

ORG=${1:?falta org_id}
BILLING=${2:?falta billing_account}
PREFIX=${3:-sbx}
REGION=us-central1
REPO=DiegoLarrieta/gcp-ai-sandbox
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TF_VERSION=1.11.4
paso() { echo; echo "######## $* ########"; }

paso "1. Terraform $TF_VERSION"
if ! terraform version 2>/dev/null | grep -q "v$TF_VERSION"; then
  mkdir -p "$HOME/bin"
  curl -sSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  unzip -oq /tmp/tf.zip -d "$HOME/bin"
fi
export PATH="$HOME/bin:$PATH"
terraform version | head -1

ADMIN=$(gcloud config get-value account 2>/dev/null)
echo "Admin: $ADMIN"

paso "2. Permisos del admin en la organización"
for role in roles/resourcemanager.folderAdmin roles/resourcemanager.projectCreator roles/accesscontextmanager.policyAdmin; do
  gcloud organizations add-iam-policy-binding "$ORG" --member="user:$ADMIN" --role="$role" --condition=None --quiet >/dev/null
  echo "  $role"
done

paso "3. Etapa 0-bootstrap"
cd "$ROOT/stages/0-bootstrap"
cat > terraform.tfvars <<VARS
org_id          = "$ORG"
billing_account = "$BILLING"
prefix          = "$PREFIX"
region          = "$REGION"
github_repo     = "$REPO"
owner           = "$ADMIN"
VARS
terraform init -input=false -upgrade >/dev/null
# Primero el proyecto semilla y sus APIs: se vuelve el proyecto de cuota.
terraform apply -input=false -auto-approve -target=google_project_service.seed
SEED=$(terraform output -raw seed_project_id 2>/dev/null || terraform state show -no-color google_project.seed | awk -F'"' '/project_id/{print $2; exit}')
export GOOGLE_BILLING_PROJECT=$SEED USER_PROJECT_OVERRIDE=true
gcloud auth application-default set-quota-project "$SEED" >/dev/null 2>&1 || true
terraform apply -input=false -auto-approve
BUCKET=$(terraform output -raw tfstate_bucket)

paso "4. Estado de 0-bootstrap al bucket remoto"
cat > backend.tf <<BK
terraform {
  backend "gcs" {
    bucket = "$BUCKET"
    prefix = "stages/0-bootstrap"
  }
}
BK
terraform init -input=false -migrate-state -force-copy >/dev/null
echo "  estado en gs://$BUCKET/stages/0-bootstrap"
SA_JSON=$(terraform output -json stage_service_accounts)
sa() { echo "$SA_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }
WIF=$(terraform output -raw wif_provider)

# El admin puede actuar como las cuentas de las etapas: así cada etapa se
# despliega con sus propios permisos mínimos, igual que en el pipeline.
gcloud projects add-iam-policy-binding "$SEED" --member="user:$ADMIN" --role=roles/iam.serviceAccountTokenCreator --condition=None --quiet >/dev/null
sleep 60  # propagación de IAM

etapa() {
  local stage=$1 account=$2; shift 2
  paso "Etapa $stage como $account"
  cd "$ROOT/stages/$stage"
  export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=$account
  terraform init -input=false -reconfigure -backend-config="bucket=$BUCKET" >/dev/null
  terraform apply -input=false -auto-approve -var "tfstate_bucket=$BUCKET" "$@"
  unset GOOGLE_IMPERSONATE_SERVICE_ACCOUNT
}

etapa 1-org "$(sa org)" -var "prefix=$PREFIX" -var "billing_account=$BILLING" -var "owner=$ADMIN"
sleep 60  # las APIs recién habilitadas tardan en propagar
etapa 2-security "$(sa security)" -var "admin_members=[\"user:$ADMIN\"]"
etapa 3-networks "$(sa networks)" -var "enable_hybrid=true"

paso "5. Validación del hito"
cd "$ROOT/stages/1-org"
P=$(terraform output -json projects)
pid() { echo "$P" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1']['project_id'])"; }
echo "  esperando 90 s a que el perímetro y los túneles terminen de levantar"; sleep 90
set +e
bash "$ROOT/scripts/validar-sprint2.sh" "$SEED" "$(pid ai-data)" "$(pid security)" "$(pid net-hub)" "$(pid logging)" | tee "$HOME/validacion-sprint2.txt"
RES=${PIPESTATUS[0]}
set -e

paso "6. Apagar el HA VPN para no generar costo"
etapa 3-networks "$(sa networks)" -var "enable_hybrid=false"

paso "Resumen"
cat <<FIN
Resultado de la validación: $([ "$RES" -eq 0 ] && echo "TODO OK" || echo "HAY FALLAS, revisa arriba")
Detalle guardado en ~/validacion-sprint2.txt

Variables para GitHub (Settings > Secrets and variables > Actions > Variables):
  TFSTATE_BUCKET          $BUCKET
  WIF_PROVIDER            $WIF
  STAGE_SERVICE_ACCOUNTS  $SA_JSON
  GCP_PREFIX              $PREFIX
  GCP_ADMIN_MEMBERS       ["user:$ADMIN"]
FIN
