#!/usr/bin/env python3
"""Independent golden model of the tick-to-trade engine, written ONLY from
docs/spec_system.md and the module cards (not from the user's RTL).
It produces the expected stream at every module boundary."""

CNT_NAMES = [
    "par_good", "par_drop_ethertype", "par_drop_ipver", "par_drop_proto", "par_drop_port", "par_drop_len",
    "asm_pkt_good", "asm_pkt_bad_count", "asm_pkt_bad_len",
    "rt_quote", "rt_trade", "rt_config", "rt_unknown", "rt_badfield",
    "cfg_write", "cfg_bad",
    "risk_nofire", "risk_pass", "risk_rej_kill", "risk_rej_qty0", "risk_rej_band", "risk_rej_rate",
    "enc_orders_sent",
]
M32 = 0xFFFFFFFF


class Model:
    def __init__(self, dport=0x5000):
        self.dport = dport
        self.cnt = {n: 0 for n in CNT_NAMES}
        # config
        self.buy = [0] * 8
        self.sell = [M32] * 8
        self.max_qty = M32
        self.px_lo = 0
        self.px_hi = M32
        self.kill = 0
        self.rate_n = 0
        self.rate_k = 0
        # book
        self.bid = [[0, 0] for _ in range(8)]
        self.ask = [[0, 0] for _ in range(8)]
        self.w = 0
        self.o = 0
        self.next_id = 1
        # boundary streams
        self.s_payload = []   # (byte,last) parser -> fifo -> assembler
        self.s_msgs = []      # assembler -> router
        self.s_cfgw = []      # (idx,val) router -> cfg_regs
        self.s_quote = []     # router -> book
        self.s_book = []      # book -> strategy
        self.s_dec = []       # strategy -> risk
        self.s_ord = []       # risk -> encoder
        self.s_obytes = []    # (byte,last)
        self.qidx = []        # per order: index of the quote that caused it
        self.trigger = []     # per order: global input byte index of the trigger message's last byte
        self.in_bytes = 0     # global input bytes consumed so far

    # ---------------- parser ----------------
    def parse(self, fb):
        n = len(fb)
        if n < 14: return "drop_len", []
        if fb[12:14] != b"\x08\x00": return "drop_ethertype", []
        if n < 15: return "drop_len", []
        if fb[14] != 0x45: return "drop_ipver", []
        if n < 24: return "drop_len", []
        if fb[23] != 17: return "drop_proto", []
        if n < 38: return "drop_len", []
        if int.from_bytes(fb[36:38], "big") != self.dport: return "drop_port", []
        if n < 40: return "drop_len", []
        ip_len = int.from_bytes(fb[16:18], "big")
        udp_len = int.from_bytes(fb[38:40], "big")
        if ip_len != udp_len + 20 or udp_len < 9: return "drop_len", []
        P = udp_len - 8
        got = min(P, max(0, n - 42))
        out = []
        for k in range(got):
            last = 1 if (k == P - 1 or (k == got - 1 and got < P)) else 0
            out.append((fb[42 + k], last))
        return ("good" if got == P else "drop_len"), out

    # ---------------- assembler ----------------
    def assemble(self, pl):
        P = len(pl)
        if P < 6: return "bad_len", []
        n = (pl[4] << 8) | pl[5]
        if not (1 <= n <= 8): return "bad_count", []
        msgs = []
        for m in range(n):
            b = 8 + 12 * m
            if P >= b + 12:
                x = pl[b:b + 12]
                msgs.append((x[0], x[1], x[2], int.from_bytes(x[4:8], "big"), int.from_bytes(x[8:12], "big"), b + 11))
        return ("good" if P == 8 + 12 * n else "bad_len"), msgs

    # ---------------- config ----------------
    def cfg_write(self, idx, val):
        if idx <= 7: self.buy[idx] = val
        elif 8 <= idx <= 15: self.sell[idx - 8] = val
        elif idx == 0x10: self.max_qty = val
        elif idx == 0x11: self.px_lo = val
        elif idx == 0x12: self.px_hi = val
        elif idx == 0x13: self.kill = val & 1
        elif idx == 0x14: self.rate_n = val; self.w = self.o = 0
        elif idx == 0x15: self.rate_k = val; self.w = self.o = 0
        else:
            self.cnt["cfg_bad"] += 1
            return
        self.cnt["cfg_write"] += 1

    # ---------------- strategy ----------------
    def strategy(self, sym, side, px, qty, opp_px, opp_qty):
        if side == 1:   # ask quote -> buy
            fire = qty > 0 and px < self.buy[sym] and opp_qty > 0 and opp_px < px
            oside = 0
        else:           # bid quote -> sell
            fire = qty > 0 and px > self.sell[sym] and opp_qty > 0 and opp_px > px
            oside = 1
        oq = min(qty, self.max_qty)
        return fire, oside, oq

    # ---------------- risk ----------------
    def risk(self, fire, sym, oside, px, qty):
        passed = False
        if not fire:
            self.cnt["risk_nofire"] += 1
        elif self.kill:
            self.cnt["risk_rej_kill"] += 1
        elif qty == 0:
            self.cnt["risk_rej_qty0"] += 1
        elif px < self.px_lo or px > self.px_hi:
            self.cnt["risk_rej_band"] += 1
        elif self.rate_k != 0 and self.o >= self.rate_n:
            self.cnt["risk_rej_rate"] += 1
        else:
            self.cnt["risk_pass"] += 1
            passed = True
        # window update
        if self.rate_k == 0:
            self.w = self.o = 0
        elif self.w + 1 >= self.rate_k:
            self.w = self.o = 0
        else:
            self.w += 1
            if passed: self.o += 1
        return passed

    # ---------------- encoder ----------------
    def encode(self, sym, oside, px, qty):
        oid = self.next_id
        self.next_id += 1
        b = bytes([0x10, sym, oside, 0]) + px.to_bytes(4, "big") + qty.to_bytes(4, "big") + oid.to_bytes(4, "big")
        for i, x in enumerate(b):
            self.s_obytes.append((x, 1 if i == 15 else 0))
        self.cnt["enc_orders_sent"] += 1

    # ---------------- one frame ----------------
    def frame(self, fb):
        base = self.in_bytes
        self.in_bytes += len(fb)
        ev, pl = self.parse(fb)
        self.cnt["par_" + ev] += 1
        if not pl:
            return
        self.s_payload.extend(pl)
        plb = bytes(x for x, _ in pl)
        aev, msgs = self.assemble(plb)
        self.cnt["asm_pkt_" + aev] += 1
        for (t, sym, side, px, qty, lastidx) in msgs:
            self.s_msgs.append((t, sym, side, px, qty))
            trig = base + 42 + lastidx
            if t in (1, 2):
                if sym > 7 or side > 1:
                    self.cnt["rt_badfield"] += 1
                    continue
                if t == 2:
                    self.cnt["rt_trade"] += 1
                    continue
                self.cnt["rt_quote"] += 1
                self.s_quote.append((sym, side, px, qty))
                book = self.ask if side == 1 else self.bid
                opp = self.bid[sym] if side == 1 else self.ask[sym]
                opp_px, opp_qty = opp
                book[sym] = [px, qty]
                self.s_book.append((sym, side, px, qty, opp_px, opp_qty))
                fire, oside, oq = self.strategy(sym, side, px, qty, opp_px, opp_qty)
                if fire:
                    self.s_dec.append((1, oside, sym, px, oq))
                else:
                    self.s_dec.append((0, 0, 0, 0, 0))
                if self.risk(fire, sym, oside, px, oq):
                    self.s_ord.append((sym, oside, px, oq))
                    self.encode(sym, oside, px, oq)
                    self.trigger.append(trig)
                    self.qidx.append(len(self.s_quote) - 1)
            elif t == 3:
                self.cnt["rt_config"] += 1
                self.s_cfgw.append((sym, px))
                self.cfg_write(sym, px)
            else:
                self.cnt["rt_unknown"] += 1


