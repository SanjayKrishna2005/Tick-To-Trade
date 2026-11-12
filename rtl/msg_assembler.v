module msg_assembler (
    input  wire        clk,
    input  wire        rst,

    // BYTE input interface
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_data,
    input  wire        s_last,

    // MSG output interface
    output reg         msg_valid,
    input  wire        msg_ready,
    output reg  [7:0]  msg_type,
    output reg  [7:0]  msg_sym,
    output reg  [7:0]  msg_side,
    output reg  [31:0] msg_px,
    output reg  [31:0] msg_qty,

    // One-cycle packet classification event pulses
    output reg         ev_pkt_good,
    output reg         ev_pkt_bad_count,
    output reg         ev_pkt_bad_len
);

    // -------------------------------------------------------------------------
    // Input backpressure
    // -------------------------------------------------------------------------
    assign s_ready = (~msg_valid) | msg_ready;

    // -------------------------------------------------------------------------
    // Packet and message parsing state
    // -------------------------------------------------------------------------

    reg [6:0] byte_idx;
    reg [6:0] pkt_len;

    reg [7:0] n_msb;
    reg [3:0] msg_count;
    reg       count_valid;

    reg [3:0] msg_index;
    reg [3:0] msg_offset;

    reg [7:0]  work_type;
    reg [7:0]  work_sym;
    reg [7:0]  work_side;
    reg [31:0] px_shift;
    reg [31:0] qty_shift;

    // Expected length minus one = 7 + 12*n.
    wire [6:0] msg_count_ext;
    wire [6:0] msg_count_times_12;
    wire [6:0] expected_len_minus1;

    assign msg_count_ext       = {3'b000, msg_count};
    assign msg_count_times_12  = (msg_count_ext << 3) +
                                 (msg_count_ext << 2);
    assign expected_len_minus1 = 7'd7 + msg_count_times_12;

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin

            msg_valid       <= 1'b0;
            msg_type        <= 8'h00;
            msg_sym         <= 8'h00;
            msg_side        <= 8'h00;
            msg_px          <= 32'h00000000;
            msg_qty         <= 32'h00000000;

            ev_pkt_good      <= 1'b0;
            ev_pkt_bad_count <= 1'b0;
            ev_pkt_bad_len   <= 1'b0;

            byte_idx        <= 7'd0;
            pkt_len         <= 7'd0;
            n_msb           <= 8'h00;
            msg_count       <= 4'd0;
            count_valid     <= 1'b0;

            msg_index       <= 4'd0;
            msg_offset      <= 4'd0;

            work_type       <= 8'h00;
            work_sym        <= 8'h00;
            work_side       <= 8'h00;
            px_shift        <= 32'h00000000;
            qty_shift       <= 32'h00000000;

        end else begin

            // Default event values: events are one-cycle pulses.
            ev_pkt_good      <= 1'b0;
            ev_pkt_bad_count <= 1'b0;
            ev_pkt_bad_len   <= 1'b0;

            // Retire the current MSG token.
            if (msg_valid && msg_ready) begin
                msg_valid <= 1'b0;
            end

            // Accept an input byte only when the output slot is available.
            if (s_valid && s_ready) begin

                // -------------------------------------------------------------
                // Packet byte count and byte position
                // -------------------------------------------------------------

                if (pkt_len < 7'd105) begin
                    pkt_len <= pkt_len + 7'd1;
                end

                if (s_last) begin
                    byte_idx <= 7'd0;
                end else if (byte_idx < 7'd105) begin
                    byte_idx <= byte_idx + 7'd1;
                end

                // -------------------------------------------------------------
                // Header extraction
                // -------------------------------------------------------------

                case (byte_idx)

                    7'd4: begin
                        n_msb <= s_data;
                    end

                    7'd5: begin
                        if ((n_msb == 8'h00) &&
                            (s_data >= 8'd1) &&
                            (s_data <= 8'd8)) begin

                            count_valid <= 1'b1;
                            msg_count   <= s_data[3:0];

                        end else begin

                            count_valid <= 1'b0;
                            msg_count   <= 4'd0;

                        end
                    end

                    7'd7: begin
                        msg_index  <= 4'd0;
                        msg_offset <= 4'd0;
                    end

                    default: begin
                    end

                endcase

                // -------------------------------------------------------------
                // Message extraction
                // -------------------------------------------------------------

                if ((byte_idx >= 7'd8) && count_valid &&
                    (msg_index < msg_count)) begin

                    case (msg_offset)

                        4'd0: begin
                            work_type <= s_data;
                            msg_offset <= 4'd1;
                        end

                        4'd1: begin
                            work_sym <= s_data;
                            msg_offset <= 4'd2;
                        end

                        4'd2: begin
                            work_side <= s_data;
                            msg_offset <= 4'd3;
                        end

                        4'd3: begin
                            // Reserved byte.
                            msg_offset <= 4'd4;
                        end

                        4'd4,
                        4'd5,
                        4'd6,
                        4'd7: begin

                            px_shift <= {px_shift[23:0], s_data};
                            msg_offset <= msg_offset + 4'd1;

                        end

                        4'd8,
                        4'd9,
                        4'd10: begin

                            qty_shift <= {qty_shift[23:0], s_data};
                            msg_offset <= msg_offset + 4'd1;

                        end

                        4'd11: begin

                            // Complete message: publish the MSG transaction.
                            msg_type <= work_type;
                            msg_sym  <= work_sym;
                            msg_side <= work_side;
                            msg_px   <= px_shift;
                            msg_qty  <= {qty_shift[23:0], s_data};

                            msg_valid <= 1'b1;

                            msg_index  <= msg_index + 4'd1;
                            msg_offset <= 4'd0;

                        end

                        default: begin
                            msg_offset <= 4'd0;
                        end

                    endcase
                end

                // -------------------------------------------------------------
                // Packet termination and classification
                // -------------------------------------------------------------

                if (s_last) begin

                    if (byte_idx < 7'd5) begin

                        // P < 6: count field incomplete.
                        ev_pkt_bad_len <= 1'b1;

                    end else if (byte_idx == 7'd5) begin

                        // Packet ends on the low count byte.
                        if ((n_msb == 8'h00) &&
                            (s_data >= 8'd1) &&
                            (s_data <= 8'd8)) begin

                            ev_pkt_bad_len <= 1'b1;

                        end else begin

                            ev_pkt_bad_count <= 1'b1;

                        end

                    end else if (!count_valid) begin

                        ev_pkt_bad_count <= 1'b1;

                    end else if (pkt_len == expected_len_minus1) begin

                        ev_pkt_good <= 1'b1;

                    end else begin

                        ev_pkt_bad_len <= 1'b1;

                    end

                    // Start a fresh packet after this accepted s_last beat.
                    byte_idx    <= 7'd0;
                    pkt_len     <= 7'd0;
                    n_msb       <= 8'h00;
                    msg_count   <= 4'd0;
                    count_valid <= 1'b0;

                    msg_index   <= 4'd0;
                    msg_offset  <= 4'd0;

                    work_type  <= 8'h00;
                    work_sym   <= 8'h00;
                    work_side  <= 8'h00;
                    px_shift   <= 32'h00000000;
                    qty_shift  <= 32'h00000000;

                end
            end
        end
    end

endmodule
