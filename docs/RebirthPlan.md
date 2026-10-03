# Rebirth System Plan

## What the screenshot shows

The finished tycoon is a fully built plot: every pen slot filled (fenced pens laid out in a fixed pattern, not a line), the stone road, the Sell NPC, and a **Rebirth** button. Rebirth is the prestige reset that happens once the player has nothing left to buy.

## Goal

A rebirth must feel earned and make the next run faster, but never trivialise the first hour. To rebirth, the player needs **all three**:

| Requirement | What it checks | Why it exists |
|---|---|---|
| **Sheep in a pen** | A sheep of at least a minimum rarity is currently seated in one of the player's pens | Forces pen upgrades (luck) to matter and gives a "boss moment" |
| **Money** | `leaderstats.Money >= cost` | Forces the player to finish the tycoon instead of rebirthing early |
| **Wool** | `Inventory.Wool >= cost` (held, not sold) | Creates a real choice: sell wool for cash now, or hoard it for the rebirth |

All three are consumed on rebirth.

## Requirement table (starting values)

`n` = the rebirth the player is attempting (1 for the first).

| Rebirth | Min. sheep rarity | Money | Wool |
|---|---|---|---|
| 1 | Rare | `M0` | `0.4 × M0` |
| 2 | Epic | `M0 × 1.8` | `0.4 × M0 × 1.8` |
| 3 | Epic | `M0 × 1.8²` | … |
| 4 | Legendary | `M0 × 1.8³` | … |
| 5–9 | Legendary | `M0 × 1.8^(n-1)` | … |
| 10+ | Mythic | `M0 × 1.8^(n-1)` | … |

Formulas: `money(n) = M0 × 1.8^(n-1)`, `wool(n) = money(n) × 0.4`. The rarity ladder is a plain list in data, indexed by `n`.

- **Wool is 0.4× the money cost**, which at `WOOL_SELL_PRICE = 0.5` means the held wool is worth about 20% of the money cost if sold. That is enough to hurt, not enough to feel like a second grind.
- **Growth 1.8×** was chosen against the reward curve below so each rebirth takes about 1.4× longer than the last (see "Pacing").

## Rewards (permanent, kept across rebirths)

| Reward | Formula | Where it plugs in |
|---|---|---|
| Wool sell multiplier | `1 + 0.5 × n` | `SellWoolHandler` (price per wool) |
| Luck bonus | `+5% × n` on Rare+ weights, capped | `SheepData.buildChancesForLevel` / the level-1 table |
| Starting money | `1000 + 500 × n` | `PlayerSetup` / reset |
| Rebirth title / cosmetic pen skin | one per milestone (1, 5, 10) | `PenShopData` |

Linear rewards against an exponential cost give a soft ceiling around rebirth 10 instead of a runaway. After that, add a second prestige tier rather than stretching the same curve.

### Pacing check

Time to rebirth is roughly `cost(n) / (income × multiplier(n))`. With cost growth 1.8× and multiplier `1 + 0.5n`:

| n | cost factor | multiplier | relative time |
|---|---|---|---|
| 1 | 1.00 | 1.5 | 0.67 |
| 2 | 1.80 | 2.0 | 0.90 |
| 3 | 3.24 | 2.5 | 1.30 |
| 4 | 5.83 | 3.0 | 1.94 |
| 5 | 10.5 | 3.5 | 3.00 |

That is a steady ~1.4× per rebirth. A 2.5× cost growth would give ~1.9× per rebirth and a wall by rebirth 5.

## What a rebirth resets and keeps

| Resets | Keeps |
|---|---|
| Money (to the starting amount) | Rebirth count and its multipliers |
| Held wool | Owned pen styles and pen inventory (cosmetics) |
| All pens except the base pen (pens 2..N destroyed) | Equipped pen style |
| Pen levels, workers and their upgrades | Shear shop purchases (decide: keep or reset) |
| The sacrificed sheep | |

## Balance notes from the current numbers

- Building out the plot costs about 272k: pens 100+300+900+2,700+8,100 = 12,100, all upgrades 6 × 42,500 = 255,000, workers 6 × 750 = 4,500.
- Average wool per sheep is ~18.3 at pen level 1 and ~25.5 at level 5, so upgrades add only ~40% wool. Their real value is **rarity access**, which is exactly what the sheep requirement needs.
- Chance of a Legendary or better per sheep is ~0.05% at level 1 and ~0.84% at level 5, about 17× better. A "Legendary" requirement is therefore close to impossible without upgrades and reachable with them, which is the intended gate.
- **Open risk:** income is not yet measured. If a fully automated plot earns only ~100–300 money/min, `M0` near the 272k build cost would take many hours. **Do not hard-code `M0` from this document.** Set `M0` from measured income (see below).

## Tuning `M0`

