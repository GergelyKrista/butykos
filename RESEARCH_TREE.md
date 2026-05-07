# Research Tree Design — Alcohol Empire Tycoon (PRE-PIVOT SNAPSHOT)

> **⚠️ Pre-pivot single-tree design.** The Drinkustry pivot splits research into two layers: per-corp internal (boosts/efficiency) + shared higher-level (new chains/tiers/vehicles). The 40 nodes below stay as content but get tagged `tier: "corp_internal"` and distributed across the four corps in new Phase 8. The tier-unlock-by-selling mechanic stays for the corp-internal layer; shared layer is funded by shared credits with proposal/vote UI.
>
> See `design_docs/2026-04-30_design_summary.html` (Two-Layer Tech Tree section) and `design_docs/2026-05-07_technical_architecture.html` for the refactor.

## Overview

A **Satisfactory-style tier system** with **8 horizontal branches**, each containing **5 progressive technologies**.

**Tier System:**
- **Tier 1:** Unlocked from the start - buy with money
- **Tier 2-5:** Unlock by SELLING products (tracked automatically)

**Starting Money:** $100,000
**Research Costs:** $5,000 → $150,000 (scales with tier)
**Upgrade Costs:** Separate from research (building-specific)

---

## Tier Unlock Requirements

To unlock each tier, you must **sell** the required products:

| Tier | Product Requirements |
|------|---------------------|
| **Tier 1** | Unlocked by default |
| **Tier 2** | 500 Barley + 500 Wheat + 100 Malt |
| **Tier 3** | 200 Ale + 500 Malt + 100 Raw Spirit |
| **Tier 4** | 300 Packaged Ale + 100 Whiskey + 500 Mash |
| **Tier 5** | 500 Whiskey + 500 Packaged Ale + 200 Vodka |

Product sales are tracked automatically. When all requirements for a tier are met, that tier unlocks immediately.

---

## Visual Tree Structure

