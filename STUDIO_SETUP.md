# Studio Setup — Graybox & Script Install

Companion to DESIGN.md. This is the practical checklist for getting the
prototype running in Roblox Studio.

## 1. Graybox map checklist

Gray parts only — layout over looks. In a new Baseplate place:

- [ ] Floor, outer walls, 4–6 aisles of long box parts
- [ ] Shelves ~6 studs tall (blocks sightlines — that's what makes chases work)
- [ ] **Two gaps per aisle** so runners always have an escape route (no dead ends)
- [ ] **Wide storefront exit** (anti-camping; risk gradient runs front-to-back:
      safe near exit, dangerous deep in the aisles). Room for a 2nd exit later
- [ ] Lobby area off to the side
- [ ] Checkout/exit zone part at the store front

## 2. Explorer structure (names matter — scripts find things by name)

```
Workspace
├── Map
│   ├── Shelves        (Folder — all shelf parts)
│   ├── ItemSpawns     (Folder — ~10–15 small invisible anchored parts on
│   │                   shelf tops, where brainrot figures will spawn)
│   ├── CoinSpawns     (Folder — 30–40 small invisible anchored parts
│   │                   scattered along aisle floors, where coins spawn)
│   ├── ExitZone       (Part, CanCollide off, Transparency ~0.5)
│   ├── ChaserSpawn    (Part — where Security starts; near entrance/security
│   │                   office is thematic)
│   └── ShopperSpawns  (Folder — a few Parts where shoppers start)
└── Lobby
    └── LobbySpawn     (SpawnLocation, **Neutral = true** so everyone
                        respawns there between rounds)
```

## 3. Install scripts (from the `scripts/` folder here)

| File | Where in Studio | Object type |
|---|---|---|
| `RoundManager.server.lua` | ServerScriptService | Script |
| `StatusGui.client.lua` | StarterGui | LocalScript |

Right-click the container → Insert Object → paste the file's contents in,
replacing any placeholder code. Name them RoundManager / StatusGui.

## 4. Game settings

- [ ] Home tab → Game Settings → Places → max players **10**

## 5. Test

Test tab → Players dropdown → **2 players** → Start.

Expected: 15s countdown → one player turns red (Security) at ChaserSpawn,
the other blue (Shopper) at a shopper spawn → 4:00 round timer ticks in the
top bar. With 1 player it says "Waiting for players…" (correct — solo play
arrives with the AI chaser, build-order step 7).

If anything errors, check the Output window (View tab → Output) and share
the red text.

## Script integration contract (for future scripts)

RoundManager reads these player attributes each second — later systems just
set them, no RoundManager changes needed:

- `Frozen` (bool) — set by tag/freeze script
- `Out` (bool) — set when a frozen player's rescue timer expires
- `Escaped` (bool) — set by the exit/checkout script

Or end a round directly: `ServerStorage.EndRound:Fire("Shoppers" | "Security")`
