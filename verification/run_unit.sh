#!/bin/bash
# usage: bash run_unit.sh <rtl_dir>      runs axis_slice and axis_register under many stall mixes
RTL=$(cd "$1" && pwd); T=$(cd "$(dirname "$0")" && pwd); W=$T/build_unit; mkdir -p "$W"
for D in axis_slice:axi_slice.v axis_register:axis_register.v; do
  M=${D%%:*}; F=${D##*:}
  iverilog -g2005 -DDUT=$M -DDUTSTR="\"$M\"" -s tb_unit -o "$W/$M.vvp" "$RTL/$F" "$T/tb_unit.v" 2>&1 | grep -v "timescale\|sensitive"
  for mix in "100 100" "100 50" "50 100" "50 50" "90 20" "20 90" "100 5" "70 70"; do
    set -- $mix
    for s in 1 2 3; do vvp "$W/$M.vvp" +PV=$1 +PR=$2 +SEED=$s +N=3000 | grep -E "ERROR|exp |RESULT|^$M" | tr '\n' ' '; echo; done
  done
done | sed 's/RESULT: //'
