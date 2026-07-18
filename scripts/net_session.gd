class_name NetSession
extends RefCounted
## Жизненный цикл сессии: старт одиночки/хоста/клиента, адреса для приглашений
## Discord, завершение и пинг. RPC-поверхность остаётся в Net (автолоад).

var net # Net-владелец (автолоад): состояние сессии и multiplayer


func _init(net_) -> void:
	net = net_


## Требует уже выставленного campaign_chapter — для сюжета биом берётся по
## текущей главе, а не всегда по первой (иначе продолжение с 3-й главы грузило
## поляну вместо зимы до первого перехода через портал).
func resolve_biome() -> void:
	if net.game_mode == "story":
		var ci: int = clampi(net.campaign_chapter - 1, 0, Quests.CHAPTER_BIOMES.size() - 1)
		net.biome = Quests.CHAPTER_BIOMES[ci]
	elif net.biome_choice == "random":
		net.biome = WorldGen.BIOME_LIST[randi() % WorldGen.BIOME_LIST.size()]
	else:
		net.biome = net.biome_choice


func start_single(mode_name: String = "pve") -> void:
	net.mode = net.Mode.SINGLE
	net.game_mode = mode_name
	net.world_seed = randi()
	net.campaign_chapter = Save.chapter if (net.game_mode == "story" and net.continue_campaign) else 1
	net.sides_mask = Save.sides_mask if (net.game_mode == "story" and net.continue_campaign) else 0
	net.doctrine_steel = Save.doctrine_steel if (net.game_mode == "story" and net.continue_campaign) else 0
	net.doctrine_word = Save.doctrine_word if (net.game_mode == "story" and net.continue_campaign) else 0
	resolve_biome()
	net.players = {1: net._fresh_player(net.my_name)}


func start_host(port: int, mode_name: String, private := false) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, net.MAX_PARTY)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	net.multiplayer.multiplayer_peer = peer
	net.mode = net.Mode.HOST
	net.game_mode = mode_name
	net.host_port = port
	net.session_private = private
	net.party_id = "gs-%d-%d" % [randi(), randi()] # уникальна на сессию, для Discord-пати
	net.world_seed = randi()
	net.campaign_chapter = Save.chapter if (net.game_mode == "story" and net.continue_campaign) else 1
	net.sides_mask = Save.sides_mask if (net.game_mode == "story" and net.continue_campaign) else 0
	net.doctrine_steel = Save.doctrine_steel if (net.game_mode == "story" and net.continue_campaign) else 0
	net.doctrine_word = Save.doctrine_word if (net.game_mode == "story" and net.continue_campaign) else 0
	resolve_biome()
	net.players = {1: net._fresh_player(net.my_name)}
	return OK


func start_client(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	net.multiplayer.multiplayer_peer = peer
	net.mode = net.Mode.CLIENT
	net.players = {}
	return OK


## Все локальные IPv4-адреса хоста (LAN/VPN), кроме петлевого — их и передаём
## в секрете приглашения, чтобы присоединяющийся перебрал их по очереди.
func local_ipv4() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			if not out.has(a):
				out.append(a)
	return out


## Секрет присоединения для Discord: base64(JSON) с адресами хоста и портом.
## Discord доставляет эту строку тому, кто нажал «Join», игра сама подключается.
func build_join_secret() -> String:
	var payload := {"ips": local_ipv4(), "port": net.host_port, "v": 1}
	return Marshalls.utf8_to_base64(JSON.stringify(payload))


## Разбор секрета из Discord: {ips:[...], port:int} или {} при ошибке.
func parse_join_secret(secret: String) -> Dictionary:
	var raw := Marshalls.base64_to_utf8(secret)
	if raw == "":
		return {}
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY or not data.has("ips") or not data.has("port"):
		return {}
	return data


func shutdown(reason: String = "") -> void:
	if net.multiplayer.multiplayer_peer != null and net.mode in [net.Mode.HOST, net.Mode.CLIENT]:
		net.multiplayer.multiplayer_peer.close()
	net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net.mode = net.Mode.NONE
	net.players = {}
	net.game = null
	if reason != "":
		net.session_ended.emit(reason)


## Пинг (мс): клиент — до сервера, хост — худший из пингов клиентов.
## −1, если сессии нет (одиночка) или мерить не с кем.
func ping_ms() -> int:
	if net.multiplayer.multiplayer_peer == null:
		return -1
	if net.mode == net.Mode.CLIENT:
		var peer: ENetPacketPeer = net.multiplayer.multiplayer_peer.get_peer(1)
		if peer == null:
			return -1
		return peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	if net.mode == net.Mode.HOST:
		var worst := -1
		for pid in net.players:
			if pid == 1:
				continue
			var peer: ENetPacketPeer = net.multiplayer.multiplayer_peer.get_peer(pid)
			if peer != null:
				worst = maxi(worst, peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		return worst
	return -1
