
module sync_fifo #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4
)(
    input  wire                  clk,
    input  wire                  rst,

    // Input interface
    input  wire                  s_valid,
    output wire                  s_ready,
    input  wire [DATA_W-1:0]     s_data,
    input  wire                  s_last,

    // Output interface
    output wire                  m_valid,
    input  wire                  m_ready,
    output wire [DATA_W-1:0]     m_data,
    output wire                  m_last,

    // Occupancy
    output wire [ADDR_W:0]       level
);

    // ------------------------------------------------
    // 1. FIFO PARAMETERS
    // ------------------------------------------------

    localparam DEPTH = (1 << ADDR_W);

    // ------------------------------------------------
    // 2. STORAGE
    // ------------------------------------------------

    // Each memory location stores {last, data}
    reg [DATA_W:0] mem [0:DEPTH-1];

    // Circular buffer pointers
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;

    // Number of beats currently stored
    reg [ADDR_W:0] count;

    // ------------------------------------------------
    // 3. STATUS SIGNALS
    // ------------------------------------------------

    assign level = count;

    // Ready when FIFO is not full
    assign s_ready = (count != DEPTH);

    // Valid when FIFO is not empty
    assign m_valid = (count != 0);

    // First-word fall-through:
    // Directly expose the oldest stored beat
    assign m_data = mem[rd_ptr][DATA_W-1:0];
    assign m_last = mem[rd_ptr][DATA_W];

    // ------------------------------------------------
    // 4. TRANSFER CONDITIONS
    // ------------------------------------------------

    wire input_transfer;
    wire output_transfer;

    assign input_transfer  = s_valid && s_ready;
    assign output_transfer = m_valid && m_ready;

    // ------------------------------------------------
    // 5. FIFO SEQUENTIAL LOGIC
    // ------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            // Synchronous reset
            wr_ptr <= {ADDR_W{1'b0}};
            rd_ptr <= {ADDR_W{1'b0}};
            count  <= {(ADDR_W+1){1'b0}};

        end

        else begin

            // ----------------------------------------
            // WRITE OPERATION
            // ----------------------------------------

            if (input_transfer) begin

                mem[wr_ptr] <= {s_last, s_data};

                wr_ptr <= wr_ptr + 1'b1;

            end

            // ----------------------------------------
            // READ OPERATION
            // ----------------------------------------

            if (output_transfer) begin

                rd_ptr <= rd_ptr + 1'b1;

            end

            // ----------------------------------------
            // OCCUPANCY COUNTER
            // ----------------------------------------

            case ({input_transfer, output_transfer})

                2'b10: count <= count + 1'b1;

                2'b01: count <= count - 1'b1;

                2'b11: count <= count;

                2'b00: count <= count;

                default: count <= count;

            endcase

        end

    end

endmodule
