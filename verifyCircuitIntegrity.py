"""

SPIRE NETWORK

Purpose: Verify the integrity of the circuit by checking for any discrepancies or issues.

Last Update: 2026 / 04 / 16

"""

import json
import re
from datetime import datetime
from pathlib import Path

from handlers.generateChip import build_skript_content, slugify_path_part


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
NODE_DATA_DIR = DATA_DIR / "node"
CONFIG_CANDIDATES = (
    DATA_DIR / "ChipConfigs.json",
    BASE_DIR / "ChipConfigs.json",
)
REQUIRED_CONFIG_FLAGS = ("beta", "deprecated", "hidden", "dev")
VALID_PORT_GROUPS = ("static", "dynamic")
TYPE_DEFAULTS = {
    "bool": "false",
    "int": "0",
    "float": "0",
    "string": '',
    "text": '',
    "exec": "0",
}


def _resolve_config_file():
    for candidate in CONFIG_CANDIDATES:
        if candidate.exists():
            return candidate

    return CONFIG_CANDIDATES[0]


CONFIG_FILE = _resolve_config_file()


def grabCircuitData():

    """

    Loads the circuit configuration JSON and returns the decoded data.

    """

    with CONFIG_FILE.open("r", encoding="utf-8") as file:
        return json.load(file)


def _is_non_empty_string(value):
    return isinstance(value, str) and bool(value.strip())


def _slugify_path_part(value):
    return slugify_path_part(value)


def _coerce_type_name(type_names):
    if not isinstance(type_names, list) or not type_names:
        return "any"

    preferred_order = ("bool", "int", "float", "string", "text", "vector3", "exec")
    for preferred_type in preferred_order:
        if preferred_type in type_names:
            return preferred_type

    return type_names[0]


def _skript_type_name(type_names):
    type_name = _coerce_type_name(type_names)
    if type_name == "vector3":
        return "vector"
    return type_name


def _skript_type_names(type_names):
    if not isinstance(type_names, list):
        return []

    return [_skript_type_name([type_name]) for type_name in type_names if _is_non_empty_string(type_name)]


def _format_type_comment(type_names):
    normalized_types = _skript_type_names(type_names)
    return " | ".join(normalized_types) if normalized_types else "object"


def _format_port_metadata(entry, prefix):
    port_definition = entry["definition"]
    port_name = port_definition.get("name")
    if not _is_non_empty_string(port_name):
        port_name = f"{prefix.title()} {entry['index']}"
    type_comment = _format_type_comment(port_definition.get("types", []))

    metadata = f"# {prefix}{entry['index']} ({port_name}) [{entry['kind']}]: {type_comment}"
    if entry["kind"] == "dynamic":
        dynamic_rules = port_definition.get("dynamic", {})
        minimum = dynamic_rules.get("min")
        maximum = dynamic_rules.get("max")
        maximum_label = "unbounded" if maximum is None else str(maximum)
        metadata = f"{metadata} (min {minimum}, max {maximum_label})"

    return metadata


def _expand_port_entries(collection):
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


def _default_return_for_type(type_names):
    type_name = _coerce_type_name(type_names)
    if type_name == "vector3":
        return "vector(0, 0, 0)"
    if type_name == "exec":
        return "None"
    return TYPE_DEFAULTS.get(type_name, "0")


def _build_function_block(port_index, inputs, outputs):
    parameter_lines = []

    for input_port in inputs:
        index = input_port["index"]
        port_definition = input_port["definition"]
        if "exec" in port_definition.get("types", []):
            continue

        parameter_lines.append(f"port{index}: object")

    signature = f"function port{port_index}"
    if parameter_lines:
        signature = f"{signature}({', '.join(parameter_lines)}):"
    else:
        signature = f"{signature}():"

    lines = [signature]

    if outputs:
        return_value = _default_return_for_type(outputs[0]["definition"].get("types", []))
        lines.append(f"    return {return_value}")
        return lines

    lines.append("    return")
    return lines


