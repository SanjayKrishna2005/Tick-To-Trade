// -----------------------------------------------------------------------------
// Module: stats_counters
//
// Purpose:
//   Count independent one-cycle event pulses and expose the counters on a
//   packed output bus.
//
// Specification:
//   spec_stats_counters.md, version 1.0
//   spec_system.md, section 6
//
// Language: Verilog-2001
// Reset:    synchronous, active-high
//
// Packing:
//   Counter i is available at cnt_flat[CNT_W*i +: CNT_W].
//   Counter 0 occupies the least-significant CNT_W bits.
// -----------------------------------------------------------------------------

module stats_counters #(
    parameter CNT_W = 32,
    parameter N_EV  = 23
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire [N_EV-1:0]              ev_flat,
    output wire [(N_EV*CNT_W)-1:0]      cnt_flat
);

    // One independent counter for each event input.
    reg [CNT_W-1:0] counters [0:N_EV-1];

    genvar i;
    generate
        for (i = 0; i < N_EV; i = i + 1) begin : GEN_EVENT_COUNTER

            // Pack counter i into its specified output-bus slice.
            assign cnt_flat[(CNT_W*i) +: CNT_W] = counters[i];

            // Synchronous reset; otherwise count this event independently.
            // Natural fixed-width arithmetic provides modulo-2**CNT_W wrap.
            always @(posedge clk) begin
                if (rst) begin
                    counters[i] <= {CNT_W{1'b0}};
                end else if (ev_flat[i]) begin
                    counters[i] <= counters[i] + {{(CNT_W-1){1'b0}}, 1'b1};
                end
            end

        end
    endgenerate

endmodule
