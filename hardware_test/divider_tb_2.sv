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
  // CRV: random stimulus via $urandom (Icarus-friendly; no class randomize)
  // -----------------------
  localparam int NUM_RAND_TESTS = 1000;
  localparam int RAND_TIMEOUT   = 500;

  logic [31:0] n_rand, d_rand;
  logic        mode_u_rand, want_quot_rand;
  int          crv_i;
  int          total_cases, passed_cases;

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
    logic        failed;

    begin
      total_cases++;
      failed = 1'b0;
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
        $error("[FAIL] %s error mismatch: got %0b exp %0b (diff=%0d)",
               name, error_o, exp_err, error_o - exp_err);
        failed = 1'b1;
      end
      if (result !== exp_res) begin
        $error("[FAIL] %s result mismatch: got %0d exp %0d (diff=%0d)",
               name, result, exp_res, $signed(result) - $signed(exp_res));
        failed = 1'b1;
      end

      // ready_o must drop next cycle
      @(posedge clk_i);
      if (ready_o !== 1'b0) begin
        $error("[FAIL] %s ready_o not a 1-cycle pulse (still high next cycle)", name);
        failed = 1'b1;
      end

      if (!failed) begin
        passed_cases++;
        $display("[PASS] %s | cycles_to_ready=%0d | err=%0b res=%0d",
                 name, cyc, error_o, result);
      end
    end
  endtask

  // -----------------------
  // Test sequence: directed corners + CRV
  // -----------------------
  initial begin
    valid_i    = 1'b0;
    mode_i     = 1'b0;
    out_type_i = 1'b0;
    n_i        = 32'd0;
    d_i        = 32'd0;

    rst_i = 1'b1;
    repeat (2) @(posedge clk_i);
    rst_i = 1'b0;
    @(posedge clk_i);

    // ----- Directed: must-hit corners -----
    run_case("DIV by 0 => q",           1'b0, 1'b1, 32'd123,      32'd0,  50);
    run_case("REM by 0 => r",           1'b0, 1'b0, 32'd123,      32'd0,  50);
    run_case("DIV ovf INT_MIN/-1 => q", 1'b0, 1'b1, 32'h8000_0000,32'hFFFF_FFFF, 50);
    run_case("REM ovf INT_MIN/-1 => r", 1'b0, 1'b0, 32'h8000_0000,32'hFFFF_FFFF, 50);

    // ----- CRV: $urandom-based random transactions (no class randomize) -----
    for (crv_i = 0; crv_i < NUM_RAND_TESTS; crv_i++) begin
      n_rand         = $urandom();
      d_rand         = $urandom();
      mode_u_rand    = $urandom() & 1;
      want_quot_rand = $urandom() & 1;
      run_case($sformatf("CRV #%0d %s n=%0d d=%0d => %s",
                         crv_i, mode_u_rand ? "U" : "S", n_rand, d_rand, want_quot_rand ? "q" : "r"),
               mode_u_rand, want_quot_rand, n_rand, d_rand, RAND_TIMEOUT);
    end
    $display("ALL TESTS FINISHED (%0d directed + %0d random)", 4, NUM_RAND_TESTS);
    $display("PASSED: %0d / %0d (%0d%%)", passed_cases, total_cases,
             total_cases ? (passed_cases * 100) / total_cases : 0);
    $finish;
  end

endmodule
