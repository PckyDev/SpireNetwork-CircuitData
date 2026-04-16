"""

SPIRE NETWORK

Purpose: Verify the integrity of the circuit by checking for any discrepancies or issues.

Last Update: 2026 / 04 / 16

"""

import json
from pathlib import Path


CONFIG_FILE = Path(__file__).with_name("ChipConfigs.json")
REQUIRED_CONFIG_FLAGS = ("beta", "deprecated", "hidden", "dev")
VALID_PORT_GROUPS = ("static", "dynamic")


def grabCircuitData():

    """

    Loads the circuit configuration JSON and returns the decoded data.

    """

    with CONFIG_FILE.open("r", encoding="utf-8") as file:
        return json.load(file)


def _is_non_empty_string(value):
    return isinstance(value, str) and bool(value.strip())


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

    if not _is_non_empty_string(port_definition.get("name")):
        issues.append(f"{path_label}.name must be a non-empty string.")

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

    if not any(group_name in collection for group_name in VALID_PORT_GROUPS):
        issues.append(f"{path_label} must include at least one of: {', '.join(VALID_PORT_GROUPS)}.")

    for group_name, port_definitions in collection.items():
        if group_name not in VALID_PORT_GROUPS:
            issues.append(f"{path_label}.{group_name} is not a valid port group.")
            continue

        if not isinstance(port_definitions, list) or not port_definitions:
            issues.append(f"{path_label}.{group_name} must be a non-empty list.")
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

        if "inputs" not in port_group:
            issues.append(f"{port_group_label}.inputs is required.")
        else:
            _validate_port_collection(port_group["inputs"], f"{port_group_label}.inputs", issues)

        if "outputs" not in port_group:
            issues.append(f"{port_group_label}.outputs is required.")
        else:
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

    print("Circuit integrity verified successfully.")
    return True


if __name__ == "__main__":
    verifyCircuitIntegrity()
    