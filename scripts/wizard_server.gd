class_name WizardServer
extends Node

signal state_updated(state: Dictionary)
signal server_log(message: String)
signal local_error(message: String)

const HTTP_PORT := 8080
const WS_PORT := 8081
const DISCOVERY_PORT := 40393

var _http_server := TCPServer.new()
var _ws_server := TCPServer.new()
var _udp := PacketPeerUDP.new()
var _running := false

# HTTP client state: {stream: StreamPeerTCP, req_buf: PackedByteArray, resp_buf: PackedByteArray, resp_offset: int, phase: String, age: float}
var _http_clients: Array[Dictionary] = []

# WS client state: peer_id -> {peer: WebSocketPeer, seat: int, token: String, last_seen: float}
var _ws_clients: Dictionary = {}
var _next_peer_id := 1
var _broadcast_timer := 0.0

# Cached web app HTML & static asset bytes
var _web_html_bytes := PackedByteArray()
var _asset_cache: Dictionary = {}

# Game state
var _rng := RandomNumberGenerator.new()
var room_name := "Wizard-Tisch"
var quick_mode := false
var plus_minus_rule := true
var phase := "lobby" # lobby, choose_trump, bidding, playing, trick_end, round_end, game_end
var players: Array[Dictionary] = []
var round_number := 0
var max_rounds := 0
var dealer_seat := 0
var turn_seat := 0
var trump_suit := "none"
var trump_card: Dictionary = {}
var trick_cards: Array = [] # [{player_idx: int, card: Dictionary}]
var trick_number := 0
var trick_winner_seat := -1
var trick_winner_reason := ""
var status_banner := "Waiting for players..."
var _phase_timer := 0.0
var _bot_timer := 0.0
var _bot_counter := 1

func _ready() -> void:
	_rng.randomize()
	_load_web_html()

func _load_web_html() -> void:
	var f := FileAccess.open("res://web/index.html", FileAccess.READ)
	if f != null:
		var text := f.get_as_text()
		f.close()
		_web_html_bytes = text.to_utf8_buffer()
	else:
		var fallback := "<html><body><h2>Wizard Web Client Missing</h2></body></html>"
		_web_html_bytes = fallback.to_utf8_buffer()

func start_hosting(host_name: String) -> bool:
	stop_hosting()
	var err_http := _http_server.listen(HTTP_PORT, "*")
	var err_ws := _ws_server.listen(WS_PORT, "*")
	if err_http != OK or err_ws != OK:
		server_log.emit("Failed to bind ports (HTTP=%d, WS=%d)" % [err_http, err_ws])
		stop_hosting()
		return false

	_udp.set_broadcast_enabled(true)
	var err_udp := _udp.bind(DISCOVERY_PORT)
	if err_udp != OK:
		server_log.emit("UDP discovery bind warning (%d); manual IP & QR still work." % err_udp)

	_running = true
	room_name = "Tisch von %s" % host_name
	phase = "lobby"
	quick_mode = false
	plus_minus_rule = true
	players.clear()
	_bot_counter = 1
	players.append(_make_player(0, host_name, true, false, _generate_token()))
	status_banner = "QR-Code teilen oder Raum in der Nähe beitreten!"
	_broadcast_state()
	server_log.emit("Hosting started on HTTP :%d, WS :%d" % [HTTP_PORT, WS_PORT])
	return true

func stop_hosting() -> void:
	_running = false
	for c in _http_clients:
		var st: StreamPeerTCP = c["stream"]
		st.disconnect_from_host()
	_http_clients.clear()
	for pid in _ws_clients.keys():
		var peer: WebSocketPeer = _ws_clients[pid]["peer"]
		peer.close(1000, "Host closed table")
	_ws_clients.clear()
	_http_server.stop()
	_ws_server.stop()
	_udp.close()
	players.clear()
	phase = "lobby"

func is_hosting() -> bool:
	return _running

