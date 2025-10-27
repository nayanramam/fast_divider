
 // tb_flip_flop.sv
`timescale 1ns/1ps

module flipflop_tb;
  // DUT signals
  logic clk_i, reset_i, d_i;
  logic q_o;

  // Instantiate DUT
  flip_flop dut (.*);

  // Clock gen
  localparam int CLK_PER = 10; // ns
  initial clk_i = 0;
  always #(CLK_PER/2) clk_i = ~clk_i;

  // Handy "one full clock" tick
  task automatic tick;
    @(negedge clk_i); @(posedge clk_i);
  endtask

  initial begin
    $dumpfile("waves.vcd"); $dumpvars(0, flipflop_tb);

    // 1) Reset brings q_o low
    reset_i = 1; d_i = 0;
    repeat (2) tick();
    if (q_o !== 1'b0) $fatal(1, "q_o not 0 during reset");

    // 2) Release reset and capture '1'
    reset_i = 0; d_i = 1;
    tick();
    if (q_o !== 1'b1) $fatal(1, "q_o didn't capture 1 on posedge");

    // 3) Capture '0'
    d_i = 0;
    tick();
    if (q_o !== 1'b0) $fatal(1, "q_o didn't capture 0 on posedge");

    // 4) Async reset in the middle of a cycle
    d_i = 1;
    @(negedge clk_i); reset_i = 1; // assert async reset between edges
    #1;
    if (q_o !== 1'b0) $fatal(1, "q_o not cleared by async reset");
    @(posedge clk_i); reset_i = 0;

    // 5) Recover and capture again
    d_i = 1;
    tick();
    if (q_o !== 1'b1) $fatal(1, "q_o didn't recover after reset");

    $display("PASS: flip_flop basic checks OK");
    $finish;
  end
endmodule


// iverilog -g2012 -o flipflop_sim flipflop_tb.sv flipflop.sv
// vvp flipflop_sim