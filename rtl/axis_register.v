
module axis_register #(
    parameter DATA_W = 8
)(
    input                   clk,
    input                   rst,

    
    input                   s_valid,
    output                  s_ready,
    input  [DATA_W-1:0]     s_data,
    input                   s_last,

    
    output                  m_valid,
    input                   m_ready,
    output [DATA_W-1:0]     m_data,
    output                  m_last
);
    reg [DATA_W:0] main_reg;
    reg [DATA_W:0] skid_reg;


    reg main_valid;
    reg skid_valid;



    reg s_ready_reg;

 

    assign s_ready = s_ready_reg;

    assign m_valid = main_valid;

    assign m_data  = main_reg[DATA_W:1];
    assign m_last  = main_reg[0];



    wire input_transfer;
    wire output_transfer;

    assign input_transfer  = s_valid && s_ready;
    assign output_transfer = m_valid && m_ready;



    always @(posedge clk) begin

        if (rst) begin

            // Clear occupancy
            main_valid <= 1'b0;
            skid_valid <= 1'b0;

            // Buffer can accept input after reset
            s_ready_reg <= 1'b1;

        end

        else begin

            // ----------------------------------------
            // A. MAIN REGISTER MANAGEMENT
            // ----------------------------------------

            if (output_transfer) begin

                if (skid_valid) begin

                    // Promote skid beat to main
                    main_reg  <= skid_reg;
                    main_valid <= 1'b1;

                    skid_valid <= 1'b0;

                end

                else if (input_transfer) begin

                    // Simultaneous output and input
                    // Replace consumed beat
                    main_reg  <= {s_data, s_last};
                    main_valid <= 1'b1;

                end

                else begin

                    // Output consumed, no replacement
                    main_valid <= 1'b0;

                end

            end

            else if (input_transfer) begin

                if (!main_valid) begin

                    // Empty buffer: load main
                    main_reg   <= {s_data, s_last};
                    main_valid <= 1'b1;

                end

                else begin

                    // Main occupied and stalled:
                    // capture additional beat in skid
                    skid_reg  <= {s_data, s_last};
                    skid_valid <= 1'b1;

                end

            end

            // ----------------------------------------
            // B. REGISTERED READY MANAGEMENT
            // ----------------------------------------

            if (input_transfer && main_valid &&
                !output_transfer) begin

                // Skid slot has just been filled
                s_ready_reg <= 1'b0;

            end

            else if (output_transfer && skid_valid) begin

                // Skid beat has been promoted;
                // skid slot is now available
                s_ready_reg <= 1'b1;

            end

        end
    end

endmodule
