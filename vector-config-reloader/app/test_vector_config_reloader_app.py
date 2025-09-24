import yaml, os
import pytest
import vector_config_reloader_app as reloader


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


def test_no_pods(base_vector_config, sample_reloader_config):
    base_file, out_file = base_vector_config
    v1 = DummyClient([])

    dcgm_ep, dyn_eps = reloader.discover_endpoints(v1, "test-node", sample_reloader_config)
    assert dcgm_ep is None
    assert dyn_eps == []

    # Call write_config (should always produce a file now)
    reloader.write_config(dcgm_ep, dyn_eps, (None, []), sample_reloader_config, base_file, out_file)

    assert os.path.exists(out_file), "Expected base config file to be written even when no pods found"

    out_cfg = load_cfg(out_file)

    # Verify no dcgm/dynamic scrapes or custom transforms/sinks were added
    assert "dcgm_exporter_scrape" not in out_cfg.get("sources", {})
    assert "dynamic_scrapes" not in out_cfg.get("sources", {})
    assert "enrich_custom_metrics" not in out_cfg.get("transforms", {})
    assert "cms_gateway_custom_metrics" not in out_cfg.get("sinks", {})



def test_dcgm_pod_present(base_vector_config, sample_reloader_config):
    base_file, out_file = base_vector_config
    pods = [DummyPod("dcgm1", "nvidia-gpu-operator", ip="10.1.1.1", labels={"app": "nvidia-dcgm-exporter"})]
    v1 = DummyClient(pods)

    dcgm_ep, dyn_eps = reloader.discover_endpoints(v1, "test-node", sample_reloader_config)
    assert dcgm_ep == "http://10.1.1.1:9400/metrics"

    reloader.write_config(dcgm_ep, dyn_eps, (None, []), sample_reloader_config, base_file, out_file)
    out_cfg = load_cfg(out_file)

    assert "dcgm_exporter_scrape" in out_cfg["sources"]
    assert "dcgm_exporter_scrape" in out_cfg["transforms"]["enrich_node_metrics"]["inputs"]


def test_custom_metrics_pod_present(base_vector_config, sample_reloader_config):
    base_file, out_file = base_vector_config
    pods = [DummyPod("mypod", "default", ip="10.2.2.2", ann={"vector.scrape": "true"})]
    v1 = DummyClient(pods)

    dcgm_ep, dyn_eps = reloader.discover_endpoints(v1, "test-node", sample_reloader_config)
    assert dyn_eps == ["http://10.2.2.2:9100/metrics"]

    reloader.write_config(dcgm_ep, dyn_eps, (None, []), sample_reloader_config, base_file, out_file)
    out_cfg = load_cfg(out_file)

    assert "dynamic_scrapes" in out_cfg["sources"]
    assert "enrich_custom_metrics" in out_cfg["transforms"]
    assert "cms_gateway_custom_metrics" in out_cfg["sinks"]


def test_both_pod_types(base_vector_config, sample_reloader_config):
    base_file, out_file = base_vector_config
    pods = [
        DummyPod("dcgm1", "nvidia-gpu-operator", ip="10.1.1.1", labels={"app": "nvidia-dcgm-exporter"}),
        DummyPod("mypod", "default", ip="10.2.2.2", ann={"vector.scrape": "true"})
    ]
    v1 = DummyClient(pods)

    dcgm_ep, dyn_eps = reloader.discover_endpoints(v1, "test-node", sample_reloader_config)
    assert dcgm_ep and dyn_eps

    reloader.write_config(dcgm_ep, dyn_eps, (None, []), sample_reloader_config, base_file, out_file)
    out_cfg = load_cfg(out_file)

    assert "dcgm_exporter_scrape" in out_cfg["sources"]
    assert "dynamic_scrapes" in out_cfg["sources"]
    assert "enrich_node_metrics" in out_cfg["transforms"]
    assert "enrich_custom_metrics" in out_cfg["transforms"]
    assert "cms_gateway_custom_metrics" in out_cfg["sinks"]
