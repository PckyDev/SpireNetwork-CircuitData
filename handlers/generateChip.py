import json
import re
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
ROOT_DIR = BASE_DIR.parent
CONFIG_PATH = ROOT_DIR / "ChipConfigs.json"
OUTPUT_PATH = ROOT_DIR / "test.sk"
VALID_PORT_GROUPS = ("static", "dynamic")
TYPE_DEFAULTS = {
    "bool": "false",
    "int": "0",
    "float": "0",
    "string": "''",
    "text": "''",
    "exec": "None",
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
    if not isinstance(type_names, list) or not type_names:
        return "object"

    normalized_types = []
    for type_name in type_names:
        if not isinstance(type_name, str):
            continue

        normalized_name = skript_type_name([type_name])
        if normalized_name not in normalized_types:
            normalized_types.append(normalized_name)

    if not normalized_types:
        return "object"

    if len(normalized_types) > 1:
        return "object"

    return normalized_types[0]


def format_parameter_type(type_names):
    normalized_type = format_type_comment(type_names)
    if normalized_type in {"bool", "int", "float", "string", "text", "vector"}:
        return normalized_type
    return "object"


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


def format_port_metadata(entry, direction_label):
    port_definition = entry["definition"]
    type_comment = format_type_comment(port_definition.get("types", []))
    return f"#   {direction_label} {entry['index']} | Type: {type_comment} | Name: {port_definition['name']}"


def default_return_for_type(type_names):
    type_name = coerce_type_name(type_names)
    if type_name == "vector3":
        return "vector(0, 0, 0)"
    return TYPE_DEFAULTS.get(type_name, "0")


def build_header_block(config_data, inputs, outputs):
    lines = [
        f"# Chip: {config_data['name']}",
        "# Ports:",
    ]

    for input_port in inputs:
        lines.append(format_port_metadata(input_port, "Input"))

    for output_port in outputs:
        lines.append(format_port_metadata(output_port, "Output"))

    lines.extend(
        [
            "",
            "# Required Libraries",
            "#   - None",
        ]
    )
    return lines


def build_function_block(chip_name, inputs, outputs):
    parameter_lines = []
    chip_identifier = slugify_path_part(chip_name).upper()

    for input_port in inputs:
        input_index = input_port["index"]
        port_definition = input_port["definition"]
        if "exec" in port_definition.get("types", []):
            continue

        parameter_type = format_parameter_type(port_definition.get("types", []))
        parameter_lines.append(f"input{input_index} : {parameter_type}")

    signature = ", ".join(parameter_lines)

    if signature:
        lines = [f"function CHIP_{chip_identifier}_TRIGGER({signature}):"]
    else:
        lines = [f"function CHIP_{chip_identifier}_TRIGGER():"]

    lines.append('    return "{error.not_implemented}"')
    return lines


def build_skript_content(config_data):
    port_group = config_data["ports"][0]
    inputs = expand_port_entries(port_group["inputs"])
    outputs = expand_port_entries(port_group["outputs"])

    lines = build_header_block(config_data, inputs, outputs)
    lines.append("")
    lines.append("variables:")
    lines.append("    _CHIP_VER = 1.0.0")
    lines.append("    _CURRENT_EXEC = None")
    lines.append("")
    lines.extend(build_function_block(config_data["name"], inputs, outputs))

    return "\n".join(lines).rstrip() + "\n"


def main():
    config_data = load_first_chip_config()
    OUTPUT_PATH.write_text(build_skript_content(config_data), encoding="utf-8")
    print(f"Created {OUTPUT_PATH.name} from chip '{config_data['name']}'")


if __name__ == "__main__":
    main()

