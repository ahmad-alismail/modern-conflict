extends Commander
## Optional LLM commander. Sends a fog-filtered battlefield observation to a language
## model on a fixed cadence and turns its JSON reply into validated game commands.
## Providers: Ollama (local), any OpenAI-compatible endpoint (LM Studio local, or cloud),
## Anthropic Claude (cloud). Never required: if it is disabled, unconfigured, lacks paid
## consent, or keeps failing, a classic AI commands the team instead so the match stays
## playable. The simulation never waits for the model.
class_name LLMCommander

const MAX_ORDERS := 24
const ANTHROPIC_URL := "https://api.anthropic.com/v1/messages"
const ANTHROPIC_VERSION := "2026-10-21"
const ACTIONS := ["move", "attack_move", "attack", "garrison", "retreat", "hold", "stop", "smoke", "support", "reinforce", "unload", "board"]

const ORDER_SCHEMA := {
	"type": "object",
	"properties": {
		"reasoning": {"type": "string", "description": "One or two short sentences explaining the plan."},
		"orders": {
			"type": "array",
			"items": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ACTIONS},
					"unit_ids": {"type": "array", "items": {"type": "integer"}},
					"x": {"type": "number"},
					"y": {"type": "number"},
					"target_id": {"type": "integer"},
					"power": {"type": "string"},
				},
				"required": ["action", "unit_ids"],
				"additionalProperties": false,
			},
		},
	},
	"required": ["reasoning", "orders"],
	"additionalProperties": false,
}

const SYSTEM_PROMPT := """You are the battlefield commander of one side in Modern Conflict, a real-time tactical wargame in a fictional modern city. You receive a JSON observation of what your side can currently see (fog of war: enemies you cannot see are not listed; last_known_contacts are stale sightings) and you reply with orders.

Coordinates are meters: x grows east, y grows south. Your deployment zone is where retreating units go.

Victory: in "vp" mode, holding more objectives than the enemy drains their tickets, and every unit lost costs tickets, so avoid needless losses. In "hold" mode the defender must keep at least one objective until the deadline.

Order actions (unit_ids are YOUR unit ids):
- move {x,y}: move there, firing only if fired upon on the way.
- attack_move {x,y}: advance and engage enemies met on the way (default for assaults).
- attack {target_id}: focus fire on a VISIBLE enemy id.
- garrison {x,y}: infantry enter the building at/near x,y (strong protection, great vision).
- retreat: fall back to the deployment zone fast (preserves damaged units).
- hold: stop and hold position. stop: cancel orders.
- smoke {x,y}: smoke screen (vehicles pop smoke around themselves; infantry throw at x,y).
- unload: transport drops its passengers. board {target_id}: infantry board YOUR transport id.
- support {power, x, y}: call a team support power listed in support_powers (only if charges>0 and ready).
- reinforce (unit_ids may be empty): call the next reinforcement wave.

Tactics that work: keep infantry with armor (tanks die to close-range anti-tank infantry in buildings); use buildings for infantry; scout before committing; concentrate force on one or two objectives instead of spreading thin; pull back pinned or badly damaged units; use artillery or airstrikes on clustered visible enemies away from your own units; anti-air units and heavy machine guns threaten helicopters and drones.

Only give orders that change something; units keep their current orders otherwise. Keep it to the most important orders (at most 24). Reply with JSON only, matching the schema: {"reasoning": "...", "orders": [...]}."""

var session
var _fallback: ClassicAI
var _http: HTTPRequest
var _busy := false
var _timer := 3.0
var _failures := 0
var _interval := 10.0
var _provider := ""
var _disabled_reason := ""
var _pending_world: SimWorld
var _pending_orders: Array = []


func _init(p_team: int, p_session) -> void:
	team = p_team
	session = p_session
	_fallback = ClassicAI.new(p_team, "medium")
	_provider = Settings.get_value("llm", "provider")
	_interval = float(Settings.get_value("llm", "think_interval"))
	_disabled_reason = _check_config()
	if _disabled_reason != "":
		_log("LLM commander unavailable (%s); classic AI is in command." % _disabled_reason)
	elif session != null:
		_http = HTTPRequest.new()
		_http.timeout = 120.0
		session.add_child(_http)
		_http.request_completed.connect(_on_response)
		_log("LLM commander online (%s · %s)" % [_provider, _model()])


