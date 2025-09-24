import os, yaml, signal, argparse
from kubernetes import client, config, watch

running = True

class LiteralStr(str): pass

def literal_str_representer(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")

yaml.add_representer(LiteralStr, literal_str_representer)

NODEPOOL_TAG_SCRIPT = """if exists(.tags.Hostname) {
  parts, _ = split(.tags.Hostname, ".")
  host_prefix = get(parts, [0]) ?? ""
  prefix_parts, _ = split(host_prefix, "-")
  nodepool_id_parts, _ = slice(prefix_parts, 0, length(prefix_parts) - 1)
  .tags.nodepool, _ = join(nodepool_id_parts, "-")
}

"""

def handle_sigterm(sig, frame):
    global running
    running = False

def load_reloader_config(path):
    with open(path) as f:
        return yaml.safe_load(f)

def discover_endpoints(v1, node_name, cfg):
    dcgm_cfg = cfg["dcgm"]
    cm_cfg = cfg["custom_metrics"]

    dcgm_endpoint = None
    dynamic_endpoints = []

    # dcgm-exporter pod (1 per node)
    dcgm_pods = v1.list_namespaced_pod(
        namespace=dcgm_cfg["namespace"],
        label_selector=dcgm_cfg["label_selector"],
        field_selector=f"spec.nodeName={node_name},status.phase=Running",
    ).items
    if dcgm_pods:
        pod = dcgm_pods[0]
        if pod.status.pod_ip:
            dcgm_endpoint = f"{dcgm_cfg['scheme']}://{pod.status.pod_ip}:{dcgm_cfg['port']}{dcgm_cfg['path']}"

    # annotated pods
    pods = v1.list_pod_for_all_namespaces(
        field_selector=f"spec.nodeName={node_name},status.phase=Running"
    ).items
    for pod in pods:
        ann = pod.metadata.annotations or {}
        if ann.get(cm_cfg["annotation_key"], "false").lower() == "true":
            pod_ip = pod.status.pod_ip
            port = ann.get(f"{cm_cfg['annotation_key']}/port", cm_cfg["port"])
            path = ann.get(f"{cm_cfg['annotation_key']}/path", cm_cfg["path"])
            scheme = ann.get(f"{cm_cfg['annotation_key']}/scheme", cm_cfg["scheme"])
            if pod_ip:
                dynamic_endpoints.append(f"{scheme}://{pod_ip}:{port}{path}")

    return dcgm_endpoint, sorted(dynamic_endpoints)

def merge_config(base_cfg, dcgm_ep, dynamic_eps, cfg):
    dcgm_cfg = cfg["dcgm"]
    cm_cfg = cfg["custom_metrics"]

    cfg_out = dict(base_cfg)

    # sources
    if dcgm_ep:
        cfg_out.setdefault("sources", {})["dcgm_exporter_scrape"] = {
            "type": "prometheus_scrape",
            "endpoints": [dcgm_ep],
            "scrape_interval_secs": dcgm_cfg["scrape_interval"],
        }
    else:
        cfg_out.get("sources", {}).pop("dcgm_exporter_scrape", None)

    if dynamic_eps:
        cfg_out.setdefault("sources", {})["dynamic_scrapes"] = {
            "type": "prometheus_scrape",
            "endpoints": dynamic_eps,
            "scrape_interval_secs": cm_cfg["scrape_interval"],
        }
    else:
        cfg_out.get("sources", {}).pop("dynamic_scrapes", None)

    # transforms
    transforms = cfg_out.setdefault("transforms", {})
    if "add_update_labels" in transforms:
        transforms["enrich_node_metrics"] = transforms.pop("add_update_labels")

    if "enrich_node_metrics" in transforms:
        inputs = set(transforms["enrich_node_metrics"].get("inputs", []))
        inputs.add("host_metrics")
        if dcgm_ep:
            inputs.add("dcgm_exporter_scrape")
        else:
            inputs.discard("dcgm_exporter_scrape")
        transforms["enrich_node_metrics"]["inputs"] = sorted(inputs)

        transforms["enrich_node_metrics"]["source"] = LiteralStr(
                NODEPOOL_TAG_SCRIPT
                + """
.tags.cluster_id = "${CRUSOE_CLUSTER_ID}"
.tags.vm_id = "${VM_ID}"
.tags.crusoe_resource = "vm"
"""
        )

    if dynamic_eps:
        transforms["enrich_custom_metrics"] = {
            "type": "remap",
            "inputs": ["dynamic_scrapes"],
            "source": LiteralStr(NODEPOOL_TAG_SCRIPT + """
.tags.crusoe_resource = "custom_metrics"
"""),
        }
    else:
        transforms.pop("enrich_custom_metrics", None)

    # sinks
    sinks = cfg_out.setdefault("sinks", {})
    if dynamic_eps:
        sinks["cms_gateway_custom_metrics"] = {
            "type": "prometheus_remote_write",
            "inputs": ["enrich_custom_metrics"],
            "endpoint": "https://cms-monitoring.crusoecloud.com/ingest",
            "auth": {"strategy": "bearer", "token": "${CRUSOE_MONITORING_TOKEN}"},
            "healthcheck": {"enabled": False},
            "request": {
                "concurrency": "none",
                "rate_limit_duration_secs": 60,
                "rate_limit_num": 1,
            },
            "compression": "snappy",
            "tls": {"verify_certificate": True, "verify_hostname": True},
        }
    else:
        sinks.pop("cms_gateway_custom_metrics", None)

    return cfg_out

def write_config(dcgm_ep, dynamic_eps, last_state, cfg, base_config_path, vector_config_path):
    # Always write if config file does not exist yet
    if (dcgm_ep, dynamic_eps) == last_state and os.path.exists(vector_config_path):
        return last_state

    with open(base_config_path) as f:
        base_cfg = yaml.safe_load(f)

    final_cfg = merge_config(base_cfg, dcgm_ep, dynamic_eps, cfg)

    os.makedirs(os.path.dirname(vector_config_path), exist_ok=True)
    with open(vector_config_path, "w") as f:
        yaml.dump(final_cfg, f, sort_keys=False)

    print(f"[reloader] Updated vector.yaml (dcgm: {dcgm_ep}, dynamic: {dynamic_eps})")
    return dcgm_ep, dynamic_eps

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-config", default="/etc/vector-base/vector.yaml")
    parser.add_argument("--vector-config", default="/etc/vector/vector.yaml")
    parser.add_argument("--reloader-config", default="/etc/reloader/config.yaml")
    args = parser.parse_args()

    config.load_incluster_config()
    v1 = client.CoreV1Api()
    w = watch.Watch()

    cfg = load_reloader_config(args.reloader_config)

    node_name = os.environ.get("NODE_NAME")
    if not node_name:
        raise RuntimeError("NODE_NAME not set")

    signal.signal(signal.SIGINT, handle_sigterm)
    signal.signal(signal.SIGTERM, handle_sigterm)

    dcgm_ep, dynamic_eps = discover_endpoints(v1, node_name, cfg)
    last_state = write_config(dcgm_ep, dynamic_eps, (None, []), cfg, args.base_config, args.vector_config)

    while running:
        try:
            stream = w.stream(
                v1.list_pod_for_all_namespaces,
                field_selector=f"spec.nodeName={node_name}",
                timeout_seconds=60,
            )
            for event in stream:
                if not running:
                    break
                pod = event["object"]
                labels = pod.metadata.labels or {}
                ann = pod.metadata.annotations or {}
                if (
                        (pod.metadata.namespace == cfg["dcgm"]["namespace"] and
                         labels.get("app") == cfg["dcgm"]["label_selector"].split("=")[-1])
                        or (cfg["custom_metrics"]["annotation_key"] in ann)
                ):
                    dcgm_ep, dynamic_eps = discover_endpoints(v1, node_name, cfg)
                    last_state = write_config(dcgm_ep, dynamic_eps, last_state, cfg, args.base_config, args.vector_config)
        except Exception as e:
            print(f"Watch error: {e}, retrying...")

    print("Exiting reloader.")

if __name__ == "__main__":
    main()