func get_local_ipv4_candidates() -> Array[String]:
	var addrs := IP.get_local_addresses()
	var preferred: Array[String] = []
	var others: Array[String] = []
	for a in addrs:
		if ":" in a or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("172.") or a.begins_with("10."):
			if a not in preferred:
				preferred.append(a)
		else:
			if a not in others:
				others.append(a)
	preferred.sort_custom(func(a: String, b: String) -> bool:
		return _ip_rank(a) < _ip_rank(b)
	)
	for o in others:
		preferred.append(o)
	if preferred.is_empty():
		preferred.append("127.0.0.1")
	return preferred

func _ip_rank(ip: String) -> int:
	if ip.begins_with("192.168.43.") or ip.begins_with("192.168.137."):
		return 0 # Android / Windows Mobile Hotspot default
	if ip.begins_with("192.168."):
		return 1
	if ip.begins_with("172."):
		return 2
	if ip.begins_with("10."):
		return 3
	return 4

func _process(delta: float) -> void:
	if not _running:
		return
	_poll_http(delta)
	_poll_ws(delta)
	_poll_udp(delta)
	_tick_game(delta)

func _poll_http(delta: float) -> void:
	while _http_server.is_connection_available():
		var st := _http_server.take_connection()
		if st != null:
			st.set_no_delay(true)
			_http_clients.append({
				"stream": st,
				"req_buf": PackedByteArray(),
				"resp_buf": PackedByteArray(),
				"resp_offset": 0,
				"phase": "reading",
				"age": 0.0
			})

	var idx := _http_clients.size() - 1
	while idx >= 0:
		var c: Dictionary = _http_clients[idx]
		var st: StreamPeerTCP = c["stream"]
		st.poll()
		c["age"] += delta
		var status := st.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE or c["age"] > 10.0:
			st.disconnect_from_host()
			_http_clients.remove_at(idx)
			idx -= 1
			continue

		if c["phase"] == "reading":
			var avail := st.get_available_bytes()
			if avail > 0:
				var res := st.get_partial_data(mini(avail, 4096))
				if res[0] == OK:
					c["req_buf"].append_array(res[1])
			var req_buf: PackedByteArray = c["req_buf"]
			var req_str: String = req_buf.get_string_from_utf8()
			if "\r\n\r\n" in req_str or "\n\n" in req_str or req_buf.size() > 8192:
				var first_line: String = req_str.split("\n")[0].strip_edges()
				var resp := _build_http_response(first_line)
				c["resp_buf"] = resp
				c["resp_offset"] = 0
				c["phase"] = "writing"
		elif c["phase"] == "writing":
			var resp_buf: PackedByteArray = c["resp_buf"]
			var offset: int = c["resp_offset"]
			if offset < resp_buf.size():
				var slice := resp_buf.slice(offset, mini(offset + 16384, resp_buf.size()))
				var res := st.put_partial_data(slice)
				if res[0] == OK:
					c["resp_offset"] = offset + int(res[1])
				else:
					st.disconnect_from_host()
					_http_clients.remove_at(idx)
					idx -= 1
					continue
			if c["resp_offset"] >= resp_buf.size():
				c["phase"] = "closing"
				c["age"] = 9.85 # close after 150ms flush grace
		idx -= 1

