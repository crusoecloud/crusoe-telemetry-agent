# Crusoe Telemetry Agent (Helm)

This chart generates a Crusoe Monitoring token via a Job and stores it in a Kubernetes Secret under crusoe-systems namespace.
It also deploys a dcgm exporter service as a Local NodePort service. 
It then deploys Vector using the generated token.

## Quickstart

```bash
helm dependency update helm-charts/
helm install crusoe-telemetry-agent ./helm-charts -n crusoe-system -f ./helm-charts/values-cpu.yaml
```

For GPU clusters:
```bash
helm install crusoe-telemetry-agent ./helm-charts -n crusoe-system -f ./helm-charts/values-gpu.yaml
```

If you need to re-run token generation on upgrade, simply run `helm upgrade` and the hook will execute again.