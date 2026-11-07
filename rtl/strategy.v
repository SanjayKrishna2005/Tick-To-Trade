// -----------------------------------------------------------------------------
// Module: strategy
//
// Purpose:
//   For every accepted BOOK token, generate exactly one DEC token. The token
//   either represents a candidate order (d_fire = 1) or a no-order decision
//   (d_fire = 0).
//
// Specification:
//   spec_system.md  : sections 1, 2, 3.3, 4 and 5.1
//   spec_strategy.md: sections 1 through 10
//
// Language: Verilog-2001
// Reset:    synchronous, active-high
// -----------------------------------------------------------------------------

module strategy (
    input  wire        clk,
    input  wire        rst,

    // BOOK input interface
    input  wire        b_valid,
    output wire        b_ready,
    input  wire [2:0]  b_sym,
    input  wire        b_side,
    input  wire [31:0] b_px,
    input  wire [31:0] b_qty,
    input  wire [31:0] b_opp_px,
    input  wire [31:0] b_opp_qty,
    input  wire [31:0] b_ts,

    // DEC output interface
    output reg         d_valid,
    input  wire        d_ready,
    output reg         d_fire,
    output reg  [2:0]  d_sym,
    output reg         d_side,
    output reg  [31:0] d_px,
    output reg  [31:0] d_qty,
    output reg  [31:0] d_ts,

    // Configuration inputs: 8 packed unsigned 32-bit thresholds each
    input  wire [255:0] cfg_buy_thr_flat,
    input  wire [255:0] cfg_sell_thr_flat,
    input  wire [31:0]  cfg_max_qty,

    // Busy indication
    output wire        busy
);

    // -------------------------------------------------------------------------
    // Select the threshold belonging to the incoming BOOK token's symbol.
    // K4: element k is cfg_flat[32*k +: 32].
    // Indexed part-select is supported by Verilog-2001.
    // -------------------------------------------------------------------------

    wire [31:0] selected_buy_thr;
    wire [31:0] selected_sell_thr;

    assign selected_buy_thr  = cfg_buy_thr_flat [32*b_sym +: 32];
    assign selected_sell_thr = cfg_sell_thr_flat[32*b_sym +: 32];

    // -------------------------------------------------------------------------
    // Strategy decision conditions.
    // All operands are unsigned 32-bit vectors; comparisons are strict.
    // Market side: 0 = bid, 1 = ask.
    // Order side : 0 = buy, 1 = sell.
    // -------------------------------------------------------------------------

    wire ask_fire;
    wire bid_fire;
    wire decision_fire;
    wire [31:0] clamped_qty;

    assign ask_fire = (b_qty > 32'd0) &&
                      (b_px < selected_buy_thr) &&
                      (b_opp_qty > 32'd0) &&
                      (b_opp_px < b_px);

    assign bid_fire = (b_qty > 32'd0) &&
                      (b_px > selected_sell_thr) &&
                      (b_opp_qty > 32'd0) &&
                      (b_opp_px > b_px);

    // An ask quote may trigger a buy; a bid quote may trigger a sell.
    assign decision_fire = b_side ? ask_fire : bid_fire;

    // Clamp quantity to min(b_qty, cfg_max_qty). This does not affect fire.
    assign clamped_qty = (b_qty < cfg_max_qty) ? b_qty : cfg_max_qty;

    // -------------------------------------------------------------------------
    // Ready / busy logic.
    // b_ready is independent of b_valid (S8).
    // -------------------------------------------------------------------------

    assign b_ready = (~d_valid) | d_ready;
    assign busy    = d_valid;

    // -------------------------------------------------------------------------
    // Registered one-entry DEC output stage.
    // A BOOK transfer is b_valid && b_ready at the rising edge.
    // The configuration values used are those visible at that edge.
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            d_valid <= 1'b0;
            d_fire  <= 1'b0;
            d_sym   <= 3'd0;
            d_side  <= 1'b0;
            d_px    <= 32'd0;
            d_qty   <= 32'd0;
            d_ts    <= 32'd0;
        end else begin
            // Retire the current DEC token when accepted downstream.
            if (d_valid && d_ready) begin
                d_valid <= 1'b0;
            end

            // Accept a BOOK token and replace/refill the DEC output slot.
            // This also supports simultaneous DEC consumption and BOOK
            // acceptance in the same cycle.
            if (b_valid && b_ready) begin
                d_valid <= 1'b1;

                d_fire <= decision_fire;
                d_sym  <= b_sym;
                d_side <= ~b_side;
                d_px   <= b_px;
                d_qty  <= clamped_qty;
                d_ts   <= b_ts;
            end
        end
    end

endmodule
