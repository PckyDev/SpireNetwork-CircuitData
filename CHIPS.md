# CHIPS

This document provides a checklist of all the chips that have been added to the game, and whether they have been successfully tested in-game.

| Available in Editor | Runtime File Created | Dedicated Runtime Implemented | Tested In-Game | Chip Name | Notes |
|--------------------|---------------------|--------------------------------|-----------------|-----------|-------|
| [x] | [x] | [x] | [x] | Command Get Sender |  |
| [x] | [x] | [x] | [x] | Player Show Title |  |
| [x] | [x] | [x] | [x] | To String |  |
| [x] | [x] | [x] | [X] | Cancel Event | Only cancels synchronously during cancellable event dispatches. |
| [x] | [X] | [x] | [X] | If |  |
| [x] | [X] | [x] | [ ] | And |
| [x] | [x] | [x] | [ ] | Execution Integer Switch |
| [x] | [x] | [x] | [ ] | Not |
| [x] | [x] | [x] | [ ] | Value Integer Switch |
| [x] | [x] | [x] | [ ] | Nand |
| [x] | [x] | [x] | [X] | Add |
| [x] | [x] | [x] | [ ] | Subtract |
| [x] | [x] | [x] | [ ] | Multiply |
| [x] | [x] | [x] | [ ] | Divide |
| [x] | [x] | [x] | [ ] | Modulo |
| [x] | [x] | [x] | [ ] | Clamp |
| [x] | [x] | [x] | [ ] | Abs |
| [x] | [x] | [x] | [ ] | Sin |
| [x] | [x] | [x] | [ ] | Cos |
| [x] | [x] | [x] | [ ] | Tan |
| [x] | [x] | [x] | [ ] | Asin |
| [x] | [x] | [x] | [ ] | Acos |
| [x] | [x] | [x] | [ ] | Atan |
| [x] | [x] | [x] | [ ] | Atan2 |
| [x] | [x] | [x] | [X] | Equals |
| [x] | [x] | [x] | [ ] | Not Equals |
| [x] | [x] | [x] | [ ] | Greater Than |
| [x] | [x] | [x] | [ ] | Less Than |
| [x] | [x] | [x] | [ ] | Greater Than Or Equal |
| [x] | [x] | [x] | [ ] | Less Than Or Equal |
| [x] | [x] | [x] | [X] | Delay |
| [x] | [x] | [x] | [ ] | Floor |
| [x] | [x] | [x] | [ ] | Ceil |
| [x] | [x] | [x] | [ ] | Round |
| [x] | [x] | [x] | [ ] | Min |
| [x] | [x] | [x] | [ ] | Max |
| [x] | [x] | [x] | [ ] | Lerp |
| [x] | [x] | [x] | [ ] | Inverse Lerp |
| [x] | [x] | [x] | [ ] | Lerp Unclamped |
| [x] | [x] | [x] | [ ] | Distance |
| [x] | [x] | [x] | [ ] | Vector3 Create |
| [x] | [x] | [ ] | [ ] | Vector3 Split |
| [x] | [x] | [x] | [ ] | Vector3 Normalize |
| [x] | [x] | [x] | [ ] | Vector3 Dot |
| [x] | [x] | [x] | [ ] | Vector3 Cross |
| [x] | [ ] | [ ] | [ ] | API Request |
| [x] | [x] | [x] | [X] | Command Get Arguments |
| [x] | [x] | [x] | [ ] | Get All Players |
| [x] | [x] | [x] | [ ] | Get Player Count |
| [x] | [x] | [x] | [X] | Get Player By Name |
| [x] | [x] | [x] | [ ] | Get Player By UUID |
| [x] | [x] | [x] | [ ] | Player Get Is Creative |
| [x] | [x] | [x] | [ ] | Player Get Is Survival |
| [x] | [x] | [x] | [ ] | Player Get Is Adventure |
| [x] | [x] | [x] | [ ] | Player Get Is Spectator |
| [x] | [x] | [x] | [ ] | Player Get Is Jumping |
| [x] | [x] | [x] | [ ] | Player Get Is Crouching |
| [x] | [x] | [x] | [ ] | Player Get In Air |
| [x] | [x] | [x] | [ ] | Player Get On Ground |
| [x] | [x] | [x] | [ ] | Player Get Is Flying |
| [x] | [x] | [x] | [ ] | Player Get Is Swimming |
| [x] | [ ] | [x] | [ ] | Player Get Hunger | Returns the player's current food level from 0 to 20. |
| [x] | [x] | [x] | [ ] | Player Get Head Position |
| [x] | [x] | [x] | [ ] | Player Get Head Forward |
| [x] | [x] | [x] | [ ] | Get Held Item | Outputs the player's main hand material value and quantity. |
| [x] | [x] | [x] | [ ] | Get Off Hand Item | Outputs the player's off hand material value and quantity. |
| [x] | [x] | [ ] | [ ] | Get Armor Slot | Armor Slot input uses 0 boots, 1 leggings, 2 chestplate, 3 helmet; outputs a material value and quantity. |
| [x] | [x] | [ ] | [ ] | Get Inventory Slot | Slot input reads inventory slots 0-35 and outputs a material value and quantity. |
| [x] | [x] | [x] | [ ] | Player Give Item | Quantity defaults to 1 when unset or not positive; only succeeds when the full amount fits in the player's main inventory slots. |
| [x] | [x] | [ ] | [ ] | Player Take Item | Quantity defaults to 1 when unset or not positive; removes matching material from the player's inventory only when the full amount is present. |
| [x] | [x] | [ ] | [ ] | Player Take Item From Slot | Slot input uses 0-35; quantity defaults to 1 when unset or not positive and only removes when the selected slot already contains enough of the requested material. |
| [x] | [x] | [x] | [ ] | Player Clear Inventory | Clears the player's full inventory contents. |
| [x] | [x] | [x] | [ ] | Player Clear Slot | Slot input uses 0-35. |
| [x] | [ ] | [x] | [ ] | Player Set Hunger | Clamps the target player's food level from 0 to 20. |
| [x] | [x] | [ ] | [ ] | Player Set Item In Slot | Slot input uses 0-35; quantity defaults to 1 when unset or not positive; air clears the slot. |
| [x] | [x] | [x] | [ ] | Play Audio At Position | On Complete follows the audio duration metadata when available on the audio input. |
| [x] | [x] | [x] | [ ] | Play Audio At Position For Player | Only targets the selected player and requires that player to be in the same world as the playback position. |
| [x] | [x] | [x] | [ ] | Get Position |
| [x] | [x] | [x] | [ ] | Execution Integer Switch |
| [x] | [ ] | [ ] | [ ] | Execution String Switch |
| [x] | [x] | [x] | [ ] | Value Integer Switch |
| [x] | [ ] | [ ] | [ ] | Value String Switch |
| [x] | [x] | [x] | [X] | For |  |
| [x] | [x] | [x] | [X] | For Each |  |
| [x] | [x] | [x] | [X] | Sequence |
| [x] | [x] | [x] | [ ] | Ceil to Int |
| [x] | [ ] | [ ] | [ ] | Color To HSV |
| [x] | [ ] | [ ] | [ ] | Color to RGB |
| [x] | [x] | [x] | [ ] | Floor to Int |
| [x] | [x] | [x] | [ ] | Int to Float |
| [x] | [x] | [x] | [ ] | Round to Int |
| [x] | [x] | [x] | [ ] | Parse Bool |
| [x] | [x] | [ ] | [ ] | Parse Color |
| [x] | [x] | [x] | [ ] | Parse Float |
| [x] | [x] | [x] | [ ] | Parse Int |
| [x] | [x] | [x] | [X] | String Concat |
| [x] | [x] | [x] | [X] | String Format |
| [x] | [x] | [x] | [X] | String To Lower |
| [x] | [x] | [x] | [X] | String To Upper |
| [x] | [x] | [x] | [ ] | List Get First Index Of |
| [x] | [x] | [ ] | [ ] | Instance Get Is Private |
| [x] | [x] | [x] | [X] | List Create |
| [x] | [x] | [x] | [ ] | List Insert |
| [x] | [x] | [ ] | [ ] | List Intersect |
| [x] | [x] | [x] | [ ] | List Remove At |
| [x] | [x] | [x] | [ ] | List Get Count |
| [x] | [x] | [x] | [ ] | List Remove Last |
| [x] | [x] | [ ] | [ ] | List Sort By Key |
| [x] | [x] | [ ] | [ ] | List Subtract |
| [x] | [x] | [ ] | [ ] | AABB Contains Point |
| [x] | [x] | [x] | [ ] | Get Forward Vector |
| [x] | [x] | [x] | [ ] | Get Up Vector |
| [x] | [x] | [x] | [ ] | Get Down Vector |
| [x] | [x] | [x] | [ ] | Get Left Vector |
| [x] | [x] | [x] | [ ] | Get Right Vector |
| [x] | [x] | [ ] | [ ] | Raycast |
| [x] | [x] | [ ] | [ ] | Get Closest |
| [x] | [x] | [ ] | [ ] | Get Farthest |
| [x] | [ ] | [ ] | [ ] | Player Get Time Zone |
| [x] | [x] | [x] | [X] | Time Get Universal Seconds |
| [x] | [x] | [x] | [ ] | Time Get Universal Time |
| [x] | [x] | [x] | [ ] | Get Time |
| [x] | [x] | [x] | [ ] | Get Day Night Cycle |
| [x] | [x] | [ ] | [ ] | Set Time |
| [x] | [x] | [ ] | [ ] | Set Day Night Cycle |
| [x] | [x] | [x] | [ ] | Get Weather |
| [x] | [x] | [x] | [ ] | Get Weather Cycle |
| [x] | [x] | [ ] | [ ] | Set Weather |
| [x] | [x] | [ ] | [ ] | Set Weather Cycle |
| [x] | [x] | [x] | [X] | Set Block |
| [x] | [x] | [x] | [X] | Set Block Area |
| [x] | [x] | [x] | [X] | Replace All Blocks In Area |
| [x] | [x] | [x] | [X] | Block Get Name |
| [x] | [x] | [x] | [X] | Block Get Coordinates |
| [x] | [x] | [x] | [X] | Get Block At Position |
| [x] | [x] | [x] | [ ] | Get Block By Name |
| [x] | [x] | [x] | [X] | Set Position |
| [x] | [x] | [ ] | [ ] | Entity Spawn | Spawns a resolved entity type at an instance-relative position and outputs the spawned entity. |
| [x] | [x] | [x] | [ ] | Entity Get Type |  |
| [x] | [x] | [x] | [ ] | Entity Set Health |  |
| [x] | [x] | [x] | [ ] | Entity Get Health |  |
| [x] | [x] | [x] | [ ] | Entity Deal Damage |  |
| [x] | [x] | [ ] | [ ] | Entity Set Immortal |  |
| [x] | [x] | [ ] | [ ] | Entity Get Immortal |  |
| [x] | [x] | [x] | [ ] | Entity Set Glowing |  |
| [x] | [x] | [x] | [ ] | Entity Get Glowing |  |
| [x] | [x] | [x] | [ ] | Entity Set Custom Name |  |
| [x] | [x] | [x] | [ ] | Entity Get Custom Name |  |
| [x] | [x] | [x] | [ ] | Entity Set Custom Name Visible |  |
| [x] | [x] | [x] | [ ] | Entity Get Custom Name Visible |  |
| [x] | [x] | [x] | [ ] | Entity Set No Gravity |  |
| [x] | [x] | [x] | [ ] | Entity Get No Gravity |  |
| [x] | [x] | [x] | [ ] | Entity Set Silent |  |
| [x] | [x] | [x] | [ ] | Entity Get Silent |  |
| [x] | [x] | [x] | [ ] | Entity Set Invisible |  |
| [x] | [x] | [x] | [ ] | Entity Get Invisible |  |
| [x] | [x] | [ ] | [ ] | Entity Set Can Burn | Stores a per-entity burn permission used by the burning chips and clears fire when disabled. |
| [x] | [x] | [ ] | [ ] | Entity Get Can Burn | Returns the configured per-entity burn permission, defaulting to true when unset. |
| [x] | [x] | [ ] | [ ] | Entity Get Is Burning | Returns whether the entity currently has fire ticks. |
| [x] | [x] | [ ] | [ ] | Entity Set Is Burning | Sets fire ticks directly and respects the configured per-entity burn permission. |
| [x] | [x] | [ ] | [ ] | Entity Set Pathfind Speed | Stores a per-entity pathfinding speed used by the pathfind chip. |
| [x] | [x] | [ ] | [ ] | Entity Get Pathfind Speed | Returns the configured per-entity pathfinding speed, defaulting to 1 when unset. |
| [x] | [x] | [ ] | [ ] | Entity Pathfind To Location | Uses Paper's mob pathfinder in the instance world and applies the configured pathfinding speed. |
| [x] | [x] | [ ] | [ ] | Entity Look At Location | Uses the entity look-at API in the instance world. |
| [x] | [x] | [x] | [ ] | Entity Is Player |  |
| [x] | [x] | [x] | [ ] | Get Player From Entity |  |
| [x] | [x] | [ ] | [ ] | Entity Is Hostile |  |
| [x] | [x] | [ ] | [ ] | Entity Is Passive |  |
| [x] | [x] | [ ] | [ ] | Entity Is Neutral | Uses a normalized entity-type allowlist for neutral mobs. |
| [x] | [x] | [ ] | [ ] | Get All Entities In Radius | Searches the instance world and filters by true radius distance. |
| [x] | [x] | [ ] | [ ] | Get Nearest Entity | Searches the instance world and returns the closest entity within radius. |
| [x] | [x] | [x] | [ ] | Add Tag | Uses entity scoreboard tags. |
| [x] | [x] | [x] | [ ] | Remove Tag | Uses entity scoreboard tags. |
| [x] | [x] | [x] | [ ] | Has Tag | Uses entity scoreboard tags. |
| [x] | [x] | [x] | [ ] | Get Tags | Uses entity scoreboard tags. |
| [x] | [x] | [ ] | [ ] | Get All With Tag | Searches entity scoreboard tags in the instance world. |
| [x] | [x] | [ ] | [ ] | Get First With Tag | Searches entity scoreboard tags in the instance world. |
| [x] | [x] | [x] | [ ] | Get Player As Entity |  |
| [x] | [x] | [x] | [ ] | Velocity Add |
| [x] | [x] | [x] | [ ] | Velocity Set |
| [x] | [x] | [x] | [ ] | Player Show Action Bar |
| [x] | [x] | [x] | [X] | String Contains |
| [x] | [x] | [x] | [ ] | String Substring |
| [x] | [ ] | [ ] | [ ] | Player Force Resource Pack |
| [x] | [x] | [x] | [X] | Send Chat Message To Player |
| [x] | [x] | [x] | [ ] | Send Chat Message To All |
| [x] | [x] | [x] | [X] | Variable |
| [x] | [x] | [x] | [ ] | List Get Element |
| [x] | [x] | [x] | [ ] | Power |
| [x] | [x] | [x] | [ ] | If Value |
| [x] | [x] | [x] | [X] | Random Number |
| [x] | [x] | [x] | [X] | List Get Random |
| [x] | [x] | [x] | [ ] | List Contains |
| [x] | [x] | [x] | [ ] | List Add |

