# Wallmart Chase — Design Doc

*Round-based asymmetric PvP chase/collection game set in a shopping center.*
*Status: idea stage → prototyping. Last updated: 2026-07-17.*

## Elevator pitch

You're a shopper in a chaotic superstore. Scavenge coins from the aisles, buy
the brainrot figures on your shopping list, and make it to checkout before
Security catches you. Get tagged → you freeze in the aisle until a teammate
rescues you. Escape with the loot to win.

## Genre & references

Asymmetric round-based PvP (Piggy, Flee the Facility, freeze tag).
Collection appeal inspired by Steal a Brainrot.

## Roles

| Role | Goal |
|---|---|
| **Shoppers** (runners) | Collect required items, reach the exit/checkout, escape |
| **Security** (chaser) | Freeze all shoppers before the round timer ends |

Many-weak-vs-few-strong (Among Us model): Security should feel outnumbered
but powerful. Never approach 50/50 — with too many chasers, freeze-tag rescue
breaks (a chaser can guard every frozen shopper).

**AI chaser fallback:** Security can be computer-controlled so the game is
playable solo. Human chasers are always preferred — the AI only fills in when
the lobby is too small (1 player). In solo rounds there are no teammates to
rescue you, so getting frozen ends the round (Security wins) — freeze/rescue
rules are unchanged, that outcome just falls out of them naturally.

## Lobby & player counts

- **Server size:** 10 players max
- **Minimum to start a round: 1** — a solo player gets an AI chaser (see AI
  chaser fallback above). Low minimums are survival-critical for new Roblox
  games — early servers have 1–3 players, and a round that never starts kills
  the game at launch. (Until the AI exists, the prototype uses a minimum of 2.)
- **Intermission:** ~15s countdown in the lobby; if below minimum, wait and
  show "Waiting for players…"
- **Chaser count scales with lobby size:**

| Players in round | Security | Shoppers |
|---|---|---|
| 1 | 1 (AI) | 1 |
| 2–6 | 1 (human) | 1–5 |
| 7–10 | 2 (human) | 5–8 |

## Core loop (one round)

1. Lobby → roles assigned (1 chaser, rest shoppers)
2. Shoppers spawn in the store; each gets a shopping list of brainrot figures
3. Collect items off shelves — best loot is in the riskiest spots
4. Chaser hunts; tagging a shopper **freezes them in place**
5. Teammates can rescue frozen shoppers (risky — see below)
6. Shoppers with a full list reach checkout/exit → escaped (win for them)
7. Round ends when everyone is frozen/out (chaser wins) or timer expires
   (any shopper still free/escaped → shoppers win)

## Collection: coins → brainrot figures

Two-stage collection loop:

1. **Coins** are scattered through the aisles and respawn over time. They're
   the moment-to-moment breadcrumb (Pac-Man pellet logic) — they keep
   shoppers moving through dangerous space instead of beelining to 3 shelves
2. **Figures** sit on shelves with a coin price. Walk up with enough coins →
   scan & pay on the spot. The collectibles ARE the theme: shelves stock
   brainrot figures/plushies

**Decision: pay at the shelf, NOT at a checkout counter.** A pay-at-counter
system makes one mandatory chokepoint that Security will just camp. Pay-at-
shelf spreads the action across the map and gives instant feedback. The
climactic "checkout moment" still exists — the exit zone is a run-through
escape with a completed list, not a stand-still transaction (harder to camp;
keep the storefront exit wide, or add a second exit, if camping shows up in
playtests)
- Shopping list gates the exit — you can't check out until your list is done
  (this is what stops the game from being plain tag)
- Coins are **in-round only** for v1 (balance resets each round). A persistent
  wallet can bridge into the trophy-case meta later
- Pricier figures = more time exposed collecting coins → natural difficulty
  and rarity knob
- Balance lever in reserve: getting frozen drops some of your coins
  (Sonic-style) — extra sting for getting caught, loot for the rescuer to guard
- Rarity tiers later (common → secret); keep prices flat-ish for v1
- Make original knockoff-flavored variants, not direct copies of meme
  characters (IP gray zone; knockoff energy is on-brand anyway)
- Trend-proofing: brainrot is a *skin* on the collectible system, not the core
  identity — shelves can restock with whatever the next trend is

## Freeze & rescue (anti-frustration design)

