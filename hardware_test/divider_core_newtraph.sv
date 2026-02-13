typedef enum logic [2:0] {
    START,
    CHECK_ZERO,
    SHIFT,
    DIV_START,
    DIV_ITER,
    DIV_FIN,
    FINISHED
} state_div_nr;

state_div_nr state, next_state;


module divider_core_newtraph
    #(
        parameter WIDTH = 32
    )
    (
        input  logic        clk,  // clk_i
        input  logic        rst,  // rst_i

        input  logic        start_calc,  // valid_i
        input  logic [31:0] numerator,   // n_i
        input  logic [31:0] denominator, // d_i

        output logic        done_calc,   // ready_o
        output logic [31:0] div_output,  // q_o
        output logic [31:0] div_remainder // r_o
    );


    localparam int N_ITER = 1;

    logic [WIDTH-1:0] n_reg, d_reg, next_n, next_d;
    logic [WIDTH-1:0] g_prev, g_new;   // 1.31: stored value = real * 2^31 (e.g. 268435456 = 0.125)
    logic [5:0] iter_cnt, next_iter_cnt;
    logic [31:0] LUT [0:32];           // 1.31: LUT[bit_length] = 1/(1<<bit_length)
    logic [63:0] factor;
    logic [95:0] prod_g;
    logic [31:0] result_q_reg, result_r_reg;  // latched so outputs valid when done_calc=1
    logic [31:0] result_q_comb, result_r_comb;

    assign div_output    = result_q_reg;
    assign div_remainder = result_r_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= START;
            g_prev <= '0;
            iter_cnt <= '0;
            result_q_reg <= '0;
            result_r_reg <= '0;
        end else begin
            state <= next_state;
            n_reg <= next_n;
            d_reg <= next_d;
            g_prev <= g_new;
            iter_cnt <= next_iter_cnt;
            // Latch Q,R when transitioning to FINISHED so outputs stay valid for done_calc cycle
            if (state == DIV_FIN || state == SHIFT || (state == CHECK_ZERO && (!d_reg || !n_reg))) begin
                result_q_reg <= result_q_comb;
                result_r_reg <= result_r_comb;
            end
        end
    end

    always_comb begin
        next_state = state;
        done_calc = 1'b0;
        result_q_comb = result_q_reg;
        result_r_comb = result_r_reg;
        g_new = g_prev;
        next_iter_cnt = iter_cnt;
        next_n = n_reg;
        next_d = d_reg;

        case (state)
            START: begin
                if (start_calc) begin
                    //$display("[newtraph] START start_calc N=%0d D=%0d", numerator, denominator);
                    next_n = numerator;
                    next_d = denominator;
                    next_state = CHECK_ZERO;
                end
            end

            CHECK_ZERO: begin
                if (!d_reg) begin
                    //$display("[newtraph] CHECK_ZERO div_by_zero -> Q=0 R=%0d", n_reg);
                    result_q_comb = '0;
                    result_r_comb = n_reg;
                    next_state = FINISHED;
                end else if (!n_reg) begin
                    //$display("[newtraph] CHECK_ZERO n=0 -> Q=0 R=0");
                    result_q_comb = '0;
                    result_r_comb = '0;
                    next_state = FINISHED;
                end else if ((d_reg & (d_reg - 1)) == 0) begin  // power of 2
                    //$display("[newtraph] CHECK_ZERO d power-of-2 -> SHIFT");
                    next_state = SHIFT;
                end else begin
                    //$display("[newtraph] CHECK_ZERO n_reg=%0d d_reg=%0d -> DIV_START", n_reg, d_reg);
                    next_state = DIV_START;
                end
            end

            SHIFT: begin
                result_q_comb = n_reg >> msb_index(d_reg);
                result_r_comb = n_reg & (d_reg - 1);
                //$display("[newtraph] SHIFT Q=%0d R=%0d", result_q_comb, result_r_comb);
                next_state = FINISHED;
            end

            DIV_START: begin
                // Initial guess 1/(1<<bit_length(D)); bit_length = msb_index + 1
                g_new = LUT[msb_index(d_reg) + 1];
                next_iter_cnt = 6'd0;
                //$display("[newtraph] DIV_START d_reg=%0d bitlen=%0d g_init=%0d (real=1/%0d)", d_reg, msb_index(d_reg)+1, LUT[msb_index(d_reg)+1], 1<<(msb_index(d_reg)+1));
                next_state = DIV_ITER;
            end

            DIV_ITER: begin
                // g_new = g_prev * (2 - d*g_prev) in 1.31. Use 64-bit 2^32 and full-width mult.
                factor = (64'd1 << 32) - 64'(d_reg) * 64'(g_prev);
                prod_g = 64'(g_prev) * factor;
                g_new  = 32'(prod_g >> 31);
                next_iter_cnt = iter_cnt + 6'd1;
                //$display("[newtraph] DIV_ITER cnt=%0d g_prev=%0d (real=%0.6f) g_new=%0d", iter_cnt, g_prev, 1.0*g_prev/(1<<31), g_new);
                if (iter_cnt >= N_ITER - 1)
                    next_state = DIV_FIN;
                else
                    next_state = DIV_ITER;
            end

            DIV_FIN: begin
                // Q = N * (1/D) in 1.31: (n_reg * g_new) >> 31
                prod_g = 64'(n_reg) * 64'(g_new);
                result_q_comb = 32'(prod_g >> 31);
                result_r_comb = n_reg - (d_reg * result_q_comb);
                //$display("[newtraph] DIV_FIN Q=%0d R=%0d", result_q_comb, result_r_comb);
                next_state = FINISHED;
            end

            FINISHED: begin
                done_calc = 1'b1;
                //$display("[newtraph] FINISHED done_calc=1");
                next_state = START;
            end

            default: begin
                next_state = START;
                done_calc = 1'b0;
                result_q_comb = '0;
                result_r_comb = '0;
                g_new = '0;
                next_iter_cnt = '0;
            end
        endcase
    end

    // LUT[i] = 1/(1<<i) in 1.31 format for i = bit_length (1..32). LUT[i] = 2^(31-i).
    initial begin
        LUT[0] = 32'd0;  // unused (bit_length >= 1)
        for (int i = 1; i <= 31; i++)
            LUT[i] = 32'(1 << (31 - i));
        LUT[32] = 32'(1 << 30);  // 1/2^32 in 1.31 ≈ 0.5 (2^30)
    end

    function automatic int msb_index(input int value);
        for (int i = 31; i >= 0; i--) begin
            if (value[i]) begin
                //$display("[newtraph] msb_index=%0d", i);
                return i;
            end
            // NOTE: no need for else bc we already check for d_reg > 0
        end
    endfunction

endmodule