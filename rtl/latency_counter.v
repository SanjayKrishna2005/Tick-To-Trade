// -----------------------------------------------------------------------------
// Module: latency_counter
// Description:
//   Free-running 32-bit cycle counter and on-chip decision-latency statistics.
//
// Specification references:
//   - spec_system.md: K1, K2, K6, K7 and Section 7
//   - spec_latency_counter.md: Sections 1 through 5
//
// Language: Verilog-2001
// Reset: synchronous, active-high
// -----------------------------------------------------------------------------

module latency_counter #(
    parameter [31:0] NOW_RESET = 32'd0
) (
    input  wire        clk,
    input  wire        rst,

    output reg  [31:0] now,

    input  wire        meas_valid,
    input  wire [31:0] meas_ts,

    output reg  [31:0] lat_last,
    output reg  [31:0] lat_min,
    output reg  [31:0] lat_max,
    output reg  [63:0] lat_sum,
    output reg  [31:0] lat_count
);

    // Unsigned 32-bit modulo subtraction. Because this is evaluated from the
    // current value of `now`, the measurement uses the value visible during
    // the cycle ending at the sampling edge (not the incremented value).
    wire [31:0] measured_latency;
    assign measured_latency = now - meas_ts;

    always @(posedge clk) begin
        if (rst) begin
            // Reset has priority over a simultaneous measurement strobe.
            now       <= NOW_RESET;
            lat_last  <= 32'd0;
            lat_min   <= 32'hFFFFFFFF;
            lat_max   <= 32'd0;
            lat_sum   <= 64'd0;
            lat_count <= 32'd0;
        end else begin
            // Free-running cycle counter; natural 32-bit wrap-around.
            now <= now + 32'd1;

            // meas_valid is a strobe sampled at this edge. All statistics
            // become visible in the cycle immediately following this edge.
            if (meas_valid) begin
                lat_last  <= measured_latency;

                if (measured_latency < lat_min)
                    lat_min <= measured_latency;

                if (measured_latency > lat_max)
                    lat_max <= measured_latency;

                // Explicit zero extension prevents truncation of the sum.
                lat_sum   <= lat_sum + {32'd0, measured_latency};
                lat_count <= lat_count + 32'd1;
            end
        end
    end

endmodule
