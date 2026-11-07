#!/usr/bin/env python3
"""Compare every module's ports (name, direction, width) with the interface specification.
Usage: port_check.py <yosys_json>   (json from: yosys -p 'read_verilog ...; write_json x.json')
Widths are for default parameter values: DATA_W=8, ADDR_W=4, N_EV=23, CNT_W=32."""
import json, sys

I, O = "input", "output"

def P(spec):
    """'name:dir:width' list -> dict"""
    d = {}
    for item in spec.split():
        n, dr, w = item.split(":")
        d[n] = (I if dr == "i" else O, int(w))
    return d

BYTE_IN  = "s_valid:i:1 s_ready:o:1 s_data:i:8 s_last:i:1"
BYTE_OUT = "m_valid:o:1 m_ready:i:1 m_data:o:8 m_last:o:1"
CK = "clk:i:1 rst:i:1"

EXPECT = {
 "axis_slice":    P(CK + " s_valid:i:1 s_ready:o:1 s_data:i:8 s_last:i:1 " + BYTE_OUT),
 "axis_register": P(CK + " s_valid:i:1 s_ready:o:1 s_data:i:8 s_last:i:1 " + BYTE_OUT),
 "sync_fifo":     P(CK + " " + BYTE_IN + " " + BYTE_OUT + " level:o:5"),
 "eth_ip_udp_parser": P(CK + " cfg_dport:i:16 " + BYTE_IN + " " + BYTE_OUT +
    " ev_good:o:1 ev_drop_ethertype:o:1 ev_drop_ipver:o:1 ev_drop_proto:o:1 ev_drop_port:o:1 ev_drop_len:o:1"),
 "msg_assembler": P(CK + " " + BYTE_IN + " msg_valid:o:1 msg_ready:i:1 msg_type:o:8 msg_sym:o:8 msg_side:o:8"
    " msg_px:o:32 msg_qty:o:32 ev_pkt_good:o:1 ev_pkt_bad_count:o:1 ev_pkt_bad_len:o:1"),
 "msg_router": P(CK + " msg_valid:i:1 msg_ready:o:1 msg_type:i:8 msg_sym:i:8 msg_side:i:8 msg_px:i:32 msg_qty:i:32"
    " q_valid:o:1 q_ready:i:1 q_sym:o:3 q_side:o:1 q_px:o:32 q_qty:o:32 q_ts:o:32"
    " cfg_we:o:1 cfg_idx:o:8 cfg_val:o:32 busy_q:i:1 now:i:32"
    " ev_quote:o:1 ev_trade:o:1 ev_config:o:1 ev_unknown:o:1 ev_badfield:o:1"),
 "cfg_regs": P(CK + " cfg_we:i:1 cfg_idx:i:8 cfg_val:i:32 cfg_buy_thr_flat:o:256 cfg_sell_thr_flat:o:256"
    " cfg_max_qty:o:32 cfg_px_lo:o:32 cfg_px_hi:o:32 cfg_kill:o:1 cfg_rate_n:o:32 cfg_rate_k:o:32"
    " rate_clr:o:1 ev_cfg_write:o:1 ev_cfg_bad:o:1 rd_idx:i:8 rd_val:o:32"),
 "book_tracker": P(CK + " q_valid:i:1 q_ready:o:1 q_sym:i:3 q_side:i:1 q_px:i:32 q_qty:i:32 q_ts:i:32"
    " b_valid:o:1 b_ready:i:1 b_sym:o:3 b_side:o:1 b_px:o:32 b_qty:o:32 b_opp_px:o:32 b_opp_qty:o:32 b_ts:o:32"
    " busy:o:1 rd_sym:i:3 rd_bid_px:o:32 rd_bid_qty:o:32 rd_ask_px:o:32 rd_ask_qty:o:32"),
 "strategy": P(CK + " b_valid:i:1 b_ready:o:1 b_sym:i:3 b_side:i:1 b_px:i:32 b_qty:i:32 b_opp_px:i:32 b_opp_qty:i:32 b_ts:i:32"
    " d_valid:o:1 d_ready:i:1 d_fire:o:1 d_sym:o:3 d_side:o:1 d_px:o:32 d_qty:o:32 d_ts:o:32"
    " cfg_buy_thr_flat:i:256 cfg_sell_thr_flat:i:256 cfg_max_qty:i:32 busy:o:1"),
 "risk_check": P(CK + " d_valid:i:1 d_ready:o:1 d_fire:i:1 d_sym:i:3 d_side:i:1 d_px:i:32 d_qty:i:32 d_ts:i:32"
    " o_valid:o:1 o_ready:i:1 o_sym:o:3 o_side:o:1 o_px:o:32 o_qty:o:32 o_ts:o:32"
    " cfg_kill:i:1 cfg_px_lo:i:32 cfg_px_hi:i:32 cfg_rate_n:i:32 cfg_rate_k:i:32 rate_clr:i:1"
    " ev_nofire:o:1 ev_pass:o:1 ev_rej_kill:o:1 ev_rej_qty0:o:1 ev_rej_band:o:1 ev_rej_rate:o:1"),
 "order_encoder": P(CK + " o_valid:i:1 o_ready:o:1 o_sym:i:3 o_side:i:1 o_px:i:32 o_qty:i:32 o_ts:i:32 " + BYTE_OUT +
    " first_byte_xfer:o:1 first_byte_ts:o:32 ev_order_done:o:1"),
 "stats_counters": P(CK + " ev_flat:i:23 cnt_flat:o:736"),
 "latency_counter": P(CK + " now:o:32 meas_valid:i:1 meas_ts:i:32 lat_last:o:32 lat_min:o:32 lat_max:o:32 lat_sum:o:64 lat_count:o:32"),
 "replay_rom": P(CK + " start:i:1 loop:i:1 " + BYTE_OUT + " done:o:1"),
 "t2t_top": P(CK + " cfg_dport:i:16 " + BYTE_IN + " " + BYTE_OUT + " cnt_flat:o:736"
    " lat_last:o:32 lat_min:o:32 lat_max:o:32 lat_count:o:32 lat_sum:o:64"
    " dbg_book_sym:i:3 dbg_bid_px:o:32 dbg_bid_qty:o:32 dbg_ask_px:o:32 dbg_ask_qty:o:32 dbg_cfg_idx:i:8 dbg_cfg_val:o:32"),
}

def main(path):
    mods = json.load(open(path))["modules"]
    bad = 0
    for m, exp in EXPECT.items():
        if m not in mods:
            print(f"{m:20s} MISSING MODULE"); bad += 1; continue
        got = {n: (p["direction"], len(p["bits"])) for n, p in mods[m]["ports"].items()}
        problems = []
        for n, (d, w) in exp.items():
            if n not in got: problems.append(f"missing port {n}")
            else:
                gd, gw = got[n]
                if gd != d: problems.append(f"{n}: direction {gd}, specification says {d}")
                if gw != w: problems.append(f"{n}: width {gw}, specification says {w}")
        for n in got:
            if n not in exp: problems.append(f"extra port {n}")
        status = "ok" if not problems else "MISMATCH"
        print(f"{m:20s} {status:9s} ({len(got)} ports)")
        for p in problems: print("      -", p)
        bad += bool(problems)
    print(f"\n{len(EXPECT)-bad}/{len(EXPECT)} modules match the interface specification")
    return bad

if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1]) else 0)
