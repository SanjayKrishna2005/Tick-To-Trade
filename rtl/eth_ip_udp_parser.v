
module eth_ip_udp_parser (
    input  wire        clk,
    input  wire        rst,

    input  wire [15:0] cfg_dport,

    // Input AXI-Stream
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_data,
    input  wire        s_last,

    // Output AXI-Stream
    output reg         m_valid,
    input  wire        m_ready,
    output reg  [7:0]  m_data,
    output reg         m_last,

    // Frame events
    output reg         ev_good,
    output reg         ev_drop_ethertype,
    output reg         ev_drop_ipver,
    output reg         ev_drop_proto,
    output reg         ev_drop_port,
    output reg         ev_drop_len
);

    // =================================================
    // 1. FSM STATES
    // =================================================

    localparam ST_HEADER  = 2'b00;
    localparam ST_PAYLOAD = 2'b01;
    localparam ST_PAD     = 2'b10;
    localparam ST_DROP    = 2'b11;

    reg [1:0] state;

    // =================================================
    // 2. HEADER REGISTERS
    // =================================================

    reg [5:0] byte_count;

    reg [7:0] eth_hi;

    reg [7:0] ip_len_hi;
    reg [15:0] ip_len;

    reg [7:0] port_hi;

    reg [7:0] udp_len_hi;

    reg [15:0] payload_remaining;

    // Drop reason encoding
    localparam DROP_ETHERTYPE = 3'd1;
    localparam DROP_IPVER     = 3'd2;
    localparam DROP_PROTO     = 3'd3;
    localparam DROP_PORT      = 3'd4;
    localparam DROP_LEN       = 3'd5;

    reg [2:0] drop_reason;

    // =================================================
    // 3. LENGTH COMPARISON
    // =================================================

    wire [15:0] udp_len_current;

    wire [16:0] ip_len_extended;
    wire [16:0] udp_len_plus20;

    assign udp_len_current = {udp_len_hi, s_data};

    assign ip_len_extended = {1'b0, ip_len};

    assign udp_len_plus20 =
        {1'b0, udp_len_current} + 17'd20;

    // =================================================
    // 4. HEADER VALIDATION
    // =================================================

    reg       fail_now;
    reg [2:0] fail_code;

    always @(*) begin

        fail_now  = 1'b0;
        fail_code = 3'd0;

        case (byte_count)

            // -----------------------------------------
            // EtherType: bytes 12 and 13
            // -----------------------------------------

            6'd13: begin

                if ({eth_hi, s_data} != 16'h0800) begin
                    fail_now  = 1'b1;
                    fail_code = DROP_ETHERTYPE;
                end

            end

            // -----------------------------------------
            // IPv4 Version / IHL: byte 14
            // -----------------------------------------

            6'd14: begin

                if (s_data != 8'h45) begin
                    fail_now  = 1'b1;
                    fail_code = DROP_IPVER;
                end

            end

            // -----------------------------------------
            // IP Protocol: byte 23
            // -----------------------------------------

            6'd23: begin

                if (s_data != 8'd17) begin
                    fail_now  = 1'b1;
                    fail_code = DROP_PROTO;
                end

            end

            // -----------------------------------------
            // UDP Destination Port: bytes 36 and 37
            // -----------------------------------------

            6'd37: begin

                if ({port_hi, s_data} != cfg_dport) begin
                    fail_now  = 1'b1;
                    fail_code = DROP_PORT;
                end

            end

            // -----------------------------------------
            // UDP Length: bytes 38 and 39
            // -----------------------------------------

            6'd39: begin

                if (ip_len_extended != udp_len_plus20) begin

                    fail_now  = 1'b1;
                    fail_code = DROP_LEN;

                end

                else if (udp_len_current < 16'd9) begin

                    fail_now  = 1'b1;
                    fail_code = DROP_LEN;

                end

            end

            default: begin

                fail_now  = 1'b0;
                fail_code = 3'd0;

            end

        endcase

    end

    // =================================================
    // 5. INPUT / OUTPUT HANDSHAKE
    // =================================================

    // One-entry registered output buffer.
    // Accept input if the output buffer is empty
    // or its current contents are being consumed.

    assign s_ready = !m_valid || m_ready;

    wire input_transfer;
    wire output_transfer;

    assign input_transfer  = s_valid && s_ready;
    assign output_transfer = m_valid && m_ready;

    // =================================================
    // 6. OUTPUT REGISTER
    // =================================================

    always @(posedge clk) begin

        if (rst) begin

            m_valid <= 1'b0;

        end

        else begin

            // Consume current output byte
            if (output_transfer) begin
                m_valid <= 1'b0;
            end

            // Load next payload byte
            if (input_transfer && state == ST_PAYLOAD) begin

                m_valid <= 1'b1;
                m_data  <= s_data;

                // Declared final payload byte
                if (payload_remaining == 16'd1) begin
                    m_last <= 1'b1;
                end

                // Truncated frame: final received byte
                else if (s_last) begin
                    m_last <= 1'b1;
                end

                else begin
                    m_last <= 1'b0;
                end

            end

        end

    end

    // =================================================
    // 7. MAIN PARSER FSM
    // =================================================

    always @(posedge clk) begin

        if (rst) begin

            state             <= ST_HEADER;
            byte_count        <= 6'd0;

            eth_hi            <= 8'd0;

            ip_len_hi         <= 8'd0;
            ip_len            <= 16'd0;

            port_hi           <= 8'd0;
            udp_len_hi        <= 8'd0;

            payload_remaining <= 16'd0;

            drop_reason       <= 3'd0;

            ev_good           <= 1'b0;
            ev_drop_ethertype <= 1'b0;
            ev_drop_ipver     <= 1'b0;
            ev_drop_proto     <= 1'b0;
            ev_drop_port      <= 1'b0;
            ev_drop_len       <= 1'b0;

        end

        else begin

            // -----------------------------------------
            // Clear event pulses every cycle
            // -----------------------------------------

            ev_good           <= 1'b0;
            ev_drop_ethertype <= 1'b0;
            ev_drop_ipver     <= 1'b0;
            ev_drop_proto     <= 1'b0;
            ev_drop_port      <= 1'b0;
            ev_drop_len       <= 1'b0;

            if (input_transfer) begin

                case (state)

                    // =================================
                    // STATE 1: HEADER
                    // =================================

                    ST_HEADER: begin

                        // Capture required header fields

                        case (byte_count)

                            6'd12: eth_hi <= s_data;

                            6'd16: ip_len_hi <= s_data;

                            6'd17:
                                ip_len <= {ip_len_hi, s_data};

                            6'd36: port_hi <= s_data;

                            6'd38: udp_len_hi <= s_data;

                            default: begin
                            end

                        endcase

                        // ---------------------------------
                        // Header validation failure
                        // ---------------------------------

                        if (fail_now) begin

                            drop_reason <= fail_code;

                            if (s_last) begin

                                // Failure and frame end
                                // occur on the same byte.

                                state      <= ST_HEADER;
                                byte_count <= 6'd0;

                                case (fail_code)

                                    DROP_ETHERTYPE:
                                        ev_drop_ethertype <= 1'b1;

                                    DROP_IPVER:
                                        ev_drop_ipver <= 1'b1;

                                    DROP_PROTO:
                                        ev_drop_proto <= 1'b1;

                                    DROP_PORT:
                                        ev_drop_port <= 1'b1;

                                    DROP_LEN:
                                        ev_drop_len <= 1'b1;

                                    default: begin
                                    end

                                endcase

                            end

                            else begin

                                // Preserve the first failure
                                // and discard until frame end.

                                state <= ST_DROP;

                            end

                        end

                        // ---------------------------------
                        // No header failure
                        // ---------------------------------

                        else begin

                            // A frame ending before payload
                            // begins is a length failure.

                            if (s_last) begin

                                state      <= ST_HEADER;
                                byte_count <= 6'd0;

                                ev_drop_len <= 1'b1;

                            end

                            // Capture complete UDP length
                            // and calculate payload length.

                            else if (byte_count == 6'd39) begin

                                payload_remaining <=
                                    udp_len_current - 16'd8;

                                byte_count <= byte_count + 1'b1;

                            end

                            // Header ends at byte 41.
                            // Payload starts at byte 42.

                            else if (byte_count == 6'd41) begin

                                state <= ST_PAYLOAD;

                            end

                            else begin

                                byte_count <= byte_count + 1'b1;

                            end

                        end

                    end

                    // =================================
                    // STATE 2: PAYLOAD
                    // =================================

                    ST_PAYLOAD: begin

                        // payload_remaining is guaranteed
                        // to be at least 1 here.

                        if (payload_remaining == 16'd1) begin

                            // Last declared payload byte

                            payload_remaining <= 16'd0;

                            if (s_last) begin

                                // Frame ends with payload

                                ev_good    <= 1'b1;
                                state      <= ST_HEADER;
                                byte_count <= 6'd0;

                            end

                            else begin

                                // Payload complete.
                                // Remaining bytes are padding.

                                state <= ST_PAD;

                            end

                        end

                        else begin

                            payload_remaining <=
                                payload_remaining - 1'b1;

                            if (s_last) begin

                                // Frame ended before the
                                // declared payload completed.

                                ev_drop_len <= 1'b1;

                                state      <= ST_HEADER;
                                byte_count <= 6'd0;

                            end

                        end

                    end

                    // =================================
                    // STATE 3: PADDING
                    // =================================

                    ST_PAD: begin

                        // Discard every byte after the
                        // declared UDP payload.

                        if (s_last) begin

                            ev_good    <= 1'b1;
                            state      <= ST_HEADER;
                            byte_count <= 6'd0;

                        end

                    end

                    // =================================
                    // STATE 4: DROP
                    // =================================

                    ST_DROP: begin

                        // Consume invalid frame completely.
                        // Do not forward any payload.

                        if (s_last) begin

                            state      <= ST_HEADER;
                            byte_count <= 6'd0;

                            case (drop_reason)

                                DROP_ETHERTYPE:
                                    ev_drop_ethertype <= 1'b1;

                                DROP_IPVER:
                                    ev_drop_ipver <= 1'b1;

                                DROP_PROTO:
                                    ev_drop_proto <= 1'b1;

                                DROP_PORT:
                                    ev_drop_port <= 1'b1;

                                DROP_LEN:
                                    ev_drop_len <= 1'b1;

                                default: begin
                                end

                            endcase

                        end

                    end

                    // =================================
                    // DEFAULT RECOVERY
                    // =================================

                    default: begin

                        state      <= ST_HEADER;
                        byte_count <= 6'd0;

                    end

                endcase

            end

        end

    end

endmodule
