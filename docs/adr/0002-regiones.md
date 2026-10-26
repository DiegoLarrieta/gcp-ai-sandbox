# ADR-0002: Región principal y alterna

- Estado: Aceptado
- Fecha: 2026-10-26

## Contexto

El sandbox depende de GPU (L4, A100, H100), TPU y modelos Gemini. La oferta de estos recursos varía por región y las cuotas las aprueba Google.

## Decisión

- Región principal: `us-central1`, por tener la mayor oferta de GPU, TPU y modelos de Vertex AI.
- Región alterna: `us-east4`, solo para capacidad de GPU cuando no haya cuota en la principal.
- Ninguna otra región se permite. Se valida en las variables de Terraform y se aplicará con la org policy `gcp.resourceLocations` en la etapa 1.

## Consecuencias

- Los datasets y modelos se respaldan, pero el cómputo no es multirregión: se recrea con Terraform.
- La latencia desde México es aceptable para un entorno de experimentación.
- Si Google no aprueba cuota de H100 o TPU a tiempo, el plan sigue con L4 y A100 (ver registro de riesgos).