```
TIER 1: FOUNDATIONS         TIER 2: EXPANSION          TIER 3: INDUSTRIALIZATION     TIER 4: MODERNIZATION        TIER 5: MASTERY
($5K-$10K)                  ($12K-$25K)                ($30K-$50K)                   ($60K-$100K)                 ($120K-$150K)
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

AGRICULTURE BRANCH
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Crop         │────▶│ Fertilizers  │────▶│ Crop         │────▶│ Mechanized   │────▶│ Agricultural │
│ Rotation     │     │              │     │ Genetics     │     │ Harvesting   │     │ Science      │
│ $5,000       │     │ $15,000      │     │ $35,000      │     │ $70,000      │     │ $130,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                                │                      │
                                                ▼                      ▼
GRAIN PROCESSING BRANCH                    (cross-link)           (cross-link)
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Millstone    │────▶│ Water        │────▶│ Steam        │────▶│ Roller       │────▶│ Automated    │
│ Grinding     │     │ Mills        │     │ Power        │     │ Mills        │     │ Milling      │
│ $6,000       │     │ $14,000      │     │ $32,000      │     │ $65,000      │     │ $125,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                                         │
       ▼                                         ▼
BREWING BRANCH                              (cross-link)
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Basic        │────▶│ Yeast        │────▶│ Temperature  │────▶│ Lager        │────▶│ Master       │
│ Fermentation │     │ Cultivation  │     │ Control      │     │ Brewing      │     │ Brewer       │
│ $8,000       │     │ $18,000      │     │ $38,000      │     │ $75,000      │     │ $140,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                    │                    │                    │
       │                    ▼                    ▼                    ▼
       │              (cross-link)         (cross-link)         (cross-link)
       ▼
DISTILLATION BRANCH
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Pot          │────▶│ Copper       │────▶│ Double       │────▶│ Column       │────▶│ Continuous   │
│ Stills       │     │ Condensers   │     │ Distillation │     │ Stills       │     │ Distillation │
│ $10,000      │     │ $20,000      │     │ $42,000      │     │ $80,000      │     │ $150,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                            │                    │                    │
                            ▼                    ▼                    ▼
                      (cross-link)         (cross-link)         (cross-link)

AGING & MATURATION BRANCH
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Oak          │────▶│ Charred      │────▶│ Climate      │────▶│ Solera       │────▶│ Angel's      │
│ Barrels      │     │ Barrels      │     │ Cellars      │     │ System       │     │ Share        │
│ $7,000       │     │ $16,000      │     │ $36,000      │     │ $72,000      │     │ $135,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                    │                    │
       ▼                    ▼                    ▼
  (cross-link)        (cross-link)         (cross-link)

PACKAGING & QUALITY BRANCH
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Wooden       │────▶│ Glass        │────▶│ Quality      │────▶│ Premium      │────▶│ Luxury       │
│ Casks        │     │ Bottles      │     │ Control      │     │ Branding     │     │ Editions     │
│ $5,000       │     │ $15,000      │     │ $34,000      │     │ $68,000      │     │ $128,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                            │                    │                    │
                            ▼                    ▼                    ▼
                      (cross-link)         (cross-link)         (cross-link)

LOGISTICS BRANCH
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Horse        │────▶│ Improved     │────▶│ Steam        │────▶│ Rail         │────▶│ National     │
│ Carts        │     │ Roads        │     │ Wagons       │     │ Transport    │     │ Distribution │
│ $6,000       │     │ $14,000      │     │ $30,000      │     │ $62,000      │     │ $120,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                                │                    │
                                                ▼                    ▼
                                          (cross-link)         (cross-link)

COMMERCE BRANCH
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Local        │────▶│ Regional     │────▶│ Trade        │────▶│ Export       │────▶│ Global       │
│ Markets      │     │ Trade        │     │ Agreements   │     │ License      │     │ Empire       │
│ $5,000       │     │ $12,000      │     │ $28,000      │     │ $58,000      │     │ $145,000     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

---

## Detailed Technology Descriptions

### AGRICULTURE BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Crop Rotation** | 1 | $5,000 | None | Barley Field Lvl 2, Wheat Farm Lvl 2 |
| **Fertilizers** | 2 | $15,000 | Crop Rotation | +25% all crop yields |
| **Crop Genetics** | 3 | $35,000 | Fertilizers | Barley Field Lvl 3, Wheat Farm Lvl 3, unlock Corn |
| **Mechanized Harvesting** | 4 | $70,000 | Crop Genetics + Steam Power | -40% field cycle time |
| **Agricultural Science** | 5 | $130,000 | Mechanized Harvesting | Unlock Hops Farm, Vineyard |

### GRAIN PROCESSING BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Millstone Grinding** | 1 | $6,000 | None | Grain Mill Lvl 2 |
| **Water Mills** | 2 | $14,000 | Millstone Grinding | +20% mill speed |
| **Steam Power** | 3 | $32,000 | Water Mills | Grain Mill Lvl 3, enables Mechanized Harvesting |
| **Roller Mills** | 4 | $65,000 | Steam Power | +40% mill efficiency, higher malt quality |
| **Automated Milling** | 5 | $125,000 | Roller Mills + Rail Transport | Mills auto-request inputs |

### BREWING BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Basic Fermentation** | 1 | $8,000 | Millstone Grinding | Brewery Lvl 2 |
| **Yeast Cultivation** | 2 | $18,000 | Basic Fermentation | +15% ale quality, consistent output |
| **Temperature Control** | 3 | $38,000 | Yeast Cultivation + Steam Power | Brewery Lvl 3, unlock Wheat Beer |
| **Lager Brewing** | 4 | $75,000 | Temperature Control + Climate Cellars | Unlock Lager ($140/unit) |
| **Master Brewer** | 5 | $140,000 | Lager Brewing + Premium Branding | Unlock Stout, Porter, +50% all beer prices |

### DISTILLATION BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Pot Stills** | 1 | $10,000 | Basic Fermentation | Distillery Lvl 2 |
| **Copper Condensers** | 2 | $20,000 | Pot Stills | +20% spirit purity |
| **Double Distillation** | 3 | $42,000 | Copper Condensers + Charred Barrels | Distillery Lvl 3, unlock Whiskey |
| **Column Stills** | 4 | $80,000 | Double Distillation | Unlock Vodka, +30% distillery speed |
| **Continuous Distillation** | 5 | $150,000 | Column Stills + Automated Milling | Distillery Lvl 4, -60% cycle time |

### AGING & MATURATION BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Oak Barrels** | 1 | $7,000 | None | Storage Warehouse Lvl 2, basic aging |
| **Charred Barrels** | 2 | $16,000 | Oak Barrels | +25% aged spirit value |
| **Climate Cellars** | 3 | $36,000 | Charred Barrels | Storage Warehouse Lvl 3, enables Lager |
| **Solera System** | 4 | $72,000 | Climate Cellars + Quality Control | Unlock Premium Whiskey ($350/unit) |
| **Angel's Share** | 5 | $135,000 | Solera System | Unlock 25-Year Reserve ($500/unit) |

### PACKAGING & QUALITY BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Wooden Casks** | 1 | $5,000 | None | Packaging Plant Lvl 2 |
| **Glass Bottles** | 2 | $15,000 | Wooden Casks | +20% packaged product value |
| **Quality Control** | 3 | $34,000 | Glass Bottles | Packaging Plant Lvl 3, reject low-quality |
| **Premium Branding** | 4 | $68,000 | Quality Control + Trade Agreements | +35% all product prices |
| **Luxury Editions** | 5 | $128,000 | Premium Branding + Solera System | Unlock Limited Edition products (+100% value) |

### LOGISTICS BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Horse Carts** | 1 | $6,000 | None | +25% vehicle speed |
| **Improved Roads** | 2 | $14,000 | Horse Carts | +25% vehicle speed, +50% capacity |
| **Steam Wagons** | 3 | $30,000 | Improved Roads + Steam Power | +50% speed, +100% capacity |
| **Rail Transport** | 4 | $62,000 | Steam Wagons | +100% speed, unlimited capacity |
| **National Distribution** | 5 | $120,000 | Rail Transport + Export License | Instant delivery anywhere |

### COMMERCE BRANCH

| Tech | Tier | Cost | Prerequisites | Unlocks |
|------|-----|------|---------------|---------|
| **Local Markets** | 1 | $5,000 | None | +10% sell prices |
| **Regional Trade** | 2 | $12,000 | Local Markets | +15% sell prices, market demand visible |
| **Trade Agreements** | 3 | $28,000 | Regional Trade | Contract bonuses +25% |
| **Export License** | 4 | $58,000 | Trade Agreements + Quality Control | Access foreign markets (+50% prices) |
| **Global Empire** | 5 | $145,000 | Export License + National Distribution | +100% all prices, win condition? |

---

## Cross-Branch Prerequisites (Key Dependencies)

These are the critical cross-branch links that create interesting tech choices:

```
Steam Power (Processing) ────────────┬──▶ Mechanized Harvesting (Agriculture)
                                     ├──▶ Temperature Control (Brewing)
                                     └──▶ Steam Wagons (Logistics)

