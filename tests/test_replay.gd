extends TestBase


func _setup() -> SimWorld:
	var w := SimWorld.new()
	w.setup({"map": CityGenerator.generate(31), "seed": 31, "teams": [{"faction": "pdb"}, {"faction": "hac"}]})
	return w


func test_replay_reproduces_ai_battle() -> void:
	var live := _setup()
	var ais := [ClassicAI.new(0, "hard"), ClassicAI.new(1, "medium")]
	for i in 3000:
		for ai in ais:
			ai.think(live)
		live.step()
		live.events.clear()
	var log := live.command_log.duplicate(true)
	check(log.size() > 20, "AI issued commands (%d)" % log.size())
	# play back: no AI, only the recorded command stream
	var rep := _setup()
	var k := 0
	for i in 3000:
		while k < log.size() and int(log[k]["tick"]) <= rep.tick:
			rep.issue(log[k]["cmd"])
			k += 1
		rep.step()
		rep.events.clear()
	eq(rep.state_hash(), live.state_hash(), "replay matches the live battle exactly")
