# Asset plan: weather, sheep sizes, new abilities, Ability Shack

Everything below is optional. The code runs without any of it and falls back to plain parts, default particle textures and silence. Add the assets one at a time and they get picked up by the names shown.

## 1. Build in Studio

| What | Where / name | Notes |
|---|---|---|
| Ability Shack | `workspace.AbilityShack` (Model or Folder) | Keep ~10 studs clear above the podium. If StreamingEnabled is on, set ModelStreamingMode = Persistent. |
| Podium | `workspace.AbilityShack.Podium` (BasePart, or Model with PrimaryPart) | The roll prompt (F) and the Abilities prompt (G) are created by code if missing. |
| Clouds | `Terrain.Clouds` | Rain/storm thicken them. Skipped if missing. |
| Sky | `Lighting.Sky` with stars and a moon | Makes Night look right. |
| Mobile ability button (optional) | `PlayerGui.Main.MobileAbility` (ImageButton, direct child of Main) | Optional children: `CooldownOverlay`, `Cooldown` (TextLabel), `AbilityName` (TextLabel). Otherwise set `ABILITY_BUTTON_IMAGE` in AbilityClient. |
| Size alert label (optional) | `Alerts.Main.SizeAlert` + add it to Announcements | The Giant/Colossal pop currently borrows `ClaimAlert`. |

## 2. Animations: `ReplicatedStorage.Assets.Animations.Abilities.<Id>`

| Id | Pose | Timing the code expects |
|---|---|---|
| `Smash` | Jump/crouch, both fists slam the ground | Impact at **0.55 s** (`stats.impactDelay`), total ~1.2 s, not looped |
| `Gravity` | Both arms rise and lift, hold, then pull down | ~3.5 s, not looped |
| `PumpkinSplash` | Overhand lob | Release at **0.35 s** (`stats.throwDelay`), ~0.9 s total |
| `Clone` | Short cast / snap pose (optional) | ~0.8 s |

Set the priority to Action. If your impact or release frame lands at a different time, change the stat in `AbilityData.luau` to match.

## 3. Models / VFX: `ReplicatedStorage.Assets`

| Path | Type | Look |
|---|---|---|
| `Models.Pumpkin` | Model or MeshPart, ~2.4 studs | Cartoon pumpkin with a curly stem; optional carved face |
| `VFX.PumpkinSplash` | Attachment of ParticleEmitters (`EmitCount` attribute each) | Orange goo blobs, seeds, juice spray |
| `VFX.PumpkinSplat` | Decal | Top-down orange splat, transparent background |
| `VFX.GravityAura` | Attachment of ParticleEmitters | Faint purple/blue sparkles drifting upward |
| `VFX.ClonePoof` | Attachment of ParticleEmitters | Bluish smoke puff with a few stars |

## 4. Sounds

| Where | Name / constant | Sound |
|---|---|---|
| `SoundService.AbilitySounds` | `SmashImpact` | Heavy rock crunch + low thud |
| | `GravityRise` | Rising magical hum/whoosh, 1.5-2 s |
| | `GravityLand` | Soft multi-thump landing |
| `SoundService.UISounds` | `PumpkinThrow` | Whoosh |
| | `PumpkinSplash` | Wet squelch |
| | `CloneSpawn`, `CloneDespawn` | Poofs |
| `Client/Modules/WeatherEffects.luau` | `RAIN_SOUND_ID` | Medium rain loop, no thunder, seamless |
| | `NIGHT_SOUND_ID` | Crickets + occasional owl loop, quiet |
| `Client/Modules/Lightning.luau` | `THUNDER_SOUND_ID` | Sharp crack then rolling rumble, 2-4 s |
| `Client/Modules/AbilityShackVFX.luau` | `TICK_SOUND_ID` | Short slot-machine click |
| | `WIN_SOUND_IDS` | Rare: chime, Epic: sparkle swell, Legendary: fanfare, Mythic: choir/impact boom |
| (no hook yet) | | Giant+ sheep spawn stinger, deeper baa for big sheep, charge zap |

## 5. Textures / images (constants are `""` until you set them)

| Constant (file) | Image |
|---|---|
| `RAIN_TEXTURE` (WeatherEffects) | Thin white vertical streak, soft ends, mostly transparent |
| `FIREFLY_TEXTURE` (WeatherEffects) | Soft round dot, bright centre, feathered edge |
| `SPARK_TEXTURE` (ChargedSheep) | Small jagged blue-white electric crackle |
| `ABILITY_BUTTON_IMAGE` (AbilityClient) | 256x256 round-safe icon for the mobile ability button |
| (optional) Auto Shear icon | 256x256 to replace the text toggle |
| (optional) Ability icons | 512x512 for Spin, Smash, Clone, Pumpkin Splash, Gravity, for the shack cards |
| (optional) Size glow sparkle | Replace the default particle texture on Giant/Colossal sheep |

---

## 6. Prompt for Claude

Copy everything inside the block into a new Claude conversation, together with this file.

