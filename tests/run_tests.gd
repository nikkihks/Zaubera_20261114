extends SceneTree

var _failures := 0

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
		_failures += 1
	else:
		print("PASS: " + msg)

func _initialize() -> void:
	print("=== Running Zaubera / Wizard Unit & Integration Tests ===")
	_test_rules()
	_test_plus_minus_rule()
	_test_hand_fan_first_card()
	_test_qr()
	await _test_server_client_e2e()
	print("=== Finished with %d failures ===" % _failures)
	quit(1 if _failures > 0 else 0)

func _test_rules() -> void:
	var deck := WizardRules.create_deck()
	_assert(deck.size() == 60, "Deck has 60 cards")
	var w_count := 0
	var j_count := 0
	for c in deck:
		if c["kind"] == "wizard": w_count += 1
		elif c["kind"] == "jester": j_count += 1
	_assert(w_count == 4 and j_count == 4, "Deck has 4 Wizards and 4 Jesters")

	_assert(WizardRules.suit_label("red") == "Rot", "German suit label for red is Rot")
	_assert(WizardRules.card_label({"kind": "wizard"}) == "Zauberer", "German card label for wizard is Zauberer")
	_assert(WizardRules.card_label({"kind": "jester"}) == "Narr", "German card label for jester is Narr")

	_assert(WizardRules.total_rounds_for_players(3) == 20, "3 players = 20 rounds")
	_assert(WizardRules.total_rounds_for_players(4) == 15, "4 players = 15 rounds")
	_assert(WizardRules.total_rounds_for_players(5) == 12, "5 players = 12 rounds")
	_assert(WizardRules.total_rounds_for_players(6) == 10, "6 players = 10 rounds")

	# Jester led -> Blue 5 sets lead suit
	var trick1 := [
		{"player_idx": 0, "card": {"id": 56, "kind": "jester", "suit": "", "value": 0}},
		{"player_idx": 1, "card": {"id": 17, "kind": "num", "suit": "blue", "value": 5}}
	]
	_assert(WizardRules.determine_lead_suit(trick1) == "blue", "First numbered after Jester sets lead suit")

	# Legal cards check: holding blue 2, red 13, wizard 52 -> only blue 2 and wizard 52 legal
	var hand := [
		{"id": 14, "kind": "num", "suit": "blue", "value": 2},
		{"id": 12, "kind": "num", "suit": "red", "value": 13},
		{"id": 52, "kind": "wizard", "suit": "", "value": 14}
	]
	var legal := WizardRules.get_legal_card_ids(hand, trick1)
	_assert(14 in legal and 52 in legal and not (12 in legal), "Must follow Blue suit when holding Blue, Wizard allowed")

	# Wizard led -> any card legal
	var trick_wiz_led := [
		{"player_idx": 0, "card": {"id": 52, "kind": "wizard", "suit": "", "value": 14}},
		{"player_idx": 1, "kind": "num", "card": {"id": 17, "kind": "num", "suit": "blue", "value": 5}}
	]
	_assert(WizardRules.determine_lead_suit(trick_wiz_led) == "", "Wizard led means no lead suit restriction")
	_assert(WizardRules.get_legal_card_ids(hand, trick_wiz_led).size() == 3, "All cards legal after Wizard led")

	# Trick winner rules
	var trick_two_wiz := [
		{"player_idx": 1, "card": {"id": 52, "kind": "wizard", "suit": "", "value": 14}},
		{"player_idx": 2, "card": {"id": 53, "kind": "wizard", "suit": "", "value": 14}},
		{"player_idx": 0, "card": {"id": 12, "kind": "num", "suit": "red", "value": 13}}
	]
	_assert(WizardRules.evaluate_trick_winner(trick_two_wiz, "red") == 1, "First Wizard wins over second Wizard and Trump")

	var trick_trump := [
		{"player_idx": 0, "card": {"id": 12, "kind": "num", "suit": "red", "value": 13}},
		{"player_idx": 1, "card": {"id": 13, "kind": "num", "suit": "blue", "value": 1}},
		{"player_idx": 2, "card": {"id": 26, "kind": "num", "suit": "green", "value": 12}}
	]
	_assert(WizardRules.evaluate_trick_winner(trick_trump, "blue") == 1, "Lowest Trump beats highest off-suit")

	var trick_jesters := [
		{"player_idx": 2, "card": {"id": 56, "kind": "jester", "suit": "", "value": 0}},
		{"player_idx": 0, "card": {"id": 57, "kind": "jester", "suit": "", "value": 0}},
		{"player_idx": 1, "card": {"id": 58, "kind": "jester", "suit": "", "value": 0}}
	]
	_assert(WizardRules.evaluate_trick_winner(trick_jesters, "red") == 2, "All Jesters -> first Jester wins")

	_assert(WizardRules.calculate_round_score(0, 0) == 20, "Bid 0 Won 0 = +20")
	_assert(WizardRules.calculate_round_score(3, 3) == 50, "Bid 3 Won 3 = +50")
	_assert(WizardRules.calculate_round_score(3, 1) == -20, "Bid 3 Won 1 = -20")

