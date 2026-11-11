#!/usr/bin/env bash
# Validación del Sprint 2 (hito: perímetro y red validados).
# Se corre en Cloud Shell con un usuario incluido en admin_members.
#
#   ./scripts/validar-sprint2.sh <seed_project> <ai_data_project> <security_project> <net_hub_project> <logging_project>
#
# Cada prueba imprime OK o FALLA. Las que deben ser bloqueadas cuentan como
# OK cuando GCP las rechaza.
set -uo pipefail

SEED=$1; AIDATA=$2; SEC=$3; HUB=$4; LOGS=$5
REGION=us-central1
RUN=$(date +%s)
IN="gs://${AIDATA}-vpcsc-${RUN}"
OUT="gs://${SEED}-fuera-${RUN}"
KEY="projects/${SEC}/locations/${REGION}/keyRings/ai-sandbox-${REGION}/cryptoKeys/storage"
pass=0; fail=0
ok()   { echo "  OK    $1"; pass=$((pass+1)); }
bad()  { echo "  FALLA $1"; fail=$((fail+1)); }
debe_fallar() { local nombre=$1; shift; if out=$("$@" 2>&1); then bad "$nombre (se permitió)"; else echo "$out" | tail -2 | sed 's/^/        /'; ok "$nombre"; fi; }

echo "== 1. Perímetro VPC Service Controls"
gcloud storage buckets create "$IN" --project="$AIDATA" --location="$REGION" --default-encryption-key="$KEY" --uniform-bucket-level-access >/dev/null \
  && ok "bucket CMEK dentro del perímetro (ai-data)" || bad "crear bucket dentro del perímetro"
echo "dato de prueba $RUN" | gcloud storage cp - "$IN/dato.txt" >/dev/null && ok "escribir dentro del perímetro" || bad "escribir dentro del perímetro"
gcloud storage buckets create "$OUT" --project="$SEED" --location="$REGION" --uniform-bucket-level-access >/dev/null \
  && ok "bucket fuera del perímetro (seed)" || bad "crear bucket fuera del perímetro"
debe_fallar "copiar datos fuera del perímetro es bloqueado" gcloud storage cp "$IN/dato.txt" "$OUT/robado.txt"

echo "== 2. CMEK obligatorio en ai-sandbox"
debe_fallar "bucket sin CMEK en ai-data es rechazado" gcloud storage buckets create "gs://${AIDATA}-sincmek-${RUN}" --project="$AIDATA" --location="$REGION"

echo "== 3. Org policies"
debe_fallar "bucket en Europa es rechazado (gcp.resourceLocations)" gcloud storage buckets create "gs://${AIDATA}-eu-${RUN}" --project="$AIDATA" --location=europe-west1 --default-encryption-key="$KEY"
debe_fallar "llave de cuenta de servicio es rechazada" bash -c "gcloud iam service-accounts create sbx-prueba-$RUN --project=$HUB >/dev/null 2>&1; gcloud iam service-accounts keys create /tmp/k.json --iam-account=sbx-prueba-$RUN@$HUB.iam.gserviceaccount.com --project=$HUB"
gcloud iam service-accounts delete "sbx-prueba-$RUN@$HUB.iam.gserviceaccount.com" --project="$HUB" --quiet >/dev/null 2>&1

echo "== 4. Registro de la violación (puede tardar 1 a 2 minutos)"
for i in 1 2 3 4 5 6; do
  hits=$(gcloud logging read 'protoPayload.metadata.@type="type.googleapis.com/google.cloud.audit.VpcServiceControlAuditMetadata"' \
    --project="$AIDATA" --freshness=15m --limit=5 --format='value(protoPayload.metadata.violationReason)' 2>/dev/null | head -1)
  [ -n "$hits" ] && break; sleep 20
done
[ -n "$hits" ] && ok "violación registrada en ai-data: $hits" || bad "no apareció el registro de la violación"
central=$(gcloud logging read 'protoPayload.metadata.@type="type.googleapis.com/google.cloud.audit.VpcServiceControlAuditMetadata"' \
  --project="$LOGS" --bucket=audit-logs --location="$REGION" --view=_AllLogs --freshness=15m --limit=1 --format='value(timestamp)' 2>/dev/null)
[ -n "$central" ] && ok "violación también en el bucket central audit-logs" || echo "  AVISO aún no llega al bucket central (el sink puede tardar)"

echo "== 5. Red"
gcloud compute networks describe vpc-hub --project="$HUB" --format='value(name)' >/dev/null && ok "VPC hub existe" || bad "VPC hub"
gcloud compute shared-vpc associated-projects list "$HUB" --format='value(RESOURCE_ID)' | sed 's/^/        spoke: /'
[ "$(gcloud compute forwarding-rules describe pscvpcsc --global --project="$HUB" --format='value(IPAddress)')" = "10.0.200.10" ] && ok "endpoint PSC 10.0.200.10 (bundle vpc-sc)" || bad "endpoint PSC"
gcloud compute routers nats describe "nat-$REGION" --router="cr-nat-$REGION" --region="$REGION" --project="$HUB" --format='value(name)' >/dev/null && ok "Cloud NAT" || bad "Cloud NAT"
if gcloud compute vpn-tunnels list --project="$HUB" --format='value(name)' | grep -q tunnel-hub; then
  for t in tunnel-hub-0 tunnel-hub-1; do
    st=$(gcloud compute vpn-tunnels describe "$t" --region="$REGION" --project="$HUB" --format='value(status)')
    [ "$st" = "ESTABLISHED" ] && ok "HA VPN $t ESTABLISHED" || bad "HA VPN $t $st"
  done
  up=$(gcloud compute routers get-status cr-vpn-hub --region="$REGION" --project="$HUB" --format='value(result.bgpPeerStatus[].status)')
  echo "        BGP: $up"
  echo "$up" | grep -qv DOWN && ok "sesiones BGP arriba" || bad "BGP"
else
  echo "  AVISO HA VPN no desplegado (enable_hybrid = false)"
fi

echo "== Limpieza"
gcloud storage rm -r "$IN" "$OUT" --quiet >/dev/null 2>&1 && echo "  buckets de prueba borrados"

echo
echo "Resultado: $pass OK, $fail FALLA"
[ "$fail" -eq 0 ]
