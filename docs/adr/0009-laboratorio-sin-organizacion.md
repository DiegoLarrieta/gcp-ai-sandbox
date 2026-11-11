# ADR-0009: Laboratorio en un proyecto mientras no hay permisos de organización

- Estado: Aceptado
- Fecha: 2026-11-10

## Contexto

La cuenta disponible tiene créditos y puede crear proyectos, pero no tiene Organization Administrator en la organización. Sin ese rol no se pueden crear carpetas, org policies, Shared VPC, firewall jerárquico ni el perímetro VPC-SC.

## Decisión

- `labs/proyecto` despliega en un solo proyecto todo lo del Sprint 2 que no exige organización: VPC con las subredes del plan de IPs, Cloud NAT, firewall con lista de dominios, Private Service Connect (bundle `all-apis`), DNS privado, Private Service Access, HA VPN con BGP hacia un on-premises simulado, CMEK y Secret Manager.
- `scripts/desplegar-lab.sh` lo despliega y lo valida con VMs de prueba: VPN de punta a punta, salida a Internet permitida y bloqueada, DNS hacia PSC, CMEK y registro del bloqueo. Al final borra las VMs y apaga el VPN.
- Las etapas `1-org`, `2-security` y `3-networks` siguen siendo la versión objetivo y se validan con `terraform test`. Se aplican con `scripts/desplegar-sprint2.sh` en cuanto exista el rol de organización.

## Consecuencias

- El criterio "copiar datos fuera del perímetro VPC-SC falla y queda registrado" queda pendiente de demostrar en vivo.
- `scripts/borrar-lab.sh` elimina el laboratorio al cerrar el reto.