def _validate_filter_paths(filter_paths, path_label, issues):
    if not isinstance(filter_paths, list) or not filter_paths:
        issues.append(f"{path_label}.filterPaths must be a non-empty list.")
        return

    for index, filter_path in enumerate(filter_paths):
        if not isinstance(filter_path, list) or not filter_path:
            issues.append(
                f"{path_label}.filterPaths[{index}] must be a non-empty list of category names."
            )
            continue

        for segment_index, segment in enumerate(filter_path):
            if not _is_non_empty_string(segment):
                issues.append(
                    f"{path_label}.filterPaths[{index}][{segment_index}] must be a non-empty string."
                )


def _validate_port_definition(port_definition, path_label, issues, require_dynamic_rules=False):
    if not isinstance(port_definition, dict):
        issues.append(f"{path_label} must be an object.")
        return

    name = port_definition.get("name")
    if name is not None and not isinstance(name, str):
        issues.append(f"{path_label}.name must be a string when provided.")

    if not _is_non_empty_string(port_definition.get("description")):
        issues.append(f"{path_label}.description must be a non-empty string.")

    types = port_definition.get("types")
    if not isinstance(types, list) or not types:
        issues.append(f"{path_label}.types must be a non-empty list.")
    else:
        for type_index, type_name in enumerate(types):
            if not _is_non_empty_string(type_name):
                issues.append(f"{path_label}.types[{type_index}] must be a non-empty string.")

    dynamic_rules = port_definition.get("dynamic")
    if require_dynamic_rules:
        if not isinstance(dynamic_rules, dict):
            issues.append(f"{path_label}.dynamic must be an object for dynamic ports.")
            return

        minimum = dynamic_rules.get("min")
        maximum = dynamic_rules.get("max")

        if not isinstance(minimum, int) or minimum < 1:
            issues.append(f"{path_label}.dynamic.min must be an integer greater than or equal to 1.")

        if maximum is not None and (not isinstance(maximum, int) or maximum < 1):
            issues.append(f"{path_label}.dynamic.max must be null or an integer greater than or equal to 1.")

        if isinstance(minimum, int) and isinstance(maximum, int) and maximum < minimum:
            issues.append(f"{path_label}.dynamic.max cannot be smaller than dynamic.min.")
    return TYPE_DEFAULTS.get(type_name, "0")


def _expand_port_definitions(collection):
    expanded_ports = []



def _build_circuit_data_block(inputs, outputs):
    lines = [
        "# ===================== #",
        "# Circuit Data",
        "# ===================== #",
        "# Inputs",
    ]

    if inputs:
        for input_port in inputs:
            lines.append(_format_port_metadata(input_port, "port"))
    else:
        lines.append("# None")

    lines.append("# -------------------- #")
    lines.append("# Outputs")

    if outputs:
        for output_port in outputs:
            lines.append(_format_port_metadata(output_port, "output"))
    else:
        lines.append("# None")

    lines.append("# ===================== #")
    return lines


def _build_function_block(port_index, inputs, outputs):
    parameter_lines = []

    for input_port in inputs:
        index = input_port["index"]
        port_definition = input_port["definition"]
        if "exec" in port_definition.get("types", []):
            continue

        parameter_lines.append(f"port{index}: object")

    signature = f"function port{port_index}"
    if parameter_lines:
        signature = f"{signature}({', '.join(parameter_lines)}):"
    else:
        signature = f"{signature}():"

    lines = [signature]

    if outputs:
        return_value = _default_return_for_type(outputs[0]["definition"].get("types", []))
        lines.append(f"    return {return_value}")
        return lines

    lines.append("    return")
    return lines


def _validate_filter_paths(filter_paths, path_label, issues):
    if not isinstance(filter_paths, list) or not filter_paths:
        issues.append(f"{path_label}.filterPaths must be a non-empty list.")
        return

    for index, filter_path in enumerate(filter_paths):
        if not isinstance(filter_path, list) or not filter_path:
            issues.append(
                f"{path_label}.filterPaths[{index}] must be a non-empty list of category names."
            )
            continue

        for segment_index, segment in enumerate(filter_path):
            if not _is_non_empty_string(segment):
                issues.append(
                    f"{path_label}.filterPaths[{index}][{segment_index}] must be a non-empty string."
                )


