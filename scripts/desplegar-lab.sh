#!/usr/bin/env bash
# Despliegue y validación del Sprint 2 en un solo proyecto (ADR-0009).
# Se corre en Cloud Shell:
#
#   bash scripts/desplegar-lab.sh <billing_account> [project_id]
#
# Sin project_id crea uno nuevo llamado reto-terraform. Al final borra las
# VMs de prueba y apaga el HA VPN para no generar costo.
set -euo pipefail

BILLING=${1:?falta billing_account}
PROJECT=${2:-}
REGION=us-central1
ZONE=us-central1-a
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TF_VERSION=1.11.4
pass=0; fail=0
paso() { echo; echo "######## $* ########"; }
ok()   { echo "  OK    $1"; pass=$((pass+1)); }
bad()  { echo "  FALLA $1"; fail=$((fail+1)); }

paso "1. Terraform $TF_VERSION"
if ! terraform version 2>/dev/null | grep -q "v$TF_VERSION"; then
  mkdir -p "$HOME/bin"
  curl -sSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  unzip -oq /tmp/tf.zip -d "$HOME/bin"
fi
export PATH="$HOME/bin:$PATH"
terraform version | head -1

paso "2. Proyecto"
if [ -z "$PROJECT" ]; then
  PROJECT="reto-terraform-$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  gcloud projects create "$PROJECT" --name="reto-terraform" --labels=managed_by=terraform,team=plataforma
fi
gcloud billing projects link "$PROJECT" --billing-account="$BILLING" >/dev/null
gcloud config set project "$PROJECT" >/dev/null 2>&1
# Que gcloud y Terraform cobren las llamadas al proyecto del laboratorio.
gcloud config set billing/quota_project "$PROJECT" >/dev/null 2>&1
export GOOGLE_CLOUD_QUOTA_PROJECT=$PROJECT
echo "  proyecto: $PROJECT"
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com storage.googleapis.com compute.googleapis.com iap.googleapis.com --project="$PROJECT"

paso "3. Estado remoto"
BUCKET="${PROJECT}-tfstate"
if ! gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$BUCKET" --project="$PROJECT" --location="$REGION" --uniform-bucket-level-access --public-access-prevention
  gcloud storage buckets update "gs://$BUCKET" --versioning >/dev/null
fi
echo "  gs://$BUCKET"

# El agente de Cloud Storage se crea la primera vez que se consulta; sin él
# no se le puede dar acceso a la llave CMEK.
gcloud storage service-agent --project="$PROJECT" >/dev/null && sleep 15

paso "4. Terraform apply (con HA VPN)"
cd "$ROOT/labs/proyecto"
terraform init -input=false -reconfigure -backend-config="bucket=$BUCKET" >/dev/null
terraform apply -input=false -auto-approve -var "project_id=$PROJECT" -var "enable_hybrid=true"
KEY=$(terraform output -raw storage_key)

paso "5. VMs de prueba (sin IP pública)"
for vm in "vm-hub hub-usc1" "vm-onprem onprem-sim"; do
  set -- $vm
  gcloud compute instances create "$1" --project="$PROJECT" --zone="$ZONE" --machine-type=e2-micro \
    --subnet="$2" --no-address --image-family=debian-12 --image-project=debian-cloud \
    --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --quiet >/dev/null && echo "  $1 en $2"
done
ONPREM_IP=$(gcloud compute instances describe vm-onprem --zone="$ZONE" --project="$PROJECT" --format='value(networkInterfaces[0].networkIP)')
[ -f "$HOME/.ssh/google_compute_engine" ] || ssh-keygen -q -t rsa -N "" -f "$HOME/.ssh/google_compute_engine"
echo "  esperando 60 s a que arranquen las VMs y BGP"; sleep 60

en_vm() { gcloud compute ssh vm-hub --zone="$ZONE" --project="$PROJECT" --tunnel-through-iap --quiet \
  --strict-host-key-checking=no --command="$1" 2>/dev/null; }
for i in 1 2 3 4 5; do en_vm true && break; echo "  SSH aún no responde, reintento"; sleep 20; done

