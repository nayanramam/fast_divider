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

  localparam int N_ITER = 3;  // iterations (convergence for 32-bit)

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
            end else if (numerator < denominator) begin
              // Magnitudes from wrapper: |N| < |D| => truncating quotient is 0.
              // NR path refines 1/D only; it does not yield q=0 without this.
              div_output    <= 32'd0;
              div_remainder <= numerator;
              done_calc     <= 1'b1;
              state         <= IDLE;
            end else begin
              n_fp     <= {numerator, 32'b0} >> s_idle;  // fp 32.32
              d_fp     <= d_init_idle;  // fp 1.31
              F_fp     <= (33'b1 << 32) - {1'b0, d_init_idle};  // fp 2.31
              iter_cnt <= 3'd0;
              state    <= ITER;
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
        end

        CORR: begin
          Q_raw = n_fp[63:32];  // just the integer part
          R_full = {32'b0, N_lat} - (D_lat * Q_raw);
          R_raw  = R_full[31:0];  // 32 bit int part of 64 bit R_full
          if (R_raw < 32'd0) begin
            div_output <= Q_raw - 32'd1;
            div_remainder <= R_raw + D_lat;
          end
          else if (R_raw >= D_lat) begin
            div_output <= Q_raw + 32'd1;
            div_remainder <= R_raw -  D_lat;
          end else begin
            div_output <= Q_raw;
            div_remainder <= R_raw;
          end
          done_calc <= 1'b1;
          state     <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
