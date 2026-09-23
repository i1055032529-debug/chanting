extends RefCounted
## Deterministic input policy used by integration tests and preview capture.

static func finish(rules: RefCounted, target_heat := 88.0, target_done := 98.0, timing := 0.80, delta := 1.0 / 120.0, spam := false) -> Dictionary:
	if rules.state == 0: rules.start()
	for i in range(6000):
		if rules.state != 1: break
		if rules.doneness >= target_done:
			rules.plate()
			break
		if spam or (rules.stir_progress >= timing and rules.doneness + 12.0 <= target_done + 4.0):
			rules.stir()
		rules.advance(delta, rules.temperature < target_heat)
	return rules.result.duplicate(true)
