# ADR-0008: Salida a Internet, APIs privadas y conectividad híbrida

- Estado: Aceptado
- Fecha: 2026-11-10

## Contexto

Los sandboxes no tienen IP públicas y solo deben llegar a repositorios de paquetes y de modelos. Los datos de on-premises llegan por HA VPN. No contamos con un on-premises real para el reto.

## Decisión

- **Cloud NAT** regional para la salida, con registro de todas las conexiones.
- **Network firewall policy** en la VPC hub, evaluada antes que las reglas clásicas: permite tráfico interno, SSH solo desde IAP, salida HTTPS a una lista de dominios (`allowed_egress_fqdns`) y bloquea todo lo demás hacia Internet. Se usan reglas FQDN de Cloud NGFW en lugar de Secure Web Proxy por costo.
- **Firewall jerárquico** en la carpeta `ai-sandbox` que bloquea la salida hacia rangos de producción.
- **Private Service Connect** para las APIs de Google con el bundle `vpc-sc` en `10.0.200.10`. Las zonas privadas de DNS `googleapis.com` y `pkg.dev` resuelven a ese endpoint, así el tráfico a las APIs nunca sale a Internet y solo alcanza APIs compatibles con VPC-SC.
- **Private Service Access** en `10.0.64.0/20` para Vector Search y Cloud SQL (Sprints 3 y 4).
- **HA VPN** de dos túneles con BGP hacia un on-premises simulado (una segunda VPC `vpc-onprem-sim` con `172.16.0.0/24`). Se activa con `enable_hybrid = true` solo durante las pruebas, porque cuesta unos 0.10 USD por hora.

## Consecuencias

- Para conectar un on-premises real basta con reemplazar la VPC simulada por un `google_compute_external_vpn_gateway`; el resto del módulo no cambia.
- Agregar un dominio permitido es un PR sobre `allowed_egress_fqdns`, revisado como cualquier cambio.
