// Goldschmidt division (unsigned 32-bit). Normalize d in [0.5,1), iterate n,d *= F (F=2-d),
// then Q = trunc(n), R = N - D*Q corrected to [0, D). div_by_zero/0÷D: done next cycle.
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

  typedef enum logic [2:0] { IDLE, NORM, ITER, CORR, DONE } state_t;
  state_t state;

  logic [5:0]  s;           // bit_length(D_lat), 1..32
  logic [5:0]  iter_cnt;
  logic [63:0] n_fp;        // 32.32 fixed-point (n = N/2^s)
  logic [31:0] d_fp;        // 1.31 fixed-point (d = D/2^s in [0.5, 1))
  logic [32:0] F_fp;        // 2 - d in 2.31 scale (33 bits)
  logic [31:0] N_lat, D_lat;

  // Intermediates for ITER and CORR (assigned in those states only)
  logic [96:0] prod_nF;
  logic [64:0] prod_dF;
  logic [31:0] d_new, Q_raw, R_raw, d_init;
  logic [63:0] R_full;

  // s = bit_length(D_lat) so d = D/2^s is in [0.5, 1)
  always_comb begin
    s = 6'd32;
    for (int i = 0; i <= 31; i++)
      if (D_lat[i])
        s = 6'(i + 1);
  end

  assign d_init = 32'(({D_lat, 31'b0} >> s));

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
      iter_cnt      <= 6'd0;
      N_lat         <= 32'd0;
      D_lat         <= 32'd0;
    end else begin
      done_calc <= 1'b0;

      case (state)
        IDLE: begin
          if (start_calc) begin
            N_lat <= numerator;
            D_lat <= denominator;
            if (denominator == 32'd0) begin
              // divide-by-zero: Q=0, R=N
              div_output    <= 32'd0;
              div_remainder <= numerator;
              state         <= DONE;
            end else if (numerator == 32'd0) begin
              // 0/D = 0 remainder 0
              div_output    <= 32'd0;
              div_remainder <= 32'd0;
              state         <= DONE;
            end else begin
              state <= NORM;
            end
          end
        end

        NORM: begin
          // n = N / 2^s  -> n_fp = {N, 32'b0} >> s  (32.32 fixed-point)
          // d = D / 2^s  -> d_fp = {D, 31'b0} >> s  (1.31 fixed-point)
          // F = 2 - d    -> F_fp = 2^32 - d_fp       (33-bit)
          n_fp     <= {N_lat, 32'b0} >> s;
          d_fp     <= d_init;
          F_fp     <= (33'd1 << 32) - {1'b0, d_init};
          iter_cnt <= 6'd0;
          state    <= ITER;
        end

        ITER: begin
          // Full-width mult (64*33, 32*33) then >>31 for n_new, d_new; F_new = 2^32 - d_new
          prod_nF = ({33'b0, n_fp} * F_fp);
          prod_dF = ({33'b0, d_fp} * F_fp);
          d_new   = prod_dF[62:31];
          n_fp    <= prod_nF[94:31];
          d_fp    <= d_new;
          F_fp    <= (33'd1 << 32) - {1'b0, d_new};
          iter_cnt <= iter_cnt + 6'd1;
          if (iter_cnt >= N_ITER - 1)
            state <= CORR;
        end

        CORR: begin
          Q_raw = n_fp[63:32];
          R_full = {32'b0, N_lat} - (64'(D_lat) * 64'(Q_raw));
          R_raw  = R_full[31:0];
          if (R_raw >= D_lat) begin
            div_output    <= Q_raw + 32'd1;
            div_remainder <= R_raw - D_lat;
          end else begin
            div_output    <= Q_raw;
            div_remainder <= R_raw;
          end
          state <= DONE;
        end

        DONE: begin
          done_calc <= 1'b1;
          state     <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