func _check_config() -> String:
	if not Settings.get_value("llm", "enabled"):
		return "disabled in Settings"
	match _provider:
		"anthropic":
			if String(Settings.get_value("llm", "anthropic_key")).strip_edges() == "":
				return "no Anthropic API key"
			if not Settings.get_value("llm", "paid_consent"):
				return "paid-service consent not given"
		"openai_compat":
			var url := String(Settings.get_value("llm", "openai_url"))
			var local := url.contains("localhost") or url.contains("127.0.0.1")
			if not local and not Settings.get_value("llm", "paid_consent"):
				return "cloud endpoint requires paid-service consent"
		"ollama":
			pass
		_:
			return "unknown provider"
	return ""


func _model() -> String:
	match _provider:
		"anthropic": return String(Settings.get_value("llm", "anthropic_model"))
		"openai_compat": return String(Settings.get_value("llm", "openai_model"))
		_: return String(Settings.get_value("llm", "ollama_model"))


func _log(text: String) -> void:
	print("[LLM team %d] %s" % [team, text])
	if session != null and session.hud != null and session.hud.has_method("commander_log"):
		session.hud.commander_log(team, text)


func using_fallback() -> bool:
	return _disabled_reason != "" or _failures >= 4


# ================================================================== cadence ===

func think(w: SimWorld) -> void:
	if using_fallback():
		_fallback.think(w)
		return
	# apply orders that arrived since the last tick (deterministically, inside the sim loop)
	if not _pending_orders.is_empty():
		for cmd in _pending_orders:
			issue(w, cmd)
		_pending_orders.clear()
	_timer -= SimWorld.DT
	if _timer > 0.0 or _busy:
		return
	_timer = _interval * (1.0 + _failures * 0.75)
	_pending_world = w
	_send(Observation.build(w, team))


