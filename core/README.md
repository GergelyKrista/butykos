# Core Singleton Managers

This directory contains singleton autoload scripts that manage global game state.

## Files

- `game_manager.gd` - Main game loop, state transitions, and global coordination
- `event_bus.gd` - Signal-based event system for decoupled communication
- `save_manager.gd` - Save/load game state, player preferences

## Usage

All scripts in this directory are configured as autoloads in Project Settings.
Access them globally via their singleton names (e.g., `GameManager.pause_game()`).
