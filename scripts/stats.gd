class_name Stats
extends RefCounted
## Batch summaries: who won and how, and what each side's men actually did.


static func summarize(results: Array[Dictionary]) -> Dictionary:
	var wins := [0, 0]
	var draws := 0
	var dur := 0.0
	var reasons := {}
	var fb := 0.0
	var shots := [0, 0]
	var hits := [0, 0]
	var heads := [0, 0]
	var kills := [0, 0]
	var fist_kills := [0, 0]
	var deny := [0, 0]
	var high := [0, 0]
	var flips := [0, 0]
	var ff := [0.0, 0.0]
	var plans := [{}, {}]
	var by_preset := {}   # preset -> {kills, deaths, shots, hits, n}
	for r in results:
		if r["winner"] >= 0:
			wins[r["winner"]] += 1
		else:
			draws += 1
		dur += float(r["duration"])
		fb += maxf(float(r["first_blood"]), 0.0)
		var reason := String(r["reason"])
		if reason.begins_with("decision"):
			reason = "decision"
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		for t in 2:
			for k in r["plans"][t]:
				if String(k) != "":
					plans[t][k] = float(plans[t].get(k, 0.0)) + float(r["plans"][t][k])
		for m in r["men"]:
			var t: int = m["team"]
			shots[t] += int(m["shots"])
			hits[t] += int(m["hits"])
			heads[t] += int(m["heads"])
			kills[t] += int(m["kills"])
			fist_kills[t] += int(m["fist_kills"])
			deny[t] += int(m["deny_hits"])
			high[t] += int(m["high_hits"])
			flips[t] += int(m["flips"])
			ff[t] += float(m["ff"])
			var key := String(m["preset"])
			var bp: Dictionary = by_preset.get(key, {"kills": 0, "deaths": 0, "shots": 0, "hits": 0, "n": 0, "dmg": 0.0})
			bp["kills"] += int(m["kills"])
			bp["deaths"] += 0 if m["alive"] else 1
			bp["shots"] += int(m["shots"])
			bp["hits"] += int(m["hits"])
			bp["dmg"] += float(m["dmg"])
			bp["n"] += 1
			by_preset[key] = bp
	var n := maxi(results.size(), 1)
	var last: Dictionary = results[-1] if results.size() > 0 else {}
	var docs: Array = last.get("doctrines", ["?", "?"])
	var pres: Array = last.get("presets", ["?", "?"])
	var txt := "Batch of %d: Red(%s/%s) %d, Blue(%s/%s) %d, draws %d, avg %ds, first blood avg %ds. " % [
		results.size(), docs[0], pres[0], wins[0], docs[1], pres[1], wins[1], draws, int(dur / n), int(fb / n)]
	var rs := PackedStringArray()
	for k in reasons:
		rs.append("%s:%d" % [k, reasons[k]])
	txt += "Endings " + ", ".join(rs) + ". "
	for t in 2:
		txt += "%s acc %d%% heads %d deny %d high %d fistkills %d flips %d ff %d. " % [MatchManager.TEAM_NAMES[t], int(100.0 * hits[t] / maxf(shots[t], 1)), heads[t], deny[t], high[t], fist_kills[t], flips[t], int(ff[t])]
	return {"text": txt, "data": {"matches": results.size(), "wins": wins, "draws": draws, "avg_duration": dur / n,
		"first_blood": fb / n, "reasons": reasons, "shots": shots, "hits": hits, "heads": heads, "kills": kills,
		"fist_kills": fist_kills, "deny": deny, "high": high, "flips": flips, "ff": ff, "plans": plans,
		"by_preset": by_preset, "doctrines": docs, "presets": pres}}
