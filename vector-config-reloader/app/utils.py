import yaml

class LiteralStr(str): pass

def literal_str_representer(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")

class YamlUtils:
    def __init__(self):
        yaml.add_representer(LiteralStr, literal_str_representer)

    def load_yaml_config(self, path: str) -> dict:
        with open(path) as f:
            cfg = dict(yaml.safe_load(f))
        return cfg

    def save_yaml(self, path: str, cfg: dict):
        with open(path, "w") as f:
            yaml.safe_dump(cfg, f)