# ---------------- frame builder (used by the generator and tests) ----------------
def build_frame(payload, dport=0x5000, pad=True, ethertype=0x0800, vihl=0x45, proto=17,
                ip_len_adj=0, udp_len_override=None):
    udp_len = 8 + len(payload) if udp_len_override is None else udp_len_override
    ip_len = (20 + 8 + len(payload) + ip_len_adj) & 0xFFFF
    eth = bytes.fromhex("020000000001020000000002") + ethertype.to_bytes(2, "big")
    ip = bytes([vihl, 0]) + ip_len.to_bytes(2, "big") + bytes(4) + bytes([64, proto]) + bytes(2) + bytes([10, 0, 0, 1, 10, 0, 0, 2])
    udp = (1234).to_bytes(2, "big") + dport.to_bytes(2, "big") + (udp_len & 0xFFFF).to_bytes(2, "big") + bytes(2)
    f = eth + ip + udp + payload
    if pad and len(f) < 60:
        f += bytes(60 - len(f))
    return f


def msg(t, sym, side, px, qty, rsv=0):
    return bytes([t, sym, side, rsv]) + px.to_bytes(4, "big") + qty.to_bytes(4, "big")


def payload(msgs, n=None, seq=1):
    n = len(msgs) if n is None else n
    return seq.to_bytes(4, "big") + n.to_bytes(2, "big") + bytes(2) + b"".join(msgs)