Goal: no dead time for tagged players, but the chaser must always accumulate
progress (freeze tag's classic failure mode is infinite rescue stalemate).

- Tagged shopper **freezes in place** (no spectator queue, stays in the round)
- Rescue = teammate stands next to them for a **3-second channel**, vulnerable
  the whole time → frozen players become bait the chaser can guard
- Frozen players have a **25-second rescue timer** — not freed in time → out
  for the round → every tag is guaranteed progress for the chaser
- Balance levers held in reserve if playtests feel stalematey:
  - Cap rescues per shopper (e.g. out on 3rd tag)
  - Chaser speed boost for a few seconds after a successful tag
  - Frozen teammates glow/ping on the chaser's screen
  - Chaser slightly faster baseline; runner advantage is agility/hiding

## Build order (prototype)

1. **Graybox map** — simple store layout: aisles, shelves, spawn, checkout/exit
2. **Round manager** — lobby → assign roles → play → win/lose → repeat
3. **Tag/freeze** — chaser touch freezes a shopper; freeze timer; out-tracking
4. **Rescue channel** — 3s proximity channel to unfreeze
5. **Collection** — coin pickups (+ coin counter HUD), purchasable shelf
   figures, per-player shopping list, exit gated on list
6. **Win conditions + timer** — wire up both teams' win/lose states
7. **AI chaser (solo fallback)** — NPC Security guard using PathfindingService:
   wander/patrol until a shopper is in sight, then chase and tag. Built after
   tag/freeze so it reuses the same tagging system. v1 AI can be dumb — it only
   needs to make solo play tense, not clever. Then drop round minimum to 1
8. Playtest → tune numbers (timers, speeds, ratio) before ANY new features

## Monetization

**Golden rule: never sell power in a PvP round.** No paid speed, unfreezes,
revives, or list skips — losers must blame skill, not wallets, or retention
dies. Sell identity, expression, and collection progress instead (the
Piggy / Flee the Facility model).

### Tier 1 — collection meta (the goldmine; needs persistent trophy case)
- Figure rarity tiers — the free-player grind for rares IS the product
- **2x Figure Drops** game pass (faster progression, doesn't win rounds)
- Exclusive/limited/seasonal figures — FOMO is the top Roblox revenue driver
- Figure packs as dev products — if randomized, Roblox policy requires
  disclosed odds (paid loot-box rules); fixed-content packs avoid that

### Tier 2 — cosmetics & expression
- Shopper skins + Security skins (chaser skin = premium real estate, everyone
  sees the chaser)
- Freeze/rescue effects (custom ice, rescue sparkles — visible at the most
  dramatic moments, which is where cosmetics sell)
- Emotes/taunts (taunting the chaser mid-escape is the social loop)
- Cart/trail effects

### Tier 3 — structural
- VIP private servers (friend groups + round-based games; near-zero effort)
- Premium Payouts (automatic; just make the game sticky)

### Anti-patterns (do not build)
- ❌ Pay-to-unfreeze/revive — most tempting dev product in freeze tag, and it
  directly breaks the rescue teamwork loop
- ❌ Any paid round-power (speed, radar, list skips)
- ❌ **Selling in-round coins for Robux** — coins gate the round win, so paid
  coins = pay-to-win. If coins ever become persistent, the sellable thing is
  cosmetic/meta only, never round advantage
- ⚠️ Monetizing before retention — monetization multiplies fun, can't create it

### Sequencing
1. v1 prototype: nothing — prove the loop is fun
2. First pass: VIP servers + 2–3 skins + 2x Drops game pass
3. Real engine: persistent collection + rarity + exclusives, once retention
   numbers show players coming back

## Future add-ons (not in v1 — do not build until core loop is fun)

- **Persistent collection meta** — escaped rounds bank figures into a trophy
  case/inventory between rounds (DataStores); long-term retention hook
- **Paint/camouflage** — consumable paint cans as an escape tool: pop one to
  blend into a shelf for ~3s and break the chaser's lock (Meccha
  Chameleon-inspired; deliberately reactive so it rewards moving, not hiding)
- **Rarity tiers** on figures (common → secret)
- **Chaser team** — 2+ chasers for bigger lobbies
- **Brainrot chaser skins** — chaser plays as a giant brainrot character
- **Jail/holding-pen variant** — send tagged players to a security office that
  teammates raid to free them (more strategic, more camping risk than freeze)
- **"Unpaid cart" mode** — figures are grabbed free but unpaid; Security
  confiscates your cart on tag; pay to secure them. Real shoplifter-vs-security
  fantasy, but needs a carried-inventory system — variant mode only, and it
  reintroduces checkout-camping risk, so it must solve that first

## Open questions

- Round timer length (start ~4–5 min, tune in playtests)
- List size: how many items before checkout unlocks (start ~3)
- Coin economy: coins on map, respawn rate, figure prices (tune so a full
  list takes ~60–70% of the round for an average player)
