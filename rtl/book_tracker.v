// -----------------------------------------------------------------------------
// Module: book_tracker
//
// Purpose:
//   Maintain bid/ask price and quantity for 8 symbols. For every accepted
//   quote, update the quoted side and emit one BOOK token containing the quote
//   and the previously stored values of the opposite side.
//
// Specification:
//   spec_system.md       sections 1, 2, 3.3 and 5
//   spec_book_tracker.md sections 1 through 11
//
// Language: Verilog-2001
// Reset:    synchronous, active-high
// -----------------------------------------------------------------------------

module book_tracker (
    input  wire        clk,
    input  wire        rst,

    // QUOTE input interface
    input  wire        q_valid,
    output wire        q_ready,
    input  wire [2:0]  q_sym,
    input  wire        q_side,
    input  wire [31:0] q_px,
    input  wire [31:0] q_qty,
    input  wire [31:0] q_ts,

    // BOOK output interface
    output reg         b_valid,
    input  wire        b_ready,
    output reg  [2:0]  b_sym,
    output reg         b_side,
    output reg  [31:0] b_px,
    output reg  [31:0] b_qty,
    output reg  [31:0] b_opp_px,
    output reg  [31:0] b_opp_qty,
    output reg  [31:0] b_ts,

    // Busy indication
    output wire        busy,

    // Combinational debug read port
    input  wire [2:0]  rd_sym,
    output wire [31:0] rd_bid_px,
    output wire [31:0] rd_bid_qty,
    output wire [31:0] rd_ask_px,
    output wire [31:0] rd_ask_qty
);

    // -------------------------------------------------------------------------
    // Book storage: one bid and one ask level for each of 8 symbols.
    // A quantity of zero represents no liquidity on that side.
    // -------------------------------------------------------------------------

    reg [31:0] bid_px  [0:7];
    reg [31:0] bid_qty [0:7];
    reg [31:0] ask_px  [0:7];
    reg [31:0] ask_qty [0:7];

    integer i;

    // -------------------------------------------------------------------------
    // Handshake and status signals
    // -------------------------------------------------------------------------

    // The input can advance if the output slot is empty or its current token
    // will be consumed on this clock edge. This is independent of q_valid.
    assign q_ready = (~b_valid) | b_ready;

    // Busy is exactly the occupancy of the one-entry BOOK output slot.
    assign busy = b_valid;

    // -------------------------------------------------------------------------
    // Debug read port (combinational)
    // -------------------------------------------------------------------------

    assign rd_bid_px  = bid_px[rd_sym];
    assign rd_bid_qty = bid_qty[rd_sym];
    assign rd_ask_px  = ask_px[rd_sym];
    assign rd_ask_qty = ask_qty[rd_sym];

    // -------------------------------------------------------------------------
    // Sequential book update and one-entry BOOK output stage
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin

            // Clear the output token and its payload.
            b_valid   <= 1'b0;
            b_sym     <= 3'b000;
            b_side    <= 1'b0;
            b_px      <= 32'h00000000;
            b_qty     <= 32'h00000000;
            b_opp_px  <= 32'h00000000;
            b_opp_qty <= 32'h00000000;
            b_ts      <= 32'h00000000;

            // Clear all 8 symbols, both sides, after synchronous reset.
            for (i = 0; i < 8; i = i + 1) begin
                bid_px[i]  <= 32'h00000000;
                bid_qty[i] <= 32'h00000000;
                ask_px[i]  <= 32'h00000000;
                ask_qty[i] <= 32'h00000000;
            end

        end else begin

            // Retire the current BOOK token when the downstream accepts it.
            // A simultaneous accepted quote below can refill the slot on this
            // same edge, keeping one-quote-per-cycle throughput.
            if (b_valid && b_ready) begin
                b_valid <= 1'b0;
            end

            // Process each input quote exactly once, on its handshake edge.
            if (q_valid && q_ready) begin

                // Capture the QUOTE fields into the BOOK token.
                b_valid <= 1'b1;
                b_sym   <= q_sym;
                b_side  <= q_side;
                b_px    <= q_px;
                b_qty   <= q_qty;
                b_ts    <= q_ts;

                // Update only the quoted side. The opposite-side token fields
                // read the old array contents because these are nonblocking
                // assignments in the same clocked process (read-before-write).
                if (q_side == 1'b0) begin

                    // Market side 0 = bid. Opposite side is the stored ask.
                    b_opp_px  <= ask_px[q_sym];
                    b_opp_qty <= ask_qty[q_sym];

                    bid_px[q_sym]  <= q_px;
                    bid_qty[q_sym] <= q_qty;

                end else begin

                    // Market side 1 = ask. Opposite side is the stored bid.
                    b_opp_px  <= bid_px[q_sym];
                    b_opp_qty <= bid_qty[q_sym];

                    ask_px[q_sym]  <= q_px;
                    ask_qty[q_sym] <= q_qty;

                end
            end
        end
    end

endmodule
