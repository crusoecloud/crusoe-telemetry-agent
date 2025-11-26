from typing import Dict

AMD_EXPORTER_SOURCE_NAME = "amd_exporter_scrape"
DEFAULT_AMD_APP_LABEL = "metrics-exporter"
AMD_LABEL_KEY = "app.kubernetes.io/name"
DEFAULT_AMD_NAMESPACE = "kube-amd-gpu"
DEFAULT_AMD_SCRAPE_INTERVAL = 60


class AmdExporterManager:
    def __init__(self, cfg: Dict):
        self.enabled = cfg.get("enabled", True)
        self.port = cfg.get("port", 5000)
        self.path = cfg.get("path", "/metrics")
        self.scrape_interval = cfg.get("scrape_interval", DEFAULT_AMD_SCRAPE_INTERVAL)
        self.app_label = DEFAULT_AMD_APP_LABEL
        self.namespace = DEFAULT_AMD_NAMESPACE

    def is_exporter_pod(self, pod) -> bool:
        labels = pod.metadata.labels or {}
        if not labels:
            return False
        return (
                pod.metadata.namespace == self.namespace
                and labels.get(AMD_LABEL_KEY) == self.app_label
        )

    def build_endpoint(self, pod_ip: str) -> str:
        return f"http://{pod_ip}:{self.port}{self.path}"

    def set_scrape(self, vector_cfg: dict, endpoint: str, transform_name: str, timeout_percentage: float):
        if not endpoint:
            return
        vector_cfg.setdefault("sources", {})[AMD_EXPORTER_SOURCE_NAME] = {
            "type": "prometheus_scrape",
            "endpoints": [endpoint],
            "scrape_interval_secs": self.scrape_interval,
            "scrape_timeout_secs": int(self.scrape_interval * timeout_percentage),
        }
        inputs = set(vector_cfg["transforms"][transform_name]["inputs"])
        if AMD_EXPORTER_SOURCE_NAME not in inputs:
            vector_cfg["transforms"][transform_name]["inputs"].append(AMD_EXPORTER_SOURCE_NAME)

    def remove_scrape(self, vector_cfg: dict, transform_name: str):
        vector_cfg.get("sources", {}).pop(AMD_EXPORTER_SOURCE_NAME, None)
        inputs = set(vector_cfg["transforms"][transform_name].get("inputs", []))
        inputs.discard(AMD_EXPORTER_SOURCE_NAME)
        vector_cfg["transforms"][transform_name]["inputs"] = sorted(inputs)