## EVENTS

| Available in Editor | Runtime Implemented | Dedicated Runtime Implemented | Tested In-Game | Event Name | Notes |
|--------------------|---------------------|--------------------------------|-----------------|------------|-------|
| [x] | [x] | [x] | [x] | Command |  |
| [x] | [x] | [x] | [X] | Block Broken |  |
| [x] | [x] | [x] | [X] | Block Placed |  |
| [x] | [x] | [x] | [X] | Update 1 Tick |  |
| [x] | [x] | [x] | [X] | Update 20 Ticks |  |
| [x] | [x] | [x] | [X] | Player Join |  |
| [x] | [x] | [x] | [X] | Player Leave |  |
| [x] | [x] | [x] | [ ] | World Loaded |  |
| [x] | [x] | [x] | [X] | Mob Spawned |  |
| [x] | [X] | [x] | [ ] | Left Click |  |
| [x] | [X] | [x] | [ ] | Right Click |  |
| [x] | [x] | [x] | [ ] | Button Pressed |  |
| [x] | [x] | [x] | [ ] | Lever Toggled |  |
| [x] | [x] | [x] | [ ] | Pressure Plate Stepped On |  |
| [x] | [x] | [x] | [ ] | Pressure Plate Stepped Off |  |
| [x] | [ ] | [x] | [X] | Player Died | Dedicated runtime fires from lethal damage so Cancel Event can prevent the death. |
| [x] | [ ] | [x] | [X] | Player Respawned | Cancel Event keeps the player at their current location because Bukkit respawn itself is not directly cancellable. |
| [x] | [ ] | [x] | [ ] | Player Gained Health | Outputs player, old health, new health, and amount. |
| [x] | [ ] | [x] | [X] | Player Lost Health | Outputs player, old health, new health, and amount. |
| [x] | [ ] | [x] | [ ] | Player Gained Hunger | Outputs player, old hunger, new hunger, and amount. |
| [x] | [ ] | [x] | [X] | Player Lost Hunger | Outputs player, old hunger, new hunger, and amount. |
| [x] | [ ] | [x] | [ ] | Player Gained Experience | Outputs player, old total experience, new total experience, and amount. |
| [x] | [ ] | [x] | [ ] | Player Lost Experience | Outputs player, old total experience, new total experience, and amount. |

