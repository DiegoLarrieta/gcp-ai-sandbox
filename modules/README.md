# Módulos

Módulos reutilizables que consumen las etapas. Se agregan a partir del Sprint 2, cada uno con su carpeta `tests/` y pruebas con `mock_provider`.

| Módulo | Sprint | Qué hace |
|---|---|---|
| `project-factory` | 2 | Proyecto con APIs, etiquetas y facturación |
| `network-hub`, `network-spoke` | 2 | Shared VPC, subredes, NAT, DNS |
| `firewall`, `kms`, `vpc-sc` | 2 | Firewall jerárquico, CMEK, perímetro |
| `hybrid-connectivity` | 2 | HA VPN con BGP |
| `observability` | 2 | Sinks de logs y tableros |
| `data-lake`, `dlp-pipeline` | 3 | Zonas raw y curated, anonimización |
| `gke-gpu`, `tpu`, `workbench` | 3 | Cómputo acelerado y entornos de trabajo |
| `vertex-models`, `vertex-training`, `vertex-endpoints` | 4 | Gemini, Model Garden, entrenamiento y servicio |
| `vector-search`, `agents`, `mlops` | 4 | RAG, agentes, pipelines y registro |
| `ai-guardrails` | 4 | Model Armor y registro de peticiones |
| `cost-guard` | 5 | Presupuestos con apagado automático |

Convención: versionado semántico con tags `modules/<nombre>/vX.Y.Z`.
