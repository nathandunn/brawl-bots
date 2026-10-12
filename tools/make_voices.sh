#!/usr/bin/env bash
## Regenerates sfx/voice/*.wav - the only sounds not synthesised at runtime by sfx.gd.
## Needs espeak-ng (built from https://github.com/espeak-ng/espeak-ng if your distro has none)
## and python3. ESPEAK=/path/to/espeak-ng ESPEAK_DATA=/path/to/data-dir bash tools/make_voices.sh
set -euo pipefail
cd "$(dirname "$0")/../sfx/voice"
E="${ESPEAK:-espeak-ng}"
D=(); [ -n "${ESPEAK_DATA:-}" ] && D=(--path="$ESPEAK_DATA")
gen(){ "$E" "${D[@]}" -v "$2" -p "$3" -s "$4" -a 160 -w "$1.wav" "$5"; }
V=(en-us+m3 en+m7 en-us+m1)
P=(28 38 46)
for i in 0 1 2; do
  gen got_$i ${V[$i]} ${P[$i]} 165 "He got me!"
  gen hit_$i ${V[$i]} ${P[$i]} 175 "Agh! I'm hit!"
  gen leg_$i ${V[$i]} ${P[$i]} 165 "Argh! My leg!"
  gen arm_$i ${V[$i]} ${P[$i]} 170 "Aah! My arm!"
  gen die_$i ${V[$i]} $((${P[$i]}-12)) 110 "He... got me."
  gen out_$i ${V[$i]} ${P[$i]} 170 "I'm out!"
done
gen draw en-us+m2 30 120 "Draw!"
K=("Hai!" "Kiai!" "Yaah!")
H=("Ugh!" "Argh!" "Hngh!")
for i in 0 1 2; do
  gen kiai_$i ${V[$i]} $((${P[$i]}+8)) 190 "${K[$i]}"
  gen nhit_$i ${V[$i]} ${P[$i]} 170 "${H[$i]}"
  gen ndie_$i ${V[$i]} $((${P[$i]}-10)) 100 "Aaaahh..."
done
# trim the silence, add a little grit, take the fizz off
python3 - <<'PY'
import wave, glob, array, math
for f in sorted(glob.glob('*.wav')):
    w=wave.open(f); n=w.getnframes(); sr=w.getframerate(); a=array.array('h', w.readframes(n)); w.close()
    s=next(i for i,v in enumerate(a) if abs(v)>600); e=len(a)-next(i for i,v in enumerate(reversed(a)) if abs(v)>600)
    b=a[max(0,s-200):min(len(a),e+800)]
    out=array.array('h'); y=0.0
    for i,v in enumerate(b):
        x=math.tanh(v/32768.0*1.8)/math.tanh(1.8); y+=0.55*(x-y)
        out.append(int(max(-1,min(1,y*0.9*min(1.0,(len(b)-i)/400.0)))*32000))
    w=wave.open(f,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(out.tobytes()); w.close()
PY
