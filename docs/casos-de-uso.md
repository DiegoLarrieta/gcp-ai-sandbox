# Casos de uso

El sandbox debe permitir que un equipo pase de una idea a un prototipo de IA funcionando en días, con costo acotado y sin tocar producción.

## Objetivos medibles

| # | Objetivo | Cómo se mide |
|---|---|---|
| 1 | Sandbox nuevo en menos de 30 minutos con un PR | Duración del job de apply en `5-sandboxes` |
| 2 | Plataforma completa desde cero con un solo pipeline | Etapas 0 a 4 sin pasos manuales fuera del bootstrap; un segundo plan reporta cero cambios |
| 3 | Ningún sandbox supera su presupuesto | Alertas al 50, 80 y 100 %; apagado automático de GPU al 100 % |
| 4 | Cero datos productivos sin anonimizar | Escaneo de Sensitive Data Protection sobre la zona curated |

## Casos de uso soportados

| Caso | Ejemplo | Servicios principales | Sprint en que se habilita |
|---|---|---|---|
| IA generativa con modelos administrados | Asistente interno que responde con documentos de la empresa (RAG) | Gemini en Vertex AI, Vector Search, Cloud Storage | 4 |
| Modelos abiertos | Probar y comparar Llama, Gemma o Mistral | Model Garden, endpoints de Vertex AI, GKE con GPU | 3 y 4 |
| Ajuste fino | Adaptar un modelo al lenguaje del negocio | Vertex AI Training, GPU L4 o A100 Spot | 3 |
| ML clásico | Pronóstico de demanda, clasificación | BigQuery ML, Vertex AI Training, Workbench | 3 |
| Agentes | Agente que consulta APIs internas | Vertex AI Agent Builder, Cloud Run | 4 |
| Evaluación de modelos | Medir calidad y seguridad antes de producción | Vertex AI Evaluation, Experiments | 4 |

## Caso piloto

El acta de aceptación se firma cuando el equipo piloto completa este flujo dentro de su sandbox:

1. Pide su sandbox con un archivo YAML y un PR.
2. Carga documentos anonimizados en la zona curated.
3. Construye un asistente RAG con Gemini y Vector Search.
4. Ajusta un modelo pequeño en GPU Spot y lo registra en Model Registry.
5. Sirve un modelo abierto de Model Garden en un endpoint privado.
6. Comprueba que los controles funcionan: modelo no permitido rechazado, Model Armor bloquea inyección de prompts, copia fuera del perímetro VPC-SC falla, presupuesto agotado apaga GPU.

Equipo piloto propuesto: **analitica** (archivo `stages/5-sandboxes/teams/analitica.yaml`).

## Roles

| Rol | Puede | No puede |
|---|---|---|
| Científico de datos | Usar Workbench, entrenar, desplegar endpoints en su sandbox | Leer la zona raw; crear redes o cambiar IAM |
| Ingeniero ML | Lo anterior más administrar GKE con GPU y pipelines del equipo | Exceder cuotas o presupuesto asignado |
| Líder de equipo | Solicitar sandboxes, ampliar presupuesto dentro de su límite | Aprobar sus propios cambios en producción |
| Equipo de plataforma | Administrar la base y los módulos de Terraform | Acceder a los datos de los equipos |

## Fuera del alcance

- Desarrollo de los casos de uso o de modelos de negocio.
- Paso a producción de modelos (solo se especifica la interfaz de salida).
- Contratación de capacidad reservada de GPU o TPU.
