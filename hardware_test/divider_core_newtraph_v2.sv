module divider_core_newtraph_v2 (
        input  logic        clk,  // clk_i
        input  logic        rst,  // rst_i

        input  logic        start_calc,  // valid_i
        input  logic [31:0] numerator,   // n_i
        input  logic [31:0] denominator, // d_i

        output logic        done_calc,   // ready_o
        output logic [31:0] div_output,  // q_o
        output logic [31:0] div_remainder // r_o
    );

    localparam int N_ITER = 2;

    typedef enum logic [1:0] { IDLE, ITER, CORR } state_t;
    state_t state;

    logic [5:0]  iter_cnt;
    logic [5:0]  s_idle;
    logic [31:0] N_lat, D_lat, Q_crop, R_crop;
    logic [31:0] LUT [0:32];           // 1.31: LUT[bit_length] = 1/(1<<bit_length)
    logic [63:0] g_fp;

    logic [63:0] Q_raw, R_raw;
    logic [127:0] g_prod;  // g_fp * (2 - D*g) for Newton-Raphson iteration
    logic [95:0] prod_inter;



    // State and datapath
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            done_calc     <= 1'b0;
            div_output    <= 32'd0;
            div_remainder <= 32'd0;
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
                if (numerator == 32'd0) begin
                  div_output    <= 32'd0;
                  div_remainder <= 32'd0;
                  done_calc     <= 1'b1;
                  state         <= IDLE;
                end else begin
                  iter_cnt <= 6'd0;
                  g_fp <= {32'b0, LUT[s_idle]};
                  state    <= ITER;
                end
              end
            end

            ITER: begin
              // Newton-Raphson: g_{n+1} = g_n * (2 - D*g_n).  g in 32.32 => factor 2^33 - (D*g)[95:32]
              prod_inter = (D_lat * g_fp);
              g_prod = g_fp * ((64'd1 << 33) - prod_inter[95:32]);
              g_fp <= g_prod[127:64];
              iter_cnt <= iter_cnt + 6'd1;
              if (iter_cnt >= N_ITER) state <= CORR;
              else state <= ITER;

            end

            CORR: begin
              Q_raw <= N_lat * g_fp[63:32];  // Q = N * g
              Q_crop <= Q_raw[31:0];
              R_raw <= {32'b0, N_lat} - (D_lat * Q_crop);
              R_crop <= R_raw[31:0];
              if (R_crop < 32'd0) begin
                div_output <= Q_crop - 32'd1;
                div_remainder <= R_crop + D_lat;
              end
              else if (R_crop >= D_lat) begin
                div_output <= Q_crop + 32'd1;
                div_remainder <= R_crop - D_lat;
              end
              else begin
                div_output <= Q_crop;
                div_remainder <= R_crop;
              end
            done_calc <= 1'b1;
            state     <= IDLE;
            end

            default: state <= IDLE;
        endcase
        end
    end

    // LUT[i] = 1/(1<<i) in 1.31 format for i = bit_length (1..32). LUT[i] = 2^(31-i).
    initial begin
        LUT[0] = 32'd0;  // unused (bit_length >= 1)
        for (int i = 1; i <= 31; i++)
            LUT[i] = 32'(1 << (31 - i));
        LUT[32] = 32'(1 << 30);  // 1/2^32 in 1.31 ≈ 0.5 (2^30)
    end

    // bit_length(denominator) for normalizing in IDLE (saves NORM cycle)
    always_comb begin
      s_idle = 6'd0;
      for (int i = 0; i <= 31; i++)
        if (denominator[i])
          s_idle = 6'(i + 1);
    end

endmodule