func _test_plus_minus_rule() -> void:
	var srv := WizardServer.new()
	srv.players = [
		srv._make_player(0, "Host", true, false, "t0"),
		srv._make_player(1, "Anna", false, false, "t1"),
		srv._make_player(2, "Bot1", false, true, "t2")
	]
	srv.phase = "bidding"
	srv.plus_minus_rule = true
	srv.round_number = 4
	srv.dealer_seat = 0

	# Seat 1 bids 2 -> Seat 2 bids 1 -> sum so far = 3 -> last bidder (Seat 0) cannot bid 1 (sum 4)!
	srv.players[1]["bid"] = 2
	srv.turn_seat = 2
	_assert(srv.get_forbidden_bid(2) == -1, "Non-last bidder has no forbidden bid")

	srv.players[2]["bid"] = 1
	srv.turn_seat = 0
	_assert(srv.get_forbidden_bid(0) == 1, "Last bidder has forbidden bid = 4 - 3 = 1")

	var err_seen := {"msg": ""}
	srv.local_error.connect(func(m: String): err_seen["msg"] = m)
	srv.process_bid(0, 1)
	_assert(srv.players[0]["bid"] == -1 and not err_seen["msg"].is_empty(), "Server rejects forbidden bid = 1 for last bidder")

	srv.process_bid(0, 2)
	_assert(srv.players[0]["bid"] == 2 and srv.phase == "playing", "Server accepts legal bid = 2 (sum = 5 != 4) and advances to playing")

	# Case where sum already exceeds round_number (3 + 3 = 6 > 4): no bid forbidden!
	srv.phase = "bidding"
	srv.players[0]["bid"] = -1
	srv.players[1]["bid"] = 3
	srv.players[2]["bid"] = 3
	srv.turn_seat = 0
	_assert(srv.get_forbidden_bid(0) == -1, "When prior bids already exceed 4, last bidder can choose 0..4 freely")

	srv.free()

func _test_hand_fan_first_card() -> void:
	var fan := HandFan.new()
	fan.size = Vector2(680, 224)
	root.add_child(fan)

	# Include card_id == 0 at index 0 to catch any falsy 0 bug and leftmost-edge clipping bug!
	var cards := [
		{"id": 0, "kind": "num", "suit": "red", "value": 1},
		{"id": 14, "kind": "num", "suit": "blue", "value": 2},
		{"id": 28, "kind": "num", "suit": "green", "value": 3},
		{"id": 52, "kind": "wizard", "suit": "", "value": 14}
	]
	var legal := [0, 14, 28, 52]
	fan.set_hand(cards, legal, true, -1, false)

	var picked_left := fan.debug_pick_card_at(fan.get_card_view(0).position + Vector2(18, 40))
	_assert(picked_left == 0, "Leftmost card (idx 0, id 0) corner is cleanly hittable in HandFan")

	var swiped := {"id": -1}
	fan.card_swipe_played.connect(func(cid: int, _gpos: Vector2): swiped["id"] = cid)
	fan.debug_simulate_swipe_play(0)
	_assert(swiped["id"] == 0, "Swiping card 0 upward plays card_id 0")

	fan.queue_free()

