# ADR-0003: Estado remoto de Terraform

- Estado: Aceptado
- Fecha: 2026-10-26

## Contexto

Varias etapas y decenas de sandboxes comparten un pipeline. El estado contiene información sensible y no se puede perder.

## Decisión

- Un solo bucket de Cloud Storage en el proyecto semilla.
- Versionado activo y se conservan las últimas 10 versiones no actuales de cada archivo.
- Cifrado con CMEK: llave `tfstate` en Cloud KMS con rotación cada 90 días.
- Acceso uniforme a nivel bucket y prevención de acceso público forzada.
- Prefijos: `stages/<etapa>/` y `sandboxes/<equipo>/`.
- La etapa 0 arranca con estado local; tras su primer apply se migra al bucket que ella misma crea (`terraform init -migrate-state`).

## Consecuencias

- Recuperar un estado dañado es restaurar una versión anterior del objeto.
- Las cuentas de servicio de cada etapa pueden leer y escribir el bucket. Restringirlas a su propio prefijo con condiciones de IAM queda como mejora para el Sprint 2.
