# Podium Sheep Bonuses

Right now a podium sheep is only for show. Putting a sheep on a podium already costs something: it leaves the pen, so it can't be shorn. A passive bonus makes that a real choice between keeping it to shear and keeping it to display.

## What a podium sheep gives

Every podium sheep gives a **passive bonus**. Its **rarity** sets the base size, its **mutation** picks the stat, and its **size** scales the bonus.

| Rarity | Base bonus |
|---|---|
| Common | +2% |
| Uncommon | +4% |
| Rare | +7% |
| Epic | +12% |
| Legendary | +20% |
| Mythic | +35% |

Mutation picks the stat the bonus goes to:

| Mutation | Stat | Hooks into |
|---|---|---|
| none / Shiny | Wool | `ShearHandler.getWoolReward` multiplier (next to Prestige and More Wool) |
| Haunted | Spawn Luck | `SheepSpawnHandler.spawnOne` luck multiplier (next to `WeatherHandler.getLuckMultiplier()`) |
| Rainbow | Respawn speed | `SheepSpawnHandler.getSpawnInterval` (like `WeatherHandler.getRespawnMultiplier()`) |
| Galaxy | All three at 60% each | all of the above |

Size multiplies the bonus: Tiny x0.75, Normal x1, Huge x1.5. Shiny gives an extra x1.25 on top.

Bonuses of the same stat add up across podiums. Each stat is capped, for example Wool at +100%, Luck at +50% and Respawn at -40% interval. Without caps, a full row of Mythics would break the Prestige curve.

### Idle wool trickle (optional, genre standard)
Every podium sheep also makes `WoolAmount / 60` wool per second while the owner is online, so a display wall feels alive. Leave offline earnings out at first.

## Display
- A billboard above each podium, e.g. "+20% Wool" or "+12% Luck" in the stat's colour.
- One HUD line or a tooltip with the totals, e.g. "Podiums: +34% Wool · +12% Luck".
- Use player attributes `PodiumWool`, `PodiumLuck` and `PodiumRespawn`, the same way `ShearDamage` is mirrored.

## Implementation
1. `Constants/PodiumData.luau`: the rarity bonus table, the mutation-to-stat map, the size factors and the caps.
2. `Controllers/PodiumBonusHandler.luau`: reads `PodiumSheep` from PlayerDataHandler and recalculates on `Changed`. It caches the totals per player, sets the player attributes and exposes `getWoolMultiplier`, `getLuckMultiplier` and `getRespawnMultiplier`.
   - Read the saved data (`SavedSheep.type / size / mutation`), not the live models, so it works before the podiums finish loading.
3. Hook the three multipliers into ShearHandler and SheepSpawnHandler.
4. Podium billboard plus HUD totals on the client.
5. (Optional) the idle trickle loop.

## Robux stealing: not implemented
Paying Robux to take another player's podium sheep is a bad fit here:
- **It's pay-to-grief.** The victim loses their rarest sheep for good, often a Mythic they spent hours rolling, and can do nothing about it. Kids who get hit report the game and quit. Players who leave don't come back to pay.
- **It doesn't work without a defense loop.** Steal-genre games work because stealing is *free and contestable*: you carry the item home while the owner chases you, and bases have locks and shields. A Robux-only steal skips all that and gives players no reason to log in to defend.
- **Once podiums give buffs, it's even worse.** Stealing would remove both the sheep and the victim's stat bonuses.
- **There's no purchase setup yet.** There is no `ProcessReceipt` handler, and a half-built paid feature that takes items from other players is the worst place to start.

### Better ways to earn Robux from podiums
- **Extra podium slots** (game pass or product): more slots mean more bonus. This is the cleanest option.
- **Podium Boost** (developer product): podium bonuses x2 for 15 minutes.
- **"Clone" a sheep you admire** (developer product): get a copy of a sheep on someone else's podium, with a lower-tier size and no mutation. The owner keeps theirs and gets a small wool tip as a "fan" reward. This keeps the social excitement of stealing without anyone losing a sheep.
- If a steal mechanic comes later, make it a **free gameplay loop** with counterplay (carry it back across the map, the owner can tag you, plot shields). Robux can then sell **shield time** or **faster carry**, never the theft itself.
