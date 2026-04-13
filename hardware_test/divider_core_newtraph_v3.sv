module divider_core_newtraph_v3 #(
        parameter bit DEBUG_PRINT = 1'b1  // set 0 in divider_top to silence
    ) (
        input  logic        clk,  // clk_i
        input  logic        rst,  // rst_i

        input  logic        start_calc,  // valid_i
        input  logic [31:0] numerator,   // n_i
        input  logic [31:0] denominator, // d_i

        output logic        done_calc,   // ready_o
        output logic [31:0] div_output,  // q_o
        output logic [31:0] div_remainder // r_o
    );

    // NR uses 1.31 mantissa d_norm_comb only (same as v2). 1/D = (1/d_norm)/2^d -> q = N*guess >> (31+d).
    localparam int N_ITER = 2;

    typedef enum logic [1:0] { IDLE, ITER, CORR } state_t;
    state_t state;

    logic [5:0]  iter_cnt;
    logic [5:0]  d_idle;
    logic [5:0]  d_idle_lat;
    logic [31:0] N_lat, D_lat;

    logic [62:0] d_norm;  // 32.31 fixed point

    logic [31:0] guess;  // 1.31 fixed point estimate of 1/d_norm

    logic [63:0]  factor_nr;
    logic [127:0] prod_g128;  // guess * factor_nr

    logic [127:0] n_times_g;  // N * guess for CORR
    logic [63:0]  q_raw;
    logic [63:0]  r64;
    logic [31:0]  q_est, r_est;

    // Combinational normalized D (same as Goldschmidt) for LUT index in IDLE
    logic [31:0] d_norm_comb;
    assign d_norm_comb = d_norm[31:0]; // 1.31 fixed point

    // 8-entry LUT: index = next 3 fractional bits below the leading 1 (bits [29:27])
    // for d_norm in [0.5,1). Values are x0 = 1/D in 1.31, D = 0.5 + (i + 0.5)/16 at bin center.
    logic [31:0] recip_lut[0:7];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            done_calc     <= 1'b0;
            div_output    <= 32'd0;
            div_remainder <= 32'd0;
            iter_cnt      <= 6'd0;
            d_idle_lat    <= 6'd0;
            N_lat         <= 32'd0;
            D_lat         <= 32'd0;
            d_norm        <= '0;
            guess         <= 32'd0;
        end else begin
            done_calc <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_calc) begin
                        d_idle_lat <= d_idle;
                        N_lat <= numerator;
                        D_lat <= denominator;
                        if (numerator == 32'd0) begin
                            if (DEBUG_PRINT)
                                $display("[%0t] %m IDLE | N=0 -> q=0 r=0 (early exit)", $time);
                            div_output    <= 32'd0;
                            div_remainder <= 32'd0;
                            done_calc     <= 1'b1;
                            state         <= IDLE;
                        end else if (numerator < denominator) begin
                            if (DEBUG_PRINT)
                                $display(
                                    "[%0t] %m IDLE | N<D (unsigned) -> q=0 r=N | N=%0d D=%0d",
                                    $time, numerator, denominator);
                            div_output    <= 32'd0;
                            div_remainder <= numerator;
                            done_calc     <= 1'b1;
                            state         <= IDLE;
                        end else begin
                            iter_cnt  <= 6'd0;
                            guess     <= recip_lut[d_norm_comb[29:27]];
                            if (DEBUG_PRINT) begin
                                $display(
                                    "[%0t] %m IDLE | start NR | N=%0d D=%0d | d_idle(shifts)=%0d",
                                    $time, numerator, denominator, d_idle);
                                $display(
                                    "         %m      | d_norm[62:0]=%h (32.31) d_norm_comb[1.31]=%h lut_idx[2:0]=%0d",
                                    d_norm, d_norm_comb, d_norm_comb[29:27]);
                                $display(
                                    "         %m      | recip_lut[idx] seed (1.31 guess)=%h",
                                    recip_lut[d_norm_comb[29:27]]);
                            end
                            state <= ITER;
                        end
                    end
                end

                ITER: begin
                    // d_norm_comb (1.31) * guess (1.31) → 2.62 product; "2" in 2.62 = 2^63
                    factor_nr  = (64'd1 << 63) - (64'(d_norm_comb) * 64'(guess));
                    prod_g128  = 64'(guess) * factor_nr;
                    // g_new = g * factor / 2^62 → bits [93:62] of 128b product
                    guess      <= prod_g128[93:62];
                    iter_cnt   <= iter_cnt + 6'd1;
                    if (DEBUG_PRINT) begin
                        $display(
                            "[%0t] %m ITER | iter=%0d/%0d | d_norm_comb(1.31)=%h | guess=%h",
                            $time, iter_cnt, N_ITER, d_norm_comb, guess);
                        $display(
                            "         %m      | d*g(2.62)=%h | factor(2.62)=%h | prod[93:62](next guess)=%h | -> %s",
                            64'(d_norm_comb) * 64'(guess), factor_nr, prod_g128[93:62],
                            (iter_cnt >= N_ITER - 1) ? "CORR" : "ITER");
                    end
                    if (iter_cnt >= N_ITER - 1)
                        state <= CORR;
                    else
                        state <= ITER;
                end

                CORR: begin
                    // D = d_norm_real * 2^d, guess ≈ (1/d_norm_real)*2^31 => N/D = N*guess / 2^(31+d)
                    n_times_g     = 64'(N_lat) * 64'(guess);
                    q_raw         = n_times_g >> (31 + d_idle_lat);
                    q_est         = q_raw[31:0];
                    r64           = 64'(N_lat) - (64'(D_lat) * q_raw);
                    r_est         = r64[31:0];
                    if (DEBUG_PRINT) begin
                        $display("[%0t] %m CORR | N_lat=%0d D_lat=%0d d_idle=%0d", $time, N_lat, D_lat,
                                 d_idle);
                        $display(
                            "         %m      | guess(1.31)=%h n_times_g=%h >>%0d -> q_est=%0d",
                            guess, n_times_g, 31 + d_idle_lat, q_est);
                        $display("         %m      | r64(before fix)=%h", r64);
                    end
                    if (r64[63]) begin  // R < 0
                        q_est = q_est - 32'd1;
                        r_est = r_est + D_lat;
                        if (DEBUG_PRINT)
                            $display(
                                "         %m      | fix: R<0 -> q_est-- r_est+=D | q_est=%0d r_est=%0d",
                                q_est, r_est);
                    end else if (r_est >= D_lat) begin  // R >= D
                        q_est = q_est + 32'd1;
                        r_est = r_est - D_lat;
                        if (DEBUG_PRINT)
                            $display(
                                "         %m      | fix: R>=D -> q_est++ r_est-=D | q_est=%0d r_est=%0d",
                                q_est, r_est);
                    end else if (DEBUG_PRINT)
                        $display("         %m      | fix: 0<=R<D (no change)");
                    if (DEBUG_PRINT)
                        $display("[%0t] %m CORR done | div_output<=q_est=%0d div_remainder<=r_est=%0d",
                                 $time, q_est, r_est);
                    div_output    <= q_est;
                    div_remainder <= r_est;
                    done_calc     <= 1'b1;
                    state         <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    initial begin
        // 1.31 reciprocal seed x0 per bin (index = d_norm[29:27])
        recip_lut[0] = 32'hfd6a052c;
        recip_lut[1] = 32'he4d9364e;
        recip_lut[2] = 32'hcede6243;
        recip_lut[3] = 32'hbb79890d;
        recip_lut[4] = 32'haaaaaaab;
        recip_lut[5] = 32'h9c71c71c;
        recip_lut[6] = 32'h90cede62;
        recip_lut[7] = 32'h87c1f07c;
        if (DEBUG_PRINT) begin
            $display("[%0t] %m --- recip_lut[0:7]: 1.31 NR seeds, idx = d_norm_comb[29:27] ---",
                     $time);
            for (int k = 0; k < 8; k++)
                $display("         %m  lut[%0d] = %h", k, recip_lut[k]);
        end
    end

    always_comb begin
        d_idle = 6'd0;
        d_norm = {denominator, 31'b0};
        while (d_norm > (63'd1 << 31)) begin
            d_norm = d_norm >> 1;
            d_idle = d_idle + 1;
        end
    end

endmodule
