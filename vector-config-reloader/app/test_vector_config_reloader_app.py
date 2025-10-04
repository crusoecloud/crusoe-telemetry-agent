import yaml
import pytest

@pytest.fixture
def sample_reloader_config():
    return {
        "dcgm": {
            "namespace": "nvidia-gpu-operator",
            "label_selector": "app=nvidia-dcgm-exporter",
            "port": 9400,
            "path": "/metrics",
            "scheme": "http",
            "scrape_interval": 30,
        },
        "custom_metrics": {
            "port": 9100,
            "path": "/metrics",
            "scheme": "http",
            "scrape_interval": 30,
            "annotation_key": "vector.scrape",
        },
    }


@pytest.fixture
def base_vector_config(tmp_path):
    """Create a fake base vector config file."""
    base_cfg = {
        "sources": {
            "host_metrics": {"type": "host_metrics"}
        },
        "transforms": {
            "add_update_labels": {
                "type": "remap",
                "inputs": ["host_metrics"],
                "source": ".tags.cluster_id = \"${CRUSOE_CLUSTER_ID}\""
            }
        },
        "sinks": {
            "cms_gateway_node_metrics": {
                "type": "prometheus_remote_write",
                "inputs": ["add_update_labels"],
                "endpoint": "https://cms-monitoring.crusoecloud.com/ingest"
            }
        }
    }

    base_file = tmp_path / "vector.yaml"
    with open(base_file, "w") as f:
        yaml.dump(base_cfg, f)

    out_file = tmp_path / "out_vector.yaml"
    return str(base_file), str(out_file)


class DummyPod:
    def __init__(self, name, ns, ip=None, labels=None, ann=None, phase="Running"):
        self.metadata = type("M", (), {})()
        self.metadata.name = name
        self.metadata.namespace = ns
        self.metadata.annotations = ann or {}
        self.metadata.labels = labels or {}
        self.status = type("S", (), {})()
        self.status.phase = phase
        self.status.pod_ip = ip


class DummyClient:
    def __init__(self, pods):
        self._pods = pods

    def list_namespaced_pod(self, namespace, **kwargs):
        return type("R", (), {"items": [p for p in self._pods if p.metadata.namespace == namespace]})

    def list_pod_for_all_namespaces(self, **kwargs):
        return type("R", (), {"items": self._pods})


def load_cfg(path):
    with open(path) as f:
        return yaml.safe_load(f)
