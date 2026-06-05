# Per-corp responsibilities, slice-1 brewery chain, and design open questions

**Date:** 2026-06-05
**Author:** Ambrus (artist)
**Captured by:** Claude (in-session brainstorm dump)
**Status:** Design intent — not all parts are implementation-ready. Items marked **[shipped]** are already live on a branch; **[needs plan]** items need their own architect pass before code.

---

## 1. Context

After landing the dev corp switcher (`feature/corp-switcher-debug-ui`), the artist worked through what each corp actually *owns* and *does* in slice‑1, plus an end‑to‑end pass of the brewery interior production chain. This doc preserves that direction so subsequent sessions don't have to re‑derive it.

The first two items (corp ownership mapping + per‑corp build menus) are already implemented. Everything from §3 down is design intent that still needs implementation work, in some cases significant.

---

## 2. Per‑corp ownership mapping  **[shipped — commit `f5142ed`]**

Every facility and road now carries a `corp_id` field. The build menu filters by `GameManager.active_corp_id`.

| Domain | Corp | Concretes |
|---|---|---|
| Agriculture | `agri` | farmhouse, all crop fields, hop farm, vineyard, water source (legacy — see §8) |
| Processing + Production | `industrial` | grain mill / malt house, brewery, distillery, packaging plant, industrial mill, lager brewery, all whiskey/vodka/winery/tavern/trade office variants (tavern + trade office are likely Business once Business lands — see §9) |
| Storage | `logistics` | storage warehouse, aging cellar, barrel house, distribution depot, rail depot |
| Main road network | `logistics` | `dirt_road`, `cobblestone_road` |
| Farm roads | `agri` | `agri_road_dirt` (new — separate "actor" from logistics roads so its functionality can diverge) |
| Routing tools | `logistics` | Logistics Network panel, Create Route tool |
| Demolish | every corp | Each corp demolishes only what it owns (ownership predicate from Phase 8 step 1) |
| Business corp | — | No buildings yet (placeholder for Phase 11+ spatial demand / contracts work) |

`single` (dev/legacy default) bypasses the filter — shows everything. Useful for testing without a hot‑seat flow.

`shared` is reserved for cross‑corp infrastructure (Phase 11 utilities, shared research). No facilities use it today.

---

## 3. Slice‑1 brewery interior production chain  **[needs plan]**

> The current brewery interior chain is a placeholder. The chain below is the intended slice‑1 build. It requires several new machines, several new products, and **multi‑input recipes** (`data/recipes.json` is empty today per CLAUDE.md).

### 3.1 Chain diagram

```
external inputs (via Input Hopper, configured per hopper):
  Malt   ←  Malt House (off‑map, world‑map facility)
  Water  ←  Water source / water pipe / tanker (see §8)
  Hops   ←  Hop Farm (off‑map, world‑map facility, Agri corp)
  Bottles ← Packaging Plant (see §7)

Input Hopper (set to "Malt")
  → Mill (2×2)              [NEW]   malt → grist
  → Mash Tun (existing)      grist + water (from another Input Hopper set to "Water") → mash
  → Lauter Tun (2×2)        [NEW]   mash → wort
  → Brewer                  [NEW]   wort + hops (from Input Hopper set to "Hops") → boiled_wort
  → Whirlpool Separator (2×2) [NEW] boiled_wort → cleaned_wort  (separates sediment)
  → Cooler (1×2)            [NEW]   cleaned_wort → cooled_wort
  → Fermentation Vessel (2×3) [NEW] cooled_wort → green_beer
  → Maturation Tank (2×3)   [NEW]   green_beer → matured_beer  (a.k.a. lagering)
  → Filtration Unit         [NEW]   matured_beer → finished_beer
  → Bottling Line (existing) finished_beer + bottles (from Input Hopper set to "Bottles") → lager
→ Output Depot → facility inventory → logistics route out → Storage Warehouse OR sale outlet
```

### 3.2 New products needed in `data/products.json`

- `grist` — intermediate (post‑mill, pre‑mash)
- `wort` — intermediate (post‑lauter, pre‑brew)
- `boiled_wort` — intermediate (post‑brewer, pre‑whirlpool)
- `cleaned_wort` — intermediate (post‑whirlpool, pre‑cool)
- `cooled_wort` — intermediate (post‑cool, pre‑ferment)
- `green_beer` — intermediate (post‑ferment, pre‑maturation)
- `matured_beer` — intermediate (post‑maturation, pre‑filter)
- `finished_beer` — intermediate (post‑filter, pre‑bottling)
- `hops` — raw input from Hop Farm (Agri corp)
- `bottles` — input from Packaging Plant
- `water` — raw input from water source / pipe / tanker

