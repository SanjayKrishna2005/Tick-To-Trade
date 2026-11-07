// Verilog-2001
// Module: risk_check
// Purpose: Apply ordered risk checks to each accepted DEC token,
//          maintain the rate window, and forward passed orders.

module risk_check (
    input             clk,
    input             rst,

    input             d_valid,
    output            d_ready,
    input             d_fire,
    input      [2:0]  d_sym,
    input             d_side,
    input      [31:0] d_px,
    input      [31:0] d_qty,
    input      [31:0] d_ts,

    output reg        o_valid,
    input             o_ready,
    output reg [2:0]  o_sym,
    output reg        o_side,
    output reg [31:0] o_px,
    output reg [31:0] o_qty,
    output reg [31:0] o_ts,

    input             cfg_kill,
    input      [31:0] cfg_px_lo,
    input      [31:0] cfg_px_hi,
    input      [31:0] cfg_rate_n,
    input      [31:0] cfg_rate_k,
    input             rate_clr,

    output reg        ev_nofire,
    output reg        ev_pass,
    output reg        ev_rej_kill,
    output reg        ev_rej_qty0,
    output reg        ev_rej_band,
    output reg        ev_rej_rate
);

    // Rate-window state:
    // window_count counts every accepted DEC token.
    // passed_count counts only passed orders in the current window.
    reg [31:0] window_count;
    reg [31:0] passed_count;

    wire        d_transfer;
    wire        decision_pass;
    wire        decision_nofire;
    wire        decision_rej_kill;
    wire        decision_rej_qty0;
    wire        decision_rej_band;
    wire        decision_rej_rate;

    wire [32:0] window_count_plus_one;

    // Ready is independent of d_valid, as required by X9.
    // A DEC token can be accepted whenever the output slot is empty
    // or the current output order is being consumed.
    assign d_ready = (!o_valid) || o_ready;

    // A transfer is suppressed during synchronous reset.
    assign d_transfer = d_valid && d_ready && !rst;

    // Extend before adding so FFFFFFFF + 1 does not wrap to zero.
    assign window_count_plus_one = {1'b0, window_count} + 33'd1;

    // Ordered decision logic. No-fire takes precedence over all checks.
    assign decision_nofire = !d_fire;

    assign decision_rej_kill =
        d_fire && cfg_kill;

    assign decision_rej_qty0 =
        d_fire && !cfg_kill && (d_qty == 32'd0);

    assign decision_rej_band =
        d_fire && !cfg_kill && (d_qty != 32'd0) &&
        ((d_px < cfg_px_lo) || (d_px > cfg_px_hi));

    assign decision_rej_rate =
        d_fire && !cfg_kill && (d_qty != 32'd0) &&
        (d_px >= cfg_px_lo) && (d_px <= cfg_px_hi) &&
        (cfg_rate_k != 32'd0) &&
        (passed_count >= cfg_rate_n);

    assign decision_pass =
        d_fire && !cfg_kill && (d_qty != 32'd0) &&
        (d_px >= cfg_px_lo) && (d_px <= cfg_px_hi) &&
        ((cfg_rate_k == 32'd0) ||
         (passed_count < cfg_rate_n));

    // State, output slot, and one-cycle event pulses.
    always @(posedge clk) begin
        if (rst) begin
            window_count <= 32'd0;
            passed_count <= 32'd0;

            o_valid <= 1'b0;
            o_sym   <= 3'd0;
            o_side  <= 1'b0;
            o_px    <= 32'd0;
            o_qty   <= 32'd0;
            o_ts    <= 32'd0;

            ev_nofire   <= 1'b0;
            ev_pass     <= 1'b0;
            ev_rej_kill <= 1'b0;
            ev_rej_qty0 <= 1'b0;
            ev_rej_band <= 1'b0;
            ev_rej_rate <= 1'b0;
        end
        else begin
            // Events are registered one-cycle pulses.
            ev_nofire   <= 1'b0;
            ev_pass     <= 1'b0;
            ev_rej_kill <= 1'b0;
            ev_rej_qty0 <= 1'b0;
            ev_rej_band <= 1'b0;
            ev_rej_rate <= 1'b0;

            // Consume the current output order when the ORD side is ready.
            // A newly passed DEC token below may replace it on this edge.
            if (o_valid && o_ready)
                o_valid <= 1'b0;

            // Rate clear has priority over window advancement.
            // The system specification states that rate_clr and a DEC
            // transfer cannot occur on the same edge.
            if (rate_clr) begin
                window_count <= 32'd0;
                passed_count <= 32'd0;
            end
            else if (d_transfer) begin
                // Every DEC token advances the window, including no-fire
                // and rejected tokens. RATE_K == 0 disables the limiter
                // and keeps both window counters at zero.
                if (cfg_rate_k == 32'd0) begin
                    window_count <= 32'd0;
                    passed_count <= 32'd0;
                end
                else if (window_count_plus_one >= {1'b0, cfg_rate_k}) begin
                    window_count <= 32'd0;
                    passed_count <= 32'd0;
                end
                else begin
                    window_count <= window_count + 32'd1;

                    if (decision_pass)
                        passed_count <= passed_count + 32'd1;
                end

                // Exactly one outcome event for this transferred token.
                if (decision_nofire)
                    ev_nofire <= 1'b1;
                else if (decision_rej_kill)
                    ev_rej_kill <= 1'b1;
                else if (decision_rej_qty0)
                    ev_rej_qty0 <= 1'b1;
                else if (decision_rej_band)
                    ev_rej_band <= 1'b1;
                else if (decision_rej_rate)
                    ev_rej_rate <= 1'b1;
                else if (decision_pass)
                    ev_pass <= 1'b1;

                // Only a passed token loads the ORD output slot.
                if (decision_pass) begin
                    o_valid <= 1'b1;
                    o_sym   <= d_sym;
                    o_side  <= d_side;
                    o_px    <= d_px;
                    o_qty   <= d_qty;
                    o_ts    <= d_ts;
                end
            end
        end
    end

endmodule
