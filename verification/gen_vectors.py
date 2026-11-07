#!/usr/bin/env python3
"""Generate input feed and expected files for one scenario.
usage: gen_vectors.py <scenario> <seed> <outdir>      scenarios: ref, story, edge, gaps, defaults, random, nofire"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from t2t_model import *


def cfg(idx, val): return msg(3, idx, 0, val, 0)


def setup_msgs(buy=105, sell=95, maxq=8, lo=0, hi=M32, kill=0, rate_n=0, rate_k=0, syms=range(8)):
    m = []
    for s in syms:
        m.append(cfg(s, buy)); m.append(cfg(8 + s, sell))
    m += [cfg(0x10, maxq), cfg(0x11, lo), cfg(0x12, hi), cfg(0x13, kill), cfg(0x14, rate_n), cfg(0x15, rate_k)]
    return m


def frames_ref():
    """configure, then bid quote (to make the book two-sided), then a firing ask quote"""
    f = []
    sm = setup_msgs(syms=[3])
    f.append(build_frame(payload(sm[:8])))
    f.append(build_frame(payload(sm[8:])))
    f.append(build_frame(payload([msg(1, 3, 0, 98, 5)])))
    for i in range(6):   # several firing asks, each alone in a frame
        f.append(build_frame(payload([msg(1, 3, 1, 100 - i % 2, 10)])))
    return f


def frames_story():
    f = []
    P = lambda ms, **k: f.append(build_frame(payload(ms), **k))
    # config in two frames
    sm = setup_msgs(maxq=8)
    P(sm[:8]); P(sm[8:16]); P(sm[16:])
    # book building and firing
    P([msg(1, 3, 0, 98, 5), msg(1, 3, 1, 100, 10)])                 # fires buy 100 qty 8
    P([msg(1, 3, 1, 105, 10)])                                       # equal thr: no fire
    P([msg(1, 3, 1, 100, 0)])                                        # qty 0 no fire
    P([msg(1, 4, 1, 100, 10)])                                       # no bid on sym 4: no fire
    P([msg(1, 3, 0, 101, 5), msg(1, 3, 1, 100, 10)])                 # crossed (bid 101 > ask 100): ask quote opp_px<px false
    P([msg(1, 5, 1, 110, 5), msg(1, 5, 0, 96, 6)])                   # bid 96>95, ask 110>96 sell fires
    P([msg(1, 5, 0, 95, 6)])                                         # equal sell thr: no
    P([msg(2, 3, 0, 1, 1), msg(0x7E, 3, 0, 1, 1), msg(1, 9, 0, 100, 1), msg(1, 3, 2, 100, 1)])   # trade, unknown, badsym, badside
    # kill on / off
    P([cfg(0x13, 1), msg(1, 3, 0, 98, 5), msg(1, 3, 1, 100, 10)])   # rejected by kill
    P([cfg(0x13, 0), msg(1, 3, 0, 98, 5), msg(1, 3, 1, 100, 10)])   # passes again
    # band
    P([cfg(0x11, 99), cfg(0x12, 120), msg(1, 3, 0, 98, 5), msg(1, 3, 1, 100, 10), msg(1, 3, 1, 98, 10)])
    P([cfg(0x11, 0), cfg(0x12, M32), cfg(0x10, 0), msg(1, 3, 0, 98, 5), msg(1, 3, 1, 100, 10)])  # max_qty 0 -> qty0 reject
    P([cfg(0x10, 3)])
    # rate window K=4 N=2
    P([cfg(0x14, 2), cfg(0x15, 4)] + [msg(1, 3, 1, 100 - i % 3, 10) for i in range(6)])
    P([msg(1, 3, 1, 99, 10)] * 4)
    # invalid config indexes, kill upper bits
    P([cfg(0x16, 5), cfg(0xFF, 5), cfg(0x13, 2)])
    # bad frames of each kind
    good = payload([msg(1, 3, 1, 100, 10)])
    f.append(build_frame(good, ethertype=0x86DD))
    f.append(build_frame(good, vihl=0x46))
    f.append(build_frame(good, proto=6))
    f.append(build_frame(good, dport=0x5001))
    f.append(build_frame(good, ip_len_adj=3))
    f.append(build_frame(good, udp_len_override=8))
    f.append(build_frame(good)[:30])                                # runt
    f.append(build_frame(good)[:41])                                # header only
    f.append(build_frame(payload([msg(1, 3, 0, 98, 5), msg(1, 3, 1, 100, 10)]), pad=False)[:42 + 8 + 12 + 5])   # truncated
    # bad counts / lengths
    P([msg(1, 3, 1, 100, 10)] * 2, ) if False else None
    f.append(build_frame(payload([msg(1, 3, 1, 100, 10)], n=0)))
    f.append(build_frame(payload([msg(1, 3, 1, 100, 10)], n=9)))
    f.append(build_frame(payload([msg(1, 3, 1, 100, 10)], n=3)))   # lying count: 1 complete message then short
    f.append(build_frame(payload([msg(1, 3, 1, 100, 10)] * 3, n=1)))   # extra bytes
    # long payload frames, no padding
    P([msg(1, 3, 0, 98, 5)] + [msg(1, 3, 1, 100 - i % 2, 10) for i in range(7)])
    return f



def frames_edge():
    """directed boundary sweeps: rate limiter (N,K), price band edges, max_qty clip, both sides,
    plus corner cases (config barrier, 8-msg packets, back-to-back minimum frames, extreme values)."""
    f = []
    P = lambda ms, **k: f.append(build_frame(payload(ms), **k))
    base = setup_msgs(buy=105, sell=95, maxq=M32)
    for i in range(0, len(base), 8): P(base[i:i + 8])
    def book(): P([msg(1, 3, 0, 98, 5), msg(1, 3, 1, 110, 5)])      # bid 98, ask 110 resting on sym 3
    book()
    ask8 = [msg(1, 3, 1, 100, 10)] * 8                                  # 8 firing buys at px 100 (bid 98 < 100)
    bid8 = [msg(1, 3, 0, 100, 10)] * 8                                  # 8 firing sells at px 100 (ask 110 > 100)
    # 1. rate limiter sweep: every N in 0..4 and K in 0..6, buy side then sell side
    for n in range(0, 5):
        for k in range(0, 7):
            P([cfg(0x14, n), cfg(0x15, k)]); book(); P(ask8); P(bid8)
    P([cfg(0x14, 0), cfg(0x15, 0)])
    # 2. rate limiter edge: N bigger than K, huge K, K=1
    for n, k in [(10, 3), (3, 1), (1, 1), (1, 0xFFFFFFFF), (0xFFFFFFFF, 2), (2, 0xFFFFFFFF)]:
        P([cfg(0x14, n), cfg(0x15, k)]); book(); P(ask8)
    P([cfg(0x14, 0), cfg(0x15, 0)])
    # 3. price band edges, with and without the rate limiter, both sides (px is 100 everywhere)
    bands = [(100, 100), (100, 200), (0, 100), (101, 200), (0, 99), (100, 99), (99, 101), (0, 0), (M32, M32), (0, M32)]
    for lo, hi in bands:
        for n, k in [(0, 0), (2, 5), (1, 3)]:
            P([cfg(0x11, lo), cfg(0x12, hi), cfg(0x14, n), cfg(0x15, k)]); book(); P(ask8); P(bid8)
    P([cfg(0x11, 0), cfg(0x12, M32), cfg(0x14, 0), cfg(0x15, 0)])
    # 4. max_qty clip edges (quote qty 10)
    for mq in [0, 1, 9, 10, 11, M32]:
        P([cfg(0x10, mq)]); book(); P([msg(1, 3, 1, 100, 10), msg(1, 3, 0, 100, 10)])
    P([cfg(0x10, M32)])
    # 5. config barrier: a config message right behind a firing quote, same packet and next packet
    book()
    P([msg(1, 3, 1, 100, 10), cfg(3, 90), msg(1, 3, 1, 100, 10)])      # 2nd quote must NOT fire (thr now 90)
    P([cfg(3, 105), msg(1, 3, 1, 100, 10), cfg(0x13, 1), msg(1, 3, 1, 100, 10), cfg(0x13, 0), msg(1, 3, 1, 100, 10)])
    P([cfg(0x14, 1), cfg(0x15, 4), msg(1, 3, 1, 100, 10), msg(1, 3, 1, 100, 10), cfg(0x15, 4), msg(1, 3, 1, 100, 10), msg(1, 3, 1, 100, 10)])
    P([cfg(0x14, 0), cfg(0x15, 0)])
    # 6. strategy gates: equal prices, crossed book, zero qty, equal thresholds (both sides)
    P([msg(1, 3, 0, 100, 5), msg(1, 3, 1, 100, 10)])                   # opp_px == px: no fire
    P([msg(1, 3, 1, 100, 5), msg(1, 3, 0, 100, 10)])
    P([msg(1, 3, 0, 98, 0), msg(1, 3, 1, 100, 10)])                    # opposite qty 0: no fire
    P([msg(1, 3, 1, 110, 5), msg(1, 3, 0, 98, 5), msg(1, 3, 1, 104, 10), msg(1, 3, 1, 105, 10), msg(1, 3, 1, 106, 10)])
    P([msg(1, 3, 0, 94, 10), msg(1, 3, 0, 95, 10), msg(1, 3, 0, 96, 10)])
    # 7. extreme values
    P([cfg(3, M32), cfg(11, 0)])
    P([msg(1, 3, 0, 0, 1), msg(1, 3, 1, M32 - 1, M32), msg(1, 3, 1, 0, 1), msg(1, 3, 0, M32, M32)])
    P([cfg(3, 105), cfg(11, 95)])
    # 8. all 8 symbols interleaved in one 8-message packet, then twice
    for _ in range(3):
        P([msg(1, s, s & 1, 100 + s, 3 + s) for s in range(8)])
    # 9. back-to-back minimum-size frames, all firing (fed with GAP=0 this is zero idle cycles between frames)
    book()
    for i in range(40): P([msg(1, 3, 1, 100 - (i % 3), 1 + i % 5)])
    # 10. a packet of 8 trades/unknown/bad messages mixed with one firing quote
    P([msg(2, 3, 1, 100, 1), msg(0x44, 0, 0, 0, 0), msg(1, 3, 1, 100, 10), msg(3, 0x16, 0, 1, 0), msg(1, 9, 0, 0, 0), msg(2, 0, 0, 0, 0), msg(1, 3, 2, 1, 1), msg(1, 3, 1, 99, 4)])
    return f


def frames_gaps():
    """frames that hit parser/assembler corner cases the random run rarely reaches, plus RATE_N/K window clears"""
    f = []
    P = lambda ms, **k: f.append(build_frame(payload(ms), **k))
    base = setup_msgs(buy=105, sell=95, maxq=M32)
    for i in range(0, len(base), 8): P(base[i:i + 8])
    good = payload([msg(1, 3, 1, 100, 10)])
    # A. a header failure on the very LAST byte of the frame (frame ends exactly where the check fails)
    f.append(build_frame(good, ethertype=0x86DD, pad=False)[:14])
    f.append(build_frame(good, vihl=0x46, pad=False)[:15])
    f.append(build_frame(good, proto=6, pad=False)[:24])
    f.append(build_frame(good, dport=0x5001, pad=False)[:38])
    f.append(build_frame(good, ip_len_adj=3, pad=False)[:40])
    f.append(build_frame(b"", pad=False)[:40])                        # consistent lengths, udp_len = 8 (<9), ends at byte 39
    # B. consistent short UDP lengths (ip_len = udp_len + 20): 0..13
    for u in range(0, 14):
        f.append(build_frame(bytes(max(0, u - 8)), udp_len_override=u, ip_len_adj=u - 8 if u >= 8 else u - 8))
        f.append(build_frame(bytes(max(0, u - 8)), udp_len_override=u, ip_len_adj=u - 8, pad=False))
    # C. exact payload sizes around the 8-byte header, with valid and invalid message counts
    for cnt in [0, 1, 3, 8, 9, 256, 65535]:
        for extra in [0, 1, 2, 12, 13]:                              # payload = 4 (seq) + 2 (count) + 2 (rsv) ... built byte by byte below
            pass
    for size in [1, 4, 5, 6, 7, 8, 9, 19, 20, 21]:
        for cnt in [0, 1, 2, 8, 9, 256, 65535]:
            body = (b"\x00\x00\x00\x07" + cnt.to_bytes(2, "big") + b"\x00\x00" + msg(1, 3, 1, 100, 10))[:size]
            f.append(build_frame(body))
            f.append(build_frame(body, pad=False))
    # D. RATE_N and RATE_K writes clear the window: N=1, K=100
    book = lambda: P([msg(1, 3, 0, 98, 5), msg(1, 3, 1, 110, 5)])
    fire = msg(1, 3, 1, 100, 10)
    book(); P([cfg(0x14, 1), cfg(0x15, 100)]); book()
    P([fire, fire])                         # first passes, second rate-rejected
    P([cfg(0x14, 1), fire, fire])           # RATE_N write clears: first passes again, second rejected
    P([cfg(0x15, 100), fire, fire])         # RATE_K write clears
    P([cfg(0x14, 5), fire, fire, fire])     # RATE_N changes to 5 (clears)
    P([cfg(0x14, 0), cfg(0x15, 0)])
    # E. short UDP payload carrying one config or one quote message (6..20 bytes)
    P([msg(1, 3, 1, 100, 10)])
    return f


def frames_defaults():
    """only BUY thresholds are configured: kill, max_qty, band and rate limiter stay at their reset defaults"""
    f = []
    P = lambda ms, **k: f.append(build_frame(payload(ms), **k))
    P([cfg(s, 105) for s in range(8)])
    for s in range(8):
        P([msg(1, s, 0, 98, 5), msg(1, s, 1, 100, 1000 + s)])        # ask 100 < 105: fires a buy, qty unclamped
        P([msg(1, s, 0, 0xFFFFFFFF, 5), msg(1, s, 1, 0xFFFFFFFF, 7)])  # sell thr default (all ones): never fires
    for i in range(20): P([msg(1, i & 7, 1, 100 - i % 3, 1 + i)])
    return f


def frames_random(rng, nframes):
    f = []
    cur_thr = {}
    def rprice(lo=88, hi=118): return rng.randint(lo, hi)
    def rand_msg():
        r = rng.random()
        sym = rng.randint(0, 7) if rng.random() > 0.05 else rng.choice([8, 9, 200, 255])
        side = rng.randint(0, 1) if rng.random() > 0.03 else rng.choice([2, 7, 255])
        qty = rng.choice([0, 1, 3, 5, 8, 10, 50, 1000, M32]) if rng.random() < 0.9 else rng.randint(0, M32)
        px = (rprice(96,110) if side==1 else rprice(90,104)) if rng.random() < 0.95 else rng.choice([0, 1, M32, M32 - 1, rng.randint(0, M32)])
        if r < 0.62: return msg(1, sym, side, px, qty, rng.choice([0, 0, 0, 0x55]))
        if r < 0.70: return msg(2, sym, side, px, qty)
        if r < 0.90:
            idx = rng.randint(0, 0x15) if rng.random() < 0.9 else rng.choice([0x16, 0x17, 0x40, 0x80, 0xFF])
            if idx <= 7: v = rng.randint(100, 112)
            elif idx <= 15: v = rng.randint(88, 98)
            elif idx == 0x10: v = rng.choice([0, 1, 3, 8, 50, M32])
            elif idx == 0x11: v = rng.choice([0, 0, 0, 90, 96, M32])
            elif idx == 0x12: v = rng.choice([M32, M32, M32, 110, 104, 0])
            elif idx == 0x13: v = rng.choice([0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, M32])
            elif idx == 0x14: v = rng.choice([1, 2, 3, 5, 100])
            elif idx == 0x15: v = rng.choice([0, 0, 0, 1, 3, 4, 7])
            else: v = rng.randint(0, M32)
            return cfg(idx, v)
        return msg(rng.choice([0, 4, 0x10, 0x7F, 0xFF]), sym, side, px, qty)
    # initial setup so trading happens
    sm = setup_msgs(buy=rng.randint(100, 110), sell=rng.randint(90, 100), maxq=rng.choice([5, 8, M32]))
    for i in range(0, len(sm), 8):
        f.append(build_frame(payload(sm[i:i + 8])))
    for _ in range(nframes):
        n = rng.choice([1, 1, 2, 3, 4, 5, 6, 7, 8])
        ms = [rand_msg() for _ in range(n)]
        pl = payload(ms)
        c = rng.random()
        kw = {}
        trunc = None
        if c < 0.55: pass
        elif c < 0.60: kw["ethertype"] = rng.choice([0x86DD, 0x0806, 0x0801])
        elif c < 0.64: kw["vihl"] = rng.choice([0x46, 0x44, 0x65])
        elif c < 0.68: kw["proto"] = rng.choice([6, 1, 16])
        elif c < 0.72: kw["dport"] = rng.choice([0x5001, 0x0050, 0x0050 ^ 0x5000])
        elif c < 0.76: kw["ip_len_adj"] = rng.choice([-1, 1, 5, -20])
        elif c < 0.78: kw["udp_len_override"] = rng.choice([8, 0, 7, 9, 3])
        elif c < 0.84: trunc = rng.randint(1, 41)
        elif c < 0.89: trunc = 42 + rng.randint(0, max(0, len(pl) - 1))
        elif c < 0.92: pl = payload(ms, n=rng.choice([0, 9, 255, 65535, max(1, n + rng.randint(1, 3))]))
        elif c < 0.95: pl = payload(ms, n=max(1, n - 1))
        elif c < 0.97: pl = pl + bytes(rng.randint(1, 30))
        else: pl = pl + bytes(rng.randrange(256) for _ in range(rng.randint(1, 20)))
        fb = build_frame(pl, pad=(rng.random() < 0.7), **kw)
        if trunc is not None: fb = fb[:trunc]
        f.append(fb)
    return f


def frames_nofire(rng, nframes):
    """only quotes and trades, defaults (no config): the design must never fire and never stall the input"""
    f = []
    for _ in range(nframes):
        ms = [msg(rng.choice([1, 1, 2]), rng.randint(0, 7), rng.randint(0, 1), rng.randint(90, 110), rng.randint(0, 20)) for _ in range(rng.randint(1, 8))]
        f.append(build_frame(payload(ms)))
    return f


def write_vectors(frames, out):
    os.makedirs(out, exist_ok=True)
    m = Model()
    for fb in frames:
        m.frame(fb)
    def w(name, lines):
        open(os.path.join(out, name), "w").write("\n".join(lines) + "\n")
    feed = []
    for fb in frames:
        for i, b in enumerate(fb):
            feed.append("%03x" % ((1 << 8 if i == len(fb) - 1 else 0) | b))
    w("feed.hex", feed)
    w("exp_payload.hex", ["%03x" % ((l << 8) | b) for b, l in m.s_payload])
    w("exp_msgs.hex", ["%022x" % ((t << 80) | (s << 72) | (sd << 64) | (px << 32) | q) for t, s, sd, px, q in m.s_msgs])
    w("exp_cfgw.hex", ["%010x" % ((i << 32) | v) for i, v in m.s_cfgw])
    w("exp_quote.hex", ["%017x" % ((s << 65) | (sd << 64) | (px << 32) | q) for s, sd, px, q in m.s_quote])
    w("exp_book.hex", ["%033x" % ((s << 129) | (sd << 128) | (px << 96) | (q << 64) | (opx << 32) | oq) for s, sd, px, q, opx, oq in m.s_book])
    w("exp_dec.hex", ["%018x" % ((fire << 68) | (sd << 67) | (s << 64) | (px << 32) | q) for fire, sd, s, px, q in m.s_dec])
    w("exp_ord.hex", ["%017x" % ((s << 65) | (sd << 64) | (px << 32) | q) for s, sd, px, q in m.s_ord])
    w("exp_obytes.hex", ["%03x" % ((l << 8) | b) for b, l in m.s_obytes])
    w("exp_trigger.hex", ["%x" % t for t in m.trigger])
    w("exp_qidx.hex", ["%x" % t for t in m.qidx])
    w("exp_counters.hex", ["%08x" % m.cnt[n] for n in CNT_NAMES])
    sizes = dict(feed=len(feed), payload=len(m.s_payload), msgs=len(m.s_msgs), cfgw=len(m.s_cfgw), quote=len(m.s_quote),
                 book=len(m.s_book), dec=len(m.s_dec), ord=len(m.s_ord), obytes=len(m.s_obytes), trigger=len(m.trigger))
    fin = []
    for s in range(8):
        fin += [m.bid[s][0], m.bid[s][1], m.ask[s][0], m.ask[s][1]]
    fin += m.buy + m.sell + [m.max_qty, m.px_lo, m.px_hi, m.kill, m.rate_n, m.rate_k]
    w("exp_final.hex", ["%08x" % v for v in fin])
    sizes["final"] = len(fin)
    open(os.path.join(out, "sizes.txt"), "w").write(" ".join("%s=%d" % kv for kv in sizes.items()) + "\n")
    open(os.path.join(out, "counters.txt"), "w").write("\n".join("%s %d" % (n, m.cnt[n]) for n in CNT_NAMES) + "\n")
    return m, sizes


if __name__ == "__main__":
    scen, seed, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    rng = random.Random(seed)
    frames = {"ref": frames_ref, "story": frames_story, "edge": frames_edge, "gaps": frames_gaps, "defaults": frames_defaults}.get(scen, None)
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 3000
    frames = frames() if frames else (frames_nofire(rng, n) if scen == "nofire" else frames_random(rng, n))
    m, sizes = write_vectors(frames, out)
    print(scen, "seed", seed, "frames", len(frames), sizes)
    print({k: v for k, v in m.cnt.items() if v})
