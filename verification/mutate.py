#!/usr/bin/env python3
"""Mutation test: break your RTL one operator at a time and check the testbench notices.
usage: python3 mutate.py <rtl_dir> <vec_dir> [<vec_dir> ...]   (run gen_vectors.py first; list vec dirs fast-first)
A mutant that survives every vec dir is either harmless (equivalent) or a hole in the tests: read that line."""
import os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
JOBS = int(os.environ.get("JOBS", "4"))
HERE = os.path.dirname(os.path.abspath(__file__))
OPS = [(r" < ", " <= "), (r" <= ", " < "), (r" > ", " >= "), (r" >= ", " > "), (r"==", "!="), (r"!=", "=="),
       (r"&&", "||"), (r"\|\|", "&&"), (r" \+ 1\b(?!')", " + 2"), (r" - 1\b(?!')", " - 2"), (r"1'b0", "1'b1"), (r"1'b1", "1'b0")]
FILES = ["sync_fifo", "eth_ip_udp_parser", "msg_assembler", "msg_router", "cfg_regs", "book_tracker",
         "strategy", "risk_check", "order_encoder", "stats_counters", "latency_counter", "t2t_top"]
def run(rtl, vec, tmo=60):
    gap, stall, faw = "30", "40", ""
    if ":" in vec:                                       # dir:GAP:STALL[:FIFO_ADDR_W]
        p = vec.split(":"); vec, gap, stall = p[0], p[1], p[2]
        if len(p) > 3: faw = p[3]
    env = dict(os.environ, BUILD=tempfile.mkdtemp(), TMO=str(tmo))
    if faw: env["DEFS"] = "-DFAW=" + faw
    r = subprocess.run(["bash", os.path.join(HERE, "run_sys.sh"), rtl, vec, gap, stall, "1"], capture_output=True, text=True, env=env)
    shutil.rmtree(env["BUILD"], ignore_errors=True)
    if "RESULT: PASS" in r.stdout: return "pass"
    if "RESULT: FAIL" in r.stdout or "MISMATCH" in r.stdout or "COUNTER" in r.stdout: return "fail"
    return "error"   # compile error or timeout: counts as caught (the mutant does not behave like the original)
NB_LHS = re.compile(r"(^|\)|\belse|\bbegin)\s*[\w\.\[\]:\$ ,{}]*$")
def jobs(rtl):
    out = []
    only = set(os.environ.get("ONLY", "").split(",")) - {""}
    for f in FILES:
        path = os.path.join(rtl, f + ".v")
        lines = open(path).read().split("\n")
        for ln, line in enumerate(lines):
            code = line.split("//")[0]
            if not code.strip(): continue
            for pat, rep in OPS:
                for m in re.finditer(pat, code):
                    if only and ("%s.v:%d" % (f, ln + 1)) not in only: continue
                    if pat == r" <= " and NB_LHS.search(code[:m.start()]): continue   # non-blocking assignment, not a comparison
                    out.append((f, lines, ln, line, code, pat, rep, m.start(), m.end()))
    return out
def one(rtl, vecs, j):
    f, lines, ln, line, code, pat, rep, a, b = j
    d = tempfile.mkdtemp(); shutil.copytree(rtl, d, dirs_exist_ok=True)
    mut = list(lines); mut[ln] = code[:a] + rep + code[b:] + line[len(code):]
    open(os.path.join(d, f + ".v"), "w").write("\n".join(mut))
    res = "pass"
    for v in vecs:
        res = run(d, v)
        if res != "pass": break
    shutil.rmtree(d, ignore_errors=True)
    return res, "%s.v:%d  %r -> %r   | %s" % (f, ln + 1, pat.strip("\\ "), rep.strip(), line.strip())
def main(rtl, vecs):
    js = jobs(rtl); print(len(js), "mutants", flush=True)
    with ThreadPoolExecutor(JOBS) as ex:
        results = list(ex.map(lambda j: one(rtl, vecs, j), js))
    eq = set(l.rstrip("\n") for l in open(os.path.join(HERE, "equivalent.txt")) if l.strip() and not l.startswith("#")) if os.path.exists(os.path.join(HERE, "equivalent.txt")) else set()
    allsurv = [t for r, t in results if r == "pass"]
    surv = [t for t in allsurv if t.split("   |")[0].rstrip() not in eq]
    reviewed = len(allsurv) - len(surv)
    caught = sum(r == "fail" for r, t in results)
    inval = [t for r, t in results if r == "error"]
    for t in surv: print("SURVIVED", t)
    print("\n%d mutants: %d caught, %d invalid (compile error/timeout), %d survived-but-reviewed (equivalent.txt), %d UNEXPLAINED SURVIVORS" % (len(js), caught, len(inval), reviewed, len(surv)))
    valid = caught + len(allsurv)
    print("raw mutation score = %d/%d = %.1f%%   (excluding reviewed-equivalent: %d/%d = %.1f%%)" % (caught, valid, 100.0 * caught / max(1, valid), caught, caught + len(surv), 100.0 * caught / max(1, caught + len(surv))))
if __name__ == "__main__": main(sys.argv[1], sys.argv[2:])
