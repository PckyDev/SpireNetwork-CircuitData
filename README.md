# SpireNetwork-CircuitData

This repository stores chip definitions in JSON and generated Skript-style `.sk` files under `data/node/`.

## Chip Data Overview

Chip definitions live in `ChipConfigs.json` under the top-level `configs` object. Each entry in `configs` is one chip definition keyed by its chip name.

Example shape:

```json
{
	"configs": {
		"If": {
			"name": "If",
			"description": "Executes one of two execution outputs based on the value of the input condition.",
			"beta": false,
			"deprecated": false,
			"hidden": false,
			"dev": false,
			"filterPaths": [["Logic", "Flow Control"]],
			"ports": [
				{
					"inputs": {
						"static": [
							{
								"name": "Run",
								"types": ["exec"],
								"description": "The execution input to trigger the condition check"
							}
						]
					},
					"outputs": {
						"static": [
							{
								"name": "Then",
								"types": ["exec"],
								"description": "The execution output if the condition is true"
							}
						]
					}
				}
			]
		}
	}
}
```

## Required Chip Fields

Each chip entry should contain these properties:

| Field | Type | Notes |
| --- | --- | --- |
| `name` | `string` | Must match the chip key in `configs`. |
| `description` | `string` | Human-readable description of the chip. |
| `beta` | `boolean` | Marks the chip as beta. |
| `deprecated` | `boolean` | Marks the chip as deprecated. |
| `hidden` | `boolean` | Controls visibility. |
| `dev` | `boolean` | Marks the chip as development-only. |
| `filterPaths` | `string[][]` | Category path segments used to place generated files. |
| `ports` | `object[]` | One or more port-group definitions. |

## `filterPaths`

`filterPaths` is a list of category paths. Each category path is itself a list of strings.

Example:

```json
"filterPaths": [["Logic", "Conditional Logic"]]
```

This path is slugified into a folder path under `data/node/`, for example:

```text
data/node/logic/conditional_logic/
```

## Port Groups

Each item in `ports` contains:

```json
{
	"inputs": {
		"static": [],
		"dynamic": []
	},
	"outputs": {
		"static": [],
		"dynamic": []
	}
}
```

Only two port groups are valid:

| Group | Meaning |
| --- | --- |
| `static` | Fixed number of ports. |
| `dynamic` | Variable number of ports with min/max rules. |

At least one valid port group must exist in each `inputs` and `outputs` collection.

## Port Definition Schema

Each port definition contains:

| Field | Type | Notes |
| --- | --- | --- |
| `name` | `string` | Display name used in generated metadata. |
| `description` | `string` | Human-readable description. |
| `types` | `string[]` | One or more allowed data types. |
| `dynamic` | `object` | Required only for ports inside the `dynamic` group. |

Dynamic ports require:

```json
"dynamic": {
	"min": 2,
	"max": null
}
```

Rules:

1. `min` must be an integer greater than or equal to `1`.
2. `max` must be `null` or an integer greater than or equal to `1`.
3. If `max` is an integer, it cannot be smaller than `min`.

## Supported Type Names

The current tooling recognizes these common types:

| Config Type | Generated `.sk` Type |
| --- | --- |
| `bool` | `bool` |
| `int` | `int` |
| `float` | `float` |
| `string` | `string` |
| `text` | `text` |
| `vector3` | `vector` |
| `exec` | `exec` |

When generating a default return value, the current scripts use:

| Type | Default Return |
| --- | --- |
| `bool` | `false` |
| `int` | `0` |
| `float` | `0` |
| `string` | `''` |
| `text` | `''` |
| `vector3` | `vector(0, 0, 0)` |
| `exec` | `None` |

## Generated `.sk` Layout

Generated files in `data/node/` follow this general structure:

```sk
# Chip: If
# Ports:
#   Input 1 | Type: exec | Name: Run
#   Input 2 | Type: bool | Name: Condition
#   Output 1 | Type: exec | Name: Then
#   Output 2 | Type: exec | Name: Else

# Required Libraries
#   - None

variables:
	_CHIP_VER = 1.0.0
	_CURRENT_EXEC = None

function CHIP_IF_TRIGGER(input2 : bool):
	return "{error.not_implemented}"
```

Notes:

1. Header metadata follows the documentation contract with `# Chip:`, `# Ports:`, and `# Required Libraries` sections.
2. Multi-type ports are documented as `object` in the generated header.
3. Exec input ports are not included in the function parameter list.
4. Generated trigger functions use the `CHIP_<NAME>_TRIGGER` naming convention.
5. Generated scaffolds always include `_CHIP_VER` and `_CURRENT_EXEC`.

## Validation Rules

`verifyCircuitIntegrity.py` validates the JSON structure before generation. It checks:

1. The root value is an object containing a non-empty `configs` object.
2. Each config key is a non-empty string.
3. Each chip `name` matches its config key.
4. Required boolean flags exist and are booleans.
5. `filterPaths` is a non-empty list of non-empty string lists.
6. `ports` is a non-empty list.
7. Port collections use only `static` and `dynamic` groups.
8. Port definitions include `name`, `description`, and a non-empty `types` list.
9. Dynamic port definitions include valid `dynamic.min` and `dynamic.max` values.

## Generator Notes

`generateChip.py` currently reads the first chip in `ChipConfigs.json` and writes a test file to `test.sk`. The generator builds a documentation-compliant scaffold directly from the chip config.