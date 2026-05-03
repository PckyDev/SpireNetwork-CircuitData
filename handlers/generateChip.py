import json
import re
from datetime import datetime
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "ChipConfigs.json"
OUTPUT_PATH = BASE_DIR / "test.sk"
VALID_PORT_GROUPS = ("static", "dynamic")
TYPE_DEFAULTS = {
    "bool": "false",
    "int": "0",
    "float": "0",
    "string": "''",
    "text": "''",
    "exec": "None",
}
CONTENT = {
    "details": """
# ===================== #
# Chip: data.chip.name
# Last Modified: data.date.modification
# Created: data.date.creation
# ===================== #
""",
    "inputs": """
# data.port.index (data.port.name) (data.port.type) [ data.port.datatype ] (min data.port.min, max data.port.max)
""",
    "outputs": """
# data.port.index (data.port.name) (data.port.type) [ data.port.datatype ] (min data.port.min, max data.port.max)
""",
    "function": """
variables:
    version = "1.0.0"

execution = "port1"

function CHIP_data.chip.name(data.port.values):
    return 'TRIGGER.ERROR.NOT_IMPLEMENTED'
""",
}


def load_first_chip_config():
    with CONFIG_PATH.open("r", encoding="utf-8") as file:
        configs = json.load(file)["configs"]

    _, config_data = next(iter(configs.items()))
    return config_data


def slugify_path_part(value):
    normalized = re.sub(r"[^a-z0-9]+", "_", value.strip().lower())
    return normalized.strip("_") or "unnamed"


def coerce_type_name(type_names):
    if not isinstance(type_names, list) or not type_names:
        return "any"

    preferred_order = ("bool", "int", "float", "string", "text", "vector3", "exec")
    for preferred_type in preferred_order:
        if preferred_type in type_names:
            return preferred_type

    return type_names[0]


def skript_type_name(type_names):
    type_name = coerce_type_name(type_names)
    if type_name == "vector3":
        return "vector"
    return type_name


def format_type_comment(type_names):
    if not isinstance(type_names, list):
        return "object"

    normalized_types = [skript_type_name([type_name]) for type_name in type_names if isinstance(type_name, str)]
    return " | ".join(normalized_types) if normalized_types else "object"


def render_template(template, replacements):
    rendered = template.strip("\n")
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)
    return rendered


def expand_port_entries(collection):
    expanded_ports = []
    port_index = 1

    for group_name in VALID_PORT_GROUPS:
        for port_definition in collection.get(group_name, []):
            expanded_ports.append(
                {
                    "index": port_index,
                    "kind": group_name,
                    "definition": port_definition,
                }
            )
            port_index += 1

    return expanded_ports


def format_port_metadata(entry, prefix):
    port_definition = entry["definition"]
    type_comment = format_type_comment(port_definition.get("types", []))
    metadata = f"# {prefix}{entry['index']} ({port_definition['name']}) [{entry['kind']}]: {type_comment}"

    if entry["kind"] == "dynamic":
        dynamic_rules = port_definition.get("dynamic", {})
        minimum = dynamic_rules.get("min")
        maximum = dynamic_rules.get("max")
        maximum_label = "unbounded" if maximum is None else str(maximum)
        metadata = f"{metadata} (min {minimum}, max {maximum_label})"

    return metadata


def format_template_port_line(entry, template_key):
    port_definition = entry["definition"]
    dynamic_rules = port_definition.get("dynamic", {})
    minimum = dynamic_rules.get("min", "n/a")
    maximum = dynamic_rules.get("max", "n/a")
    maximum_label = "unbounded" if maximum is None else str(maximum)

    replacements = {
        "data.port.index": str(entry["index"]),
        "data.port.name": port_definition["name"],
        "data.port.type": entry["kind"],
        "data.port.datatype": format_type_comment(port_definition.get("types", [])),
        "data.port.min": str(minimum),
        "data.port.max": maximum_label,
    }
    return render_template(CONTENT[template_key], replacements)


def default_return_for_type(type_names):
    type_name = coerce_type_name(type_names)
    if type_name == "vector3":
        return "vector(0, 0, 0)"
    return TYPE_DEFAULTS.get(type_name, "0")


def build_circuit_data_block(inputs, outputs):
    lines = [
        "# ===================== #",
        "# Circuit Data",
        "# ===================== #",
        "# Inputs",
    ]

    if inputs:
        for input_port in inputs:
            lines.append(format_template_port_line(input_port, "inputs"))
    else:
        lines.append("# None")

    lines.append("# -------------------- #")
    lines.append("# Outputs")

    if outputs:
        for output_port in outputs:
            lines.append(format_template_port_line(output_port, "outputs"))
    else:
        lines.append("# None")

    lines.append("# =====================\n")
    return lines


def build_function_block(chip_name, port_index, inputs, outputs):
    parameter_lines = []
    chip_identifier = slugify_path_part(chip_name)

    for input_port in inputs:
        input_index = input_port["index"]
        port_definition = input_port["definition"]
        if "exec" in port_definition.get("types", []):
            continue

        parameter_lines.append(f"port{input_index}: object")

    parameter_value = ", ".join(parameter_lines)
    if not parameter_value:
        parameter_value = ""

    replacements = {
        "data.chip.name": chip_identifier,
        "data.port.values": parameter_value,
        "data.chip.name": chip_identifier,
        'execution = "port1"': f'execution = "port{port_index}"',
        "execution = 'port1'": f"execution = 'port{port_index}'",
    }
    return render_template(CONTENT["function"], replacements).splitlines()


def build_details_block(config_data, timestamp):
    replacements = {
        "data.chip.name": config_data["name"],
        "data.date.modification": timestamp,
        "data.date.creation": timestamp,
    }
    return render_template(CONTENT["details"], replacements).splitlines()


def build_skript_content(config_data):
    timestamp = datetime.now().strftime("%Y %m %d %H:%M")
    lines = build_details_block(config_data, timestamp)
    lines.append("")

    for port_group in config_data["ports"]:
        inputs = expand_port_entries(port_group["inputs"])
        outputs = expand_port_entries(port_group["outputs"])
        exec_inputs = [item for item in inputs if "exec" in item["definition"].get("types", [])]

        lines.extend(build_circuit_data_block(inputs, outputs))
        lines.append("")

        function_index = exec_inputs[0]["index"] if exec_inputs else 1
        lines.extend(build_function_block(config_data["name"], function_index, inputs, outputs))
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main():
    config_data = load_first_chip_config()
    OUTPUT_PATH.write_text(build_skript_content(config_data), encoding="utf-8")
    print(f"Created {OUTPUT_PATH.name} from chip '{config_data['name']}'")


if __name__ == "__main__":
    main()

