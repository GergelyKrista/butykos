# Game Scenes

This directory contains the main game scene hierarchies.

## Structure

- `world_map/` - Strategic layer (50x50 grid, facility placement, logistics)
- `factory_interior/` - Tactical layer (20x20 grid, machine placement, production)

## Scene Transitions

Clicking a facility on the world map loads its factory interior scene.
Factory state persists when returning to the world map.

Pre-load factory scenes and use fade transitions for smooth switching.