> Open question: do we want **separate** product IDs at every stage, or fewer aggregated stages? Each new product is a balance‑tuning surface. Lean toward fewer if the player can't act on the distinction.

### 3.3 New machines needed in `data/machines.json`

`Mill`, `Lauter Tun`, `Brewer`, `Whirlpool Separator`, `Cooler`, `Fermentation Vessel`, `Maturation Tank`, `Filtration Unit`. Sizes per the diagram above.

### 3.4 Multi‑input recipes — the gating issue

Mash Tun, Brewer, and Bottling Line each accept **two inputs**. The current production system processes one input at a time. The multi‑input case lands in `data/recipes.json` (empty today) and needs the production tick to understand "wait until *all* required inputs are present, then consume *all of them* together, then emit output."

This is one of the bigger pieces — likely warrants its own implementation plan (`design_docs/plans/2026-MM-DD_multi_input_recipes.md`).

### 3.5 Input Hopper: per‑hopper product dropdown  **[needs plan]**

Today the Input Hopper pulls whatever the facility holds. In slice‑1 it needs a **per‑hopper config**: click the hopper, pick a product from a dropdown ("Malt", "Water", "Hops", "Bottles" — populated from the products the facility's machines actually consume). The hopper then only pulls that one product from facility inventory.

UX: click hopper → small popup with dropdown → product persists per‑hopper across save/load.

---

## 4. Brewery interior cleanup — remove placeholders  **[easy]**

Three machines currently in the brewery interior are leftovers from the pre‑pivot design and should be removed before slice‑1:

- **Market Outlet** — selling will be a Business corp system in Phase 11 (spatial demand / contracts), not a per‑facility outlet. The brewery shouldn't sell directly.
- **Water Pump** — water becomes an outside building / utility (see §8). The brewery should not contain its own water source.
- **Steam Boiler** — currently has no clear function; not needed for the brewery chain. Cut.

These can either be removed entirely or marked `hidden_from_build_menu: true` and unused until repurposed. Removing is cleaner.

---

## 5. Asymmetric permissions: view vs. modify  **[needs plan]**

> "Every corp can look inside breweries but only industrial can build/modify/demolish."

This is a new permission concept. Today the permission model is binary (owner vs. not‑owner). The artist's vision adds a **read** level that's broader than the owner.

Suggested model:
- Each facility has `corp_id` (owner, write access) — exists today
- Plus optional `viewable_by: ["agri", "industrial", "logistics", "business"]` (defaults to `[corp_id]` if absent — owner‑only view)
- For breweries (and presumably all factory interiors): `viewable_by: ["agri", "industrial", "logistics", "business"]` (everyone sees inside)
- UI: when a non‑owner enters the interior, all build/modify/demolish UI is **hidden or grey‑disabled** (predicate rejection would be too late — UX needs to flag it before the click)

Decide:
- Per‑facility setting, or global rule ("all factory interiors are viewable by all corps")?
- Does **view** include seeing production state and inventory? Probably yes — that's the whole point (co‑op visibility into what your teammate is doing).

Lands during Phase 10 corp scaffold; depends on having multiple corps simultaneously meaningful in‑session (i.e. hot‑seat flow real, not just the dev switcher).

---

## 6. Field placement: rectangular, not radial  **[needs plan]**

Today fields are placed via a circular‑ish radius around the farmhouse. The artist wants rectangular placement so:

- Fields can be tiled neatly next to each other
- Adjacent‑side road connections make sense visually
- Fields and orchards must either **touch the farmhouse** OR be **connected to it via dirt road** (likely `agri_road_dirt`)

Implementation lives in `WorldManager.can_place_field_for_farmhouse` (currently a radius check). New rule: rectangle adjacency + road‑path check. Reuses the existing `find_road_path` machinery (Phase 8 step 3 work).

---

## 7. Wire up the orphan buildings — Packaging Plant + Storage Warehouse  **[easy‑ish]**

### 7.1 Packaging Plant → produces bottles

The Packaging Plant currently does nothing meaningful. Repurpose: it becomes the source of `bottles`, which the brewery's Bottling Line consumes. Production recipe (single input):

```
Packaging Plant: <some_input>  → bottles
```

Open: what's the input? Could be a raw material (glass cullet? sand?) or pure energy/time (no input — abstract "manufacturing"). Simplest for slice‑1: zero input, just produces bottles on a timer. Tune cost later.

### 7.2 Storage Warehouse → can hold beer

The Storage Warehouse should accept any finished product via logistics connection — at minimum `lager` from the brewery. Today it likely exists as a passive placeholder. Implementation:

- Mark it as `accepted_inputs: ["lager", "ale", ...]` (whatever finished products exist)
- Its inventory acts as a buffer for downstream sale
- No production cycle of its own — pure storage

Logistics tie‑in: routes can target storage warehouse with finished products. Storage warehouse can be source of routes to (eventual) sales outlets.

---

## 8. Water as a utility — outside the brewery  **[needs plan, Phase 11]**

The artist wants water to be a **planning concern**: where are water sources, how does it reach production buildings. Two transport options:

- **Water pipes** — placed like roads but on a separate "pipe network." Pipes carry water from a Water Source to consuming facilities.
- **Tanker vehicles** — drive on roads, carry water like any other cargo. Slower / less efficient but flexible.

This is Phase 11 utilities territory per the roadmap (`CLAUDE.md` Phase 11). One `UtilityManager`, multiple named graphs (water, sewage, power). Pipes use the same node‑graph machinery as logistics routes but on a separate layer that ignores the road graph.

In the meantime, water is a placeholder — the brewery chain documentation above assumes water is "available" without modeling the network.

Side note: the existing `water_source` facility today is tagged `corp_id: agri`. It might want to be `corp_id: shared` (utility infrastructure) instead. To decide when water is actually modeled.

---

## 9. Open questions to resolve later

1. **Tavern + Trade Office corp assignment.** Currently `industrial` because of their JSON `category: production`. Both feel more Business than Industrial. Move when Business corp has a clear domain definition.
2. **Hop Farm** — currently in `facilities.json` under `agriculture` (Agri corp) — needs the farmhouse‑crop‑rotation UI to support `hops` as a crop type. The data is there; the farmhouse UI needs the option.
3. **What does Business corp own in slice‑1?** Nothing buildable today. Likely candidates: tavern, trade office, sales outlets (don't exist yet), contracts UI. Define before Phase 10 wraps.
4. **Where does the dev corp switcher live long‑term?** Today it's a permanent debug widget. For hot‑seat play, this evolves into a "turn end → switch player" prompt. For network MP, it disappears entirely. The switcher in `world_map_ui.gd:_create_corp_switcher` should be wrapped in a debug flag before networked MP lands.
5. **Demolish refund UX** — still open from 2026‑06‑04 BUGS.md. Tied to the "undo window" question.

---

## 10. Implementation order suggestion

Given Phase 8 step 3c is queued for merge and Phase 10 step 0a/0b just shipped, a reasonable next sequence:

1. **Brewery interior cleanup** (§4) — remove Market Outlet, Water Pump, Steam Boiler. Trivial JSON / data change. Unblocks the brewery interior for the new chain.
2. **Hop Farm crop support** (§9.2) — farmhouse UI gains `hops` as a crop choice. Already a facility; just wire it up.
3. **Packaging Plant + Storage Warehouse wiring** (§7) — both are easy single‑recipe additions. Adds meaningful gameplay loops.
4. **Multi‑input recipes** (§3.4) — bigger refactor. Needed before the new brewery chain. Probably own architect plan.
5. **New brewery machines + products** (§3.2, §3.3) — large data addition. Depends on (4).
6. **Input Hopper per‑hopper product config** (§3.5) — UX addition. Depends on (4).
7. **Asymmetric view/modify permissions** (§5) — needed once multiple corps are meaningfully simultaneous.
8. **Rectangular field placement** (§6) — feels low‑priority unless you're already pained by the current placement. Worth doing alongside the hop‑farm + farmhouse work in (2).
9. **Water utility network** (§8) — defer to Phase 11.

(1)–(3) and (8) are essentially data + small UI work and can land in a single session each.
(4)–(6) are real engineering and want their own plans.
(7) and (9) are big design pieces.

---

## Memory hooks (for future sessions)

- The corp mapping in §2 is **canonical** until the user reassigns.
- Tavern, Trade Office, water_source corp assignments are flagged as **likely to move** — don't treat as load‑bearing.
- The slice‑1 brewery chain in §3 supersedes any earlier chain description; treat older docs as historical.
