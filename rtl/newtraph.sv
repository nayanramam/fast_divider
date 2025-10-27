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
    logic [WIDTH-1:0] change, new_change;
    logic flip, next_flip;

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
            change <= new_change;
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
        new_change = change;
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
                //TODO add LUT
                g_new = 0.5;   // temp until add LUT
                next_change = '1;
                next_state = DIV_BRANCH;
            end

            DIV_BRANCH: begin
                if (change > 0.001) begin // TODO change
                    next_state = DIV_ITER;
                end else begin
                    next_state = DIV_FIN;
                end
            end

            DIV_ITER: begin
                g_new = g_prev * (2-(d_reg*g_prev));
                new_change = ((g_new - g_prev) < 0) ? g_prev - g_new : g_new - g_prev; // abs val of change
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
                new_change = '0;
            end
        endcase
    end

endmodule