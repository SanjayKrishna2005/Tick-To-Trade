#!/bin/bash
# Full regression: vectors, system runs, FIFO-full run, unit tests, ROM test.
# usage: bash run_all.sh [rtl_dir]      (default: ../rtl). Exit code 0 only if everything passes.
cd "$(dirname "$0")" || exit 1
RTL=${1:-../rtl}
fail=0; n=0
echo "== generating vectors"
python3 gen_vectors.py ref      1 vec_ref      >/dev/null || exit 1
python3 gen_vectors.py story    1 vec_story    >/dev/null || exit 1
python3 gen_vectors.py edge     1 vec_edge     >/dev/null || exit 1
python3 gen_vectors.py gaps     1 vec_gaps     >/dev/null || exit 1
python3 gen_vectors.py defaults 1 vec_defaults >/dev/null || exit 1
python3 gen_vectors.py random  11 vec_r11 3000 >/dev/null || exit 1
python3 gen_vectors.py nofire   7 vec_nofire 3000 >/dev/null || exit 1
run() {   # name vec gap stall seed [burst] ; env DEFS/EXTRA pass through
  local out; n=$((n+1))
  out=$(bash run_sys.sh "$RTL" "$2" "$3" "$4" "$5" $6 2>&1)
  if echo "$out" | grep -q "RESULT: PASS"; then printf "  PASS  %-34s\n" "$1"
  else printf "  FAIL  %-34s\n" "$1"; echo "$out" | grep -E "mismatches [1-9]|COUNTER|FINAL|INPUT STALL|ERROR|error" | head -5; fail=$((fail+1)); fi
}
echo "== system simulation"
run "ref 0/0"                    vec_ref     0  0 1
run "story 40/60"                vec_story  40 60 2
run "edge 0/0"                   vec_edge    0  0 1
run "edge 30/60"                 vec_edge   30 60 2
DEFS="-DFAW=1" run "edge FIFO depth 2, 90% stalls" vec_edge 0 90 3 1
run "gaps 0/0"                   vec_gaps    0  0 1
run "gaps 30/60"                 vec_gaps   30 60 2
run "defaults 0/0"               vec_defaults 0 0 1
run "defaults 30/60"             vec_defaults 30 60 2
run "random 3000 frames 30/60"   vec_r11    30 60 3
EXTRA="+MIDRESET=20000" run "random with mid-run reset" vec_r11 30 60 3
run "nofire 0/0"                 vec_nofire  0  0 1
echo "== standalone blocks"
u=$(bash run_unit.sh "$RTL" 2>&1); nu=$(echo "$u" | grep -c "PASS"); fu=$(echo "$u" | grep -cE "FAIL|ERROR")
r=$(bash run_rom.sh "$RTL" 2>&1);  nr=$(echo "$r" | grep -c "PASS"); fr=$(echo "$r" | grep -cE "FAIL|ERROR")
echo "  axis_slice + axis_register: $nu PASS lines, $fu failures (expect 48 / 0)"
echo "  replay_rom:                 $nr PASS lines, $fr failures (expect 5 / 0)"
[ "$nu" -eq 48 ] && [ "$fu" -eq 0 ] || fail=$((fail+1))
[ "$nr" -eq 5 ]  && [ "$fr" -eq 0 ] || fail=$((fail+1))
echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED ($n system runs + unit + rom)"; else echo "$fail CHECK(S) FAILED"; fi
exit $((fail>0))
