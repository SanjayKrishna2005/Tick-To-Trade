// Standalone test for replay_rom. compile with -DROMN=<n> -DROMFILE="\"rom.hex\""
`timescale 1ns/1ps
module tb_rom;
  reg clk = 0, rst = 1; always #5 clk = ~clk;
  reg start = 0, loop = 0, m_ready = 0;
  wire m_valid, m_last, done; wire [7:0] m_data;
  replay_rom #(.HEXFILE(`ROMFILE), .N(`ROMN)) dut(.clk(clk),.rst(rst),.start(start),.loop(loop),
      .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_last(m_last),.done(done));
  reg [8:0] exp [0:`ROMN-1];
  integer errs = 0, cyc = 0, idx = 0, passes = 0, rs = 7, PR = 100;
  reg ph; reg [8:0] pb; reg pdone;
  function integer rnd; input integer m; integer x; begin x = $random(rs); if (x<0) x=-x; rnd = x % m; end endfunction
  task fail; input [255:0] m; begin errs = errs + 1; if (errs < 8) $display("ERROR @%0d: %0s", cyc, m); end endtask
  always @(negedge clk) begin cyc = cyc + 1; if (!rst) m_ready = (rnd(100) < PR); end
  always @(posedge clk) if (!rst) begin
    if (m_valid && m_ready) begin
      if ({m_last, m_data} !== exp[idx]) begin fail("byte/last mismatch"); if (errs<8) $display("  idx %0d exp %h got %h", idx, exp[idx], {m_last,m_data}); end
      if (idx == `ROMN-1) begin idx = 0; passes = passes + 1; end else idx = idx + 1;
    end
    if (ph) begin
      if (!m_valid) fail("m_valid dropped while stalled");
      else if ({m_last,m_data} !== pb) fail("data changed while stalled");
    end
    ph <= m_valid && !m_ready; pb <= {m_last, m_data};
  end
  integer k;
  task do_start; begin @(negedge clk); start = 1; @(negedge clk); start = 0; end endtask
  initial begin
    $readmemh(`ROMFILE, exp);
    repeat (3) @(posedge clk); #1 rst = 0;
    // 1. idle before start: nothing comes out
    repeat (5) @(posedge clk); if (m_valid) fail("m_valid before start");
    if (done) fail("done before any pass");
    // 2. one pass, full speed
    PR = 100; loop = 0; do_start;
    while (passes < 1 && cyc < 100000) @(posedge clk);
    repeat (3) @(posedge clk); #1;
    if (!done) fail("done not set after pass");
    if (m_valid) fail("still valid after non-loop pass");
    // 3. second pass with random stalls; start while running must be ignored
    PR = 40; do_start;
    @(posedge clk); #1; if (done && `ROMN > 2) fail("done not cleared on restart");
    repeat (3) begin @(negedge clk); start = 1; @(negedge clk); start = 0; end   // extra pulses while running: ignored
    while (passes < 2 && cyc < 400000) @(posedge clk);
    repeat (3) @(posedge clk); #1;
    if (!done) fail("done not set after pass 2");
    if (m_valid) fail("extra start pulse caused a rerun");
    // 4. loop mode: three passes back to back
    PR = 100; loop = 1; do_start;
    while (passes < 5 && cyc < 400000) @(posedge clk);
    loop = 0;
    while (m_valid && cyc < 400000) @(posedge clk);
    repeat (3) @(posedge clk); #1;
    if (passes < 5 || passes > 6) fail("loop pass count wrong");
    if (!done) fail("done not set after loop ended");
    // 4b. start held HIGH for a long time: exactly one pass (rising edge only)
    PR = 100; loop = 0; k = passes; @(negedge clk); start = 1;
    repeat (`ROMN * 3 + 20) @(posedge clk);
    @(negedge clk); start = 0; repeat (3) @(posedge clk);
    if (passes != k + 1) fail("held-high start must give exactly one pass");
    // 5. reset mid-pass
    PR = 100; do_start; repeat (3) @(posedge clk);
    @(negedge clk); rst = 1; @(negedge clk); @(negedge clk); rst = 0; idx = 0; ph = 0;
    @(posedge clk); #1; if (m_valid) fail("running after reset");
    repeat (4) @(posedge clk); if (m_valid) fail("restarted by itself after reset");
    if (done) fail("done set after reset");
    $display("replay_rom N=%0d passes=%0d errors=%0d", `ROMN, passes, errs);
    $display("RESULT: %s", errs==0 ? "PASS":"FAIL"); $finish;
  end
endmodule
