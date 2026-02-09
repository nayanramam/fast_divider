`timescale 1ns/1ps

module divider_core_tb;

  // clock
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  // reset
  logic rst_n;

  // DUT signals
  logic        start_calc;
  logic [31:0] numerator;
  logic [31:0] denominator;
  logic        done_calc;
  logic [31:0] div_output;
  logic [31:0] div_remainder;

  divider_core dut (
    .clk(clk),
    .rst_n(rst_n),
    .start_calc(start_calc),
    .numerator(numerator),
    .denominator(denominator),
    .done_calc(done_calc),
    .div_output(div_output),
    .div_remainder(div_remainder)
  );

  // expected
  logic [31:0] exp_q, exp_r;

  // cycle counter
  int cycles;

  initial begin
    $monitor("T=%0t clk=%0b start=%0b done=%0b cycles=%0d Q=%0d R=%0d",
             $time, clk, start_calc, done_calc, cycles,
             div_output, div_remainder);
  end

  initial begin
    start_calc  = 0;
    numerator   = 0;
    denominator = 0;
    cycles      = 0;

    // reset
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // ---- TEST ----
    numerator   = 100;
    denominator = 7;
    exp_q = numerator / denominator;
    exp_r = numerator % denominator;

    // start pulse
    @(posedge clk);
    start_calc <= 1;
    @(posedge clk);
    start_calc <= 0;

    // count cycles until done
    cycles = 0;
    while (done_calc == 0) begin
      @(posedge clk);
      cycles++;
    end

    // check math
    if (div_output !== exp_q || div_remainder !== exp_r)
      $error("WRONG RESULT Q=%0d R=%0d expected Q=%0d R=%0d",
             div_output, div_remainder, exp_q, exp_r);

    // print latency
    $display("Quotient = %0d", exp_q);
    $display("Cycles taken = %0d", cycles);

    // sanity check (should be >= quotient)
    if (cycles < exp_q)
      $error("Impossible latency: cycles < quotient");

    $display("TEST DONE");
    $finish;
  end

endmodule
