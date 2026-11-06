extends SceneTree
## Objective check of the synthesized sound bank (we cannot listen to it):
##   .tools/godot/<godot> --headless --path . -s res://tools/audio_report.gd [-- --png --profile]
## Prints generation time and, per clip variant: duration, peak and RMS (dBFS), DC offset,
## clipped samples, NaN/Inf repairs, and edge continuity (loops: seam jump vs. typical
## sample-to-sample step; one-shots: last sample must be ~0). Exit code 1 on any failure.
## --png also writes a waveform contact sheet to shots/audio_waveforms.png (one row per clip,
## variant 0, rows in the printed order).

const ROW_H := 56
const SHEET_W := 1400


func _initialize() -> void:
	if "--profile" in OS.get_cmdline_user_args():
		var costs := []
		for clip_name in Synth.CLIPS:
			var t0 := Time.get_ticks_usec()
			Synth.make(clip_name, 0)
			costs.append([(Time.get_ticks_usec() - t0) / 1000.0 * int(Synth.CLIPS[clip_name]), clip_name])
		costs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for c in costs:
			print("  %-22s %6.1f ms (all variants)" % [c[1], c[0]])
	var bank := Synth.bank()
	print("Synth: %d clips, %d variants generated in %.0f ms" % [bank.size(), _count(bank), Synth.gen_ms])
	var fails := 0
	var total_s := 0.0
	print("%-22s %3s %6s %7s %7s %8s %5s %s" % ["clip", "var", "dur s", "peak dB", "rms dB", "dc", "clip", "edge"])
	for clip_name in bank:
		var arr: Array = bank[clip_name]
		for v in arr.size():
			var w: AudioStreamWAV = arr[v]
			var s := _samples(w)
			var n := s.size()
			total_s += float(n) / w.mix_rate
			var peak := 0.0
			var sum2 := 0.0
			var sum := 0.0
			var clipped := 0
			var step_sum := 0.0
			for i in n:
				var x := s[i]
				peak = maxf(peak, absf(x))
				sum += x
				sum2 += x * x
				if absf(x) >= 0.9999:
					clipped += 1
				if i > 0:
					step_sum += absf(x - s[i - 1])
			var rms := sqrt(sum2 / n)
			var dc := sum / n
			var mean_step := step_sum / maxf(n - 1, 1)
			var edge := ""
			var ok := peak > 0.05 and peak < 0.995 and clipped == 0 and absf(dc) < 0.01
			if w.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				# Continuity: the wrap step must look like the steps right next to it.
				var jump := absf(s[n - 1] - s[0])
				var local := maxf(maxf(absf(s[n - 1] - s[n - 2]), absf(s[1] - s[0])), mean_step)
				var ratio := jump / maxf(local, 1e-6)
				edge = "seam jump %.4f (%.1fx neighbour steps)" % [jump, ratio]
				ok = ok and ratio < 3.0
			else:
				edge = "end %.5f" % absf(s[n - 1])
				ok = ok and absf(s[n - 1]) < 0.002
			if not ok:
				fails += 1
			print("%-22s %3d %6.2f %7.1f %7.1f %8.5f %5d %s%s" % [clip_name, v, float(n) / w.mix_rate, _db(peak), _db(rms),
					dc, clipped, edge, "" if ok else "   <-- FAIL"])
	print("total audio: %.1f s, NaN/Inf repaired: %d, failures: %d" % [total_s, Synth.bad_samples, fails])
	if "--png" in OS.get_cmdline_user_args():
		_contact_sheet(bank)
	quit(1 if fails > 0 or Synth.bad_samples > 0 else 0)


func _samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var d := w.data
	var n := d.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = d.decode_s16(i * 2) / 32768.0
	return out


func _contact_sheet(bank: Dictionary) -> void:
	var img := Image.create(SHEET_W, ROW_H * bank.size(), false, Image.FORMAT_RGB8)
	img.fill(Color(0.08, 0.09, 0.1))
	var row := 0
	for clip_name in bank:
		var w: AudioStreamWAV = bank[clip_name][0]
		var s := _samples(w)
		var y0 := row * ROW_H
		var mid := y0 + ROW_H / 2
		var col := Color(0.4, 0.85, 1.0) if w.loop_mode != AudioStreamWAV.LOOP_DISABLED else Color(1.0, 0.75, 0.35)
		# Time axis: 1 px = 4.5 ms so lengths are comparable between rows.
		var per_px := maxi(int(w.mix_rate * 0.0045), 1)
		for x in SHEET_W:
			var a := x * per_px
			if a >= s.size():
				break
			var lo := 0.0
			var hi := 0.0
			for i in range(a, mini(a + per_px, s.size())):
				lo = minf(lo, s[i])
				hi = maxf(hi, s[i])
			var ya := clampi(mid - int(hi * (ROW_H / 2 - 2)), y0, y0 + ROW_H - 1)
			var yb := clampi(mid - int(lo * (ROW_H / 2 - 2)), y0, y0 + ROW_H - 1)
			for y in range(ya, yb + 1):
				img.set_pixel(x, y, col)
		for x in SHEET_W:
			img.set_pixel(x, y0, Color(0.2, 0.2, 0.22))
		row += 1
	var path := ProjectSettings.globalize_path("res://shots/audio_waveforms.png")
	img.save_png(path)
	print("waveforms -> ", path)


func _count(bank: Dictionary) -> int:
	var c := 0
	for k in bank:
		c += (bank[k] as Array).size()
	return c


func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 1e-9)) / log(10.0)
