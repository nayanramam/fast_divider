module divider_core_goldschmidt (
    input  logic        clk,
    input  logic        rst,

    input  logic        start_calc,
    input  logic [31:0] numerator,
    input  logic [31:0] denominator,

    output logic        done_calc,
    output logic [31:0] div_output,
    output logic [31:0] div_remainder
);

  localparam int N_ITER = 1;  // iterations (convergence for 32-bit)

  typedef enum logic [1:0] { IDLE, ITER, CORR } state_t;
  state_t state;

  logic [5:0]  s_idle;      // bit_length(denominator) for normalize-in-IDLE
  logic [2:0]  iter_cnt;
  logic [63:0] n_fp;        // 64b; interpret as 32.32 (n = N/2^s)
  logic [31:0] d_fp;        // 32b; interpret as 1.31 (d = D/2^s in [0.5,1))
  logic [32:0] F_fp;        // 33b; interpret as 2.31 (2 - d)
  logic [31:0] N_lat, D_lat;

  // Intermediates for ITER and CORR (assigned in those states only)
  logic [96:0] prod_nF;
  logic [64:0] prod_dF;
  logic [31:0] d_new, Q_raw, R_raw, d_init_idle;
  logic [63:0] R_full;

  // bit_length(denominator) for normalizing in IDLE (saves NORM cycle)
  always_comb begin
    s_idle = 6'd0;
    for (int i = 0; i <= 31; i++)
      if (denominator[i])
        s_idle = 6'(i + 1);
  end
  // d = D/2^s in [0.5,1) => 1.31 value = D*2^(31-s). Compute as (D<<31)>>s so
  // the MSB of D (at position s-1) ends up at bit 30 (first digit after decimal in 1.31).
  assign d_init_idle = 32'(({denominator, 31'b0} >> s_idle));

  // State and datapath
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state         <= IDLE;
      done_calc     <= 1'b0;
      div_output    <= 32'd0;
      div_remainder <= 32'd0;
      n_fp          <= 64'd0;
      d_fp          <= 32'd0;
      F_fp          <= 33'd0;
      iter_cnt      <= 3'd0;
      N_lat         <= 32'd0;
      D_lat         <= 32'd0;
    end else begin
      done_calc <= 1'b0;

      case (state)
        IDLE: begin
          if (start_calc) begin
            N_lat <= numerator;
            D_lat <= denominator;
            if (numerator == 32'd0) begin
              div_output    <= 32'd0;
              div_remainder <= 32'd0;
              done_calc     <= 1'b1;
              state         <= IDLE;
            end else begin
              n_fp     <= {numerator, 32'b0} >> s_idle;  // fp 32.32
              d_fp     <= d_init_idle;  // fp 1.31
              F_fp     <= (33'b1 << 32) - {1'b0, d_init_idle};  // fp 2.31
              iter_cnt <= 3'd0;
              state    <= ITER;
              $display("[IDLE->ITER] s_idle:      dec=%0d  bin=%6b", s_idle, s_idle);
              $display("  d_init_idle: dec=%0d  bin=%32b", d_init_idle, d_init_idle);
              $display("  n_fp (new):   dec=%0d  bin=%64b", {numerator, 32'b0} >> s_idle, ({numerator, 32'b0} >> s_idle));
              $display("  d_fp (new):   dec=%0d  bin=%32b", d_init_idle, d_init_idle);
              $display("  F_fp (new):   dec=%0d  bin=%33b", (33'd1 << 32) - {1'b0, d_init_idle}, (33'd1 << 32) - {1'b0, d_init_idle});
              $display("  N_lat:        dec=%0d  bin=%32b", numerator, numerator);
              $display("  D_lat:        dec=%0d  bin=%32b", denominator, denominator);
            end
          end
        end

        ITER: begin
          // prod_nF = 97b. Interpret n_fp as 32.32, F_fp as 2.31 => product interprets as 34.63; take [94:31] for 32.32.
          prod_nF = n_fp * F_fp;
          prod_dF = d_fp * F_fp;  // 65b; 1.31 * 2.31 => interpret as 2.62
          d_new   = prod_dF[62:31];  // 32b as 1.31
          n_fp    <= prod_nF[94:31];  // 64b as 32.32
          d_fp    <= d_new;
          F_fp    <= (33'd1 << 32) - {1'b0, d_new};
          iter_cnt <= iter_cnt + 3'd1;
          if (iter_cnt >= N_ITER)
            state <= CORR;
          $display("[ITER] iter_cnt: dec=%0d  bin=%3b", iter_cnt, iter_cnt);
          $display("  prod_nF: dec=%0d  bin=%97b", prod_nF, prod_nF);
          $display("  prod_dF: dec=%0d  bin=%65b", prod_dF, prod_dF);
          $display("  d_new:   dec=%0d  bin=%32b", d_new, d_new);
          $display("  n_fp:    dec=%0d  bin=%64b", n_fp, n_fp);
          $display("  d_fp:    dec=%0d  bin=%32b", d_fp, d_fp);
          $display("  F_fp:    dec=%0d  bin=%33b", F_fp, F_fp);
        end

        CORR: begin
          Q_raw = n_fp[63:32];  // just the integer part
          $display("[CORR] n_fp:      dec=%0d  bin=%64b", n_fp, n_fp);
          $display("  Q_raw:   dec=%0d  bin=%32b", Q_raw, Q_raw);
          R_full = {32'b0, N_lat} - (D_lat * Q_raw);
          $display("  N_lat:   dec=%0d  bin=%32b", N_lat, N_lat);
          $display("  D_lat:   dec=%0d  bin=%32b", D_lat, D_lat);
          $display("  R_full:  dec=%0d  bin=%64b", R_full, R_full);
          R_raw  = R_full[31:0];  // 32 bit int part of 64 bit R_full
          $display("  R_raw:   dec=%0d  bin=%32b", R_raw, R_raw);
          if (R_raw < 32'd0) begin
            div_output <= Q_raw - 32'd1;
            div_remainder <= R_raw + D_lat;
            $display("  (R_raw < 0 => correction)");
            $display("  div_output:   dec=%0d  bin=%32b", Q_raw - 32'd1, Q_raw - 32'd1);
            $display("  div_remainder: dec=%0d  bin=%32b", R_raw + D_lat, R_raw + D_lat);
          end
          else if (R_raw >= D_lat) begin
            $display("  (R_raw >= D_lat => correction)");
            div_output <= Q_raw + 32'd1;
            div_remainder <= R_raw -  D_lat;
            $display("  div_output:   dec=%0d  bin=%32b", Q_raw + 32'd1, Q_raw + 32'd1);
            $display("  div_remainder: dec=%0d  bin=%32b", R_raw - D_lat, R_raw - D_lat);
          end else begin
            $display("  (R_raw < D_lat => no correction)");
            div_output <= Q_raw;
            div_remainder <= R_raw;
            $display("  div_output:   dec=%0d  bin=%32b", Q_raw, Q_raw);
            $display("  div_remainder: dec=%0d  bin=%32b", R_raw, R_raw);
          end
          done_calc <= 1'b1;
          state     <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
