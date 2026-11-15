class_name WizardClient
extends Node

signal state_received(state: Dictionary)
signal rooms_updated(rooms: Array)
signal connected_to_room()
signal connection_error(message: String)
signal disconnected(reason: String)

const DISCOVERY_PORT := 40393

var _ws: WebSocketPeer = null
var _udp: PacketPeerUDP = null
var _discovering := false
var _probe_timer := 0.0
var _discovered: Dictionary = {} # ip -> {room_name, host_name, player_count, max_players, ip, ws_port, last_seen}

var _target_url := ""
var _player_name := "Player"
var _session_token := ""
var _joined := false
var _manual_disconnect := false
var _ping_timer := 0.0

func start_discovery() -> void:
	if _discovering:
		return
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(DISCOVERY_PORT)
	if err != OK:
		# Fallback: bind ephemeral port so we can still send probes and receive direct replies
		_udp.bind(0)
	_discovering = true
	_discovered.clear()
	_probe_timer = 0.0
	_send_probe()

func stop_discovery() -> void:
	_discovering = false
	if _udp != null:
		_udp.close()
		_udp = null
	_discovered.clear()

func _send_probe() -> void:
	if _udp == null:
		return
	var msg := "DISCOVER_WIZARD_HOST".to_utf8_buffer()
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_udp.put_packet(msg)
	for a in IP.get_local_addresses():
		if ":" in a or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var segs := a.split(".")
		if segs.size() == 4:
			_udp.set_dest_address("%s.%s.%s.255" % [segs[0], segs[1], segs[2]], DISCOVERY_PORT)
			_udp.put_packet(msg)

func connect_to_host(address_input: String, player_name: String, port_override: int = 8081) -> void:
	disconnect_from_host()
	_manual_disconnect = false
	_joined = false
	_player_name = player_name.strip_edges()
	if _player_name.is_empty():
		_player_name = "Player"

	var clean := address_input.strip_edges()
	clean = clean.replace("http://", "").replace("https://", "").replace("ws://", "").replace("wss://", "")
	if "/" in clean:
		clean = clean.split("/")[0]
	var host := clean
	var port := port_override
	if ":" in clean:
		var parts := clean.split(":")
		host = parts[0]
		var parsed_port := parts[1].to_int()
		if parsed_port > 0 and parsed_port != 8080:
			port = parsed_port

	_target_url = "ws://%s:%d" % [host, port]
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(_target_url)
	if err != OK:
		_ws = null
		connection_error.emit("Could not connect to %s (error %d)" % [_target_url, err])

func disconnect_from_host() -> void:
	_manual_disconnect = true
	_joined = false
	if _ws != null:
		_ws.close(1000, "Player left")
		_ws = null

func reset_session_token() -> void:
	_session_token = ""

func is_connected_ws() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func send_choose_trump(suit: String) -> void:
	_send_json({"type": "choose_trump", "suit": suit})

func send_bid(amount: int) -> void:
	_send_json({"type": "bid", "amount": amount})

func send_play_card(card_id: int) -> void:
	_send_json({"type": "play_card", "card_id": card_id})

func _send_json(data: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))

func _process(delta: float) -> void:
	if _discovering and _udp != null:
		_probe_timer += delta
		if _probe_timer >= 2.0:
			_probe_timer = 0.0
			_send_probe()
			_prune_rooms()

		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var sender_ip := _udp.get_packet_ip()
			var text := pkt.get_string_from_utf8()
			if not text.begins_with("{"):
				continue
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY and parsed.get("game", "") == "wizard_card_game_v1":
				var ips: Array = parsed.get("ips", [])
				var chosen_ip := sender_ip
				if chosen_ip.is_empty() and not ips.is_empty():
					chosen_ip = str(ips[0])
				_discovered[chosen_ip] = {
					"ip": chosen_ip,
					"room_name": parsed.get("room_name", "Wizard Table"),
					"host_name": parsed.get("host_name", "Host"),
					"player_count": int(parsed.get("player_count", 1)),
					"max_players": int(parsed.get("max_players", 6)),
					"ws_port": int(parsed.get("ws_port", 8081)),
					"last_seen": Time.get_unix_time_from_system()
				}
				rooms_updated.emit(_discovered.values())

	if _ws != null:
		_ws.poll()
		var state := _ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not _joined:
				_joined = true
				_send_json({"type": "join", "name": _player_name, "token": _session_token})
			_ping_timer += delta
			if _ping_timer >= 8.0:
				_ping_timer = 0.0
				_send_json({"type": "ping"})
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				if _ws.was_string_packet():
					_handle_message(pkt.get_string_from_utf8())
		elif state == WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			var code := _ws.get_close_code()
			_ws = null
			_joined = false
			if not _manual_disconnect:
				disconnected.emit("Connection closed (%d: %s)" % [code, reason if not reason.is_empty() else "Host disconnected"])

func _prune_rooms() -> void:
	var now := Time.get_unix_time_from_system()
	var changed := false
	for ip in _discovered.keys():
		if now - float(_discovered[ip]["last_seen"]) > 5.0:
			_discovered.erase(ip)
			changed = true
	if changed:
		rooms_updated.emit(_discovered.values())

func _handle_message(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	var t: String = msg.get("type", "")
	match t:
		"welcome":
			_session_token = str(msg.get("token", ""))
			connected_to_room.emit()
		"state":
			var st: Dictionary = msg.get("state", {})
			if not st.is_empty():
				state_received.emit(st)
		"error":
			connection_error.emit(str(msg.get("message", "Unknown server error")))
