`timescale 1ns/1ps

module divider_tb;

  // -----------------------
  // Clock / Reset
  // -----------------------
  logic clk_i;
  logic rst_i; // active-high reset

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i; // 10ns period

  // -----------------------
  // DUT ports
  // -----------------------
  logic        valid_i;
  logic        mode_i;       // 1 unsigned, 0 signed
  logic        out_type_i;   // 1 quotient, 0 remainder
  logic [31:0] n_i;
  logic [31:0] d_i;

  logic        ready_o;      // 1-cycle pulse when done
  logic [31:0] result;
  logic [1:0]  error_o;

  // -----------------------
  // Instantiate wrapper
  // -----------------------
  divider_top dut (
    .clk_i      (clk_i),
    .rst_i      (rst_i),
    .valid_i    (valid_i),
    .mode_i     (mode_i),
    .out_type_i (out_type_i),
    .n_i        (n_i),
    .d_i        (d_i),
    .ready_o    (ready_o),
    .result     (result),
    .error_o    (error_o)
  );

  // -----------------------
  // Icarus-friendly signed views
  // -----------------------
  wire signed [31:0] n_i_s    = n_i;
  wire signed [31:0] d_i_s    = d_i;
  wire signed [31:0] result_s = result;

  // -----------------------
  // Reference model helpers
  // -----------------------

  function automatic [31:0] twos_comp(input [31:0] x);
    twos_comp = ~x + 32'd1;
  endfunction

  function automatic [31:0] abs32(input [31:0] x);
    abs32 = x[31] ? twos_comp(x) : x;
  endfunction

  function automatic [31:0] exp_result(
    input logic        mode_u,
    input logic        want_quot,
    input logic [31:0] n,
    input logic [31:0] d
  );
    logic signed [31:0] ns, ds;
    logic signed [31:0] q_s, r_s;
    logic [31:0]        q_u, r_u;

    ns = $signed(n);
    ds = $signed(d);

    if (d == 32'd0) begin
      exp_result = want_quot ? 32'hFFFF_FFFF : n;
    end
    else if (!mode_u && (n == 32'h8000_0000) && (d == 32'hFFFF_FFFF)) begin
      exp_result = want_quot ? 32'h8000_0000 : 32'd0;
    end
    else if (mode_u) begin
      q_u = n / d;
      r_u = n % d;
      exp_result = want_quot ? q_u : r_u;
    end
    else begin
      q_s = ns / ds;
      r_s = ns % ds;
      exp_result = want_quot ? $unsigned(q_s) : $unsigned(r_s);
    end
  endfunction



  function automatic [1:0] exp_error(
    input logic        mode_u,
    input logic [31:0] n,
    input logic [31:0] d
  );
    begin
      if (d == 32'd0) exp_error = 2'b01;
      else if (!mode_u && (n == 32'h8000_0000) && (d == 32'hFFFF_FFFF)) exp_error = 2'b10;
      else exp_error = 2'b00;
    end
  endfunction

  // -----------------------
  // Drive one transaction and check
  // -----------------------
  task automatic run_case(
    input string       name,
    input logic        mode_u,      // 1 unsigned, 0 signed
    input logic        want_quot,    // 1 quotient, 0 remainder
    input logic [31:0] n,
    input logic [31:0] d,
    input int          timeout_cycles
  );
    logic [31:0] exp_res;
    logic [1:0]  exp_err;
    int          cyc;

    begin
      exp_res = exp_result(mode_u, want_quot, n, d);
      exp_err = exp_error (mode_u, n, d);

      // Apply inputs and pulse valid for 1 cycle
      @(posedge clk_i);
      mode_i      <= mode_u;
      out_type_i  <= want_quot;
      n_i         <= n;
      d_i         <= d;
      valid_i     <= 1'b1;

      @(posedge clk_i);
      valid_i     <= 1'b0;

      // Wait for ready_o (1-cycle pulse) with timeout
      cyc = 0;
      while (ready_o !== 1'b1) begin
        @(posedge clk_i);
        cyc++;
        if (cyc > timeout_cycles) begin
          $error("[TIMEOUT] %s did not finish within %0d cycles", name, timeout_cycles);
          disable run_case;
        end
      end

      // Check outputs on the ready pulse cycle
      if (error_o !== exp_err) begin
        $error("[FAIL] %s error mismatch: got %0b exp %0b", name, error_o, exp_err);
      end
      if (result !== exp_res) begin
        $error("[FAIL] %s result mismatch: got 0x%08h exp 0x%08h", name, result, exp_res);
      end

      // ready_o must drop next cycle
      @(posedge clk_i);
      if (ready_o !== 1'b0) begin
        $error("[FAIL] %s ready_o not a 1-cycle pulse (still high next cycle)", name);
      end

      $display("[PASS] %s | cycles_to_ready=%0d | err=%0b res=0x%08h",
               name, cyc, error_o, result);
    end
  endtask

  // -----------------------
  // Test sequence
  // -----------------------
  initial begin
    // init
    valid_i    = 1'b0;
    mode_i     = 1'b0;
    out_type_i = 1'b0;
    n_i        = 32'd0;
    d_i        = 32'd0;

    // reset
    rst_i = 1'b1;
    repeat (2) @(posedge clk_i);
    rst_i = 1'b0;
    @(posedge clk_i);

    // Keep numbers small if core is slow

    run_case("DIV  100/7 => q",        1'b0, 1'b1, 32'd100,      32'd7,  500);
    run_case("REM -100 mod 7 => r",    1'b0, 1'b0, 32'hFFFF_FF9C,32'd7,  500); // -100

    run_case("DIVU 100/7 => q",        1'b1, 1'b1, 32'd100,      32'd7,  500);
    run_case("REMU 100%7 => r",        1'b1, 1'b0, 32'd100,      32'd7,  500);

    run_case("DIV by 0 => q",          1'b0, 1'b1, 32'd123,      32'd0,  50);
    run_case("REM by 0 => r",          1'b0, 1'b0, 32'd123,      32'd0,  50);

    run_case("DIV ovf INT_MIN/-1 => q",1'b0, 1'b1, 32'h8000_0000,32'hFFFF_FFFF, 50);
    run_case("REM ovf INT_MIN/-1 => r",1'b0, 1'b0, 32'h8000_0000,32'hFFFF_FFFF, 50);

    $display("ALL TESTS FINISHED");
    $finish;
  end

endmodule
