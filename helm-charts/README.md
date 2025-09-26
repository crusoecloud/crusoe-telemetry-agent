# Crusoe Telemetry Agent (Helm)
This chart:
1. runs a job to generate and store a monitoring token.
2. deploys vector.dev based telemetry agent with a vector-config-reloader container.

## Quickstart

```bash
helm repo add crusoe-telemetry-agent https://crusoecloud.github.io/crusoe-telemetry-agent/helm-charts
helm repo update
helm install crusoe-telemetry-agent crusoe-telemetry-agent/crusoe-telemetry-agent --namespace crusoe-system
```
