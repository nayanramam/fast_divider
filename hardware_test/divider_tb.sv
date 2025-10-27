// tb_divider_top.sv
`timescale 1ns/1ps

module tb_divider_top;

  import divider_pkg::*;

  // Clock/Reset
  logic clk, rst;

  // DUT I/O
  logic        valid_i, mode_i, out_type_i;
  logic [31:0] n_i, d_i;
  logic        ready_o;
  logic [31:0] result;
  logic [1:0]  error_o;

  // Instantiate DUT
  divider_top dut (
    .clk_i      (clk),
    .rst_i      (rst),
    .valid_i    (valid_i),
    .mode_i     (mode_i),
    .out_type_i (out_type_i),
    .n_i        (n_i),
    .d_i        (d_i),
    .ready_o    (ready_o),
    .result     (result),
    .error_o    (error_o)
  );

  // Clock: 100 MHz
  initial clk = 0;
  always  #5 clk = ~clk;

  // Reset
  initial begin
    rst = 1;
    valid_i = 0;
    mode_i = 0;
    out_type_i = 0;
    n_i = '0;
    d_i = '0;
    repeat (5) @(posedge clk);
    rst = 0;
  end

  // ------------ Golden Model -------------
  // Icarus: TASK with no early returns
  task automatic ref_calc(
    input  logic        mode,        // 1=unsigned, 0=signed
    input  logic        out_type,    // 1=quotient, 0=remainder
    input  logic [31:0] n, d,
    output logic [31:0] res,
    output logic [1:0]  err
  );
    // defaults
    res = '0;
    err = 2'b00;

    if (d == 32'd0) begin
      err = 2'b01;                    // div-by-zero
      res = (out_type) ? 32'd0 : n;
    end
    else if (!mode && (n == 32'h8000_0000) && (d == 32'hFFFF_FFFF)) begin
      err = 2'b10;                    // INT_MIN / -1 overflow
      res = (out_type) ? 32'hFFFF_FFFF : 32'd0;
    end
    else if (mode) begin
      // Unsigned
      logic [31:0] q = n / d;
      logic [31:0] r = n % d;
      res = (out_type) ? q : r;
    end
    else begin
      // Signed (truncate toward zero; remainder sign follows dividend)
      int signed ns = $signed(n);
      int signed ds = $signed(d);
      int signed qs = ns / ds;
      int signed rs = ns % ds;
      if (out_type)
        res = logic'($unsigned(qs));  // explicit cast back to 32b logic
      else
        res = logic'($unsigned(rs));
    end
  endtask

  // ------------ Sequencer -------------
  int unsigned n_tx = 0;
  int unsigned n_err = 0;

  task automatic do_tx(
    input  logic        mode,
    input  logic        out_type,
    input  logic [31:0] n,
    input  logic [31:0] d,
    input  string       tag = ""
  );
    logic [31:0] exp_res;
    logic [1:0]  exp_err;

    ref_calc(mode, out_type, n, d, exp_res, exp_err);

    // Drive inputs; pulse valid exactly one cycle
    @(posedge clk);
    mode_i     <= mode;
    out_type_i <= out_type;
    n_i        <= n;
    d_i        <= d;
    valid_i    <= 1'b1;

    @(posedge clk);
    valid_i    <= 1'b0;

    // Wait for DUT to begin processing and finish
    wait (ready_o == 1'b0);
    wait (ready_o == 1'b1);

    // Check results
    n_tx++;
    if (result !== exp_res || error_o !== exp_err) begin
      n_err++;
      $display("[%0t] MISMATCH %s mode=%0d out_type=%0d n=0x%08h d=0x%08h -> DUT(res=0x%08h err=%b) REF(res=0x%08h err=%b)",
               $time, tag, mode, out_type, n, d, result, error_o, exp_res, exp_err);
    end else begin
      $display("[%0t] PASS     %s mode=%0d out_type=%0d n=0x%08h d=0x%08h -> res=0x%08h err=%b",
               $time, tag, mode, out_type, n, d, result, error_o);
    end
  endtask

  // ------------ Directed Tests -------------
  task automatic run_directed;
    do_tx(1'b1, 1'b1, 32'd1234, 32'd0, "udiv q /0");
    do_tx(1'b1, 1'b0, 32'd1234, 32'd0, "udiv r /0");
    do_tx(1'b0, 1'b1, 32'hFFFF_FF80, 32'd0, "sdiv q /0");
    do_tx(1'b0, 1'b0, 32'hFFFF_FF80, 32'd0, "sdiv r /0");

    do_tx(1'b1, 1'b1, 32'd100, 32'd7, "udiv q 100/7");
    do_tx(1'b1, 1'b0, 32'd100, 32'd7, "udiv r 100%7");

    do_tx(1'b0, 1'b1, 32'd100, 32'd7, "sdiv q +/+");
    do_tx(1'b0, 1'b0, 32'd100, 32'd7, "sdiv r +/+");

    do_tx(1'b0, 1'b1, 32'hFFFF_FF9C, 32'd7, "sdiv q -100/7");
    do_tx(1'b0, 1'b0, 32'hFFFF_FF9C, 32'd7, "sdiv r -100%7");

    do_tx(1'b0, 1'b1, 32'd100, 32'hFFFF_FFF9, "sdiv q 100/-7");
    do_tx(1'b0, 1'b0, 32'd100, 32'hFFFF_FFF9, "sdiv r 100%-7");

    do_tx(1'b0, 1'b1, 32'hFFFF_FF9C, 32'hFFFF_FFF9, "sdiv q -100/-7");
    do_tx(1'b0, 1'b0, 32'hFFFF_FF9C, 32'hFFFF_FFF9, "sdiv r -100%-7");

    do_tx(1'b1, 1'b1, 32'd1024, 32'd32, "udiv q exact");
    do_tx(1'b1, 1'b0, 32'd1024, 32'd32, "udiv r exact");

    do_tx(1'b1, 1'b1, 32'd31, 32'd32, "udiv q <1");
    do_tx(1'b1, 1'b0, 32'd31, 32'd32, "udiv r <1");

    do_tx(1'b0, 1'b1, 32'h8000_0000, 32'hFFFF_FFFF, "sdiv q overflow");
    do_tx(1'b0, 1'b0, 32'h8000_0000, 32'hFFFF_FFFF, "sdiv r overflow");
  endtask

  // ------------ Random Tests -------------
  task automatic run_random(input int unsigned N = 200);
    for (int i = 0; i < N; i++) begin
      logic        mode      = $urandom_range(0,1);
      logic        out_type  = $urandom_range(0,1);
      logic [31:0] n         = $urandom();
      logic [31:0] d;
      case ($urandom_range(0,9))
        0: d = 32'd0;   // hit div-by-zero
        1: d = 32'd1;
        2: d = 32'd2;
        default: d = $urandom();
      endcase
      do_tx(mode, out_type, n, d, $sformatf("rand %0d", i));
    end
  endtask

  // ------------ Main -------------
  initial begin
    @(negedge rst);
    @(posedge clk);

    run_directed();
    run_random(500);

    $display("==================================================");
    $display("Test complete: %0d transactions, %0d mismatches", n_tx, n_err);
    $display("==================================================");

    if (n_err == 0) begin
      $display("ALL TESTS PASSED ✅");
      $finish;
    end else begin
      $fatal(1, "There were %0d mismatches.", n_err);
    end
  end

endmodule