def _validate_port_definition(port_definition, path_label, issues, require_dynamic_rules=False):
    if not isinstance(port_definition, dict):
        issues.append(f"{path_label} must be an object.")
        return

    name = port_definition.get("name")
    if name is not None and not isinstance(name, str):
        issues.append(f"{path_label}.name must be a string when provided.")

    if not _is_non_empty_string(port_definition.get("description")):
        issues.append(f"{path_label}.description must be a non-empty string.")

    types = port_definition.get("types")
    if not isinstance(types, list) or not types:
        issues.append(f"{path_label}.types must be a non-empty list.")
    else:
        for type_index, type_name in enumerate(types):
            if not _is_non_empty_string(type_name):
                issues.append(f"{path_label}.types[{type_index}] must be a non-empty string.")

    dynamic_rules = port_definition.get("dynamic")
    if require_dynamic_rules:
        if not isinstance(dynamic_rules, dict):
            issues.append(f"{path_label}.dynamic must be an object for dynamic ports.")
            return

        minimum = dynamic_rules.get("min")
        maximum = dynamic_rules.get("max")

        if not isinstance(minimum, int) or minimum < 1:
            issues.append(f"{path_label}.dynamic.min must be an integer greater than or equal to 1.")

        if maximum is not None and (not isinstance(maximum, int) or maximum < 1):
            issues.append(f"{path_label}.dynamic.max must be null or an integer greater than or equal to 1.")

        if isinstance(minimum, int) and isinstance(maximum, int) and maximum < minimum:
            issues.append(f"{path_label}.dynamic.max cannot be smaller than dynamic.min.")


def _validate_port_collection(collection, path_label, issues):
    if not isinstance(collection, dict):
        issues.append(f"{path_label} must be an object.")
        return

    for group_name, port_definitions in collection.items():
        if group_name not in VALID_PORT_GROUPS:
            issues.append(f"{path_label}.{group_name} is not a valid port group.")
            continue

        if not isinstance(port_definitions, list):
            issues.append(f"{path_label}.{group_name} must be a list.")
            continue

        for index, port_definition in enumerate(port_definitions):
            _validate_port_definition(
                port_definition,
                f"{path_label}.{group_name}[{index}]",
                issues,
                require_dynamic_rules=group_name == "dynamic",
            )


def _validate_ports(ports, path_label, issues):
    if not isinstance(ports, list) or not ports:
        issues.append(f"{path_label}.ports must be a non-empty list.")
        return

    for index, port_group in enumerate(ports):
        port_group_label = f"{path_label}.ports[{index}]"
        if not isinstance(port_group, dict):
            issues.append(f"{port_group_label} must be an object.")
            continue

        if "inputs" in port_group:
            _validate_port_collection(port_group["inputs"], f"{port_group_label}.inputs", issues)

        if "outputs" in port_group:
            _validate_port_collection(port_group["outputs"], f"{port_group_label}.outputs", issues)


def _validate_config_entry(config_key, config_data, issues):
    config_label = f"configs.{config_key}"

    if not isinstance(config_data, dict):
        issues.append(f"{config_label} must be an object.")
        return

    name = config_data.get("name")
    if not _is_non_empty_string(name):
        issues.append(f"{config_label}.name must be a non-empty string.")
    elif name != config_key:
        issues.append(f"{config_label}.name must match its key '{config_key}'.")

    if not _is_non_empty_string(config_data.get("description")):
        issues.append(f"{config_label}.description must be a non-empty string.")

    for flag_name in REQUIRED_CONFIG_FLAGS:
        if not isinstance(config_data.get(flag_name), bool):
            issues.append(f"{config_label}.{flag_name} must be a boolean.")

    _validate_filter_paths(config_data.get("filterPaths"), config_label, issues)
    _validate_ports(config_data.get("ports"), config_label, issues)


def validateCircuitData(circuit_data):

    """

    Validates the decoded circuit data and returns a list of format issues.

    """

    issues = []

    if not isinstance(circuit_data, dict):
        return ["Root JSON value must be an object."]

    configs = circuit_data.get("configs")
    if not isinstance(configs, dict) or not configs:
        return ["configs must exist and be a non-empty object."]

    for config_key, config_data in configs.items():
        if not _is_non_empty_string(config_key):
            issues.append("Each configs key must be a non-empty string.")
            continue

        _validate_config_entry(config_key, config_data, issues)

    return issues


