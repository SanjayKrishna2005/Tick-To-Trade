// Standalone tests for axis_slice / axis_register (same port list).
// compile: iverilog -g2005 -DDUT=axis_register -s tb_unit -o u.vvp <rtl>.v tb_unit.v
// plusargs: +PV=<%input valid> +PR=<%output ready> +SEED=n +N=beats
`timescale 1ns/1ps
module tb_unit;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg s_valid = 0; reg [7:0] s_data = 0; reg s_last = 0; wire s_ready;
  wire m_valid; wire [7:0] m_data; wire m_last; reg m_ready = 0;
  `DUT dut(.clk(clk),.rst(rst),.s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_last(s_last),
           .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_last(m_last));
  integer PV, PR, SEED, N;
  integer sent = 0, got = 0, errs = 0, cyc = 0, last_cyc = 0;
  reg [8:0] fifo [0:65535];
  reg [8:0] cur;
  reg pv_valid; reg [7:0] pd; reg pl;
  reg prev_hold; reg [8:0] prev_beat; reg prev_rst;
  integer phase;
  integer r; integer rs;
  function integer rnd; input integer m; integer x; begin x = $random(rs); if (x < 0) x = -x; rnd = x % m; end endfunction
  task fail; input [255:0] msg; begin errs = errs + 1; if (errs < 8) $display("ERROR @%0d: %0s", cyc, msg); end endtask

  // drive on negedge
  always @(negedge clk) begin
    cyc = cyc + 1;
    if (!rst) begin
      // keep a presented beat stable until accepted (valid must not drop)
      if (!(s_valid && !s_ready_q)) begin
        if (sent < N && (rnd(100)) < PV) begin
          s_valid = 1; s_data = rnd(256); s_last = (rnd(5) == 0);
        end else begin s_valid = 0; s_data = rnd(256); s_last = rnd(2); end
      end
      m_ready = (rnd(100) < PR);
    end
  end
  reg s_ready_q = 1;
  // sample on posedge (before NBA update, values are the pre-edge values)
  always @(posedge clk) begin
    s_ready_q <= s_ready;
    if (rst) begin prev_hold <= 0; end
    else begin
      if (s_valid && s_ready) begin fifo[sent] = {s_data, s_last}; sent = sent + 1; end
      if (m_valid && m_ready) begin
        if (got >= sent) fail("output beat with nothing sent (invented data)");
        else if (fifo[got] !== {m_data, m_last}) begin fail("data/last mismatch"); if (errs<8) $display("   exp %h got %h idx %0d", fifo[got], {m_data,m_last}, got); end
        got = got + 1; last_cyc = cyc;
      end
      // hold-while-stalled
      if (prev_hold) begin
        if (!m_valid) fail("m_valid dropped while stalled");
        else if ({m_data, m_last} !== prev_beat) fail("m_data/m_last changed while stalled");
      end
      prev_hold <= m_valid && !m_ready;
      prev_beat <= {m_data, m_last};
      if (m_valid && m_ready) prev_hold <= 0;
    end
  end

  integer i, t0, nx;
  initial begin
    if (!$value$plusargs("PV=%d", PV)) PV = 100;
    if (!$value$plusargs("PR=%d", PR)) PR = 100;
    if (!$value$plusargs("SEED=%d", SEED)) SEED = 1;
    if (!$value$plusargs("N=%d", N)) N = 2000;
    rs = SEED;
    repeat (3) @(posedge clk);
    #1 rst = 0;
    // main run
    t0 = 0;
    while ((got < N) && (cyc < 200000)) @(posedge clk);
    repeat (5) @(posedge clk);
    if (got != N) fail("not all beats came out (lost beats / deadlock)");
    if (sent != N) fail("sender never finished");
    // throughput check: full-rate when PV=PR=100  (one beat per cycle after fill)
    if (PV == 100 && PR == 100) begin
      if (last_cyc > N + 8) begin errs = errs + 1; $display("ERROR: not full throughput: %0d beats took %0d cycles", N, last_cyc); end
    end
    // mid-run reset check
    @(negedge clk); s_valid = 1; s_data = 8'hAA; m_ready = 0; rst = 1;
    @(posedge clk); @(posedge clk); #1;
    if (m_valid !== 1'b0) fail("m_valid not 0 during/after reset");
    @(negedge clk); s_valid = 0; rst = 0; m_ready = 1;
    #1; if (s_ready !== 1'b1) fail("s_ready not 1 after reset");
    @(posedge clk); #1; if (m_valid !== 1'b0) fail("stale beat after reset");
    $display("%s PV=%0d PR=%0d beats=%0d cycles=%0d errors=%0d", `DUTSTR, PV, PR, got, last_cyc, errs);
    $display("RESULT: %s", errs == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