paso "6. Validación"
set +e
echo "-- HA VPN"
for t in tunnel-hub-0 tunnel-hub-1; do
  st=$(gcloud compute vpn-tunnels describe "$t" --region="$REGION" --project="$PROJECT" --format='value(status)')
  [ "$st" = "ESTABLISHED" ] && ok "$t ESTABLISHED" || bad "$t $st"
done
bgp=$(gcloud compute routers get-status cr-vpn-hub --region="$REGION" --project="$PROJECT" --format='value(result.bgpPeerStatus[].status)')
echo "        BGP: $bgp"
echo "$bgp" | grep -q DOWN && bad "sesiones BGP" || ok "sesiones BGP arriba"
gcloud compute routers get-status cr-vpn-hub --region="$REGION" --project="$PROJECT" --format='value(result.bestRoutes[].destRange)' | grep -q "172.16.0.0/24" \
  && ok "la hub aprende 172.16.0.0/24 de on-premises por BGP" || bad "ruta de on-premises"
en_vm "ping -c 3 -W 2 $ONPREM_IP" | tail -2 | sed 's/^/        /'
en_vm "ping -c 3 -W 2 $ONPREM_IP >/dev/null" && ok "ping de la hub a on-premises ($ONPREM_IP) por el VPN" || bad "ping a on-premises"

echo "-- APIs de Google por Private Service Connect"
ip=$(en_vm "getent hosts storage.googleapis.com | awk '{print \$1}' | head -1")
[ "$ip" = "10.0.200.10" ] && ok "storage.googleapis.com resuelve a $ip (PSC)" || bad "DNS de PSC devolvió '$ip'"

echo "-- Salida a Internet controlada"
code=$(en_vm "curl -sS -m 15 -o /dev/null -w '%{http_code}' https://pypi.org/simple/")
[ "$code" = "200" ] && ok "pypi.org permitido (HTTP $code)" || bad "pypi.org devolvió '$code'"
code=$(en_vm "curl -sS -m 15 -o /dev/null -w '%{http_code}' https://huggingface.co")
[ "$code" = "200" ] && ok "huggingface.co permitido (HTTP $code)" || bad "huggingface.co devolvió '$code'"
en_vm "curl -sS -m 10 -o /dev/null https://example.com" && bad "example.com debió bloquearse" || ok "example.com bloqueado por el firewall"

echo "-- CMEK"
TB="gs://${PROJECT}-cmek-$(date +%s)"
gcloud storage buckets create "$TB" --project="$PROJECT" --location="$REGION" --default-encryption-key="$KEY" --uniform-bucket-level-access >/dev/null
echo "dato de prueba" | gcloud storage cp - "$TB/dato.txt" >/dev/null
k=$(gcloud storage objects describe "$TB/dato.txt" --format='value(kms_key)')
echo "$k" | grep -q "cryptoKeys/storage" && ok "objeto cifrado con la llave CMEK storage" || bad "CMEK: '$k'"
gcloud storage rm -r "$TB" --quiet >/dev/null 2>&1

echo "-- Registro del bloqueo (puede tardar 1 a 2 minutos)"
for i in 1 2 3 4 5 6; do
  log=$(gcloud logging read 'logName:"compute.googleapis.com%2Ffirewall" AND jsonPayload.disposition="DENIED"' \
    --project="$PROJECT" --freshness=15m --limit=1 --format='value(jsonPayload.connection.dest_ip,jsonPayload.rule_details.priority)')
  [ -n "$log" ] && break; sleep 20
done
[ -n "$log" ] && ok "bloqueo registrado en los logs del firewall: $log" || bad "no apareció el log del bloqueo"
set -e

paso "7. Limpieza: VMs de prueba y HA VPN"
gcloud compute instances delete vm-hub vm-onprem --zone="$ZONE" --project="$PROJECT" --quiet >/dev/null && echo "  VMs borradas"
terraform apply -input=false -auto-approve -var "project_id=$PROJECT" -var "enable_hybrid=false" >/dev/null && echo "  HA VPN apagado"

paso "Resumen"
echo "Proyecto: $PROJECT"
echo "Resultado: $pass OK, $fail FALLA"
[ "$fail" -eq 0 ]
