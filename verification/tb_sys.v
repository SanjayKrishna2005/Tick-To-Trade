`timescale 1ns/1ps
`ifndef FAW
`define FAW 4
`endif
// System testbench: drives t2t_top from feed.hex and checks, against the golden model:
//  - every internal stage boundary (token by token), the output byte stream, the 23 counters
//  - hold-while-stalled on every internal interface, official + on-chip latency, mid-run reset
module tb_sys;
    parameter MAXF = 1048576;
    reg clk = 0, rst0 = 1, rst2 = 0;
    wire rst = rst0 | rst2;
    always #5 clk = ~clk;

    reg         s_valid = 0; wire s_ready; reg [7:0] s_data = 0; reg s_last = 0;
    wire        m_valid; reg m_ready = 0; wire [7:0] m_data; wire m_last;
    wire [735:0] cnt_flat;
    wire [31:0] lat_last, lat_min, lat_max, lat_count; wire [63:0] lat_sum;
    wire [31:0] dbg_bid_px, dbg_bid_qty, dbg_ask_px, dbg_ask_qty, dbg_cfg_val;
    reg  [2:0]  dbg_sym = 0; reg [7:0] dbg_idx = 0;

    t2t_top #(.FIFO_ADDR_W(`FAW)) dut (.clk(clk), .rst(rst), .cfg_dport(16'h5000),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data), .s_last(s_last),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data), .m_last(m_last),
        .cnt_flat(cnt_flat), .lat_last(lat_last), .lat_min(lat_min), .lat_max(lat_max),
        .lat_count(lat_count), .lat_sum(lat_sum),
        .dbg_book_sym(dbg_sym), .dbg_bid_px(dbg_bid_px), .dbg_bid_qty(dbg_bid_qty),
        .dbg_ask_px(dbg_ask_px), .dbg_ask_qty(dbg_ask_qty), .dbg_cfg_idx(dbg_idx), .dbg_cfg_val(dbg_cfg_val));

    reg [8:0]   feed_m [0:MAXF-1];
    reg [8:0]   pay_m  [0:262143];
    reg [87:0]  msg_m  [0:65535];
    reg [39:0]  cfg_m  [0:65535];
    reg [67:0]  q_m    [0:65535];
    reg [131:0] bk_m   [0:65535];
    reg [68:0]  dec_m  [0:65535];
    reg [67:0]  ord_m  [0:65535];
    reg [8:0]   ob_m   [0:262143];
    reg [31:0]  trig_m [0:65535];
    reg [31:0]  qidx_m [0:65535];
    reg [31:0]  cntx_m [0:22];
    integer in_edge [0:MAXF-1];
    integer q_edge [0:65535];
    integer out_edge [0:65535];

    integer NFIN = 0; reg [31:0] fin_m [0:127]; integer fin_e = 0, fi2; reg [31:0] fexp;
    integer NFEED, NPAY, NMSG, NCFG, NQ, NBK, NDEC, NORD, NOB, NTRIG;
    integer GAP, STALL, SEED, BURST, MIDRESET;
    reg [1023:0] vec; reg [1023:0] fn;

    integer pa_n=0, pa_e=0, fo_n=0, fo_e=0, ms_n=0, ms_e=0, cf_n=0, cf_e=0, qu_n=0, qu_e=0;
    integer bk_n=0, bk_e=0, de_n=0, de_e=0, or_n=0, or_e=0, ob_n=0, ob_e=0;
    integer pa_t=-1, fo_t=-1, ms_t=-1, cf_t=-1, qu_t=-1, bk_t=-1, de_t=-1, or_t=-1, ob_t=-1;
    integer hold_e [0:7];
    integer cyc = 0, fi = 0, last_act = 0, stallc = 0, k, in_stall = 0;
    integer rstw = 0, didreset = 0, reset_e = 0;
    reg rchk_go = 0, rchk_done = 0;
    reg     pv = 0, pr = 0; reg [8:0] pd = 0;
    reg [68:0] dec_got;
    reg [159:0] hp_d [0:7]; reg hp_v [0:7]; reg hp_r [0:7];
    integer lat, lmin, lmax, lsum, lcnt, lcnt2, cnt_err, dl, dmin, dmax, dsum, dlast, dl_err;
    reg [31:0] cv;
    reg acc;

    task show_err; input [127:0] name; input integer idx; input [131:0] exp; input [131:0] got; input integer t; begin
        $display("  [%0s] MISMATCH #%0d at cycle %0d: expected %h got %h", name, idx, t, exp, got);
    end endtask

    task hchk; input integer n; input v; input r; input [159:0] d; begin
        if (hp_v[n] && !hp_r[n] && (!v || d !== hp_d[n])) begin
            hold_e[n] = hold_e[n] + 1;
            if (hold_e[n] <= 2) $display("  [hold iface %0d] value changed or valid dropped while stalled at cycle %0d", n, cyc);
        end
        hp_v[n] = v & ~rst; hp_r[n] = r; hp_d[n] = d;
    end endtask

    initial begin
        for (k = 0; k < 8; k = k + 1) begin hold_e[k] = 0; hp_v[k] = 0; hp_r[k] = 0; hp_d[k] = 0; end
        if (!$value$plusargs("VEC=%s", vec)) begin $display("need +VEC=dir"); $finish; end
        if (!$value$plusargs("NFEED=%d", NFEED)) NFEED = 0;
        if (!$value$plusargs("NPAY=%d", NPAY)) NPAY = 0;
        if (!$value$plusargs("NMSG=%d", NMSG)) NMSG = 0;
        if (!$value$plusargs("NCFG=%d", NCFG)) NCFG = 0;
        if (!$value$plusargs("NQ=%d", NQ)) NQ = 0;
        if (!$value$plusargs("NBK=%d", NBK)) NBK = 0;
        if (!$value$plusargs("NDEC=%d", NDEC)) NDEC = 0;
        if (!$value$plusargs("NORD=%d", NORD)) NORD = 0;
        if (!$value$plusargs("NOB=%d", NOB)) NOB = 0;
        if (!$value$plusargs("NTRIG=%d", NTRIG)) NTRIG = 0;
        if (!$value$plusargs("NFINAL=%d", NFIN)) NFIN = 0;
        if (!$value$plusargs("GAP=%d", GAP)) GAP = 0;
        if (!$value$plusargs("STALL=%d", STALL)) STALL = 0;
        if (!$value$plusargs("SEED=%d", SEED)) SEED = 1;
        if (!$value$plusargs("BURST=%d", BURST)) BURST = 0;
        if (!$value$plusargs("MIDRESET=%d", MIDRESET)) MIDRESET = 0;
        $sformat(fn, "%0s/feed.hex", vec);        $readmemh(fn, feed_m);
        $sformat(fn, "%0s/exp_payload.hex", vec); $readmemh(fn, pay_m);
        $sformat(fn, "%0s/exp_msgs.hex", vec);    $readmemh(fn, msg_m);
        $sformat(fn, "%0s/exp_cfgw.hex", vec);    $readmemh(fn, cfg_m);
        $sformat(fn, "%0s/exp_quote.hex", vec);   $readmemh(fn, q_m);
        $sformat(fn, "%0s/exp_book.hex", vec);    $readmemh(fn, bk_m);
        $sformat(fn, "%0s/exp_dec.hex", vec);     $readmemh(fn, dec_m);
        $sformat(fn, "%0s/exp_ord.hex", vec);     $readmemh(fn, ord_m);
        $sformat(fn, "%0s/exp_obytes.hex", vec);  $readmemh(fn, ob_m);
        $sformat(fn, "%0s/exp_trigger.hex", vec); $readmemh(fn, trig_m);
        $sformat(fn, "%0s/exp_qidx.hex", vec);    $readmemh(fn, qidx_m);
        $sformat(fn, "%0s/exp_counters.hex", vec);$readmemh(fn, cntx_m);
        if (NFIN == 54) begin $sformat(fn, "%0s/exp_final.hex", vec); $readmemh(fn, fin_m); end
    end

    initial begin repeat (5) @(posedge clk); #1 rst0 = 0; end

    always @(posedge clk) begin
        cyc = cyc + 1;
        acc = 0;
        if (!rst) begin
            if (s_valid && !s_ready) in_stall = in_stall + 1;
            if (s_valid && s_ready) begin acc = 1; in_edge[fi] = cyc; fi = fi + 1; last_act = cyc; end
            if (dut.u_parser.m_valid && dut.u_parser.m_ready) begin
                if ({dut.u_parser.m_last, dut.u_parser.m_data} !== pay_m[pa_n] || pa_n >= NPAY) begin
                    pa_e = pa_e + 1; if (pa_e <= 3) show_err("parser->fifo", pa_n, pay_m[pa_n], {dut.u_parser.m_last, dut.u_parser.m_data}, cyc); if (pa_t < 0) pa_t = cyc; end
                pa_n = pa_n + 1; last_act = cyc;
            end
            if (dut.u_payload_fifo.m_valid && dut.u_payload_fifo.m_ready) begin
                if ({dut.u_payload_fifo.m_last, dut.u_payload_fifo.m_data} !== pay_m[fo_n] || fo_n >= NPAY) begin
                    fo_e = fo_e + 1; if (fo_e <= 3) show_err("fifo->asm", fo_n, pay_m[fo_n], {dut.u_payload_fifo.m_last, dut.u_payload_fifo.m_data}, cyc); if (fo_t < 0) fo_t = cyc; end
                fo_n = fo_n + 1;
            end
            if (dut.u_msg_assembler.msg_valid && dut.u_msg_assembler.msg_ready) begin
                if ({dut.u_msg_assembler.msg_type, dut.u_msg_assembler.msg_sym, dut.u_msg_assembler.msg_side,
                     dut.u_msg_assembler.msg_px, dut.u_msg_assembler.msg_qty} !== msg_m[ms_n] || ms_n >= NMSG) begin
                    ms_e = ms_e + 1; if (ms_e <= 3) show_err("asm->router", ms_n, msg_m[ms_n], {dut.u_msg_assembler.msg_type, dut.u_msg_assembler.msg_sym, dut.u_msg_assembler.msg_side, dut.u_msg_assembler.msg_px, dut.u_msg_assembler.msg_qty}, cyc); if (ms_t < 0) ms_t = cyc; end
                ms_n = ms_n + 1;
            end
            if (dut.u_cfg_regs.cfg_we) begin
                if ({dut.u_cfg_regs.cfg_idx, dut.u_cfg_regs.cfg_val} !== cfg_m[cf_n] || cf_n >= NCFG) begin
                    cf_e = cf_e + 1; if (cf_e <= 3) show_err("router->cfg", cf_n, cfg_m[cf_n], {dut.u_cfg_regs.cfg_idx, dut.u_cfg_regs.cfg_val}, cyc); if (cf_t < 0) cf_t = cyc; end
                cf_n = cf_n + 1;
            end
            if (dut.u_book_tracker.q_valid && dut.u_book_tracker.q_ready) begin
                if ({dut.u_book_tracker.q_sym, dut.u_book_tracker.q_side, dut.u_book_tracker.q_px, dut.u_book_tracker.q_qty} !== q_m[qu_n] || qu_n >= NQ) begin
                    qu_e = qu_e + 1; if (qu_e <= 3) show_err("router->book", qu_n, q_m[qu_n], {dut.u_book_tracker.q_sym, dut.u_book_tracker.q_side, dut.u_book_tracker.q_px, dut.u_book_tracker.q_qty}, cyc); if (qu_t < 0) qu_t = cyc; end
                q_edge[qu_n] = cyc;
                qu_n = qu_n + 1;
            end
            if (dut.u_strategy.b_valid && dut.u_strategy.b_ready) begin
                if ({dut.u_strategy.b_sym, dut.u_strategy.b_side, dut.u_strategy.b_px, dut.u_strategy.b_qty,
                     dut.u_strategy.b_opp_px, dut.u_strategy.b_opp_qty} !== bk_m[bk_n] || bk_n >= NBK) begin
                    bk_e = bk_e + 1; if (bk_e <= 3) show_err("book->strategy", bk_n, bk_m[bk_n], {dut.u_strategy.b_sym, dut.u_strategy.b_side, dut.u_strategy.b_px, dut.u_strategy.b_qty, dut.u_strategy.b_opp_px, dut.u_strategy.b_opp_qty}, cyc); if (bk_t < 0) bk_t = cyc; end
                bk_n = bk_n + 1;
            end
            if (dut.u_risk_check.d_valid && dut.u_risk_check.d_ready) begin
                dec_got = dut.u_risk_check.d_fire ? {1'b1, dut.u_risk_check.d_side, dut.u_risk_check.d_sym, dut.u_risk_check.d_px, dut.u_risk_check.d_qty} : 69'd0;
                if (dec_got !== dec_m[de_n] || de_n >= NDEC) begin
                    de_e = de_e + 1; if (de_e <= 3) show_err("strategy->risk", de_n, dec_m[de_n], dec_got, cyc); if (de_t < 0) de_t = cyc; end
                de_n = de_n + 1;
            end
            if (dut.u_order_encoder.o_valid && dut.u_order_encoder.o_ready) begin
                if ({dut.u_order_encoder.o_sym, dut.u_order_encoder.o_side, dut.u_order_encoder.o_px, dut.u_order_encoder.o_qty} !== ord_m[or_n] || or_n >= NORD) begin
                    or_e = or_e + 1; if (or_e <= 3) show_err("risk->encoder", or_n, ord_m[or_n], {dut.u_order_encoder.o_sym, dut.u_order_encoder.o_side, dut.u_order_encoder.o_px, dut.u_order_encoder.o_qty}, cyc); if (or_t < 0) or_t = cyc; end
                or_n = or_n + 1;
            end
            if (m_valid && m_ready) begin
                if ({m_last, m_data} !== ob_m[ob_n] || ob_n >= NOB) begin
                    ob_e = ob_e + 1; if (ob_e <= 3) show_err("output bytes", ob_n, ob_m[ob_n], {m_last, m_data}, cyc); if (ob_t < 0) ob_t = cyc; end
                if (ob_n % 16 == 0) out_edge[ob_n / 16] = cyc;
                ob_n = ob_n + 1; last_act = cyc;
            end
            // ---- hold-while-stalled on every interface (0 parser, 1 fifo, 2 msg, 3 quote, 4 book, 5 dec, 6 ord, 7 output) ----
            hchk(0, dut.u_parser.m_valid, dut.u_parser.m_ready, {dut.u_parser.m_last, dut.u_parser.m_data});
            hchk(1, dut.u_payload_fifo.m_valid, dut.u_payload_fifo.m_ready, {dut.u_payload_fifo.m_last, dut.u_payload_fifo.m_data});
            hchk(2, dut.u_msg_assembler.msg_valid, dut.u_msg_assembler.msg_ready, {dut.u_msg_assembler.msg_type, dut.u_msg_assembler.msg_sym, dut.u_msg_assembler.msg_side, dut.u_msg_assembler.msg_px, dut.u_msg_assembler.msg_qty});
            hchk(3, dut.u_book_tracker.q_valid, dut.u_book_tracker.q_ready, {dut.u_book_tracker.q_sym, dut.u_book_tracker.q_side, dut.u_book_tracker.q_px, dut.u_book_tracker.q_qty});
            hchk(4, dut.u_strategy.b_valid, dut.u_strategy.b_ready, {dut.u_strategy.b_sym, dut.u_strategy.b_side, dut.u_strategy.b_px, dut.u_strategy.b_qty, dut.u_strategy.b_opp_px, dut.u_strategy.b_opp_qty, dut.u_strategy.b_ts});
            hchk(5, dut.u_risk_check.d_valid, dut.u_risk_check.d_ready, dut.u_risk_check.d_fire ? {dut.u_risk_check.d_fire, dut.u_risk_check.d_side, dut.u_risk_check.d_sym, dut.u_risk_check.d_px, dut.u_risk_check.d_qty, dut.u_risk_check.d_ts} : 160'd0);
            hchk(6, dut.u_order_encoder.o_valid, dut.u_order_encoder.o_ready, {dut.u_order_encoder.o_sym, dut.u_order_encoder.o_side, dut.u_order_encoder.o_px, dut.u_order_encoder.o_qty, dut.u_order_encoder.o_ts});
            hchk(7, m_valid, m_ready, {m_last, m_data});
        end else begin
            for (k = 0; k < 8; k = k + 1) hp_v[k] = 0;
        end

        // ---- drive (after the edge) ----
        #1;
        if (MIDRESET > 0 && cyc >= MIDRESET && didreset == 0 && !rst0) begin
            didreset = 1; rst2 = 1; rstw = 0; s_valid = 0; m_ready = 0;
        end
        if (rst2) begin
            s_valid = 0; m_ready = 0; rstw = rstw + 1;
            if (rstw == 4) rchk_go = 1;
            if (rchk_done) begin
                rst2 = 0; rchk_done = 0;
                // restart the scenario from scratch, as after power-up
                fi = 0; pa_n=0; pa_e=0; fo_n=0; fo_e=0; ms_n=0; ms_e=0; cf_n=0; cf_e=0; qu_n=0; qu_e=0;
                bk_n=0; bk_e=0; de_n=0; de_e=0; or_n=0; or_e=0; ob_n=0; ob_e=0;
                pa_t=-1; fo_t=-1; ms_t=-1; cf_t=-1; qu_t=-1; bk_t=-1; de_t=-1; or_t=-1; ob_t=-1;
                for (k = 0; k < 8; k = k + 1) hold_e[k] = 0;
                last_act = cyc; in_stall = 0;
            end
        end else if (!rst) begin
            if (!s_valid || acc) begin
                if (fi < NFEED && (({$random(SEED)} % 100) >= GAP)) begin
                    s_valid = 1; {s_last, s_data} = feed_m[fi];
                end else s_valid = 0;
            end
            if (stallc > 0) begin m_ready = 0; stallc = stallc - 1; end
            else if (BURST && ({$random(SEED)} % 4000) == 0) begin m_ready = 0; stallc = 400; end
            else m_ready = (({$random(SEED)} % 100) >= STALL);
        end
    end

    // ---- state check while reset is held mid-run ----
    integer ri;
    initial begin
        wait (rchk_go);
        #3;
        if (m_valid !== 1'b0) begin reset_e = reset_e + 1; $display("  [reset] m_valid not 0"); end
        if (cnt_flat !== 736'd0) begin reset_e = reset_e + 1; $display("  [reset] counters not zero"); end
        if (lat_count !== 0 || lat_max !== 0 || lat_min !== 32'hFFFFFFFF || lat_sum !== 0) begin reset_e = reset_e + 1; $display("  [reset] latency stats not at reset values (count %0d min %h max %0d)", lat_count, lat_min, lat_max); end
        if (dut.u_payload_fifo.level !== 0) begin reset_e = reset_e + 1; $display("  [reset] fifo level not 0"); end
        for (ri = 0; ri < 8; ri = ri + 1) begin
            dbg_sym = ri; #1;
            if ({dbg_bid_px, dbg_bid_qty, dbg_ask_px, dbg_ask_qty} !== 128'd0) begin reset_e = reset_e + 1; $display("  [reset] book symbol %0d not empty", ri); end
        end
        for (ri = 0; ri < 24; ri = ri + 1) begin
            dbg_idx = ri; #1;
            if (ri < 8   && dbg_cfg_val !== 32'd0)        begin reset_e = reset_e + 1; $display("  [reset] BUY_THR[%0d] = %h", ri, dbg_cfg_val); end
            if (ri >= 8 && ri < 16 && dbg_cfg_val !== 32'hFFFFFFFF) begin reset_e = reset_e + 1; $display("  [reset] SELL_THR[%0d] = %h", ri-8, dbg_cfg_val); end
            if (ri == 16 && dbg_cfg_val !== 32'hFFFFFFFF) begin reset_e = reset_e + 1; $display("  [reset] MAX_QTY = %h", dbg_cfg_val); end
            if (ri == 17 && dbg_cfg_val !== 32'd0)        begin reset_e = reset_e + 1; $display("  [reset] PX_LO = %h", dbg_cfg_val); end
            if (ri == 18 && dbg_cfg_val !== 32'hFFFFFFFF) begin reset_e = reset_e + 1; $display("  [reset] PX_HI = %h", dbg_cfg_val); end
            if (ri >= 19 && ri < 22 && dbg_cfg_val !== 32'd0) begin reset_e = reset_e + 1; $display("  [reset] cfg %0d = %h (kill/rate)", ri, dbg_cfg_val); end
        end
        rchk_done = 1;
    end

    // ---- end of run ----
    integer ht; integer perf_e = 0;
    initial begin
        wait (!rst0);
        wait (fi >= NFEED && NFEED > 0);
        while ((cyc - last_act) < 400 && cyc < 30000000) @(posedge clk);
        #2;
        $display("---- boundary results (seen / expected, mismatches) ----");
        $display("parser->fifo      %0d / %0d   mismatches %0d  first bad cycle %0d", pa_n, NPAY, pa_e, pa_t);
        $display("fifo->assembler   %0d / %0d   mismatches %0d  first bad cycle %0d", fo_n, NPAY, fo_e, fo_t);
        $display("assembler->router %0d / %0d   mismatches %0d  first bad cycle %0d", ms_n, NMSG, ms_e, ms_t);
        $display("router->cfg_regs  %0d / %0d   mismatches %0d  first bad cycle %0d", cf_n, NCFG, cf_e, cf_t);
        $display("router->book      %0d / %0d   mismatches %0d  first bad cycle %0d", qu_n, NQ, qu_e, qu_t);
        $display("book->strategy    %0d / %0d   mismatches %0d  first bad cycle %0d", bk_n, NBK, bk_e, bk_t);
        $display("strategy->risk    %0d / %0d   mismatches %0d  first bad cycle %0d", de_n, NDEC, de_e, de_t);
        $display("risk->encoder     %0d / %0d   mismatches %0d  first bad cycle %0d", or_n, NORD, or_e, or_t);
        $display("output bytes      %0d / %0d   mismatches %0d  first bad cycle %0d", ob_n, NOB, ob_e, ob_t);
        ht = 0; for (k = 0; k < 8; k = k + 1) ht = ht + hold_e[k];
        $display("hold violations on the 8 interfaces: %0d   mid-run reset state errors: %0d   input stall cycles: %0d", ht, reset_e, in_stall);
        cnt_err = 0;
        for (k = 0; k < 23; k = k + 1) begin
            cv = cnt_flat[32*k +: 32];
            if (cv !== cntx_m[k]) begin cnt_err = cnt_err + 1; $display("  COUNTER %0d: expected %0d got %0d", k, cntx_m[k], cv); end
        end
        $display("counters: %0d of 23 differ", cnt_err);
        if (NFIN == 54) begin
            for (fi2 = 0; fi2 < 8; fi2 = fi2 + 1) begin
                dbg_sym = fi2; #1;
                if ({dbg_bid_px, dbg_bid_qty, dbg_ask_px, dbg_ask_qty} !== {fin_m[4*fi2], fin_m[4*fi2+1], fin_m[4*fi2+2], fin_m[4*fi2+3]}) begin
                    fin_e = fin_e + 1; $display("  FINAL BOOK sym %0d: got bid %0d/%0d ask %0d/%0d  expected bid %0d/%0d ask %0d/%0d", fi2, dbg_bid_px, dbg_bid_qty, dbg_ask_px, dbg_ask_qty, fin_m[4*fi2], fin_m[4*fi2+1], fin_m[4*fi2+2], fin_m[4*fi2+3]);
                end
            end
            for (fi2 = 0; fi2 < 22; fi2 = fi2 + 1) begin
                dbg_idx = fi2; #1;
                if (dbg_cfg_val !== fin_m[32 + fi2]) begin fin_e = fin_e + 1; $display("  FINAL CFG[0x%0h]: got %0d expected %0d", fi2, dbg_cfg_val, fin_m[32 + fi2]); end
            end
            $display("final book/config readback: %0d mismatches", fin_e);
        end
        perf_e = (STALL == 0 && GAP == 0 && in_stall > 0);
        if (perf_e) $display("  INPUT STALLED %0d cycles although output never stalls and input has no gaps", in_stall);
        lmin = 1<<30; lmax = 0; lsum = 0; lcnt = 0; dmin = 1<<30; dmax = 0; dsum = 0; dlast = 0;
        for (k = 0; k < NTRIG && k < ob_n/16; k = k + 1) begin
            lat = out_edge[k] - in_edge[trig_m[k]];
            if (lat < lmin) lmin = lat; if (lat > lmax) lmax = lat; lsum = lsum + lat; lcnt = lcnt + 1;
            dl = out_edge[k] - q_edge[qidx_m[k]];
            if (dl < dmin) dmin = dl; if (dl > dmax) dmax = dl; dsum = dsum + dl; dlast = dl;
        end
        if (lcnt > 0) $display("official tick-to-order latency over %0d orders: min %0d  avg %0d  max %0d cycles", lcnt, lmin, lsum/lcnt, lmax);
        $display("on-chip decision latency (design): count %0d last %0d min %0d max %0d sum %0d", lat_count, lat_last, lat_min, lat_max, lat_sum);
        $display("decision latency (testbench)     : count %0d last %0d min %0d max %0d sum %0d", lcnt, dlast, dmin, dmax, dsum);
        dl_err = (lcnt > 0) && (lat_count !== lcnt || lat_last !== dlast || lat_min !== dmin || lat_max !== dmax || lat_sum !== dsum);
        if (dl_err) $display("  LATENCY COUNTER DISAGREES WITH TESTBENCH MEASUREMENT");
        if (NTRIG > 0 && NTRIG <= 8) for (k = 0; k < NTRIG; k = k + 1)
            $display("  order %0d: official latency %0d", k, out_edge[k] - in_edge[trig_m[k]]);
        if (pa_e + fo_e + ms_e + cf_e + qu_e + bk_e + de_e + or_e + ob_e + ht + reset_e + cnt_err + dl_err + fin_e + perf_e == 0 &&
            ob_n == NOB && pa_n == NPAY && fo_n == NPAY && ms_n == NMSG && cf_n == NCFG && qu_n == NQ && bk_n == NBK && de_n == NDEC && or_n == NORD)
            $display("RESULT: PASS (cycles %0d)", cyc);
        else $display("RESULT: FAIL (cycles %0d)", cyc);
        $finish;
    end
endmodule