```
I'm making a cartoony Roblox sheep-shearing simulator. Bright, chunky, friendly style (think
Pet Simulator / Bee Swarm): saturated colours, thick dark outlines on UI, soft gradients, no realism.
Rarity colours used everywhere in the game:
Common #6B7280, Uncommon #15803D, Rare #1D4ED8, Epic #7E22CE, Legendary #C2410C, Mythic #BE123C.

I've attached AssetPlan.md, which lists every asset my code looks for, with exact names, paths,
sizes and timings. Work through it with me one section at a time, in this order, and stop after
each section so I can make and import the assets before we continue:

1. PARTICLE TEXTURES (section 5: rain, firefly, spark, size-glow sparkle): for each, explain how
   to make it as a white/greyscale image on transparent so Roblox can tint it, and which
   ParticleEmitter settings (LightEmission, Size, Transparency curve) suit it.
   The UI icons are being made separately with Gemini, so skip them.

2. (skipped: UI icons are in section 7 of AssetPlan.md)

3. VFX (section 3): for each Attachment, write a Luau snippet I can paste into the Studio command
   bar that builds the Attachment and its ParticleEmitters with full property values (Rate 0 and
   an EmitCount attribute for bursts), parented to the exact path in the plan. Use only
   built-in rbxasset:// textures or a placeholder "rbxassetid://0" I'll replace. Also give a
   command-bar script for the PumpkinSplat decal holder.

4. 3D MODEL (Pumpkin): use the design-3d-roblox approach. Give me a Claude Design prompt for a
   2.4-stud cartoon pumpkin with stem and optional face, plus import steps for Roblox Studio.

5. ANIMATIONS (section 2): for each animation, a keyframe-by-keyframe guide for the Roblox
   Animation Editor on an R15 rig (time, body part, rotation in degrees, easing style), hitting the
   exact impact/release times in the plan, with anticipation and follow-through so it feels punchy.
   Also tell me which AbilityData stat to change if my timing ends up different.

6. SOUNDS (section 4): for each sound, a search phrase for the Roblox Creator Store audio library
   and a short description of what to listen for (length, loop or not, volume), plus the Volume,
   RollOffMaxDistance and PlaybackSpeed to set on the Sound.

Rules: never invent asset IDs. Keep every name/path exactly as written in AssetPlan.md, because my
scripts find assets by those names. Keep instructions short and step-by-step.
```

---

## 7. UI icons: prompts for Gemini (Nano Banana)

Nano Banana can't make real transparent backgrounds. Every prompt below asks for a flat pure-green background (#00FF00) so the background is easy to remove. A "transparent" request instead gives a fake checkerboard.

**Steps**
1. Paste the **style prompt** first, then the first icon's prompt, in the same chat.
2. Paste each later icon into that same chat, and add: "Same style, outline weight and lighting as the previous icon." Nano Banana keeps a set consistent best inside one conversation.
3. If one comes out wrong, ask for a small fix in the same chat (for example "make the outline thicker", or "remove the sparkles in the corners") instead of starting over.
4. Remove the green background: use remove.bg, Photopea's Magic Wand, or Studio's own background removal when you upload the image.
5. Scale to the size in the table and export a PNG.
6. Upload to the Creator Hub, then paste the `rbxassetid://` id where the table says.
7. Check each icon at 60px. If you can't tell what it is at that size, ask Gemini to "simplify, fewer details, bigger shapes".

| Icon | Final size | Where it goes |
|---|---|---|
| Mobile ability button | 256x256 | `ABILITY_BUTTON_IMAGE` in AbilityClient, or the Image of `Main.MobileAbility` |
| Spin, Smash, Clone, Pumpkin Splash, Gravity | 512x512 | Ability Shack cards (the code has no hook for these yet: ask Claude Code to add one) |
| Auto Shear ON / OFF | 256x256 | Auto Shear toggle (it's text-only now; ask Claude Code to switch it to an ImageButton) |

### Style prompt (paste this first)

```
You are making a matching set of game UI icons for a cartoony Roblox simulator about shearing
sheep. Style for every icon: bright saturated colours, chunky rounded shapes, a thick dark navy
outline (#1B1F3B) around the whole silhouette, soft cel shading with one highlight on the
top-left, a subtle drop shadow underneath, friendly and playful, similar to Pet Simulator 99 and
Bee Swarm Simulator icons. Square 1:1 image, the subject centred and filling about 80% of the
frame, nothing touching the edges. Flat pure green background (#00FF00) with no gradient,
texture, shadow or pattern on it. No text, no letters, no numbers, no watermark, no border frame.
Must be clear at 60 pixels wide, so use big simple shapes and few small details.
Reply "ready" and wait for the first icon.
```

### Mobile ability button

```
Icon 1: a round ability button icon. A glowing pair of golden sheep shears crossed in an X over
a bright starburst, inside a circular badge with a thick navy rim and a warm orange-to-yellow
radial glow. Everything stays inside the circle so it works on a round button.
```

### Ability icons (one message each, same chat)

```
Spin (rarity Common, accent grey #6B7280): two silver sheep shears whirling in a circle, with
curved white motion-swoosh lines around them and a few tufts of white wool flying outward.
```

```
Smash (rarity Rare, accent blue #1D4ED8): a big cartoon fist slamming down into the ground, with
chunky brown-grey rock chunks bursting up around it, a blue shockwave ring and little dust puffs.
```

```
Clone (rarity Epic, accent purple #7E22CE): three identical cartoon farmer silhouettes standing
in a row, each holding shears. The front one is solid; the two behind are semi-transparent
purple copies with a soft purple glow.
```

```
Pumpkin Splash (rarity Legendary, accent orange #C2410C): a cartoon pumpkin with a curly green
stem flying in an arc with orange motion lines, bursting into a big orange goo splat with seeds
flying out.
```

```
Gravity (rarity Mythic, accent crimson #BE123C): a fluffy white sheep floating upward inside a
glowing crimson-pink swirl, with two upward arrows beside it and wool tufts drifting down from
it.
```

### Auto Shear toggle

```
Auto Shear ON: a pair of sheep shears with a circular "repeat" arrow looping around them, on a
bright green (#22C55E) rounded-square badge with a thick navy rim. For this icon only, make the
background flat pure magenta (#FF00FF) instead of green, so the green badge isn't removed with it.
```

```
Auto Shear OFF: the exact same icon as the last one, but the badge is grey (#6B7280) and the
shears and arrow are slightly faded.
```
