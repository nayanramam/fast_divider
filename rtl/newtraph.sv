typedef enum logic [1:0] {
    START = 4'b0000,
    CHECK_ZERO = 4'b0001,
    CHECK_UNSIG_PWR = 4'b0010,
    SHIFT = 4'b0011,
    DIV_START = 4'b0100,    // find g_new/1000, go to branch
    DIV_BRANCH = 4'b0101,   // check if change meets thresh & branch to iter or fin
    DIV_ITER = 4'b0110,     // inside of the while loop, back to start
    DIV_FIN = 4'b0111,
    FINISHED = 4'b1000
} state_div_nr;

state_div_nr state, next_state;


module gcd
    #(
        parameter WIDTH = 32
    )
    (
        input logic                 clk_i,          // Posedge clk
        input logic                 rst_i,          // Active high synchronous reset
        input logic                 valid_i,        // Active high valid input signal
        input logic                 unsigned_mode,  // 1 if unsigned; 0 if signed
        input logic                 out_type,       // 1 if quotient; 0 if remainder
        input logic [WIDTH-1:0]     n_i,            // 32 bit numerator (rs1)
        input logic [WIDTH-1:0]     d_i,            // 32 bit denominator (rs2)
        
        output logic                ready_o,        // High when division is complete (or early termination)
        output logic [WIDTH-1:0]    q_o,            // Either quotient or remainder
        output logic [WIDTH-1:0]    r_o,
        output logic [1:0]          error_o         // Contains error code
    );


    logic [WIDTH-1:0] n_reg, d_reg, next_n, next_d;
    logic [WIDTH-1:0] g_prev, g_new;
    logic [WIDTH-1:0] change, next_change;
    logic flip, next_flip;
    logic [31:0] LUT [0:32];

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state <= START;
            n_reg <= n_i;
            d_reg <= d_i;
            g_prev <= '0;
            change <= '1;
            flip <= 1'b0;
        end else begin
            state <= next_state;
            n_reg <= next_n;
            d_reg <= next_d;
            g_prev <= g_new;
            change <= next_change;
            flip <= next_flip;
        end
    end

    always_comb begin
        // Default assignments
        next_state = state;
        ready_o = 1'b0;
        q_o = '0;
        r_o = '0;
        error_o = 2'b00;
        g_new = g_prev;
        next_change = change;
        next_n = n_reg;
        next_d = d_reg;
        next_flip = flip;

        case (state)
            START: begin
                if (valid_i) begin
                    next_state = CHECK_ZERO;
                end
            end

            CHECK_ZERO: begin
                if (!d_reg) begin
                    q_o = '1;
                    r_o = n_reg;
                    next_state = FINISHED;
                end

                else if (!n_reg) begin
                    q_o = '0;
                    r_o = '0;
                    next_state = FINISHED;
                end

                else begin
                    next_state = CHECK_UNSIG_PWR;
                end
            end

            CHECK_UNSIG_PWR: begin
                if (unsigned_mode) begin
                    if (n_reg * (n_reg - 1) == 0) begin     // power of 2
                        next_state = SHIFT;
                    end else begin
                        next_state = DIV_START;
                    end
                end else begin // signed mode
                    // 2's comp on N and/or D if necessary
                    if (n_reg[WIDTH-1]) begin  // Check MSB for signed negative
                        next_n = ~n_reg + 1;
                        next_flip = ~flip;
                    end if (d_reg[WIDTH-1]) begin  // Check MSB for signed negative
                        next_d = ~d_reg + 1;
                        next_flip = ~flip;
                    end


                    if (n_reg * (n_reg - 1) == 0) begin     // power of 2
                        next_state = SHIFT;
                    end else begin
                        next_state = DIV_START;
                    end
                end
            end

            SHIFT: begin
                q_o = n_reg >>> $clog2(d_reg);
                r_o = n_reg & (d_reg - 1);
                
                if (flip) begin
                    q_o = ~q_o + 1;
                    r_o = ~r_o + 1;

                end

                next_state = FINISHED;
            end

            DIV_START: begin

                g_new = msb_index(d_reg);
                g_new = LUT[g_new];

                next_change = '1;
                next_state = DIV_BRANCH;
            end

            DIV_BRANCH: begin
                if (change > 0.001) begin
                    next_state = DIV_ITER;
                end else begin
                    next_state = DIV_FIN;
                end
            end

            DIV_ITER: begin
                g_new = g_prev * (2-(d_reg*g_prev));
                next_change = ((g_new - g_prev) < 0) ? g_prev - g_new : g_new - g_prev; // abs val of change
                next_state = DIV_BRANCH;
            end

            DIV_FIN: begin
                g_new = g_new;
                if (flip) begin
                    g_new = ~g_new + 1;
                end

                q_o = n_reg * g_new; // may need to truncate
                r_o = n_reg - (d_reg * q_o);
                next_state = FINISHED;
            end

            FINISHED: begin
                ready_o = 1'b1;
                q_o = q_o;
                r_o = r_o;

            end

            default: begin
                next_state = START;
                ready_o = 1'b0;
                q_o = '0;
                r_o = '0;
                error_o = 2'b11;  // Unknown state error
                g_new = '0;
                next_change = '0;
            end
        endcase
    end

    initial begin
        LUT[0]  = 1.0;
        LUT[1]  = 0.5;
        LUT[2]  = 0.25;
        LUT[3]  = 0.125;
        LUT[4]  = 0.0625;
        LUT[5]  = 0.03125;
        LUT[6]  = 0.015625;
        LUT[7]  = 0.0078125;
        LUT[8]  = 0.00390625;
        LUT[9]  = 0.001953125;
        LUT[10] = 0.0009765625;
        LUT[11] = 0.00048828125;
        LUT[12] = 0.000244140625;
        LUT[13] = 0.0001220703125;
        LUT[14] = 0.00006103515625;
        LUT[15] = 0.000030517578125;
        LUT[16] = 0.0000152587890625;
        LUT[17] = 0.00000762939453125;
        LUT[18] = 0.000003814697265625;
        LUT[19] = 0.0000019073486328125;
        LUT[20] = 0.00000095367431640625;
        LUT[21] = 0.000000476837158203125;
        LUT[22] = 0.0000002384185791015625;
        LUT[23] = 0.00000011920928955078125;
        LUT[24] = 0.000000059604644775390625;
        LUT[25] = 0.0000000298023223876953125;
        LUT[26] = 0.00000001490116119384765625;
        LUT[27] = 0.000000007450580596923828125;
        LUT[28] = 0.0000000037252902984619140625;
        LUT[29] = 0.00000000186264514923095703125;
        LUT[30] = 0.000000000931322574615478515625;
        LUT[31] = 0.0000000004656612873077392578125;
        LUT[32] = 0.00000000023283064365386962890625;
    end

    function automatic int msb_index(input int value);
        for (int i = 31; i >= 0; i--) begin
            if (value[i]) begin
                return i;
            end
            // NOTE: no need for else bc we already check for d_reg > 0
        end
    endfunction

endmodule