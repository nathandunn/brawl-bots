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
	var tdeaths := [0, 0]
	var fist_kills := [0, 0]
	var deny := [0, 0]
	var high := [0, 0]
	var flips := [0, 0]
	var ff := [0.0, 0.0]
	var plans := [{}, {}]
	var by_preset := {}   # preset -> {kills, deaths, shots, hits, n}
	var modes := [{}, {}]
	var events := [{"cowers": 0, "flanks": 0, "hides": 0, "rushes": 0, "dry": 0}, {"cowers": 0, "flanks": 0, "hides": 0, "rushes": 0, "dry": 0}]
	var aimb := [[0, 0], [0, 0], [0, 0], [0, 0]]
	var aimr := []
	var deaths := {}
	var wounds := {}
	var melee := [{"hits": 0, "kills": 0, "blocks": 0, "parries": 0, "dodges": 0, "jumps": 0, "stars": 0, "star_hits": 0}, {"hits": 0, "kills": 0, "blocks": 0, "parries": 0, "dodges": 0, "jumps": 0, "stars": 0, "star_hits": 0}]
	var rules := [{}, {}]
	for i in 12:
		aimr.append([0, 0])
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
			tdeaths[t] += 0 if m["alive"] else 1
			fist_kills[t] += int(m["fist_kills"])
			deny[t] += int(m["deny_hits"])
			high[t] += int(m["high_hits"])
			flips[t] += int(m["flips"])
			ff[t] += float(m["ff"])
			for k in m.get("modes", {}):
				modes[t][k] = float(modes[t].get(k, 0.0)) + float(m["modes"][k])
			for k in ["jams", "slips", "gun_knocks"]:
				events[t][k] = int(events[t].get(k, 0)) + int(m.get(k, 0))
			for k in ["cowers", "flanks", "hides", "rushes"]:
				events[t][k] += int(m.get(k, 0))
			if float(m.get("dry_at", -1.0)) >= 0.0:
				events[t]["dry"] += 1
			var ab: Array = m.get("aimb", [])
			for b in ab.size():
				aimb[b][0] += int(ab[b][0])
				aimb[b][1] += int(ab[b][1])
			if not m["alive"]:
				var dp := String(m.get("death_part", ""))
				dp = "fists" if dp == "bruise" else dp
				dp = "head/heart" if dp == "head" or dp == "heart" else ("limb" if dp.begins_with("arm") or dp.begins_with("leg") else dp)
				deaths[dp] = int(deaths.get(dp, 0)) + 1
			for k in ["blocks", "parries", "dodges", "jumps", "stars", "star_hits", "bottles", "bottle_hits", "falls", "fall_kills", "kicks", "kick_hits", "wrestles", "throws", "chairs", "knives"]:
				melee[t][k] = int(melee[t].get(k, 0)) + int(m.get(k, 0))
			melee[t]["hits"] += int(m.get("melee_hits", 0))
			melee[t]["kills"] += int(m.get("melee_kills", 0))
			var rr: Dictionary = m.get("rules", {})
			for k in rr:
				rules[t][k] = int(rules[t].get(k, 0)) + int(rr[k])
			for w in m.get("wounds", []):
				wounds[w] = int(wounds.get(w, 0)) + 1
			var ar: Array = m.get("aimr", [])
			for i in ar.size():
				aimr[i][0] += int(ar[i][0])
				aimr[i][1] += int(ar[i][1])
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
	var tn: Array = last.get("team_names", ["Red", "Blue"])
	var txt := "Batch of %d on %s: %s(%s/%s x%d %s) %d, %s(%s/%s x%d %s) %d, draws %d, avg %ds, first blood avg %ds. " % [
		results.size(), String(last.get("map", "?")), tn[0], docs[0], pres[0], int(last.get("sizes", [5, 5])[0]), String(last.get("grades", ["?", "?"])[0]), wins[0], tn[1], docs[1], pres[1], int(last.get("sizes", [5, 5])[1]), String(last.get("grades", ["?", "?"])[1]), wins[1], draws, int(dur / n), int(fb / n)]
	var rs := PackedStringArray()
	for k in reasons:
		rs.append("%s:%d" % [k, reasons[k]])
	txt += "Endings " + ", ".join(rs) + ". "
	var bn := ["snap <0.3s", "quick 0.3-0.7", "steady 0.7-1.2", "careful >1.2"]
	var bs := PackedStringArray()
	for b in 4:
		bs.append("%s %d%% of %d" % [bn[b], int(100.0 * aimb[b][1] / maxf(aimb[b][0], 1)), aimb[b][0]])
	txt += "Hit rate by aim time: " + ", ".join(bs) + ". "
	for rb in 3:
		var rs2 := PackedStringArray()
		for b in 4:
			var c: Array = aimr[rb * 4 + b]
			rs2.append("%d%%/%d" % [int(100.0 * c[1] / maxf(c[0], 1)), c[0]])
		txt += "[%s] %s. " % [["<7m", "7-14m", ">14m"][rb], " ".join(rs2)]
	for t in 2:
		var tot := 0.0
		for k in modes[t]:
			tot += float(modes[t][k])
		var ms := PackedStringArray()
		for k in modes[t]:
			ms.append("%s %d%%" % [k, int(round(100.0 * float(modes[t][k]) / maxf(tot, 1.0)))])
		txt += "%s modes: %s; per match cowers %.1f flanks %.1f hides %.1f rushes %.1f, ran dry %.1f men, jams %.1f (knocked %.1f), slips %.1f. " % [String(tn[t]), ", ".join(ms), events[t]["cowers"] / float(n0(results)), events[t]["flanks"] / float(n0(results)), events[t]["hides"] / float(n0(results)), events[t]["rushes"] / float(n0(results)), events[t]["dry"] / float(n0(results)), events[t].get("jams", 0) / float(n0(results)), events[t].get("gun_knocks", 0) / float(n0(results)), events[t].get("slips", 0) / float(n0(results))]
	var dps := PackedStringArray()
	for k in deaths:
		dps.append("%s %d" % [k, deaths[k]])
	txt += "Deaths: " + ", ".join(dps) + ". "
	var wps := PackedStringArray()
	for k in wounds:
		wps.append("%s %d" % [k, wounds[k]])
	txt += "Wounds: " + ", ".join(wps) + ". "
	for t in 2:
		txt += "%s melee hits %d kills %d, blocks %d parries %d dodges %d, jumps %d, stars %d/%d, thrown %d/%d (chairs %d, knives %d), kicks %d/%d, wrestles %d (throws %d), went over the edge %d (fall kills %d). " % [String(tn[t]), melee[t]["hits"], melee[t]["kills"], melee[t]["blocks"], melee[t]["parries"], melee[t]["dodges"], melee[t]["jumps"], melee[t]["star_hits"], melee[t]["stars"], melee[t].get("bottle_hits", 0), melee[t].get("bottles", 0), melee[t].get("chairs", 0), melee[t].get("knives", 0), melee[t].get("kick_hits", 0), melee[t].get("kicks", 0), melee[t].get("wrestles", 0), melee[t].get("throws", 0), melee[t].get("falls", 0), melee[t].get("fall_kills", 0)]
	for t in 2:
		txt += "%s deaths %d acc %d%% heads %d deny %d high %d fistkills %d flips %d ff %d. " % [String(tn[t]), tdeaths[t], int(100.0 * hits[t] / maxf(shots[t], 1)), heads[t], deny[t], high[t], fist_kills[t], flips[t], int(ff[t])]
	return {"text": txt, "data": {"matches": results.size(), "wins": wins, "draws": draws, "avg_duration": dur / n,
		"first_blood": fb / n, "reasons": reasons, "shots": shots, "hits": hits, "heads": heads, "kills": kills, "team_deaths": tdeaths,
		"fist_kills": fist_kills, "deny": deny, "high": high, "flips": flips, "ff": ff, "plans": plans,
		"by_preset": by_preset, "doctrines": docs, "presets": pres, "modes": modes, "mode_events": events, "aimb": aimb, "aimr": aimr, "deaths": deaths, "wounds": wounds, "team_names": tn, "melee": melee, "rules": rules}}


static func n0(results: Array) -> int:
	return maxi(results.size(), 1)