func _build_http_response(request_line: String) -> PackedByteArray:
	var parts := request_line.split(" ")
	var path := "/"
	if parts.size() >= 2:
		path = parts[1].split("?")[0]
	if path == "/health":
		var body := JSON.stringify({"ok": true, "room": room_name, "players": players.size()}).to_utf8_buffer()
		var hdr := ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer()
		hdr.append_array(body)
		return hdr
	if path.begins_with("/assets/"):
		var asset_resp := _serve_static_asset(path)
		if not asset_resp.is_empty():
			return asset_resp
		var nf := "Not Found".to_utf8_buffer()
		var nf_hdr := ("HTTP/1.1 404 Not Found\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % nf.size()).to_utf8_buffer()
		nf_hdr.append_array(nf)
		return nf_hdr
	var hdr := ("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % _web_html_bytes.size()).to_utf8_buffer()
	hdr.append_array(_web_html_bytes)
	return hdr

func _serve_static_asset(url_path: String) -> PackedByteArray:
	if ".." in url_path or "\\" in url_path:
		return PackedByteArray()
	var allowed_prefixes := ["/assets/ui/", "/assets/cards/", "/assets/fonts/"]
	var ok_prefix := false
	for p in allowed_prefixes:
		if url_path.begins_with(p):
			ok_prefix = true
			break
	if not ok_prefix:
		return PackedByteArray()
	var mime := ""
	if url_path.ends_with(".png"):
		mime = "image/png"
	elif url_path.ends_with(".ttf"):
		mime = "font/ttf"
	else:
		return PackedByteArray()

	var bytes: PackedByteArray
	if _asset_cache.has(url_path):
		bytes = _asset_cache[url_path]
	else:
		var res_path := "res:/" + url_path
		if FileAccess.file_exists(res_path):
			bytes = FileAccess.get_file_as_bytes(res_path)
		elif url_path.ends_with(".png") and ResourceLoader.exists(res_path):
			var tex: Variant = load(res_path)
			if tex is Texture2D:
				var img: Image = tex.get_image()
				if img != null:
					if img.is_compressed():
						img.decompress()
					bytes = img.save_png_to_buffer()
		elif url_path.ends_with(".ttf") and ResourceLoader.exists(res_path):
			var font_res: Variant = load(res_path)
			if font_res is FontFile:
				bytes = (font_res as FontFile).data
		if bytes.is_empty():
			return PackedByteArray()
		_asset_cache[url_path] = bytes

	var hdr := ("HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: public, max-age=3600\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [mime, bytes.size()]).to_utf8_buffer()
	hdr.append_array(bytes)
	return hdr

func _poll_ws(_delta: float) -> void:
	while _ws_server.is_connection_available():
		var tcp := _ws_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		var ws := WebSocketPeer.new()
		var err := ws.accept_stream(tcp)
		if err != OK:
			continue
		var pid := _next_peer_id
		_next_peer_id += 1
		_ws_clients[pid] = {
			"peer": ws,
			"seat": -1,
			"token": "",
			"last_seen": Time.get_unix_time_from_system()
		}

	for pid in _ws_clients.keys():
		var entry: Dictionary = _ws_clients[pid]
		var ws: WebSocketPeer = entry["peer"]
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				if ws.was_string_packet():
					entry["last_seen"] = Time.get_unix_time_from_system()
					_handle_ws_message(pid, pkt.get_string_from_utf8())
		elif state == WebSocketPeer.STATE_CLOSED:
			var seat: int = entry["seat"]
			_ws_clients.erase(pid)
			if seat >= 0 and seat < players.size():
				players[seat]["connected"] = false
				if phase == "lobby":
					server_log.emit("%s disconnected from lobby." % players[seat]["name"])
					players.remove_at(seat)
					_recompute_seats_and_ws()
				else:
					server_log.emit("%s temporarily disconnected (seat preserved)." % players[seat]["name"])
				_broadcast_state()

func _recompute_seats_and_ws() -> void:
	for i in range(players.size()):
		players[i]["seat"] = i
	for pid in _ws_clients.keys():
		var token: String = _ws_clients[pid]["token"]
		_ws_clients[pid]["seat"] = _find_seat_by_token(token)

func _poll_udp(delta: float) -> void:
	_broadcast_timer += delta
	if _broadcast_timer >= 1.2:
		_broadcast_timer = 0.0
		_send_discovery_beacon("255.255.255.255")
		for ip in get_local_ipv4_candidates():
			var segs := ip.split(".")
			if segs.size() == 4:
				_send_discovery_beacon("%s.%s.%s.255" % [segs[0], segs[1], segs[2]])

	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var sender_ip := _udp.get_packet_ip()
		var sender_port := _udp.get_packet_port()
		var msg := pkt.get_string_from_utf8()
		if msg == "DISCOVER_WIZARD_HOST":
			_send_discovery_beacon(sender_ip, sender_port)

func _send_discovery_beacon(target_ip: String, target_port: int = DISCOVERY_PORT) -> void:
	if phase != "lobby":
		return
	var payload := JSON.stringify({
		"game": "wizard_card_game_v1",
		"room_name": room_name,
		"host_name": players[0]["name"] if not players.is_empty() else "Host",
		"player_count": players.size(),
		"max_players": 6,
		"ws_port": WS_PORT,
		"http_port": HTTP_PORT,
		"ips": get_local_ipv4_candidates()
	})
	_udp.set_dest_address(target_ip, target_port)
	_udp.put_packet(payload.to_utf8_buffer())

func _handle_ws_message(pid: int, raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	var action: String = msg.get("type", "")
	if action == "ping":
		_send_ws(pid, {"type": "pong"})
		return

	if action == "join":
		var req_name := str(msg.get("name", "Player")).strip_edges().substr(0, 18)
		if req_name.is_empty():
			req_name = "Player"
		var req_token := str(msg.get("token", ""))

		# Check reconnection by token first, then by disconnected matching name
		var seat := _find_seat_by_token(req_token)
		if seat == -1 and phase != "lobby":
			for i in range(players.size()):
				if not players[i]["is_bot"] and not players[i]["connected"] and players[i]["name"].to_lower() == req_name.to_lower():
					seat = i
					break

		if seat != -1:
			players[seat]["connected"] = true
			if phase == "lobby":
				players[seat]["name"] = _unique_name(req_name, seat)
			var tok: String = players[seat]["token"]
			_ws_clients[pid]["seat"] = seat
			_ws_clients[pid]["token"] = tok
			_send_ws(pid, {"type": "welcome", "seat": seat, "token": tok})
			_broadcast_state()
			return

		if phase != "lobby":
			_send_ws(pid, {"type": "error", "message": "Spiel läuft bereits. Tritt mit deinem alten Namen erneut bei oder warte auf die nächste Runde."})
			return
		if players.size() >= 6:
			_send_ws(pid, {"type": "error", "message": "Tisch ist voll (maximal 6 Spieler)."})
			return

		var new_seat := players.size()
		var new_token := _generate_token()
		var final_name := _unique_name(req_name, -1)
		players.append(_make_player(new_seat, final_name, false, false, new_token))
		_ws_clients[pid]["seat"] = new_seat
		_ws_clients[pid]["token"] = new_token
		_send_ws(pid, {"type": "welcome", "seat": new_seat, "token": new_token})
		server_log.emit("%s joined at seat %d" % [final_name, new_seat + 1])
		_broadcast_state()
		return

	var sender_seat: int = _ws_clients[pid]["seat"]
	if sender_seat < 0 or sender_seat >= players.size():
		_send_ws(pid, {"type": "error", "message": "Not seated at table."})
		return

	match action:
		"choose_trump":
			process_choose_trump(sender_seat, str(msg.get("suit", "")))
		"bid":
			process_bid(sender_seat, int(msg.get("amount", -1)))
		"play_card":
			process_play_card(sender_seat, int(msg.get("card_id", -1)))
		"next_round":
			if sender_seat == 0:
				process_next_round()

# --- Host Local Actions ---

func host_toggle_quick_mode(enabled: bool) -> void:
	if phase != "lobby":
		return
	quick_mode = enabled
	_broadcast_state()

func host_toggle_plus_minus(enabled: bool) -> void:
	if phase != "lobby":
		return
	plus_minus_rule = enabled
	_broadcast_state()

func host_add_bot() -> void:
	if phase != "lobby" or players.size() >= 6:
		return
	var bot_names := ["Merlin", "Gandalf", "Morgana", "Circe", "Albus", "Nimue"]
	var chosen := "Bot %d" % _bot_counter
	for bn in bot_names:
		var taken := false
		for p in players:
			if p["name"] == bn:
				taken = true
				break
		if not taken:
			chosen = bn
			break
	_bot_counter += 1
	players.append(_make_player(players.size(), chosen, false, true, _generate_token()))
	_broadcast_state()

func host_remove_last_bot() -> void:
	if phase != "lobby":
		return
	for i in range(players.size() - 1, -1, -1):
		if players[i]["is_bot"]:
			players.remove_at(i)
			_recompute_seats_and_ws()
			_broadcast_state()
			return

func host_start_game() -> bool:
	if phase != "lobby" or players.size() < 2:
		return false
	max_rounds = WizardRules.total_rounds_for_players(players.size(), quick_mode)
	round_number = 0
	dealer_seat = _rng.randi_range(0, players.size() - 1)
	for p in players:
		p["score"] = 0
		p["round_history"] = []
		p["last_round_delta"] = 0
	_start_next_round()
	return true

func host_return_to_lobby() -> void:
	phase = "lobby"
	round_number = 0
	trick_number = 0
	trick_winner_seat = -1
	trick_cards.clear()
	trump_card = {}
	trump_suit = "none"
	for i in range(players.size() - 1, -1, -1):
		if not players[i]["connected"] and not players[i]["is_bot"]:
			players.remove_at(i)
	_recompute_seats_and_ws()
	for p in players:
		p["hand"] = []
		p["bid"] = -1
		p["tricks_won"] = 0
		p["score"] = 0
		p["last_round_delta"] = 0
		p["round_history"] = []
	status_banner = "Zurück in der Lobby. Bereit für ein neues Spiel!"
	_broadcast_state()

# --- Core Rule Transitions ---

func _start_next_round() -> void:
	round_number += 1
	if round_number > max_rounds:
		phase = "game_end"
		status_banner = "Spielende! Endergebnis"
		_broadcast_state()
		return

	if round_number > 1:
		dealer_seat = (dealer_seat + 1) % players.size()

	var deck := WizardRules.create_deck()
	WizardRules.shuffle_deck(deck, _rng)

	var card_idx := 0
	for p in players:
		var hand: Array[Dictionary] = []
		for _k in range(round_number):
			hand.append(deck[card_idx])
			card_idx += 1
		p["hand"] = WizardRules.sort_hand(hand)
		p["bid"] = -1
		p["tricks_won"] = 0
		p["last_round_delta"] = 0

	trick_cards.clear()
	trick_number = 1
	trick_winner_seat = -1
	trick_winner_reason = ""

	# Check trump card
	if card_idx < deck.size():
		trump_card = deck[card_idx]
		var tkind: String = trump_card["kind"]
		if tkind == "num":
			trump_suit = trump_card["suit"]
			_enter_bidding_phase()
		elif tkind == "jester":
			trump_suit = "none"
			_enter_bidding_phase()
		else:
			# Zauberer aufgedeckt: Geber wählt Trumpffarbe
			trump_suit = "pending"
			phase = "choose_trump"
			turn_seat = dealer_seat
			status_banner = "Zauberer aufgedeckt! %s wählt die Trumpffarbe." % players[dealer_seat]["name"]
			_bot_timer = 0.75
			_broadcast_state()
	else:
		# Letzte Runde (alle 60 Karten ausgeteilt) -> Kein Trumpf
		trump_card = {}
		trump_suit = "none"
		_enter_bidding_phase()

func _enter_bidding_phase() -> void:
	phase = "bidding"
	turn_seat = (dealer_seat + 1) % players.size()
	status_banner = "%s ist dran mit Ansagen (0–%d)." % [players[turn_seat]["name"], round_number]
	_bot_timer = 0.75
	_broadcast_state()

func get_bids_sum() -> int:
	var s := 0
	for p in players:
		var b := int(p["bid"])
		if b >= 0:
			s += b
	return s

func get_forbidden_bid(seat: int) -> int:
	if not plus_minus_rule or phase != "bidding" or seat != turn_seat:
		return -1
	var unbid_count := 0
	for p in players:
		if int(p["bid"]) < 0:
			unbid_count += 1
	if unbid_count != 1:
		return -1
	var forbidden := round_number - get_bids_sum()
	if forbidden >= 0 and forbidden <= round_number:
		return forbidden
	return -1

func process_choose_trump(seat: int, suit: String) -> void:
	if phase != "choose_trump" or seat != dealer_seat:
		return
	if suit not in WizardRules.SUITS:
		return
	trump_suit = suit
	_enter_bidding_phase()

func process_bid(seat: int, amount: int) -> void:
	if phase != "bidding" or seat != turn_seat:
		return
	if amount < 0 or amount > round_number:
		return
	var forbidden := get_forbidden_bid(seat)
	if forbidden >= 0 and amount == forbidden:
		_send_error_to_seat(seat, "Verbotene Ansage (%d): Die Summe der Tipps darf nicht %d sein!" % [amount, round_number])
		return
	players[seat]["bid"] = amount

	# Check if all players have bid
	var all_bid := true
	for p in players:
		if int(p["bid"]) < 0:
			all_bid = false
			break

	if all_bid:
		phase = "playing"
		turn_seat = (dealer_seat + 1) % players.size()
		trick_number = 1
		trick_cards.clear()
		status_banner = "Stich 1/%d • %s spielt aus." % [round_number, players[turn_seat]["name"]]
	else:
		turn_seat = (turn_seat + 1) % players.size()
		status_banner = "%s ist dran mit Ansagen (0–%d)." % [players[turn_seat]["name"], round_number]

	_bot_timer = 0.75
	_broadcast_state()

func process_play_card(seat: int, card_id: int) -> void:
	if phase != "playing" or seat != turn_seat:
		return
	var hand: Array = players[seat]["hand"]
	var legal_ids := WizardRules.get_legal_card_ids(hand, trick_cards)
	if card_id not in legal_ids:
		var lead := WizardRules.determine_lead_suit(trick_cards)
		var suit_de: String = WizardRules.SUIT_LABELS.get(lead, lead)
		_send_error_to_seat(seat, "Regelverstoß: Du musst %s bedienen!" % suit_de)
		return

	var played_card: Dictionary = {}
	for i in range(hand.size()):
		if int(hand[i]["id"]) == card_id:
			played_card = hand[i]
			hand.remove_at(i)
			break
	if played_card.is_empty():
		return

	trick_cards.append({"player_idx": seat, "card": played_card})

	if trick_cards.size() >= players.size():
		var winner := WizardRules.evaluate_trick_winner(trick_cards, trump_suit)
		trick_winner_seat = winner
		players[winner]["tricks_won"] = int(players[winner]["tricks_won"]) + 1
		phase = "trick_end"
		_phase_timer = 1.65
		status_banner = "%s gewinnt Stich %d/%d!" % [players[winner]["name"], trick_number, round_number]
	else:
		turn_seat = (turn_seat + 1) % players.size()
		var lead := WizardRules.determine_lead_suit(trick_cards)
		var lead_txt := "" if lead == "" else " (%s bedienen)" % WizardRules.SUIT_LABELS.get(lead, lead)
		status_banner = "Stich %d/%d • %s ist dran%s" % [trick_number, round_number, players[turn_seat]["name"], lead_txt]

	_bot_timer = 0.75
	_broadcast_state()

func process_next_round() -> void:
	if phase != "round_end":
		return
	_start_next_round()

func _tick_game(delta: float) -> void:
	if phase == "trick_end":
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			var next_leader := trick_winner_seat
			trick_winner_seat = -1
			trick_cards.clear()
			if trick_number >= round_number:
				_score_round()
			else:
				trick_number += 1
				phase = "playing"
				turn_seat = next_leader
				status_banner = "Stich %d/%d • %s spielt aus." % [trick_number, round_number, players[turn_seat]["name"]]
				_bot_timer = 0.75
				_broadcast_state()
		return

	if phase in ["choose_trump", "bidding", "playing"]:
		if turn_seat >= 0 and turn_seat < players.size() and players[turn_seat]["is_bot"]:
			_bot_timer -= delta
			if _bot_timer <= 0.0:
				_bot_timer = 0.75
				_run_bot_turn(turn_seat)

func _run_bot_turn(seat: int) -> void:
	var hand: Array = players[seat]["hand"]
	if phase == "choose_trump":
		process_choose_trump(seat, WizardRules.choose_ai_trump(hand))
	elif phase == "bidding":
		var forb := get_forbidden_bid(seat)
		process_bid(seat, WizardRules.choose_ai_bid(hand, trump_suit, round_number, forb))
	elif phase == "playing":
		var cid := WizardRules.choose_ai_card(hand, trick_cards, trump_suit, int(players[seat]["bid"]), int(players[seat]["tricks_won"]))
		process_play_card(seat, cid)

func _score_round() -> void:
	trick_winner_seat = -1
	for p in players:
		var bid := int(p["bid"])
		var won := int(p["tricks_won"])
		var delta := WizardRules.calculate_round_score(bid, won)
		p["last_round_delta"] = delta
		p["score"] = int(p["score"]) + delta
		var hist: Array = p["round_history"]
		hist.append({"round": round_number, "bid": bid, "won": won, "delta": delta, "total": p["score"]})

	if round_number >= max_rounds:
		phase = "game_end"
		status_banner = "Letzte Runde beendet! Krönt den Zauberer!"
	else:
		phase = "round_end"
		status_banner = "Runde %d/%d beendet!" % [round_number, max_rounds]
	_broadcast_state()

# --- State Serialization & Helpers ---

func _broadcast_state() -> void:
	if not players.is_empty():
		state_updated.emit(_build_state_for_seat(0))
	for pid in _ws_clients.keys():
		var seat: int = _ws_clients[pid]["seat"]
		if seat >= 0 and seat < players.size():
			_send_ws(pid, {"type": "state", "state": _build_state_for_seat(seat)})

func _build_state_for_seat(seat: int) -> Dictionary:
	var public_players: Array = []
	for p in players:
		public_players.append({
			"seat": p["seat"],
			"name": p["name"],
			"is_host": p["is_host"],
			"is_bot": p["is_bot"],
			"connected": p["connected"],
			"bid": p["bid"],
			"tricks_won": p["tricks_won"],
			"score": p["score"],
			"card_count": p["hand"].size(),
			"last_round_delta": p["last_round_delta"],
			"round_history": p["round_history"]
		})

	var your_hand: Array = []
	var legal_ids: Array = []
	if seat >= 0 and seat < players.size():
		your_hand = players[seat]["hand"]
		if phase == "playing" and turn_seat == seat:
			legal_ids = WizardRules.get_legal_card_ids(your_hand, trick_cards)

	return {
		"room_name": room_name,
		"quick_mode": quick_mode,
		"plus_minus_rule": plus_minus_rule,
		"phase": phase,
		"your_seat": seat,
		"round_number": round_number,
		"max_rounds": max_rounds,
		"dealer_seat": dealer_seat,
		"turn_seat": turn_seat,
		"trump_suit": trump_suit,
		"trump_card": trump_card,
		"lead_suit": WizardRules.determine_lead_suit(trick_cards),
		"trick_cards": trick_cards,
		"trick_number": trick_number,
		"trick_winner_seat": trick_winner_seat,
		"bids_sum": get_bids_sum(),
		"forbidden_bid": get_forbidden_bid(seat),
		"status_banner": status_banner,
		"players": public_players,
		"your_hand": your_hand,
		"legal_card_ids": legal_ids,
		"host_ips": get_local_ipv4_candidates(),
		"http_port": HTTP_PORT,
		"ws_port": WS_PORT
	}

func _send_ws(pid: int, data: Dictionary) -> void:
	if not _ws_clients.has(pid):
		return
	var ws: WebSocketPeer = _ws_clients[pid]["peer"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(data))

func _send_error_to_seat(seat: int, msg: String) -> void:
	if seat == 0:
		local_error.emit(msg)
	for pid in _ws_clients.keys():
		if _ws_clients[pid]["seat"] == seat:
			_send_ws(pid, {"type": "error", "message": msg})

func _make_player(seat: int, p_name: String, is_host: bool, is_bot: bool, token: String) -> Dictionary:
	return {
		"seat": seat,
		"name": p_name,
		"token": token,
		"is_host": is_host,
		"is_bot": is_bot,
		"connected": true,
		"hand": [] as Array[Dictionary],
		"bid": -1,
		"tricks_won": 0,
		"score": 0,
		"last_round_delta": 0,
		"round_history": []
	}

func _find_seat_by_token(token: String) -> int:
	if token.is_empty():
		return -1
	for i in range(players.size()):
		if players[i]["token"] == token:
			return i
	return -1

func _unique_name(desired: String, exclude_seat: int) -> String:
	var candidate := desired
	var suffix := 2
	while true:
		var clash := false
		for i in range(players.size()):
			if i != exclude_seat and players[i]["name"].to_lower() == candidate.to_lower():
				clash = true
				break
		if not clash:
			return candidate
		candidate = "%s %d" % [desired, suffix]
		suffix += 1
	return candidate

func _generate_token() -> String:
	return "%08x%08x" % [_rng.randi(), _rng.randi()]
