# Etapa 3: red

| Recurso | Detalle |
|---|---|
| Shared VPC | `vpc-hub` en net-hub; spokes ai-platform y ai-data |
| Subredes | según `docs/plan-ip.md`, con Private Google Access y flow logs |
| Salida | Cloud NAT con logs; firewall que solo permite dominios de paquetes y modelos (ADR-0008) |
| Aislamiento | firewall jerárquico en ai-sandbox que bloquea rangos de producción |
| APIs privadas | endpoint PSC `10.0.200.10` (bundle vpc-sc) y DNS privado para `googleapis.com` y `pkg.dev` |
| PSA | `10.0.64.0/20` para Vector Search y Cloud SQL |
| HA VPN | dos túneles con BGP hacia `vpc-onprem-sim`, solo con `enable_hybrid = true` |

Validación completa: `scripts/validar-sprint2.sh`.