## CONSTANTS

| Available in Editor | Runtime Implemented | Dedicated Runtime Implemented | Tested In-Game | Constant Name | Notes |
|--------------------|---------------------|--------------------------------|----------------|---------------|-------|
| [x] | [x] | [x] | [ ] | Color Constant | Dedicated runtime supports generic constant values; color-specific consumers still need validation. |
| [x] | [x] | [x] | [ ] | API Constant | Dedicated runtime supports generic constant values; API request chip is not implemented yet. |
| [x] | [x] | [x] | [X] | Block Constant | Parsed for block-setting chips. |
| [x] | [x] | [x] | [ ] | Entity Type Constant | Outputs a normalized namespaced entity type id from the palette-backed selector. |
| [x] | [x] | [x] | [ ] | Material Constant | Parsed as a material value for inventory and variable chips. |
| [x] | [x] | [x] | [ ] | Audio Constant | Dedicated runtime supports generic constant values and audio playback chips now consume id/soundId/data plus category and duration metadata. |
| [x] | [x] | [x] | [ ] | Resource Pack Constant | Dedicated runtime supports generic constant values; force-resource-pack chip is not implemented yet. |
| [x] | [x] | [x] | [ ] | Weather Constant | Normalized to clear, rain, or thunder for weather chips. |
