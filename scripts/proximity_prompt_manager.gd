extends Node

var _prompts: Array[Node] = []

func register(prompt: Node) -> void:
	if not _prompts.has(prompt):
		_prompts.append(prompt)

func unregister(prompt: Node) -> void:
	_prompts.erase(prompt)

func get_winner_for_player(player: Node) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for p in _prompts:
		if not is_instance_valid(p):
			continue
		if not p.enabled:
			continue
		if p._exhausted:
			continue
		var d: float = p.global_position.distance_to(player.global_position)
		if d <= p.max_distance and d < best_dist:
			best_dist = d
			best = p
	return best
