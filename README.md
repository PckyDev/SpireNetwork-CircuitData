# SpireNetwork-CircuitData

Data source and node-script generator for Spire Network chips.

This repository uses a single JSON config file to define chip metadata, categories, ports, and type rules. The Python verifier reads that config, validates its structure, and generates Skript node files under the node data tree.

## Layout

- `data/ChipConfigs.json`: canonical chip definition source
- `data/node/`: generated `.sk` node files grouped by `filterPaths`
- `verifyCircuitIntegrity.py`: validator and generator

## What The Generator Does

Running `verifyCircuitIntegrity.py` will:

1. Load `data/ChipConfigs.json`
2. Validate the JSON structure
3. Generate node scripts into `data/node/...`
4. Remove older generated files in outdated locations or file extensions when applicable

Generated paths come from each chip's `filterPaths` entry. For example:

- `[["Logic", "Flow Control"]]` becomes `data/node/logic/flow_control/`
- `[["Math", "Arithmetic"]]` becomes `data/node/math/arithmetic/`

## Chip Config Shape

Each chip in `data/ChipConfigs.json` is stored under `configs` and is expected to include:

- `name`
- `description`
- `beta`
- `deprecated`
- `hidden`
- `dev`
- `filterPaths`
- `ports`

Each port group contains `inputs` and `outputs`, and each of those may contain:

- `static`: fixed ports
- `dynamic`: expandable ports with `min` and optional `max`

Each port definition is expected to include:

- `name`
- `types`
- `description`

## Generated Skript Format

Each generated node file contains:

- a chip header
- a `Circuit Data` block
- generated function stubs for exec entry points or a single value function when there is no exec input

Current metadata lines show:

- generated port index
- configured port name
- whether the port is `static` or `dynamic`
- supported types
- dynamic bounds when relevant

Example:

```sk
# ===================== #
# Chip: And
# Last Modified: 2026 04 16 ACDT
# Loaded: 2026 04 16 23:04 ACDT
# ===================== #

# ===================== #
# Circuit Data
# ===================== #
# Inputs
# port1 (Input) [dynamic]: bool (min 2, max unbounded)
# -------------------- #
# Outputs
# output1 (Result) [static]: bool
# ===================== #

function port1(port1: object):
    return false
```

Example with multiple exec entry points:

```sk
# Inputs
# port1 (Exec) [static]: exec
# port2 (Ticks) [static]: int
# port3 (Cancel) [static]: exec
# -------------------- #
# Outputs
# output1 (Run) [static]: exec
# output2 (After Delay) [static]: exec
# output3 (Cancel) [static]: exec

function port1(port2: object):
    return None

function port3(port2: object):
    return None
```

## Dynamic Ports

Dynamic ports are shown once in the metadata block and are currently generated as one actual function input, not expanded into multiple stub parameters.

Example:

```json
"dynamic": {
  "min": 2,
  "max": null
}
```

This will render as metadata like:

```sk
# port1 (Input) [dynamic]: bool (min 2, max unbounded)
```

## Notes

- `data/ChipConfigs.json` is the source of truth
- generated files under `data/node/` should be treated as build output from the JSON config
- if you change chip definitions, rerun `verifyCircuitIntegrity.py` to resync the node scripts