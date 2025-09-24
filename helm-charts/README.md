# Crusoe Telemetry Agent (Helm)

This chart generates a Crusoe Monitoring token via a Job and stores it in a Kubernetes Secret under crusoe-systems namespace.
It then deploys the vector agent.

## Quickstart

```bash
helm dependency update crusoe-telemetry-agent
helm install crusoe-telemetry-agent ./ -n crusoe-system -f values.yaml
```