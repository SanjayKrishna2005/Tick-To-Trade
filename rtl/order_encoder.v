// -----------------------------------------------------------------------------
// Module: order_encoder
//
// Purpose:
//   Accept an ORD token, assign a consecutive order ID, and serialize the
//   resulting 16-byte order message onto a byte-wide output interface.
//
// Specification:
//   spec_system.md       sections 1.1, 3.2, 5.3, 7
//   spec_order_encoder.md sections 1 through 10
//
// Language: Verilog-2001
// Reset:    synchronous, active-high
// -----------------------------------------------------------------------------

module order_encoder (
    input  wire        clk,
    input  wire        rst,

    // ORD input interface
    input  wire        o_valid,
    output wire        o_ready,
    input  wire [2:0]  o_sym,
    input  wire        o_side,
    input  wire [31:0] o_px,
    input  wire [31:0] o_qty,
    input  wire [31:0] o_ts,

    // BYTE output interface
    output wire        m_valid,
    input  wire        m_ready,
    output reg  [7:0]  m_data,
    output wire        m_last,

    // First-byte latency strobe and timestamp
    output wire        first_byte_xfer,
    output wire [31:0] first_byte_ts,

    // One-cycle order-completion event
    output reg         ev_order_done
);

    // -------------------------------------------------------------------------
    // Encoder state
    // -------------------------------------------------------------------------

    // busy_reg is the sole state bit controlling ORD acceptance.
    // The encoder is idle exactly when busy_reg is zero.
    reg        busy_reg;
    reg  [3:0] byte_idx;

    // Latched order fields
    reg  [2:0]  order_sym_reg;
    reg         order_side_reg;
    reg  [31:0] order_px_reg;
    reg  [31:0] order_qty_reg;
    reg  [31:0] order_ts_reg;
    reg  [31:0] order_id_reg;

    // Next ID assigned on the next accepted ORD token.
    reg  [31:0] next_order_id;

    // -------------------------------------------------------------------------
    // Interface control
    // -------------------------------------------------------------------------

    // E1: ready depends only on encoder state.
    assign o_ready = ~busy_reg;

    // E4: output is valid throughout serialization.
    assign m_valid = busy_reg;

    // E4: last is asserted only for byte index 15.
    assign m_last = busy_reg && (byte_idx == 4'd15);

    // E6: combinational strobe for the transfer of byte zero.
    assign first_byte_xfer = m_valid && m_ready && (byte_idx == 4'd0);

    // E6: timestamp belongs to the currently serialized order.
    assign first_byte_ts = order_ts_reg;

    // -------------------------------------------------------------------------
    // Byte selection
    // -------------------------------------------------------------------------

    // The selected byte changes only when byte_idx advances. Since byte_idx
    // advances only on an output transfer, m_data is stable during a stall.
    always @(*) begin
        m_data = 8'h00;

        case (byte_idx)
            4'd0:  m_data = 8'h10;
            4'd1:  m_data = {5'b00000, order_sym_reg};
            4'd2:  m_data = {7'b0000000, order_side_reg};
            4'd3:  m_data = 8'h00;

            // Price: big-endian, bytes 4 through 7.
            4'd4:  m_data = order_px_reg[31:24];
            4'd5:  m_data = order_px_reg[23:16];
            4'd6:  m_data = order_px_reg[15:8];
            4'd7:  m_data = order_px_reg[7:0];

            // Quantity: big-endian, bytes 8 through 11.
            4'd8:  m_data = order_qty_reg[31:24];
            4'd9:  m_data = order_qty_reg[23:16];
            4'd10: m_data = order_qty_reg[15:8];
            4'd11: m_data = order_qty_reg[7:0];

            // Order ID: big-endian, bytes 12 through 15.
            4'd12: m_data = order_id_reg[31:24];
            4'd13: m_data = order_id_reg[23:16];
            4'd14: m_data = order_id_reg[15:8];
            4'd15: m_data = order_id_reg[7:0];

            default: m_data = 8'h00;
        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential control
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            busy_reg       <= 1'b0;
            byte_idx       <= 4'd0;

            order_sym_reg  <= 3'd0;
            order_side_reg <= 1'b0;
            order_px_reg   <= 32'd0;
            order_qty_reg  <= 32'd0;
            order_ts_reg   <= 32'd0;
            order_id_reg   <= 32'd0;

            next_order_id  <= 32'd1;

            ev_order_done  <= 1'b0;
        end else begin
            // Default low; asserted only after the final-byte transfer edge.
            ev_order_done <= 1'b0;

            if (!busy_reg) begin
                // Accept exactly one ORD token while idle.
                if (o_valid) begin
                    order_sym_reg  <= o_sym;
                    order_side_reg <= o_side;
                    order_px_reg   <= o_px;
                    order_qty_reg  <= o_qty;
                    order_ts_reg   <= o_ts;
                    order_id_reg   <= next_order_id;

                    // Consume this ID at ORD acceptance, not during output.
                    next_order_id <= next_order_id + 32'd1;

                    // Byte zero is visible in the cycle after this edge.
                    byte_idx <= 4'd0;
                    busy_reg <= 1'b1;
                end
            end else begin
                // Advance only when the current output byte transfers.
                if (m_valid && m_ready) begin
                    if (byte_idx == 4'd15) begin
                        // Final byte transferred: become idle next cycle.
                        busy_reg      <= 1'b0;
                        byte_idx      <= 4'd0;
                        ev_order_done <= 1'b1;
                    end else begin
                        byte_idx <= byte_idx + 4'd1;
                    end
                end
            end
        end
    end

endmodule