Charred Barrels (Aging) ─────────────────▶ Double Distillation (Distillation)

Climate Cellars (Aging) ─────────────────▶ Lager Brewing (Brewing)

Quality Control (Packaging) ─────────┬──▶ Solera System (Aging)
                                     └──▶ Export License (Commerce)

Trade Agreements (Commerce) ─────────────▶ Premium Branding (Packaging)

Rail Transport (Logistics) ──────────┬──▶ Automated Milling (Processing)
                                     └──▶ National Distribution (Logistics)

Premium Branding (Packaging) ────────────▶ Master Brewer (Brewing)

Solera System (Aging) ───────────────────▶ Luxury Editions (Packaging)

Export License (Commerce) ───────────────▶ National Distribution (Logistics)
```

---

## Building Upgrade Requirements

Buildings can only be upgraded after researching the required technology:

| Building | Level 2 | Level 3 | Level 4 |
|----------|---------|---------|---------|
| **Barley Field** | Crop Rotation ($1,500) | Crop Genetics ($4,000) | - |
| **Wheat Farm** | Crop Rotation ($1,750) | Crop Genetics ($4,500) | - |
| **Grain Mill** | Millstone Grinding ($2,500) | Steam Power ($6,000) | - |
| **Brewery** | Basic Fermentation ($4,000) | Temperature Control ($10,000) | - |
| **Distillery** | Pot Stills ($5,000) | Double Distillation ($12,000) | Continuous Distillation ($25,000) |
| **Packaging Plant** | Wooden Casks ($3,000) | Quality Control ($8,000) | - |
| **Storage Warehouse** | Oak Barrels ($2,500) | Climate Cellars ($6,000) | - |

**Upgrade Cost** = Listed cost (paid per building instance)
**Research Cost** = One-time unlock for all buildings of that type

---

## Research Point System (Alternative to Direct Purchase)

Instead of buying research directly, could use research points:

| Source | Points/Cycle |
|--------|--------------|
| Each active Brewery | +1 RP |
| Each active Distillery | +2 RP |
| Research Lab building | +5 RP |
| University building | +10 RP |

**Or stick with direct money purchase for simplicity.**

---

## Tier Progression Summary

| Tier | Tech Count | Total Cost | Cumulative |
|-----|------------|------------|------------|
| Tier 1: Foundations | 8 techs | $52,000 | $52,000 |
| Tier 2: Expansion | 8 techs | $124,000 | $176,000 |
| Tier 3: Industrialization | 8 techs | $275,000 | $451,000 |
| Tier 4: Modernization | 8 techs | $550,000 | $1,001,000 |
| Tier 5: Mastery | 8 techs | $1,073,000 | $2,074,000 |

**Total to research everything: ~$2,000,000**

---

## Implementation Notes

### Data Structure (research_tree.json)
```json
{
  "crop_rotation": {
    "id": "crop_rotation",
    "name": "Crop Rotation",
    "branch": "agriculture",
    "era": 1,
    "cost": 5000,
    "prerequisites": [],
    "unlocks": {
      "building_upgrades": ["barley_field_2", "wheat_farm_2"],
      "bonuses": []
    },
    "description": "Alternate crops yearly to maintain soil fertility."
  }
}
```

### ResearchManager Singleton
- Track unlocked research
- Check prerequisites before allowing research
- Emit signals when research completes
- Save/load research state

### UI Requirements
- Research tree panel (scrollable, zoomable)
- Tech nodes with icons
- Prerequisite lines
- Locked/unlocked/researching states
- Cost display
- "Research" button

---

## Questions for Review

1. **Cost Balance:** Are costs appropriate for $100K start? (Tier 1 = 5-10% of starting money)
2. **Complexity:** 40 total techs - too many? Too few?
3. **Cross-links:** Are the dependencies interesting without being frustrating?
4. **Research Time:** Instant unlock, or takes in-game days?
5. **Research Points:** Use money directly, or introduce research point currency?
6. **Building Levels:** Max level 3 for most, level 4 for distillery only?

---

## Future Testing & Enhancement

### Testing Checklist

- [ ] **Prerequisite Validation:** Cannot research tech without all prerequisites unlocked
- [ ] **Cost Deduction:** Money properly deducted when researching
- [ ] **Insufficient Funds:** Cannot research if money < cost
- [ ] **Unlock Persistence:** Research state persists across save/load
- [ ] **Building Upgrades:** Upgrade buttons only appear after research
- [ ] **Cross-Branch:** Cross-branch prerequisites properly enforced
- [ ] **UI State:** Locked/unlocked/researching states display correctly
- [ ] **Bonus Application:** Production bonuses apply correctly after research

### Balance Testing Questions

1. Can a new player afford at least 2-3 Tier 1 techs with starting $100K?
2. Is there a viable "rush" strategy to get to Tier 3 quickly?
3. Do cross-branch dependencies force meaningful choices?
4. Is the Distillery path (expensive) balanced against Brewery path?
5. Are late-game techs ($120K+) reachable within reasonable playtime?

### Future Enhancements

1. **Visual Tech Tree:** Graphical node-based tree with pan/zoom
2. **Research Time:** Option for techs to take in-game time (not instant)
3. **Research Points:** Alternative currency generated by buildings
4. **Tech Advisor:** AI suggestions based on current empire focus
5. **Achievements:** Unlock achievements for research milestones
6. **Alternative Paths:** Multiple ways to reach same end-game techs
7. **Tech Synergies:** Bonus effects when combining certain techs
8. **Era Gates:** Require X techs from Era N before Era N+1 unlocks
9. **Random Events:** Research breakthroughs (faster) or setbacks
10. **Competitor Research:** AI competitors racing for same techs

### Known Limitations (Current Implementation)

- Instant research (no time delay)
- Money-based only (no research points)
- No visual tree UI (list-based for MVP)
- No partial refunds for unused techs
- Building bonuses not yet implemented (placeholder values)

---

## Next Steps

1. Review and adjust this design
2. Create `data/research_tree.json`
3. Implement `systems/research_manager.gd`
4. Add Research UI panel
5. Integrate with building upgrade system
6. Add research state to save/load
