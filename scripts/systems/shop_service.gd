class_name ShopService
extends RefCounted
## Лавка торговца: открытие/закрытие UI и серверные покупка/продажа.

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


func open_shop() -> void:
	game.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.open_shop(Items.shop_stock(Net.world_seed, Net.campaign_chapter), game.inventory, game.gold)


func close_shop() -> void:
	game.ui_blocked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.hud.close_shop()


## Покупка (сервер): позиция ассортимента пересчитывается тем же сидом —
## клиент не может подсунуть свой товар или цену.
func server_buy(sender: int, stock_idx: int) -> void:
	if not game.is_story() or game.match_over:
		return
	var stock := Items.shop_stock(Net.world_seed, Net.campaign_chapter)
	if stock_idx < 0 or stock_idx >= stock.size():
		return
	var entry: Dictionary = stock[stock_idx]
	if game.server_gold < entry.price:
		Net.send_sys(sender, "Не хватает золота.")
		return
	var item: Dictionary = entry.item.duplicate(true)
	var ok: bool
	if item.kind == "consumable":
		game._server_grant_item(sender, item.id)
		ok = true
	else:
		ok = game._server_grant_equipment(sender, item)
	if not ok:
		Net.send_sys(sender, "Инвентарь полон.")
		return
	game.server_gold -= entry.price
	Net.bcast("rpc_gold", [game.server_gold])
	Net.send_sys(sender, "Куплено: %s" % tr(Items.def_name(item)))


## Продажа (сервер): предмет из инвентаря — в золото отряда.
func server_sell(sender: int, inv_idx: int) -> void:
	if not game.is_story() or game.match_over:
		return
	var inv: Array = game.server_inv.get(sender, [])
	if inv_idx < 0 or inv_idx >= inv.size():
		return
	var item: Dictionary = inv[inv_idx]
	var price := Items.sell_price(item)
	if int(item.get("count", 1)) > 1:
		item.count -= 1
	else:
		inv.remove_at(inv_idx)
	game.server_inv[sender] = inv
	game._sync_inv(sender)
	game.server_gold += price
	Net.bcast("rpc_gold", [game.server_gold])
	Net.send_sys(sender, "Продано: %s (+%d з.)" % [tr(Items.def_name(item)), price])
