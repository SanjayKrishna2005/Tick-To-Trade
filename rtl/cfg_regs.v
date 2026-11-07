// ============================================================
// Module: cfg_regs
// Description: Configuration register bank
// Language: Verilog-2001
//
// Register map:
//   0x00 - 0x07 : BUY_THR[0..7]
//   0x08 - 0x0F : SELL_THR[0..7]
//   0x10        : MAX_QTY
//   0x11        : PX_LO
//   0x12        : PX_HI
//   0x13        : KILL (stores cfg_val[0] only)
//   0x14        : RATE_N
//   0x15        : RATE_K
//
// Reset is synchronous, active-high.
// ============================================================

module cfg_regs (
    input  wire         clk,
    input  wire         rst,

    // Configuration write interface
    input  wire         cfg_we,
    input  wire [7:0]   cfg_idx,
    input  wire [31:0]  cfg_val,

    // Configuration outputs
    output wire [255:0] cfg_buy_thr_flat,
    output wire [255:0] cfg_sell_thr_flat,
    output wire [31:0]  cfg_max_qty,
    output wire [31:0]  cfg_px_lo,
    output wire [31:0]  cfg_px_hi,
    output wire         cfg_kill,
    output wire [31:0]  cfg_rate_n,
    output wire [31:0]  cfg_rate_k,

    // Event pulses
    output reg          rate_clr,
    output reg          ev_cfg_write,
    output reg          ev_cfg_bad,

    // Combinational debug read interface
    input  wire [7:0]   rd_idx,
    output reg  [31:0]  rd_val
);

    // --------------------------------------------------------
    // Internal register storage
    // --------------------------------------------------------

    reg [31:0] buy_thr  [0:7];
    reg [31:0] sell_thr [0:7];

    reg [31:0] max_qty;
    reg [31:0] px_lo;
    reg [31:0] px_hi;
    reg        kill;
    reg [31:0] rate_n;
    reg [31:0] rate_k;

    integer i;

    // --------------------------------------------------------
    // Flatten threshold arrays into packed output buses.
    //
    // BUY_THR[k]  -> cfg_buy_thr_flat [32*k +: 32]
    // SELL_THR[k] -> cfg_sell_thr_flat[32*k +: 32]
    // --------------------------------------------------------

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GEN_FLAT_OUTPUTS
            assign cfg_buy_thr_flat[32*g +: 32]  = buy_thr[g];
            assign cfg_sell_thr_flat[32*g +: 32] = sell_thr[g];
        end
    endgenerate

    // Scalar register outputs come directly from storage.
    assign cfg_max_qty = max_qty;
    assign cfg_px_lo   = px_lo;
    assign cfg_px_hi   = px_hi;
    assign cfg_kill    = kill;
    assign cfg_rate_n  = rate_n;
    assign cfg_rate_k  = rate_k;

    // --------------------------------------------------------
    // Synchronous writes, reset, and event generation
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            // BUY_THR defaults to zero.
            for (i = 0; i < 8; i = i + 1) begin
                buy_thr[i] <= 32'h00000000;
            end

            // SELL_THR defaults to all ones.
            for (i = 0; i < 8; i = i + 1) begin
                sell_thr[i] <= 32'hFFFFFFFF;
            end

            max_qty <= 32'hFFFFFFFF;
            px_lo   <= 32'h00000000;
            px_hi   <= 32'hFFFFFFFF;
            kill    <= 1'b0;
            rate_n  <= 32'h00000000;
            rate_k  <= 32'h00000000;

            // Reset clears all event pulses.
            rate_clr    <= 1'b0;
            ev_cfg_write <= 1'b0;
            ev_cfg_bad   <= 1'b0;
        end
        else begin
            // Default event values: pulses last one cycle.
            rate_clr     <= 1'b0;
            ev_cfg_write <= 1'b0;
            ev_cfg_bad   <= 1'b0;

            if (cfg_we) begin
                case (cfg_idx)

                    // BUY_THR[0..7]
                    8'h00: begin buy_thr[0] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h01: begin buy_thr[1] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h02: begin buy_thr[2] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h03: begin buy_thr[3] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h04: begin buy_thr[4] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h05: begin buy_thr[5] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h06: begin buy_thr[6] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h07: begin buy_thr[7] <= cfg_val; ev_cfg_write <= 1'b1; end

                    // SELL_THR[0..7]
                    8'h08: begin sell_thr[0] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h09: begin sell_thr[1] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h0A: begin sell_thr[2] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h0B: begin sell_thr[3] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h0C: begin sell_thr[4] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h0D: begin sell_thr[5] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h0E: begin sell_thr[6] <= cfg_val; ev_cfg_write <= 1'b1; end
                    8'h0F: begin sell_thr[7] <= cfg_val; ev_cfg_write <= 1'b1; end

                    // Scalar registers
                    8'h10: begin
                        max_qty <= cfg_val;
                        ev_cfg_write <= 1'b1;
                    end

                    8'h11: begin
                        px_lo <= cfg_val;
                        ev_cfg_write <= 1'b1;
                    end

                    8'h12: begin
                        px_hi <= cfg_val;
                        ev_cfg_write <= 1'b1;
                    end

                    // KILL stores bit 0 only.
                    8'h13: begin
                        kill <= cfg_val[0];
                        ev_cfg_write <= 1'b1;
                    end

                    // RATE_N write also clears rate-window state.
                    8'h14: begin
                        rate_n <= cfg_val;
                        ev_cfg_write <= 1'b1;
                        rate_clr <= 1'b1;
                    end

                    // RATE_K write also clears rate-window state.
                    8'h15: begin
                        rate_k <= cfg_val;
                        ev_cfg_write <= 1'b1;
                        rate_clr <= 1'b1;
                    end

                    // Invalid index: no register changes.
                    default: begin
                        ev_cfg_bad <= 1'b1;
                    end

                endcase
            end
        end
    end

    // --------------------------------------------------------
    // Combinational debug read
    // --------------------------------------------------------

    // rd_val always reflects the currently stored register.
    // Invalid indexes return zero. Reads have no side effects.

    always @* begin
        rd_val = 32'h00000000;

        case (rd_idx)

            // BUY_THR[0..7]
            8'h00: rd_val = buy_thr[0];
            8'h01: rd_val = buy_thr[1];
            8'h02: rd_val = buy_thr[2];
            8'h03: rd_val = buy_thr[3];
            8'h04: rd_val = buy_thr[4];
            8'h05: rd_val = buy_thr[5];
            8'h06: rd_val = buy_thr[6];
            8'h07: rd_val = buy_thr[7];

            // SELL_THR[0..7]
            8'h08: rd_val = sell_thr[0];
            8'h09: rd_val = sell_thr[1];
            8'h0A: rd_val = sell_thr[2];
            8'h0B: rd_val = sell_thr[3];
            8'h0C: rd_val = sell_thr[4];
            8'h0D: rd_val = sell_thr[5];
            8'h0E: rd_val = sell_thr[6];
            8'h0F: rd_val = sell_thr[7];

            // Scalar registers
            8'h10: rd_val = max_qty;
            8'h11: rd_val = px_lo;
            8'h12: rd_val = px_hi;

            // KILL is zero-extended to 32 bits.
            8'h13: rd_val = {31'b0, kill};

            8'h14: rd_val = rate_n;
            8'h15: rd_val = rate_k;

            // Invalid index returns zero.
            default: rd_val = 32'h00000000;

        endcase
    end

endmodule
