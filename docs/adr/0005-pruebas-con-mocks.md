# ADR-0005: Estrategia de pruebas con mock_provider

- Estado: Aceptado
- Fecha: 2026-10-26

## Contexto

El Sprint 1 debe entregar el bootstrap y un pipeline funcionando, pero la cuenta de GCP con organización y facturación se abre hasta el Sprint 2. Además, probar contra GCP real en cada PR es lento y cuesta dinero.

## Decisión

Cuatro niveles de prueba:

| Nivel | Herramienta | Necesita GCP | Cuándo |
|---|---|---|---|
| Estático | `fmt`, `validate`, `tflint`, `checkov` | No | Cada PR |
| Políticas | Conftest sobre los YAML de equipos | No | Cada PR |
| Unitario | `terraform test` con `mock_provider` | No | Cada PR |
| Integración | Terratest en proyecto efímero | Sí | Nocturno, desde el Sprint 3 |

Los mocks usan el esquema real de los proveedores `google` y `google-beta`, pero no llaman a ninguna API. Los valores calculados se generan o se fijan en `tests/mocks/*.tfmock.hcl`.

Las pruebas requieren **Terraform 1.11 o superior** por `override_during`, que permite fijar valores calculados durante el plan. El código de las etapas sigue aceptando 1.9+. El pipeline usa 1.11.4.

Los recursos con `prevent_destroy` (la llave KMS del estado) se prueban solo con `command = plan`, porque `terraform test` destruye al final lo que aplica.

## Qué prueban los mocks

- Que la configuración es válida contra el esquema real del proveedor.
- La lógica de los módulos: `for_each`, nombres, etiquetas, condiciones de WIF, roles asignados.
- Validaciones de variables y precondiciones, incluyendo casos que deben fallar (`expect_failures`).

## Qué no prueban

- Que GCP acepte el cambio: permisos de IAM faltantes, APIs sin habilitar, cuotas, org policies que bloqueen un recurso.
- Formatos reales de atributos calculados (IDs, URLs).
- Tiempos de aprovisionamiento.

Eso lo cubren el primer apply real de cada etapa y, desde el Sprint 3, las pruebas de integración.

## Consecuencias

- El pipeline corre completo sin credenciales y sin costo.
- Un test en verde no garantiza un apply en verde; cada etapa se despliega de verdad al menos una vez en su sprint.
