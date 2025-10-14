# Game System Managers

This directory contains manager scripts for major game systems.

## Files

- `world_manager.gd` - World map grid, facility placement, resource nodes
- `factory_manager.gd` - Factory interior state, machine placement, production tracking
- `logistics_manager.gd` - Vehicles, routes, cargo transport between facilities
- `market_manager.gd` - Supply/demand simulation, pricing, sales contracts
- `economy_manager.gd` - Currency, expenses, revenue tracking, balance sheets

## Usage

These managers are also configured as autoloads and handle specific game domains.
They communicate via EventBus signals and maintain their own internal state.