func _test_qr() -> void:
	var url := "http://192.168.43.1:8080"
	var tex := QRGenerator.create_texture(url, 8, 4)
	_assert(tex != null, "QR texture generated for " + url)
	if tex != null:
		var img := tex.get_image()
		img.save_png("res://tests/qr_test.png")
		_assert(img.get_width() > 200 and img.get_width() == img.get_height(), "QR image is square and sized properly")

func _test_server_client_e2e() -> void:
	var srv := WizardServer.new()
	var cli := WizardClient.new()
	root.add_child(srv)
	root.add_child(cli)

	var ok := srv.start_hosting("Alice")
	_assert(ok, "WizardServer started on HTTP 8080 and WS 8081")

	# Test HTTP GET /
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", 8080)
	var http_resp := ""
	for _i in range(40):
		await process_frame
		srv._process(0.02)
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if http_resp.is_empty():
				tcp.put_data("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".to_utf8_buffer())
				http_resp = "sent"
			var avail := tcp.get_available_bytes()
			if avail > 0:
				var d := tcp.get_data(avail)
				if d[0] == OK:
					http_resp += d[1].get_string_from_utf8()
					if "</html>" in http_resp:
						break
	tcp.disconnect_from_host()
	_assert("200 OK" in http_resp and "ZAUBERA" in http_resp and "Plus/Minus-Eins-Regel" in http_resp and "</html>" in http_resp, "Embedded HTTP server delivers full German iOS/Web client HTML")

	# Verify static Blender & Font assets are served cleanly over HTTP
	for asset_route in ["/assets/ui/arcane_rune_ring.png", "/assets/ui/wood_card_frame.png", "/assets/ui/papyrus_btn.png", "/assets/fonts/Cinzel-Bold.ttf"]:
		var atcp := StreamPeerTCP.new()
		atcp.connect_to_host("127.0.0.1", 8080)
		var hdr_buf := PackedByteArray()
		var sent_a := false
		for _a in range(60):
			srv._process(0.02)
			atcp.poll()
			if atcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				if not sent_a:
					atcp.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % asset_route).to_utf8_buffer())
					sent_a = true
				var av := atcp.get_available_bytes()
				if av > 0:
					hdr_buf.append_array(atcp.get_data(av)[1])
					if hdr_buf.size() >= 120:
						break
			OS.delay_msec(10)
		var hdr_s := hdr_buf.slice(0, mini(160, hdr_buf.size())).get_string_from_utf8()
		_assert("200 OK" in hdr_s, "HTTP serves static theme asset %s" % asset_route)

	# Test WebSocket client join + game round
	var last_client_state := {}
	cli.state_received.connect(func(st: Dictionary): last_client_state.assign(st))
	cli.connect_to_host("127.0.0.1", "Bob", 8081)
	for _i in range(60):
		OS.delay_msec(15)
		srv._process(0.02)
		cli._process(0.02)
		if not last_client_state.is_empty() and last_client_state.get("players", []).size() == 2:
			break

	_assert(last_client_state.get("players", []).size() == 2, "Remote WebSocket client joined lobby")
	_assert(int(last_client_state.get("your_seat", -1)) == 1, "Remote client assigned seat 1")

	srv.host_add_bot()
	_assert(srv.players.size() == 3, "Added AI Bot for 3-player game")

	srv.host_start_game()
	for _i in range(60):
		OS.delay_msec(15)
		srv._process(0.05)
		cli._process(0.05)
		if last_client_state.get("phase", "") in ["choose_trump", "bidding"]:
			break

	_assert(srv.phase in ["choose_trump", "bidding"], "Game started into round 1")
	_assert(last_client_state.get("your_hand", []).size() == 1, "Round 1 dealt 1 card to remote client")
	var players_pub: Array = last_client_state.get("players", [])
	_assert(not players_pub[0].has("hand"), "Server sanitizes opponent hands (no card leak)")

	# Play through Round 1 respecting Plus/Minus-Eins-Regel
	for _step in range(120):
		OS.delay_msec(20)
		srv._process(0.2)
		cli._process(0.2)
		if srv.phase == "round_end":
			break
		if srv.phase == "choose_trump":
			if srv.turn_seat == 0:
				srv.process_choose_trump(0, "blue")
			elif srv.turn_seat == 1:
				cli.send_choose_trump("blue")
		elif srv.phase == "bidding":
			var forb := srv.get_forbidden_bid(srv.turn_seat)
			var pick := 0 if forb != 0 else 1
			if srv.turn_seat == 0:
				srv.process_bid(0, pick)
			elif srv.turn_seat == 1:
				cli.send_bid(pick)
		elif srv.phase == "playing":
			if srv.turn_seat == 0:
				var leg := WizardRules.get_legal_card_ids(srv.players[0]["hand"], srv.trick_cards)
				srv.process_play_card(0, leg[0])
			elif srv.turn_seat == 1 and int(last_client_state.get("turn_seat", -1)) == 1:
				var leg2: Array = last_client_state.get("legal_card_ids", [])
				if not leg2.is_empty():
					cli.send_play_card(int(leg2[0]))

	_assert(srv.phase == "round_end", "Completed full Round 1 over Host + WebSocket Client + AI Bot")
	var bid_sum := 0
	var total_tricks := 0
	for p in srv.players:
		bid_sum += int(p["bid"])
		total_tricks += int(p["tricks_won"])
	_assert(bid_sum != 1, "Plus/Minus-Eins-Regel enforced across E2E round (sum=%d != 1)" % bid_sum)
	_assert(total_tricks == 1, "Exactly 1 trick awarded in Round 1")

	# Advance into Round 2 (2 tricks!) and verify trick_winner_seat resets to -1 in Trick 2/2!
	srv.process_next_round()
	_assert(srv.round_number == 2, "Server advanced to Round 2")
	var trick1_seen := false
	var trick2_winner_was_reset := false
	for _step in range(240):
		OS.delay_msec(15)
		srv._process(0.25)
		cli._process(0.25)
		if srv.phase == "round_end":
			break
		if srv.phase == "playing":
			if srv.trick_number == 1:
				trick1_seen = true
			elif srv.trick_number == 2 and not trick2_winner_was_reset and srv.trick_cards.is_empty():
				trick2_winner_was_reset = (srv.trick_winner_seat == -1)
			if srv.turn_seat == 0:
				var leg := WizardRules.get_legal_card_ids(srv.players[0]["hand"], srv.trick_cards)
				srv.process_play_card(0, leg[0])
			elif srv.turn_seat == 1 and int(last_client_state.get("turn_seat", -1)) == 1:
				var leg2: Array = last_client_state.get("legal_card_ids", [])
				if not leg2.is_empty():
					cli.send_play_card(int(leg2[0]))
		elif srv.phase == "choose_trump":
			if srv.turn_seat == 0: srv.process_choose_trump(0, "red")
			elif srv.turn_seat == 1: cli.send_choose_trump("red")
		elif srv.phase == "bidding":
			var forb2 := srv.get_forbidden_bid(srv.turn_seat)
			var pick2 := 0 if forb2 != 0 else 1
			if srv.turn_seat == 0: srv.process_bid(0, pick2)
			elif srv.turn_seat == 1: cli.send_bid(pick2)

	_assert(trick1_seen and trick2_winner_was_reset, "Trick 2/2 resets trick_winner_seat to -1 cleanly")
	_assert(srv.phase == "round_end" and srv.trick_number == 2, "Completed all tricks of Round 2 cleanly")
	var total_tricks_r2 := 0
	for p in srv.players:
		total_tricks_r2 += int(p["tricks_won"])
	_assert(total_tricks_r2 == 2, "Exactly 2 tricks awarded in Round 2")

	# Play Rounds 3..10 (quick mode) to game_end -> host_return_to_lobby
	srv.quick_mode = true
	srv.max_rounds = 10
	while srv.round_number < 10 or srv.phase != "game_end":
		if srv.phase == "round_end":
			srv.process_next_round()
		for _s in range(600):
			srv._process(0.3)
			cli._process(0.3)
			if srv.phase in ["round_end", "game_end"]:
				break
			if srv.phase == "choose_trump":
				if srv.turn_seat == 0: srv.process_choose_trump(0, "green")
				elif srv.turn_seat == 1: cli.send_choose_trump("green")
			elif srv.phase == "bidding":
				var fb := srv.get_forbidden_bid(srv.turn_seat)
				var pk := 0 if fb != 0 else 1
				if srv.turn_seat == 0: srv.process_bid(0, pk)
				elif srv.turn_seat == 1: cli.send_bid(pk)
			elif srv.phase == "playing":
				if srv.turn_seat == 0:
					var lg := WizardRules.get_legal_card_ids(srv.players[0]["hand"], srv.trick_cards)
					srv.process_play_card(0, lg[0])
				elif srv.turn_seat == 1 and int(last_client_state.get("turn_seat", -1)) == 1:
					var lg2: Array = last_client_state.get("legal_card_ids", [])
					if not lg2.is_empty():
						cli.send_play_card(int(lg2[0]))
		if srv.phase == "game_end":
			break

	_assert(srv.phase == "game_end" and srv.round_number == 10, "Completed entire 10-round game to game_end without stalls")
	srv.host_return_to_lobby()
	_assert(srv.phase == "lobby" and srv.trick_winner_seat == -1, "Return to lobby resets state cleanly")

	srv.stop_hosting()
	cli.disconnect_from_host()
	srv.queue_free()
	cli.queue_free()
	await process_frame

	# Verify Main.tscn Host UI + Trick 2/2 HandFan swipe play
	var main_scene: Control = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	main_scene.size = Vector2(720, 1280)
	main_scene.trigger_host_for_test("HostTest")
	_assert(main_scene.get_qr_panel().visible, "QR invite panel visible for host in Main.tscn")
	_assert(main_scene._lobby_screen.visible, "Lobby screen visible after hosting")
	_assert(main_scene._qr_tex.texture != null, "QR code texture rendered for host")
	_assert(main_scene._lobby_count_lbl.autowrap_mode == TextServer.AUTOWRAP_OFF, "Lobby count label does not wrap vertically")
	_assert("Spieler" in main_scene._lobby_count_lbl.text, "Lobby UI is in German")

	# Add bots, start game, advance to Trick 2/2 in Round 2 via server, and test Host HandFan swipe-up play!
	var msrv: WizardServer = main_scene.get_server()
	msrv.host_add_bot()
	msrv.host_add_bot()
	msrv.host_start_game()
	# Fast-forward Round 1 -> Round 2 Trick 2/2 where Host (seat 0) holds 1 card
	var played_via_hand_fan := false
	for _tick in range(900):
		await process_frame
		msrv._process(0.25)
		if msrv.phase == "round_end" and msrv.round_number == 1:
			msrv.process_next_round()
		elif msrv.phase == "round_end" and msrv.round_number == 2:
			break
		elif msrv.phase == "choose_trump" and msrv.turn_seat == 0:
			msrv.process_choose_trump(0, "red")
		elif msrv.phase == "bidding" and msrv.turn_seat == 0:
			var fb := msrv.get_forbidden_bid(0)
			msrv.process_bid(0, 0 if fb != 0 else 1)
		elif msrv.phase == "playing" and msrv.turn_seat == 0:
			if msrv.round_number == 2 and msrv.trick_number == 2:
				# Trigger actual HandFan swipe-up on the single remaining card in UI!
				var hfan: HandFan = main_scene.get_hand_fan()
				_assert(hfan.get_card_count() == 1 and hfan._interactive, "Round 2 Trick 2/2 leaves 1 interactive card in Host HandFan")
				hfan.debug_simulate_swipe_play(0)
				played_via_hand_fan = true
			else:
				var leg := WizardRules.get_legal_card_ids(msrv.players[0]["hand"], msrv.trick_cards)
				msrv.process_play_card(0, leg[0])
	_assert(played_via_hand_fan and msrv.round_number == 2 and msrv.phase == "round_end", "Host played final card of Round 2 Trick 2/2 via HandFan swipe-up")

	# Verify Req 2, 3, 4, 11, 12 on 15-card HandFan & Table HUD
	var hfan2: HandFan = main_scene.get_hand_fan()
	var big_hand: Array = []
	var big_legal: Array = []
	for bi in range(15):
		var cid := 200 + bi
		big_hand.append({"id": cid, "kind": "num", "suit": "blue", "value": (bi % 13) + 1})
		big_legal.append(cid)
	hfan2.set_hand(big_hand, big_legal, true, 207, false)
	hfan2.size = Vector2(680, 200)
	var prev_pick := -1
	var monotonic := true
	for px in range(20, 661, 45):
		var pk := hfan2.debug_pick_card_at(Vector2(float(px), 100.0))
		if pk < prev_pick:
			monotonic = false
		prev_pick = pk
	_assert(monotonic and prev_pick >= 13, "15-card monotonic X scrub reaches across entire fan smoothly (Req 3)")

	# Req 2: Double-tap on already selected card must NEVER play
	var swipe_fired := [false]
	var conn_sw := func(_cid: int, _pos: Vector2 = Vector2.ZERO): swipe_fired[0] = true
	hfan2.card_swipe_played.connect(conn_sw)
	hfan2._set_focus(3)
	var ev_tap := InputEventMouseButton.new()
	ev_tap.button_index = MOUSE_BUTTON_LEFT
	ev_tap.pressed = true
	ev_tap.position = Vector2(180, 90)
	hfan2._gui_input(ev_tap)
	var ev_rel := InputEventMouseButton.new()
	ev_rel.button_index = MOUSE_BUTTON_LEFT
	ev_rel.pressed = false
	ev_rel.position = Vector2(180, 90)
	hfan2._gui_input(ev_rel)
	_assert(not swipe_fired[0], "Double-tap on already-selected card does NOT play card (Req 2)")

	# Req 4: Fast upward flick plays card even without reaching central rune
	hfan2.debug_simulate_fast_flick_play(3)
	_assert(swipe_fired[0], "Fast strong upward flick plays card cleanly (Req 4)")
	hfan2.card_swipe_played.disconnect(conn_sw)

	# Last-card visual drag check (1 card left in hand must follow finger up toward stack/rune)
	hfan2.set_hand([{"id": 18, "kind": "num", "suit": "blue", "value": 6}], [18], true)
	hfan2.debug_simulate_drag_hold(0, 260.0)
	var cv_last := hfan2.get_card_view(0)
	_assert(cv_last != null and cv_last.position.y < -100.0, "Last card (n == 1) elevates smoothly when dragged upward toward central Rune")

	# Req 11 & 12: Timeline records won/lost + Players strip is a wrapping GridContainer without ScrollContainer
	var rtl := ProgressWidgets.RoundTimelineBar.new()
	rtl.set_progress(4, 12, [1, -1, 1])
	_assert(rtl.outcomes.size() == 3 and rtl.outcomes[0] == 1 and rtl.outcomes[1] == -1, "RoundTimelineBar records won/lost outcomes (Req 11)")
	rtl.free()
	_assert(main_scene._players_strip is GridContainer and main_scene._players_strip.columns >= 2, "Players strip wraps cleanly via GridContainer without scrollbar (Req 12)")

	main_scene._on_leave_pressed()
	main_scene.queue_free()
