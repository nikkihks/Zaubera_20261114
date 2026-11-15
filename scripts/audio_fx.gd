class_name AudioFX
extends Node

const SFX_PATHS := {
	"scrub": "res://assets/sfx/card_scrub.wav",
	"deal": "res://assets/sfx/card_deal.wav",
	"play": "res://assets/sfx/card_play.wav",
	"wizard": "res://assets/sfx/wizard_cast.wav",
	"jester": "res://assets/sfx/jester_bell.wav",
	"trick_win": "res://assets/sfx/trick_win.wav",
	"bid": "res://assets/sfx/bid_confirm.wav",
	"error": "res://assets/sfx/error_buzz.wav"
}

const POOL_SIZE := 6

var muted := false
var haptics_enabled := true
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _last_scrub_ms := 0

func _ready() -> void:
	for k in SFX_PATHS.keys():
		var path: String = SFX_PATHS[k]
		if ResourceLoader.exists(path):
			_streams[k] = load(path)
	for _i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.volume_db = -4.0
		add_child(player)
		_pool.append(player)

func play(sfx_name: String, pitch_variance: float = 0.04, volume_offset_db: float = 0.0) -> void:
	if muted:
		return
	if not _streams.has(sfx_name) or _pool.is_empty():
		return
	if sfx_name == "scrub":
		var now := Time.get_ticks_msec()
		if now - _last_scrub_ms < 28:
			return
		_last_scrub_ms = now
	var stream: AudioStream = _streams[sfx_name]
	if stream == null:
		return
	var p: AudioStreamPlayer = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = stream
	p.volume_db = -4.0 + volume_offset_db
	if pitch_variance > 0.0:
		p.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	else:
		p.pitch_scale = 1.0
	p.play()

func haptic(duration_ms: int = 20, amplitude: float = 0.65) -> void:
	if not haptics_enabled:
		return
	if DisplayServer.get_name() == "headless":
		return
	Input.vibrate_handheld(duration_ms, amplitude)

func feedback(sfx_name: String, haptic_ms: int = 0, haptic_amp: float = 0.6) -> void:
	play(sfx_name)
	if haptic_ms > 0:
		haptic(haptic_ms, haptic_amp)