func _send(obs: Dictionary) -> void:
	var user_text := "Battlefield observation:\n" + JSON.stringify(obs) + "\n\nGive your orders now."
	var url := ""
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := {}
	match _provider:
		"anthropic":
			url = ANTHROPIC_URL
			headers.append("x-api-key: " + String(Settings.get_value("llm", "anthropic_key")).strip_edges())
			headers.append("anthropic-version: " + ANTHROPIC_VERSION)
			headers.append("anthropic-beta: server-side-fallback-2026-07-01")
			body = {
				"model": _model(),
				"max_tokens": 16000,
				"fallbacks": "default",
				"system": [{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
				"messages": [{"role": "user", "content": user_text}],
				"output_config": {"effort": "low", "format": {"type": "json_schema", "schema": ORDER_SCHEMA}},
			}
		"openai_compat":
			url = String(Settings.get_value("llm", "openai_url")).trim_suffix("/") + "/chat/completions"
			var key := String(Settings.get_value("llm", "openai_key")).strip_edges()
			if key != "":
				headers.append("Authorization: Bearer " + key)
			body = {
				"model": _model(),
				"messages": [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": user_text}],
				"response_format": {"type": "json_schema", "json_schema": {"name": "orders", "schema": ORDER_SCHEMA}},
			}
		_:
			url = String(Settings.get_value("llm", "ollama_url")).trim_suffix("/") + "/api/chat"
			body = {
				"model": _model(), "stream": false, "format": ORDER_SCHEMA, "think": false,
				"options": {"num_ctx": 16384}, "keep_alive": "15m",
				"messages": [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": user_text}],
			}
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_fail("request error %s" % error_string(err))
		return
	_busy = true


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("network error (result %d)" % result)
		return
	var text := body.get_string_from_utf8()
	if code < 200 or code >= 300:
		_fail("HTTP %d: %s" % [code, text.substr(0, 160)])
		return
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_fail("unreadable response")
		return
	var content := _extract_content(data)
	if content == "":
		return
	var reply = JSON.parse_string(_json_slice(content))
	if typeof(reply) != TYPE_DICTIONARY:
		_fail("reply was not valid JSON")
		return
	_failures = 0
	var cmds := parse_orders(reply, _pending_world, team)
	_pending_orders.append_array(cmds)
	_log("%s  [%d orders]" % [String(reply.get("reasoning", "")).substr(0, 220), cmds.size()])


func _extract_content(data: Dictionary) -> String:
	match _provider:
		"anthropic":
			if data.get("stop_reason", "") == "refusal":
				_log("Model declined this turn (refusal); holding current orders.")
				return ""
			var out := ""
			for block in data.get("content", []):
				if block.get("type", "") == "text":
					out += String(block.get("text", ""))
			if out == "":
				_fail("empty reply")
			return out
		"openai_compat":
			var ch: Array = data.get("choices", [])
			if ch.is_empty():
				_fail("no choices in reply")
				return ""
			return String(ch[0].get("message", {}).get("content", ""))
		_:
			return String(data.get("message", {}).get("content", ""))


static func _json_slice(s: String) -> String:
	var a := s.find("{")
	var b := s.rfind("}")
	return s.substr(a, b - a + 1) if a >= 0 and b > a else s


func _fail(msg: String) -> void:
	_failures += 1
	_log("LLM error: %s%s" % [msg, " — classic AI takes over." if _failures == 4 else ""])


# =============================================================== validation ===

## Convert a model reply into safe sim commands. Unknown units, enemy ids that are not
## visible, invalid powers and out-of-map positions are dropped or clamped.
static func parse_orders(reply: Dictionary, w: SimWorld, team: int) -> Array:
	var out := []
	if w == null:
		return out
	var orders = reply.get("orders", [])
	if typeof(orders) != TYPE_ARRAY:
		return out
	var size := w.map.size_m()
	for o in orders.slice(0, MAX_ORDERS):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var action := String(o.get("action", ""))
		if not action in ACTIONS:
			continue
		var ids := []
		var raw_ids = o.get("unit_ids", [])
		if typeof(raw_ids) == TYPE_ARRAY:
			for v in raw_ids:
				var u: SimUnit = w.by_id.get(int(v))
				if u != null and u.alive and u.team == team:
					ids.append(u.id)
		var has_pos: bool = o.has("x") and o.has("y")
		var pos := Vector2(clampf(float(o.get("x", 0.0)), 1.0, size.x - 1.0), clampf(float(o.get("y", 0.0)), 1.0, size.y - 1.0))
		match action:
			"reinforce":
				out.append({"type": "reinforce", "team": team})
				continue
			"support":
				var power := String(o.get("power", ""))
				if has_pos and w.teams[team]["support"].has(power):
					out.append({"type": "support", "team": team, "power": power, "pos": pos,
						"dir": (w.map.team_spawn(1 - team).get_center() - w.map.team_spawn(team).get_center()).normalized()})
				continue
		if ids.is_empty():
			continue
		match action:
			"move", "attack_move", "smoke":
				if has_pos:
					out.append({"type": action, "team": team, "ids": ids, "pos": pos})
				elif action == "smoke":
					out.append({"type": "smoke", "team": team, "ids": ids})
			"attack":
				var t: SimUnit = w.by_id.get(int(o.get("target_id", -1)))
				if t != null and t.alive and t.team != team and (t.vis_mask & (1 << team)) != 0:
					out.append({"type": "attack", "team": team, "ids": ids, "target": t.id})
			"board":
				var tr: SimUnit = w.by_id.get(int(o.get("target_id", -1)))
				if tr != null and tr.alive and tr.team == team:
					out.append({"type": "board", "team": team, "ids": ids, "target": tr.id})
			"garrison":
				if has_pos:
					var bi := _nearest_building(w, pos, 20.0)
					if bi >= 0:
						out.append({"type": "garrison", "team": team, "ids": ids, "bld": bi})
			"hold":
				out.append({"type": "hold", "team": team, "ids": ids, "value": true})
			_:
				out.append({"type": action, "team": team, "ids": ids})
	return out


static func _nearest_building(w: SimWorld, p: Vector2, max_d: float) -> int:
	var best := -1
	var bd := max_d
	for bi in w.buildings.size():
		if w.buildings[bi]["state"] == 2:
			continue
		var d := w.building_distance(bi, p)
		if d < bd:
			bd = d
			best = bi
	return best
