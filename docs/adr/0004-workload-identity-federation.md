# ADR-0004: Autenticación del pipeline con Workload Identity Federation

- Estado: Aceptado
- Fecha: 2026-10-26

## Contexto

El pipeline de GitHub Actions necesita crear recursos en GCP. Las llaves JSON de cuentas de servicio se filtran con facilidad y el reto prohíbe usarlas.

## Decisión

- Un Workload Identity Pool `github` en el proyecto semilla, con un proveedor OIDC que confía en `https://token.actions.githubusercontent.com`.
- Condición del proveedor sobre el claim `sub`: solo se aceptan tokens del repo del proyecto emitidos desde la rama `main` o desde un pull request. Otras ramas y forks no obtienen credenciales.
- Una cuenta de servicio por etapa (`sa-org`, `sa-security`, `sa-networks`, `sa-ai-platform`, `sa-sandboxes`). El repo puede suplantar cada una con `roles/iam.workloadIdentityUser`.
- Ninguna cuenta tiene `roles/owner` ni `roles/editor`; las pruebas lo verifican.
- La org policy `iam.disableServiceAccountKeyCreation` se aplicará en la etapa 1.

## Consecuencias

- No hay ningún secreto de GCP guardado en GitHub; solo dos variables públicas: el nombre del proveedor y el correo de la cuenta de servicio.
- Un fork del repo no puede autenticarse.
- Los roles de cada cuenta están a nivel organización en el Sprint 1 por simplicidad; en el Sprint 2 se acotan a carpeta cuando existan `common` y `ai-sandbox`.
