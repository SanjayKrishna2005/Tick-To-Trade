
module msg_router (
    input  wire        clk,
    input  wire        rst,

    // Message interface from msg_assembler
    input  wire        msg_valid,
    output reg         msg_ready,
    input  wire [7:0]  msg_type,
    input  wire [7:0]  msg_sym,
    input  wire [7:0]  msg_side,
    input  wire [31:0] msg_px,
    input  wire [31:0] msg_qty,

    // Quote interface to book_tracker
    output wire        q_valid,
    input  wire        q_ready,
    output wire [2:0]  q_sym,
    output wire        q_side,
    output wire [31:0] q_px,
    output wire [31:0] q_qty,
    output wire [31:0] q_ts,

    // Configuration write interface to cfg_regs
    output wire        cfg_we,
    output wire [7:0]  cfg_idx,
    output wire [31:0] cfg_val,

    // Pipeline barrier and timestamp
    input  wire        busy_q,
    input  wire [31:0] now,

    // Registered event pulses
    output reg         ev_quote,
    output reg         ev_trade,
    output reg         ev_config,
    output reg         ev_unknown,
    output reg         ev_badfield
);

    // --------------------------------------------------------
    // Message type definitions
    // --------------------------------------------------------

    localparam [7:0] MSG_TYPE_QUOTE  = 8'h01;
    localparam [7:0] MSG_TYPE_TRADE  = 8'h02;
    localparam [7:0] MSG_TYPE_CONFIG = 8'h03;

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------

    wire fields_valid;
    wire is_quote;
    wire is_trade;
    wire is_config;
    wire is_unknown;
    wire msg_transfer;

    // --------------------------------------------------------
    // Message classification and field validation
    // --------------------------------------------------------

    assign fields_valid =
        (msg_sym  <= 8'd7) &&
        (msg_side <= 8'd1);

    assign is_quote   = (msg_type == MSG_TYPE_QUOTE);
    assign is_trade   = (msg_type == MSG_TYPE_TRADE);
    assign is_config  = (msg_type == MSG_TYPE_CONFIG);

    assign is_unknown =
        !is_quote && !is_trade && !is_config;

    // --------------------------------------------------------
    // Quote output: combinational pass-through
    // --------------------------------------------------------

    assign q_valid = msg_valid && is_quote && fields_valid;

    assign q_sym  = msg_sym[2:0];
    assign q_side = msg_side[0];

    assign q_px   = msg_px;
    assign q_qty  = msg_qty;

    // Timestamp corresponds to the current transfer cycle.
    assign q_ts = now;

    // --------------------------------------------------------
    // Configuration output
    // --------------------------------------------------------

    // cfg_we is a combinational strobe.
    // It is asserted only for a valid config message when
    // the ordering barrier is clear.
    // Reset suppresses the write strobe at a reset edge.

    assign cfg_we =
        msg_valid &&
        is_config &&
        !busy_q &&
        !rst;

    assign cfg_idx = msg_sym;
    assign cfg_val = msg_px;

    // --------------------------------------------------------
    // Input ready generation
    // --------------------------------------------------------

    // IMPORTANT:
    // msg_ready does not depend on msg_valid.
    //
    // Valid quote:
    //     Wait for q_ready.
    //
    // Invalid quote:
    //     Consume immediately as badfield.
    //
    // Trade:
    //     Consume immediately.
    //
    // Config:
    //     Wait until busy_q becomes zero.
    //
    // Unknown:
    //     Consume immediately.

    always @* begin

        msg_ready = 1'b0;

        case (msg_type)

            MSG_TYPE_QUOTE: begin

                if (fields_valid)
                    msg_ready = q_ready;
                else
                    msg_ready = 1'b1;

            end

            MSG_TYPE_TRADE: begin

                msg_ready = 1'b1;

            end

            MSG_TYPE_CONFIG: begin

                msg_ready = !busy_q;

            end

            default: begin

                msg_ready = 1'b1;

            end

        endcase

    end

    // --------------------------------------------------------
    // Message transfer detection
    // --------------------------------------------------------

    assign msg_transfer =
        msg_valid &&
        msg_ready &&
        !rst;

    // --------------------------------------------------------
    // Registered event generation
    // --------------------------------------------------------

    // Each event is asserted in the cycle AFTER the edge
    // at which its corresponding message is consumed.

    always @(posedge clk) begin

        if (rst) begin

            ev_quote    <= 1'b0;
            ev_trade    <= 1'b0;
            ev_config   <= 1'b0;
            ev_unknown  <= 1'b0;
            ev_badfield <= 1'b0;

        end else begin

            // Default: clear all event pulses every cycle.
            ev_quote    <= 1'b0;
            ev_trade    <= 1'b0;
            ev_config   <= 1'b0;
            ev_unknown  <= 1'b0;
            ev_badfield <= 1'b0;

            if (msg_transfer) begin

                // --------------------------------------------
                // Quote message
                // --------------------------------------------

                if (is_quote) begin

                    if (fields_valid)
                        ev_quote <= 1'b1;
                    else
                        ev_badfield <= 1'b1;

                end

                // --------------------------------------------
                // Trade message
                // --------------------------------------------

                else if (is_trade) begin

                    if (fields_valid)
                        ev_trade <= 1'b1;
                    else
                        ev_badfield <= 1'b1;

                end

                // --------------------------------------------
                // Configuration message
                // --------------------------------------------

                else if (is_config) begin

                    ev_config <= 1'b1;

                end

                // --------------------------------------------
                // Unknown message
                // --------------------------------------------

                else begin

                    ev_unknown <= 1'b1;

                end

            end

        end

    end

endmodule
