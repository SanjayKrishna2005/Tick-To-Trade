#!/bin/bash
# usage: bash run_rom.sh <rtl_dir>     tests replay_rom with ROM sizes 1, 2, 16, 37, 100
RTL=$(cd "$1" && pwd); T=$(cd "$(dirname "$0")" && pwd); W=$T/build_rom; mkdir -p "$W"
for n in 1 2 16 37 100; do
  python3 -I -c "
import random; random.seed($n)
print('\n'.join('%03x'%((1<<8 if i==$n-1 else 0)|random.randrange(256)) for i in range($n)))" > "$W/rom$n.hex"
  iverilog -g2005 -DROMN=$n -DROMFILE="\"$W/rom$n.hex\"" -s tb_rom -o "$W/rom$n.vvp" "$RTL/replay_rom.v" "$T/tb_rom.v" 2>&1 | grep -v "timescale\|sensitive"
  timeout 120 vvp "$W/rom$n.vvp" | grep -E "ERROR|idx|replay_rom|RESULT" | tr '\n' ' '; echo
done
