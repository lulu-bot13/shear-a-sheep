# Shearing Engagement & Sheep Variety Ideas

Ideas for keeping players hooked on shearing, buffs they can earn while shearing, and ways to add more sheep to unlock without new models. Builds on what exists: size tiers, Baby variants, weather + Charged sheep, abilities and the Index.

## Engagement ideas

1. **Shear combo** – each shear within ~3s of the last adds a stack ("x12 COMBO!", ~+2% wool per stack). Stopping resets it, so players keep moving between sheep.
2. **Critical shears** – 5–10% chance a swing does 2x damage, with a big number pop-up and a satisfying sound.
3. **Frenzy meter** – fills as you shear; when full, 15s of 2x wool and faster swings.
4. **Drops** – finished sheep sometimes drop an orb you walk over: bonus wool, a buff, or rarely a gem.
5. **Bounty sheep** – every few minutes one sheep in the plaza gets a crown; first to shear it gets a big reward. Gives players a reason to gather.
6. **Mastery per sheep type** – shear 100 Basic Sheep → permanent +5% wool from Basic Sheep. Shown in the Index as a progress bar on each card.
7. **Short quests** – "Shear 15 Grey Sheep", "Shear 3 Big sheep", refreshing every 30 min.

## Buffs while shearing

| Buff | How you get it | Effect |
|---|---|---|
| Combo | Chain shears | +2% wool per stack (cap ~50%) |
| Frenzy | Fill the meter | 2x wool, faster swings, 15s |
| Lucky Orb | Drop from a sheep | Rarer sheep spawn on your farm, 60s |
| Sharp Orb | Drop from a sheep | +50% shear damage, 30s |
| Golden Touch | Shear a Legendary+ sheep | +25% wool for everyone nearby, 60s |
| Storm Charge | Shear a Charged sheep | Your next 5 shears count as Charged |

## More sheep variety without new models

1. **Mutations (top pick)** – a rolled trait that changes the look with only materials, colours and particles: Shiny (sparkles), Frozen (Ice material, light blue), Neon (glowing colour), Ghost (see-through), Rainbow (cycling colour), Galaxy (ForceField material). Charged sheep already work this way. Each mutation multiplies wool and can go on any sheep: 19 sheep x 6 mutations = 114 new Index entries.
2. **Recolours** – Grey, Brown and Black already reuse one model, so more colours (Pink, Mint, Lavender) cost almost nothing.
3. **Accessories** – small hats, bows or sunglasses that attach to any sheep; a handful of tiny meshes go a long way.
4. **Weather-only sheep** – e.g. Storm sheep that only spawn during storms (also adds FOMO).
5. **Stacking** – size + Baby + mutation combos like "Huge Frozen Golden Sheep" feel rare without new art.

## Implementation plan

### Phase 1 – Combo, crits, frenzy (start here)
- New `Constants/ShearBuffData.luau`: combo window, crit chance, frenzy numbers.
- `ShearHandler.luau`: track each player's combo, frenzy and crits on the server and multiply wool (server decides, so no cheating).
- Mirror combo/frenzy onto player attributes, like `ActiveAbility`.
- New `ShearFeedbackClient`: combo counter, frenzy bar, crit pop-ups.

### Phase 2 – Drops and timed buffs
- New `Constants/BuffData.luau` + `Controllers/BuffHandler.luau`: active buffs with end times, combined multipliers per player.
- `SheepHandler`: chance to spawn an orb when a sheep is sheared; touching it grants the buff.
- `ShearHandler` reads wool/damage multipliers from `BuffHandler`.
- New `BuffClient`: buff icons with countdown timers.

### Phase 3 – Mutations
- New `Constants/MutationData.luau`: chance, wool multiplier and look per mutation.
- `SheepSpawnHandler`: roll a mutation on spawn (like size), store it in an attribute, apply the look.
- Name label gets a prefix like "Frozen"; `SheepStyle` colours it like size prefixes.
- Index: mutation section on each sheep card. Needs new save data, so it's the riskiest phase.

### Phase 4 – Bounty sheep, mastery, quests
Best added once Phases 1–3 are in.
