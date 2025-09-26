# Crusoe Telemetry Agent (Helm)
This chart:
1. runs a job to generate and store a monitoring token.
2. deploys vector.dev based telemetry agent with a vector-config-reloader container.

## Quickstart

```bash
helm repo add crusoe https://crusoecloud.github.io/crusoe-telemetry-agent/helm-charts
helm repo update
helm install crusoe crusoe/crusoe-telemetry-agent
```