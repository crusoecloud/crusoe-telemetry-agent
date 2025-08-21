# Crusoe Telemetry Agent (Helm)

This chart generates a Crusoe Monitoring token via a Job and stores it in a Kubernetes Secret under crusoe-systems namespace.
It also deploys a dcgm exporter service as a Local NodePort service. 
It then deploys Vector using the generated token.

## Quickstart

```bash
helm dependency update crusoe-telemetry-agent
helm install crusoe-telemetry-agent ./crusoe-telemetry-agent -n crusoe-system -f ./crusoe-telemetry-agent/values-cpu.yaml
```

For GPU clusters:
```bash
helm install crusoe-telemetry-agent ./crusoe-telemetry-agent -n crusoe-system -f ./crusoe-telemetry-agent.values-gpu.yaml
```

If you need to re-run token generation on upgrade, simply run `helm upgrade` and the hook will execute again.