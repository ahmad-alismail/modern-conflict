extends RefCounted
## Base class for anything that commands a team: classic AI, LLM agents.
## `think()` is called once per simulation tick (before the step); commanders decide
## on their own cadence and submit orders through `world.issue()`. Commanders must
## only use information their team can see — use the Observation helpers.
class_name Commander

var team := 0


func think(_world: SimWorld) -> void:
	pass


func issue(world: SimWorld, cmd: Dictionary) -> void:
	cmd["team"] = team
	world.issue(cmd)
