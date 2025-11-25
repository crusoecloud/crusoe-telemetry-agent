from typing import Dict

AMD_EXPORTER_SOURCE_NAME = "amd_exporter_scrape"
DEFAULT_AMD_APP_LABEL = "metrics-exporter"


class AmdExporterManager:
    def __init__(self, cfg: Dict, fallback_interval: int):
        self.enabled = cfg.get("enabled", True)
        self.port = cfg.get("port", 5000)
        self.path = cfg.get("path", "/metrics")
        self.scrape_interval = cfg.get("scrape_interval", fallback_interval)
        self.app_label = DEFAULT_AMD_APP_LABEL

    def is_exporter_pod(self, pod) -> bool:
        labels = pod.metadata.labels or {}
        if not labels:
            return False
        return labels.get("app.kubernetes.io/name") == self.app_label

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
