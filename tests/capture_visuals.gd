extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var out_dir := OS.get_environment("ZAUBERA_OUT_DIR")
	if out_dir.is_empty():
		out_dir = "res://scratch_out"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	vp.size_2d_override = Vector2i(720, 1280)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var main_sc: Control = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	vp.add_child(main_sc)

	await _settle(6)
	await _snap(vp, out_dir.path_join("app_home.png"))

	# Host table + 4 bots (5 total players -> tests multi-row player wrap!)
	main_sc.trigger_host_for_test("Merlin")
	var srv: WizardServer = main_sc.get_server()
	srv.host_add_bot()
	srv.host_add_bot()
	srv.host_add_bot()
	srv.host_add_bot()
	await _settle(5)
	await _snap(vp, out_dir.path_join("app_lobby.png"))

	# Inject rich Round 6 playing state: 14 cards in hand, local turn active, trick cards on rune, won/lost history!
	var hand: Array = []
	var suits := ["red", "blue", "green", "yellow"]
	for i in range(12):
		hand.append({"id": 10 + i, "kind": "num", "suit": suits[i % 4], "value": ((i * 3) % 13) + 1})
	hand.append({"id": 50, "kind": "wizard", "suit": "wizard", "value": 14})
	hand.append({"id": 56, "kind": "jester", "suit": "jester", "value": 0})

	var hist_host := [
		{"round": 1, "bid": 1, "won": 1, "delta": 30, "total": 30},
		{"round": 2, "bid": 1, "won": 0, "delta": -10, "total": 20},
		{"round": 3, "bid": 2, "won": 2, "delta": 40, "total": 60},
		{"round": 4, "bid": 0, "won": 0, "delta": 20, "total": 80},
		{"round": 5, "bid": 3, "won": 1, "delta": -20, "total": 60}
	]
	var mk_hist := func(vals: Array) -> Array:
		var arr: Array = []
		var tot := 0
		for r in range(vals.size()):
			var d := int(vals[r])
			tot += d
			arr.append({"round": r + 1, "bid": 1, "won": 1 if d > 0 else 0, "delta": d, "total": tot})
		return arr

	var fake_state := {
		"room_name": "Tisch von Merlin",
		"phase": "playing",
		"quick_mode": false,
		"plus_minus_rule": true,
		"round_number": 6,
		"max_rounds": 12,
		"dealer_seat": 2,
		"turn_seat": 0,
		"your_seat": 0,
		"trump_suit": "blue",
		"trump_card": {"id": 22, "kind": "num", "suit": "blue", "value": 9},
		"lead_suit": "red",
		"trick_number": 2,
		"trick_winner_seat": -1,
		"trick_winner_reason": "",
		"status_banner": "Stich 2/6 • Rot bedienen",
		"forbidden_bid": -1,
		"bids_sum": 6,
		"host_ips": ["192.168.178.42"],
		"http_port": 8080,
		"ws_port": 8081,
		"your_hand": hand,
		"legal_card_ids": [10, 14, 18, 50, 56],
		"trick_cards": [
			{"seat": 3, "card": {"id": 9, "kind": "num", "suit": "red", "value": 10}},
			{"seat": 4, "card": {"id": 5, "kind": "num", "suit": "red", "value": 6}}
		],
		"players": [
			{"seat": 0, "name": "Merlin", "is_host": true, "is_bot": false, "connected": true, "score": 60, "bid": 2, "tricks_won": 1, "last_round_delta": -20, "card_count": 14, "round_history": hist_host},
			{"seat": 1, "name": "Morgana", "is_host": false, "is_bot": true, "connected": true, "score": 90, "bid": 1, "tricks_won": 0, "last_round_delta": 30, "card_count": 14, "round_history": mk_hist.call([20, 30, -10, 30, 20])},
			{"seat": 2, "name": "Gandalf", "is_host": false, "is_bot": true, "connected": true, "score": 40, "bid": 0, "tricks_won": 0, "last_round_delta": 20, "card_count": 14, "round_history": mk_hist.call([30, -20, 20, -10, 20])},
			{"seat": 3, "name": "Elara", "is_host": false, "is_bot": true, "connected": true, "score": 10, "bid": 2, "tricks_won": 0, "last_round_delta": -10, "card_count": 13, "round_history": mk_hist.call([-10, 20, -10, 20, -10])},
			{"seat": 4, "name": "Balthazar", "is_host": false, "is_bot": true, "connected": true, "score": 110, "bid": 1, "tricks_won": 0, "last_round_delta": 40, "card_count": 13, "round_history": mk_hist.call([20, 30, 30, -10, 40])}
		]
	}

	main_sc._on_state_received(fake_state)
	var hfan: HandFan = main_sc.get_hand_fan()
	hfan._set_focus(6)
	hfan._snap_if_idle()
	await _settle(8)
	await _snap(vp, out_dir.path_join("app_table_hand14.png"))

	# Capture Bidding menu (Stichansage with Plus/Minus-Eins forbidden bid + Aufgedeckte Trumpfkarte)
	var bid_state: Dictionary = fake_state.duplicate(true)
	bid_state["phase"] = "bidding"
	bid_state["round_number"] = 6
	bid_state["bids_sum"] = 4
	bid_state["forbidden_bid"] = 2
	bid_state["trump_suit"] = "red"
	bid_state["trump_card"] = {"id": 1, "kind": "num", "suit": "red", "value": 2}
	bid_state["trick_cards"] = []
	bid_state["status_banner"] = "Stiche ansagen (0 - 6)"
	main_sc._on_state_received(bid_state)
	await _settle(6)
	await _snap(vp, out_dir.path_join("app_bid.png"))

	# Capture Trump Choice menu (when Wizard revealed as trump card)
	var trump_state: Dictionary = fake_state.duplicate(true)
	trump_state["phase"] = "choose_trump"
	trump_state["trump_suit"] = "pending"
	trump_state["trump_card"] = {"id": 50, "kind": "wizard", "suit": "wizard", "value": 14}
	trump_state["trick_cards"] = []
	trump_state["status_banner"] = "Du hast einen Zauberer aufgedeckt!"
	main_sc._on_state_received(trump_state)
	await _settle(6)
	await _snap(vp, out_dir.path_join("app_trump_choice.png"))

	# Capture Last Card (n == 1) dragged smoothly up onto central glowing Rune
	var last_state: Dictionary = fake_state.duplicate(true)
	last_state["your_hand"] = [{"id": 18, "kind": "num", "suit": "blue", "value": 6}]
	last_state["legal_card_ids"] = [18]
	main_sc._on_state_received(last_state)
	await _settle(4)
	hfan.debug_simulate_drag_hold(0, 385.0)
	await _settle(4)
	await _snap(vp, out_dir.path_join("app_lastcard_drag.png"))

	# Restore rich 14-card state & capture Scorecard modal (Starry-Sky Graph)
	main_sc._on_state_received(fake_state)
	await _settle(4)
	main_sc._show_scorecard_modal()
	await _settle(5)
	await _snap(vp, out_dir.path_join("app_scorecard.png"))

	# Keep server open briefly ONLY if requested for browser screenshot script
	if OS.get_environment("ZAUBERA_HOLD_SERVER") == "1":
		var f_ready := FileAccess.open(out_dir.path_join("server_ready.txt"), FileAccess.WRITE)
		if f_ready:
			f_ready.store_string(JSON.stringify(fake_state))
			f_ready.close()
		for _t in range(360):
			srv._process(0.05)
			await create_timer(0.05).timeout
			if FileAccess.file_exists(out_dir.path_join("done.flag")):
				break

	srv.stop_hosting()
	quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame
		await create_timer(0.02).timeout

func _snap(vp: SubViewport, path: String) -> void:
	var img := vp.get_texture().get_image()
	img.save_png(path)
	print("SAVED_SNAP: ", path)