def _build_skript_content(config_data):
    timestamp = datetime.now().strftime("%Y %m %d %H:%M")
    lines = [
        "# ===================== #",
        f"# Chip: {config_data['name']}",
        "# Last Modified: 2026 04 16 ACDT",
        f"# Loaded: {timestamp} ACDT",
        "# ===================== #",
        "",
    ]

    generated_function_count = 0

    for port_group in config_data["ports"]:
        inputs = _expand_port_entries(port_group.get("inputs", {}))
        outputs = _expand_port_entries(port_group.get("outputs", {}))
        exec_inputs = [item for item in inputs if "exec" in item["definition"].get("types", [])]

        lines.extend(_build_circuit_data_block(inputs, outputs))
        lines.append("")

        if exec_inputs:
            for exec_input in exec_inputs:
                port_index = exec_input["index"]
                lines.extend(_build_function_block(port_index, inputs, outputs))
                lines.append("")
                generated_function_count += 1
        else:
            function_index = generated_function_count + 1
            lines.extend(_build_function_block(function_index, inputs, outputs))
            lines.append("")
            generated_function_count += 1

    return "\n".join(lines).rstrip() + "\n"


def _build_skript_paths(config_data):
    file_name = f"{_slugify_path_part(config_data['name'])}.sk"
    target_paths = []

    for filter_path in config_data["filterPaths"]:
        target_directory = NODE_DATA_DIR.joinpath(*(_slugify_path_part(part) for part in filter_path))
        target_paths.append(target_directory / file_name)

    return target_paths


def _build_cleanup_paths(config_data):
    file_stem = _slugify_path_part(config_data["name"])
    cleanup_paths = []

    for filter_path in config_data["filterPaths"]:
        slug_parts = [ _slugify_path_part(part) for part in filter_path ]
        cleanup_paths.extend(
            [
                DATA_DIR.joinpath(*slug_parts, f"{file_stem}.sk"),
                DATA_DIR.joinpath(*slug_parts, f"{file_stem}.ch"),
                NODE_DATA_DIR.joinpath(*slug_parts, f"{file_stem}.ch"),
            ]
        )

    return cleanup_paths


def _build_legacy_skript_paths(config_data):
    file_name = f"{_slugify_path_part(config_data['name'])}.sk"
    target_paths = []

    for filter_path in config_data["filterPaths"]:
        target_directory = DATA_DIR.joinpath(*(_slugify_path_part(part) for part in filter_path))
        target_paths.append(target_directory / file_name)

    return target_paths


def syncSkriptFiles(circuit_data):

    """

    Creates missing SK files from the verified circuit data without overwriting existing files.

    """

    created_files = []
    skipped_files = []

    for config_data in circuit_data["configs"].values():
        sk_content = build_skript_content(config_data)

        for target_path in _build_skript_paths(config_data):
            target_path.parent.mkdir(parents=True, exist_ok=True)
            if target_path.exists():
                skipped_files.append(target_path)
                continue

            target_path.write_text(sk_content, encoding="utf-8")
            created_files.append(target_path)

        for legacy_path in _build_cleanup_paths(config_data):
            if legacy_path.exists() and legacy_path not in created_files and legacy_path not in skipped_files:
                legacy_path.unlink()

    return created_files, skipped_files


def verifyCircuitIntegrity():

    """

    Verifies the integrity of the circuit by checking that the JSON is valid and properly formatted.

    """

    try:
        circuit_data = grabCircuitData()
    except FileNotFoundError:
        print(f"Circuit integrity verification failed.\n\nIssue found:\n- Missing file: {CONFIG_FILE.name}")
        return False
    except json.JSONDecodeError as error:
        print(
            "Circuit integrity verification failed.\n\n"
            f"Issue found:\n- Invalid JSON at line {error.lineno}, column {error.colno}: {error.msg}"
        )
        return False

    issues = validateCircuitData(circuit_data)

    if issues:
        print("Circuit integrity verification failed.\n\nThe following issues were found:")
        for issue in issues:
            print(f"- {issue}")
        return False

    created_files, skipped_files = syncSkriptFiles(circuit_data)

    print("Circuit integrity verified successfully.")
    print(
        f"Created {len(created_files)} SK files and skipped {len(skipped_files)} existing files "
        f"from {CONFIG_FILE.relative_to(BASE_DIR)}."
    )
    return True


if __name__ == "__main__":
    verifyCircuitIntegrity()
    