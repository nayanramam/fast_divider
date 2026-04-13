module divider_core_newtraph_v2 #(
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

    // Match divider_core_newtraph.sv: g is 1.31 (value = real_g * 2^31)
    localparam int N_ITER = 6;

    typedef enum logic [1:0] { IDLE, ITER, CORR } state_t;
    state_t state;

    logic [5:0]  iter_cnt;
    logic [5:0]  s_idle;
    logic [31:0] N_lat, D_lat;

    logic [31:0] LUT [0:32];
    logic [31:0] g_31;  // 1.31 reciprocal estimate

    // Newton: factor = 2^32 - D*g, prod = g * factor, g_new = prod >> 31
    logic [63:0]  factor_nr;
    logic [127:0] prod_g128;

    // CORR: Q = (N*g) >> 31, then remainder fix-up (64b for D*q)
    logic [127:0] prod_q128;
    logic [63:0]  r64;
    logic [31:0]  q_est, r_est;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            done_calc     <= 1'b0;
            div_output    <= 32'd0;
            div_remainder <= 32'd0;
            iter_cnt      <= 6'd0;
            N_lat         <= 32'd0;
            D_lat         <= 32'd0;
            g_31          <= 32'd0;
        end else begin
            done_calc <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_calc) begin
                        N_lat <= numerator;
                        D_lat <= denominator;
                        if (numerator == 32'd0) begin
                            if (DEBUG_PRINT)
                                $display("[%0t] %m IDLE zero numerator -> q=0 r=0", $time);
                            div_output    <= 32'd0;
                            div_remainder <= 32'd0;
                            done_calc     <= 1'b1;
                            state         <= IDLE;
                        end else if (numerator < denominator) begin
                            // Magnitudes from wrapper: |N| < |D| => truncating quotient is 0.
                            // NR path refines 1/D only; it does not yield q=0 without this.
                            if (DEBUG_PRINT)
                                $display("[%0t] %m IDLE N<D -> q=0 r=N", $time);
                            div_output    <= 32'd0;
                            div_remainder <= numerator;
                            done_calc     <= 1'b1;
                            state         <= IDLE;
                        end else begin
                            iter_cnt <= 6'd0;
                            g_31     <= LUT[s_idle];
                            if (DEBUG_PRINT) begin
                                $display(
                                    "[%0t] %m IDLE start | N=%0d D=%0d | s_idle(msb_idx+1)=%0d LUT[s]=%h | g_31_init=%h",
                                    $time, numerator, denominator, s_idle, LUT[s_idle], LUT[s_idle]);
                            end
                            state <= ITER;
                        end
                    end
                end

                ITER: begin
                    factor_nr = (64'd1 << 32) - (64'(D_lat) * 64'(g_31));
                    prod_g128 = 64'(g_31) * factor_nr;
                    g_31      <= prod_g128[62:31];
                    iter_cnt  <= iter_cnt + 6'd1;
                    if (DEBUG_PRINT) begin
                        $display(
                            "[%0t] %m ITER | iter_cnt(before)=%0d D_lat=%0d g_31=%h | factor_nr=%h | g_next=%h",
                            $time, iter_cnt, D_lat, g_31, factor_nr, prod_g128[62:31]);
                        $display("         %m     -> next state %s",
                                 (iter_cnt >= N_ITER - 1) ? "CORR" : "ITER");
                    end
                    if (iter_cnt >= N_ITER - 1)
                        state <= CORR;
                    else
                        state <= ITER;
                end

                CORR: begin
                    prod_q128 = 64'(N_lat) * 64'(g_31);
                    q_est     = prod_q128[62:31];
                    r64       = 64'(N_lat) - (64'(D_lat) * 64'(q_est));
                    if (DEBUG_PRINT) begin
                        $display("[%0t] %m CORR | g_31=%h N_lat=%0d D_lat=%0d", $time, g_31, N_lat,
                                 D_lat);
                        $display("         %m      | prod_q128=%h q_est=%0d r64=%h", prod_q128, q_est,
                                 r64);
                    end
                    if (r64[63]) begin
                        q_est = q_est - 32'd1;
                        r64   = r64 + 64'(D_lat);
                        if (DEBUG_PRINT)
                            $display("         %m      | branch: R<0 -> q-- r+=D");
                    end else if (r64 >= 64'(D_lat)) begin
                        q_est = q_est + 32'd1;
                        r64   = r64 - 64'(D_lat);
                        if (DEBUG_PRINT)
                            $display("         %m      | branch: R>=D -> q++ r-=D");
                    end else if (DEBUG_PRINT)
                        $display("         %m      | branch: 0<=R<D");
                    r_est = r64[31:0];
                    if (DEBUG_PRINT)
                        $display("[%0t] %m CORR out | q=%0d r=%0d", $time, q_est, r_est);
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
        LUT[0] = 32'd0;
        for (int i = 1; i <= 31; i++)
            LUT[i] = 32'(1 << (31 - i));
        LUT[32] = 32'(1 << 30);
        if (DEBUG_PRINT) begin
            $display("[%0t] %m --- LUT[0:32] (1.31 fixed) ---", $time);
            for (int j = 0; j <= 32; j++)
                $display("  LUT[%0d] = %h", j, LUT[j]);
        end
    end

    always_comb begin
        s_idle = 6'd0;
        for (int i = 0; i <= 31; i++)
            if (denominator[i])
                s_idle = 6'(i + 1);
    end

endmodule
