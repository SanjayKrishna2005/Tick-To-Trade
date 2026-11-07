// -----------------------------------------------------------------------------
// Module: replay_rom
//
// Purpose:
//   Replay a recorded BYTE stream from an inferred 9-bit ROM.
//   Each memory entry is {last, data[7:0]} and is read from HEXFILE.
//
// Specification:
//   spec_replay_rom.md, version 1.0
//   spec_system.md, sections 1.1 and 8
//
// Language: Verilog-2001
// Reset:    synchronous, active-high
// -----------------------------------------------------------------------------

module replay_rom #(
    parameter HEXFILE = "feed.hex",
    parameter N       = 4096
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       loop,

    // BYTE output interface
    output wire       m_valid,
    input  wire       m_ready,
    output wire [7:0] m_data,
    output wire       m_last,

    // Playback completion
    output reg        done
);

    // -------------------------------------------------------------------------
    // ROM storage: each entry is {last, data[7:0]}.
    // -------------------------------------------------------------------------
    reg [8:0] mem [0:N-1];

    initial begin
        $readmemh(HEXFILE, mem);
    end

    // -------------------------------------------------------------------------
    // Address width helper, written in Verilog-2001 (no $clog2 dependency).
    // -------------------------------------------------------------------------
    function integer calc_addr_width;
        input integer value;
        integer temp;
        begin
            temp = value - 1;
            calc_addr_width = 0;
            while (temp > 0) begin
                calc_addr_width = calc_addr_width + 1;
                temp = temp >> 1;
            end
            if (calc_addr_width < 1)
                calc_addr_width = 1;
        end
    endfunction

    localparam ADDR_W = calc_addr_width(N);
    localparam [ADDR_W-1:0] LAST_ADDR = N - 1;

    reg [ADDR_W-1:0] addr;
    reg              running;

    // Registered copy of start for rising-edge detection.
    reg start_d;
    wire start_rise;

    assign start_rise = start && !start_d;

    // -------------------------------------------------------------------------
    // BYTE output
    // -------------------------------------------------------------------------
    assign m_valid = running;
    assign m_data  = mem[addr][7:0];
    assign m_last  = mem[addr][8];

    // -------------------------------------------------------------------------
    // Playback control
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            running <= 1'b0;
            addr    <= {ADDR_W{1'b0}};
            done    <= 1'b0;

            // Sample start during reset so a held-high start does not create
            // a false rising edge immediately after reset is released.
            start_d <= start;
        end
        else begin
            // Edge detector history is updated on every non-reset clock.
            start_d <= start;

            if (running) begin
                // A memory entry advances only when its BYTE transfer occurs.
                // This holds both data and last stable during backpressure.
                if (m_ready) begin
                    if (addr == LAST_ADDR) begin
                        if (loop) begin
                            // Seamless loop: entry 0 is visible next cycle.
                            addr    <= {ADDR_W{1'b0}};
                            running <= 1'b1;
                        end
                        else begin
                            // Pass completed; remain idle and assert done.
                            addr    <= {ADDR_W{1'b0}};
                            running <= 1'b0;
                            done    <= 1'b1;
                        end
                    end
                    else begin
                        addr <= addr + {{(ADDR_W-1){1'b0}}, 1'b1};
                    end
                end
            end
            else begin
                // Start is accepted only while idle and only on a rising edge.
                if (start_rise) begin
                    addr    <= {ADDR_W{1'b0}};
                    running <= 1'b1;
                    done    <= 1'b0;
                end
            end
        end
    end

endmodule
