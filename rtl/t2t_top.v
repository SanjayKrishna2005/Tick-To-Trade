// -----------------------------------------------------------------------------
// Module: t2t_top
//
// Purpose:
//   Structural top-level integration of the FPGA Tick-to-Trade Engine.
//   Connects the Ethernet/IPv4/UDP parser, byte FIFO, message assembler,
//   message router, configuration registers, order book, strategy, risk check,
//   order encoder, statistics counters, and latency counter.
//
// Specification references:
//   - spec_system.md: common conventions, interfaces, event map, latency
//   - spec_t2t_top.md: top-level ports, internal wiring, and end-to-end rules
//
// Language: Verilog-2001
// Reset: synchronous, active-high (distributed to every submodule)
// -----------------------------------------------------------------------------

module t2t_top #(
    parameter FIFO_ADDR_W = 4
) (
    input  wire         clk,
    input  wire         rst,

    input  wire [15:0]  cfg_dport,

    // Input Ethernet frame byte stream
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [7:0]   s_data,
    input  wire         s_last,

    // Output order byte stream
    output wire         m_valid,
    input  wire         m_ready,
    output wire [7:0]   m_data,
    output wire         m_last,

    // 23 x 32-bit event counters; counter i occupies cnt_flat[32*i +: 32].
    output wire [735:0] cnt_flat,

    // On-chip decision-latency statistics
    output wire [31:0]  lat_last,
    output wire [31:0]  lat_min,
    output wire [31:0]  lat_max,
    output wire [63:0]  lat_sum,
    output wire [31:0]  lat_count,

    // Order-book debug read port
    input  wire [2:0]   dbg_book_sym,
    output wire [31:0]  dbg_bid_px,
    output wire [31:0]  dbg_bid_qty,
    output wire [31:0]  dbg_ask_px,
    output wire [31:0]  dbg_ask_qty,

    // Configuration-register debug read port
    input  wire [7:0]   dbg_cfg_idx,
    output wire [31:0]  dbg_cfg_val
);

    // -------------------------------------------------------------------------
    // Internal BYTE stream: parser -> FIFO -> assembler
    // -------------------------------------------------------------------------

    wire        parser_m_valid;
    wire        parser_m_ready;
    wire [7:0]  parser_m_data;
    wire        parser_m_last;

    wire        fifo_s_ready;
    wire        fifo_m_valid;
    wire        fifo_m_ready;
    wire [7:0]  fifo_m_data;
    wire        fifo_m_last;
    wire [FIFO_ADDR_W:0] fifo_level;

    // Parser event pulses, event indices 0 through 5.
    wire ev_good;
    wire ev_drop_ethertype;
    wire ev_drop_ipver;
    wire ev_drop_proto;
    wire ev_drop_port;
    wire ev_drop_len;

    // -------------------------------------------------------------------------
    // Internal MSG stream: assembler -> router
    // -------------------------------------------------------------------------

    wire        msg_valid;
    wire        msg_ready;
    wire [7:0]  msg_type;
    wire [7:0]  msg_sym;
    wire [7:0]  msg_side;
    wire [31:0] msg_px;
    wire [31:0] msg_qty;

    // Assembler event pulses, event indices 6 through 8.
    wire ev_pkt_good;
    wire ev_pkt_bad_count;
    wire ev_pkt_bad_len;

    // -------------------------------------------------------------------------
    // Router outputs: QUOTE and configuration-write interface
    // -------------------------------------------------------------------------

    wire        q_valid;
    wire        q_ready;
    wire [2:0]  q_sym;
    wire        q_side;
    wire [31:0] q_px;
    wire [31:0] q_qty;
    wire [31:0] q_ts;

    wire        cfg_we;
    wire [7:0]  cfg_idx;
    wire [31:0] cfg_val;

    wire        book_busy;
    wire        strategy_busy;
    wire        busy_q;
    wire [31:0] now;

    // Router event pulses, event indices 9 through 13.
    wire ev_quote;
    wire ev_trade;
    wire ev_config;
    wire ev_unknown;
    wire ev_badfield;

    // -------------------------------------------------------------------------
    // Configuration-register outputs
    // -------------------------------------------------------------------------

    wire [255:0] cfg_buy_thr_flat;
    wire [255:0] cfg_sell_thr_flat;
    wire [31:0]  cfg_max_qty;
    wire [31:0]  cfg_px_lo;
    wire [31:0]  cfg_px_hi;
    wire         cfg_kill;
    wire [31:0]  cfg_rate_n;
    wire [31:0]  cfg_rate_k;
    wire         rate_clr;

    // Configuration event pulses, event indices 14 and 15.
    wire ev_cfg_write;
    wire ev_cfg_bad;

    // -------------------------------------------------------------------------
    // Internal BOOK stream: book_tracker -> strategy
    // -------------------------------------------------------------------------

    wire        b_valid;
    wire        b_ready;
    wire [2:0]  b_sym;
    wire        b_side;
    wire [31:0] b_px;
    wire [31:0] b_qty;
    wire [31:0] b_opp_px;
    wire [31:0] b_opp_qty;
    wire [31:0] b_ts;

    // -------------------------------------------------------------------------
    // Internal DEC stream: strategy -> risk_check
    // -------------------------------------------------------------------------

    wire        d_valid;
    wire        d_ready;
    wire        d_fire;
    wire [2:0]  d_sym;
    wire        d_side;
    wire [31:0] d_px;
    wire [31:0] d_qty;
    wire [31:0] d_ts;

    // -------------------------------------------------------------------------
    // Internal ORD stream: risk_check -> order_encoder
    // -------------------------------------------------------------------------

    wire        o_valid;
    wire        o_ready;
    wire [2:0]  o_sym;
    wire        o_side;
    wire [31:0] o_px;
    wire [31:0] o_qty;
    wire [31:0] o_ts;

    // Risk event pulses, event indices 16 through 21.
    wire ev_nofire;
    wire ev_pass;
    wire ev_rej_kill;
    wire ev_rej_qty0;
    wire ev_rej_band;
    wire ev_rej_rate;

    // Encoder latency strobe/timestamp and completion event.
    wire        first_byte_xfer;
    wire [31:0] first_byte_ts;
    wire        ev_order_done;

    // -------------------------------------------------------------------------
    // Parser -> FIFO -> assembler
    // -------------------------------------------------------------------------

    eth_ip_udp_parser u_parser (
        .clk                (clk),
        .rst                (rst),
        .cfg_dport          (cfg_dport),

        .s_valid            (s_valid),
        .s_ready            (s_ready),
        .s_data             (s_data),
        .s_last             (s_last),

        .m_valid            (parser_m_valid),
        .m_ready            (parser_m_ready),
        .m_data             (parser_m_data),
        .m_last             (parser_m_last),

        .ev_good            (ev_good),
        .ev_drop_ethertype  (ev_drop_ethertype),
        .ev_drop_ipver      (ev_drop_ipver),
        .ev_drop_proto      (ev_drop_proto),
        .ev_drop_port       (ev_drop_port),
        .ev_drop_len        (ev_drop_len)
    );

    assign parser_m_ready = fifo_s_ready;

    sync_fifo #(
        .DATA_W (8),
        .ADDR_W (FIFO_ADDR_W)
    ) u_payload_fifo (
        .clk       (clk),
        .rst       (rst),

        .s_valid   (parser_m_valid),
        .s_ready   (fifo_s_ready),
        .s_data    (parser_m_data),
        .s_last    (parser_m_last),

        .m_valid   (fifo_m_valid),
        .m_ready   (fifo_m_ready),
        .m_data    (fifo_m_data),
        .m_last    (fifo_m_last),

        .level     (fifo_level)
    );

    msg_assembler u_msg_assembler (
        .clk                (clk),
        .rst                (rst),

        .s_valid            (fifo_m_valid),
        .s_ready            (fifo_m_ready),
        .s_data             (fifo_m_data),
        .s_last             (fifo_m_last),

        .msg_valid          (msg_valid),
        .msg_ready          (msg_ready),
        .msg_type           (msg_type),
        .msg_sym            (msg_sym),
        .msg_side           (msg_side),
        .msg_px             (msg_px),
        .msg_qty            (msg_qty),

        .ev_pkt_good        (ev_pkt_good),
        .ev_pkt_bad_count   (ev_pkt_bad_count),
        .ev_pkt_bad_len     (ev_pkt_bad_len)
    );

    // -------------------------------------------------------------------------
    // Message router -> book tracker / configuration registers
    // -------------------------------------------------------------------------

    assign busy_q = book_busy | strategy_busy;

    msg_router u_msg_router (
        .clk          (clk),
        .rst          (rst),

        .msg_valid    (msg_valid),
        .msg_ready    (msg_ready),
        .msg_type     (msg_type),
        .msg_sym      (msg_sym),
        .msg_side     (msg_side),
        .msg_px       (msg_px),
        .msg_qty      (msg_qty),

        .q_valid      (q_valid),
        .q_ready      (q_ready),
        .q_sym        (q_sym),
        .q_side       (q_side),
        .q_px         (q_px),
        .q_qty        (q_qty),
        .q_ts         (q_ts),

        .cfg_we       (cfg_we),
        .cfg_idx      (cfg_idx),
        .cfg_val      (cfg_val),

        .busy_q       (busy_q),
        .now          (now),

        .ev_quote     (ev_quote),
        .ev_trade     (ev_trade),
        .ev_config    (ev_config),
        .ev_unknown   (ev_unknown),
        .ev_badfield  (ev_badfield)
    );

    cfg_regs u_cfg_regs (
        .clk                (clk),
        .rst                (rst),

        .cfg_we             (cfg_we),
        .cfg_idx            (cfg_idx),
        .cfg_val            (cfg_val),

        .cfg_buy_thr_flat   (cfg_buy_thr_flat),
        .cfg_sell_thr_flat  (cfg_sell_thr_flat),
        .cfg_max_qty        (cfg_max_qty),
        .cfg_px_lo          (cfg_px_lo),
        .cfg_px_hi          (cfg_px_hi),
        .cfg_kill           (cfg_kill),
        .cfg_rate_n         (cfg_rate_n),
        .cfg_rate_k         (cfg_rate_k),
        .rate_clr            (rate_clr),
        .ev_cfg_write       (ev_cfg_write),
        .ev_cfg_bad         (ev_cfg_bad),

        .rd_idx             (dbg_cfg_idx),
        .rd_val             (dbg_cfg_val)
    );

    // -------------------------------------------------------------------------
    // Quote -> book -> strategy -> risk -> order encoder
    // -------------------------------------------------------------------------

    book_tracker u_book_tracker (
        .clk          (clk),
        .rst          (rst),

        .q_valid      (q_valid),
        .q_ready      (q_ready),
        .q_sym        (q_sym),
        .q_side       (q_side),
        .q_px         (q_px),
        .q_qty        (q_qty),
        .q_ts         (q_ts),

        .b_valid      (b_valid),
        .b_ready      (b_ready),
        .b_sym        (b_sym),
        .b_side       (b_side),
        .b_px         (b_px),
        .b_qty        (b_qty),
        .b_opp_px     (b_opp_px),
        .b_opp_qty    (b_opp_qty),
        .b_ts         (b_ts),

        .busy         (book_busy),

        .rd_sym       (dbg_book_sym),
        .rd_bid_px    (dbg_bid_px),
        .rd_bid_qty   (dbg_bid_qty),
        .rd_ask_px    (dbg_ask_px),
        .rd_ask_qty   (dbg_ask_qty)
    );

    strategy u_strategy (
        .clk                (clk),
        .rst                (rst),

        .b_valid            (b_valid),
        .b_ready            (b_ready),
        .b_sym              (b_sym),
        .b_side             (b_side),
        .b_px               (b_px),
        .b_qty              (b_qty),
        .b_opp_px           (b_opp_px),
        .b_opp_qty          (b_opp_qty),
        .b_ts               (b_ts),

        .d_valid            (d_valid),
        .d_ready            (d_ready),
        .d_fire             (d_fire),
        .d_sym              (d_sym),
        .d_side             (d_side),
        .d_px               (d_px),
        .d_qty              (d_qty),
        .d_ts               (d_ts),

        .cfg_buy_thr_flat   (cfg_buy_thr_flat),
        .cfg_sell_thr_flat  (cfg_sell_thr_flat),
        .cfg_max_qty        (cfg_max_qty),

        .busy               (strategy_busy)
    );

    risk_check u_risk_check (
        .clk          (clk),
        .rst          (rst),

        .d_valid      (d_valid),
        .d_ready      (d_ready),
        .d_fire       (d_fire),
        .d_sym        (d_sym),
        .d_side       (d_side),
        .d_px         (d_px),
        .d_qty        (d_qty),
        .d_ts         (d_ts),

        .o_valid      (o_valid),
        .o_ready      (o_ready),
        .o_sym        (o_sym),
        .o_side       (o_side),
        .o_px         (o_px),
        .o_qty        (o_qty),
        .o_ts         (o_ts),

        .cfg_kill     (cfg_kill),
        .cfg_px_lo    (cfg_px_lo),
        .cfg_px_hi    (cfg_px_hi),
        .cfg_rate_n   (cfg_rate_n),
        .cfg_rate_k   (cfg_rate_k),
        .rate_clr     (rate_clr),

        .ev_nofire    (ev_nofire),
        .ev_pass      (ev_pass),
        .ev_rej_kill  (ev_rej_kill),
        .ev_rej_qty0  (ev_rej_qty0),
        .ev_rej_band  (ev_rej_band),
        .ev_rej_rate  (ev_rej_rate)
    );

    order_encoder u_order_encoder (
        .clk                (clk),
        .rst                (rst),

        .o_valid            (o_valid),
        .o_ready            (o_ready),
        .o_sym              (o_sym),
        .o_side             (o_side),
        .o_px               (o_px),
        .o_qty              (o_qty),
        .o_ts               (o_ts),

        .m_valid            (m_valid),
        .m_ready            (m_ready),
        .m_data             (m_data),
        .m_last             (m_last),

        .first_byte_xfer    (first_byte_xfer),
        .first_byte_ts      (first_byte_ts),
        .ev_order_done      (ev_order_done)
    );

    // -------------------------------------------------------------------------
    // Event bus -> statistics counters
    //
    // Bit mapping follows spec_system.md section 6 exactly:
    //   [ 5: 0] parser, [ 8: 6] assembler, [13: 9] router,
    //   [15:14] cfg_regs, [21:16] risk_check, [22] encoder.
    // -------------------------------------------------------------------------

    wire [22:0] ev_flat;

    assign ev_flat = {
        ev_order_done,       // 22: enc_orders_sent
        ev_rej_rate,         // 21: risk_rej_rate
        ev_rej_band,         // 20: risk_rej_band
        ev_rej_qty0,         // 19: risk_rej_qty0
        ev_rej_kill,         // 18: risk_rej_kill
        ev_pass,             // 17: risk_pass
        ev_nofire,           // 16: risk_nofire
        ev_cfg_bad,          // 15: cfg_bad
        ev_cfg_write,        // 14: cfg_write
        ev_badfield,         // 13: rt_badfield
        ev_unknown,          // 12: rt_unknown
        ev_config,           // 11: rt_config
        ev_trade,            // 10: rt_trade
        ev_quote,            //  9: rt_quote
        ev_pkt_bad_len,      //  8: asm_pkt_bad_len
        ev_pkt_bad_count,    //  7: asm_pkt_bad_count
        ev_pkt_good,         //  6: asm_pkt_good
        ev_drop_len,         //  5: par_drop_len
        ev_drop_port,        //  4: par_drop_port
        ev_drop_proto,       //  3: par_drop_proto
        ev_drop_ipver,       //  2: par_drop_ipver
        ev_drop_ethertype,   //  1: par_drop_ethertype
        ev_good              //  0: par_good
    };

    stats_counters u_stats_counters (
        .clk       (clk),
        .rst       (rst),
        .ev_flat   (ev_flat),
        .cnt_flat  (cnt_flat)
    );

    // -------------------------------------------------------------------------
    // Cycle counter and decision-latency measurement
    // -------------------------------------------------------------------------

    latency_counter u_latency_counter (
        .clk          (clk),
        .rst          (rst),
        .now          (now),
        .meas_valid   (first_byte_xfer),
        .meas_ts      (first_byte_ts),
        .lat_last     (lat_last),
        .lat_min      (lat_min),
        .lat_max      (lat_max),
        .lat_sum      (lat_sum),
        .lat_count    (lat_count)
    );

endmodule
