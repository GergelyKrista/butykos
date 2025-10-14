extends Node

## EventBus - Signal-based event system for decoupled communication
##
## Usage: EventBus.emit_signal("facility_placed", facility_data)
##        EventBus.facility_placed.connect(_on_facility_placed)

# ========================================
# GAME STATE SIGNALS
# ========================================

## Emitted when game is paused/unpaused
signal game_paused(is_paused: bool)

## Emitted when player money changes
signal money_changed(new_amount: int, delta: int)

## Emitted when game date advances
signal date_advanced(new_date: Dictionary)

# ========================================
# FACILITY & WORLD SIGNALS
# ========================================

## Emitted when a facility is placed on the world map
signal facility_placed(facility_data: Dictionary)

## Emitted when a facility is selected
signal facility_selected(facility_id: String)

## Emitted when a facility is removed
signal facility_removed(facility_id: String)

## Emitted when a facility completes construction
signal facility_constructed(facility_id: String)

# ========================================
# FACTORY INTERIOR SIGNALS
# ========================================

## Emitted when entering factory interior view
signal factory_entered(factory_id: String)

## Emitted when exiting factory interior view
signal factory_exited(factory_id: String)

## Emitted when a machine is placed in a factory
signal machine_placed(factory_id: String, machine_data: Dictionary)

## Emitted when a machine is removed from a factory
signal machine_removed(factory_id: String, machine_id: String)

## Emitted when production starts/stops in a factory
signal production_changed(factory_id: String, is_producing: bool)

# ========================================
# LOGISTICS SIGNALS
# ========================================

## Emitted when a route is created between facilities
signal route_created(route_data: Dictionary)

## Emitted when a route is removed
signal route_removed(route_id: String)

## Emitted when a vehicle is created
signal vehicle_created(vehicle_data: Dictionary)

## Emitted when cargo is delivered
signal cargo_delivered(vehicle_id: String, cargo_data: Dictionary)

# ========================================
# MARKET & ECONOMY SIGNALS
# ========================================

## Emitted when a product is sold to a market
signal product_sold(product_type: String, quantity: int, revenue: int)

## Emitted when market prices change
signal market_prices_updated(market_data: Dictionary)

## Emitted when a contract is accepted
signal contract_accepted(contract_data: Dictionary)

## Emitted when a contract is completed
signal contract_completed(contract_id: String, reward: int)

# ========================================
# UI SIGNALS
# ========================================

## Emitted when a UI panel needs to be shown
signal ui_panel_requested(panel_name: String, data: Dictionary)

## Emitted when a notification should be displayed
signal notification_posted(message: String, type: String)

## Emitted when player requests help/tutorial
signal help_requested(topic: String)

# ========================================
# SAVE/LOAD SIGNALS
# ========================================

## Emitted before saving game state
signal before_save()

## Emitted after loading game state
signal after_load()

## Emitted when save operation completes
signal save_completed(success: bool)


func _ready() -> void:
	print("EventBus initialized")
