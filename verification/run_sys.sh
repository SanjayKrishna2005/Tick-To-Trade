#!/bin/bash
# usage: run_sys.sh <rtl_dir> <vec_dir> <GAP> <STALL> <SEED> [BURST]
RTL=$1; VEC=$2; GAP=${3:-0}; STALL=${4:-0}; SEED=${5:-1}; BURST=${6:-0}
RTL=$(cd "$RTL" && pwd); VEC=$(cd "$VEC" && pwd)
T=$(dirname "$0")
W=${BUILD:-$(dirname "$VEC")/build_$(basename "$RTL")_$(basename "$VEC")_${GAP}_${STALL}}
mkdir -p "$W"
ALL="$RTL/axis_register.v $RTL/axi_slice.v $RTL/sync_fifo.v $RTL/eth_ip_udp_parser.v $RTL/msg_assembler.v $RTL/msg_router.v $RTL/cfg_regs.v $RTL/book_tracker.v $RTL/strategy.v $RTL/risk_check.v $RTL/order_encoder.v $RTL/stats_counters.v $RTL/latency_counter.v $RTL/t2t_top.v"
iverilog -g2005 $DEFS -s tb_sys -o "$W/sim.vvp" $ALL "$T/tb_sys.v" 2>&1 | grep -v "timescale\|sensitive\|confusing\|Affected\|declared here\|WARNING"
eval $(python3 -I -c "
import sys
d=dict(kv.split('=') for kv in open('$VEC/sizes.txt').read().split())
print(' '.join('+N%s=%s'%(k.upper().replace('FEED','FEED').replace('PAYLOAD','PAY').replace('MSGS','MSG').replace('CFGW','CFG').replace('QUOTE','Q').replace('BOOK','BK').replace('OBYTES','OB').replace('TRIGGER','TRIG'),v) for k,v in d.items()))" | sed 's/^/ARGS="/; s/$/"/')
(cd "$W" && timeout ${TMO:-900} vvp sim.vvp +VEC="$VEC" $ARGS +GAP=$GAP +STALL=$STALL +SEED=$SEED +BURST=$BURST $EXTRA 2>&1 | grep -v "WARNING\|finish called")