1. Fully build a test plot (all pens, level 5, all workers).
2. Read `pen:getEstimatedMoneyPerMinute()` for each pen and sum it: that is `I`, income per minute at the end of the tycoon.
3. Choose a target for the first rebirth after the plot is complete (e.g. 10 minutes of income): `M0 = I × 10 + build cost`.
4. Check that the full build is reachable in the intended first-session length. If not, lower pen/upgrade prices in `EconomyData` rather than `M0`.
5. Playtest rebirths 1–3 and adjust the growth constant (1.8) and sheep rarity list only.

## Implementation plan

### New files

- `Modules/Constants/RebirthData.luau`: data and pure functions only, no side effects.
  - `RARITY_REQUIREMENTS: { [number]: string }` (indexed by rebirth number, last entry repeats)
  - `M0`, `WOOL_RATIO`, `COST_GROWTH`, `MAX_REBIRTHS`
  - `getRequirements(n) -> { money, wool, minRarity }`
  - `getWoolMultiplier(count)`, `getLuckBonus(count)`, `getStartingMoney(count)`
  - Rarity comparison uses `SheepData.RarityOrder`, never string compares.
- `Modules/Controllers/RebirthHandler.luau`: server authority.
- `Server/Server/RebirthRemote` wiring (or inside `RebirthHandler.Start`), plus two remotes: `RebirthRequest` (client to server) and `RebirthResult` (server to client), added next to the existing remote name lists.
- Client: `Controllers/RebirthClient.local.luau`, which opens a panel from the existing **Rebirth** button showing three rows (Sheep / Money / Wool), each with a green tick or red cross, and a confirm button enabled only when all are met.

### Rebirth count

Stored as a player attribute `Rebirths` (number) so it replicates for the UI, same pattern as `OwnedPenSkins`. **It must be persisted** (DataStore or a profile library) before this ships. Money, wool and pen skins are not saved today, and an unsaved prestige count would be lost every session. Persistence is a prerequisite, not part of the rebirth logic.

### Server flow (`RebirthHandler`)

All checks run on the server; the client only displays.

1. Rate limit the request (reuse the `RateLimit` middleware) and ignore it if the player is mid-shear (`ShearHandler.isShearing`).
2. `n = Rebirths + 1`; reject if `n > MAX_REBIRTHS`.
3. Find the qualifying sheep: iterate `PenHandler.getPens(player)` for a pen with `occupiedSheepId` and `seated == true` whose sheep `Rarity` attribute ranks at or above `minRarity`. If none, reply `NoSheep`.
4. Check money and wool (`InventoryHandler.hasItem`). If short, reply `NoMoney` / `NoWool`.
5. Apply in this order, with no yields between the check and the commit so the state cannot change underneath:
   1. Remove the sacrificed sheep (`SheepHandler.removeSheep` then `pen:releaseSheep()`).
   2. Deduct money and wool.
   3. `PenHandler.resetPens(player)`.
   4. Set money to `getStartingMoney(n)`, increment `Rebirths`.
   5. Reply success and play the effect.
6. Re-fire `PenHandler.PenAdded` consumers by recreating state through the normal paths, so the pen shop skin logic and menus stay in sync.

### Changes to existing code

- `PenHandler.resetPens(player)`: destroy pens 2..N via the existing `removePen` path (repeat from the highest id down, since `removePen` only allows the last pen), and reset the base pen to level 1 with no worker. Needs a small `Pen:reset()` that clears `data.chances`, `level`, `data.automated` and the worker model/label.
- `SellWoolHandler`: multiply the payout by `RebirthData.getWoolMultiplier(rebirths)`.
- `SheepHandler.spawnSheep` / `Pen.upgrade`: apply the luck bonus when building chance tables. The bonus has to apply at level 1 too, where the table is currently `nil` (base table as-is).
- `PenPurchase` and `EconomyData.MAX_PENS`: keep at the slot count in `PenLayout.SlotCount`. Assert at startup that `MAX_PENS <= PenLayout.SlotCount`.
- `PlayerSetup`: starting money from `getStartingMoney(Rebirths)` once persistence exists.

### Edge cases to handle

- Player disconnects mid-rebirth: all steps are synchronous on the server, so either everything applies or nothing does.
- The qualifying sheep is being sheared by a worker at the moment of the request: step 3 re-reads the sheep and the pen state at commit time.
- A player sells wool between opening the panel and confirming: the server check at step 4 is the only one that counts.
- Double-click / spam: a per-player "rebirthing" flag plus the rate limit.
- Pen skins: `resetPens` must not touch `OwnedPenSkins` or `PenSkinId`.

### Suggested build order

1. Persistence for money, wool, `Rebirths` and owned skins.
2. `RebirthData` with unit-style checks of the formulas.
3. `Pen:reset()` and `PenHandler.resetPens` (testable on its own with a dev command).
4. `RebirthHandler` and remotes.
5. Multipliers in `SellWoolHandler` and the luck bonus.
6. Client panel on the existing Rebirth button.
7. Measure income and set `M0` (see "Tuning `M0`").
