`timescale 1ns/1ps

module divider_top (
    input  logic        clk_i, rst_i,            // global clock and reset
    input  logic        valid_i,                 // strobe: new command
    input  logic        mode_i,                  // 1=unsigned, 0=signed
    input  logic        out_type_i,              // 1=quotient, 0=remainder
    input  logic [31:0] n_i, d_i,                // numerator and denominator
    output logic        ready_o,                 // ready for new input
    output logic [31:0] result,                  // result output
    output logic [1:0]  error_o                  // 00=OK, 01=div-by-0, 10=overflow
);


    typedef enum logic [2:0] {
        IDLE              = 3'b000,
        CAPTURE           = 3'b001,
        PREPROCESS        = 3'b010,
        CHECK_ERRORS      = 3'b011,
        START_CORE        = 3'b100,
        WAIT_CORE         = 3'b101,
        POSTPROCESS       = 3'b110,   
        DONE_PULSE        = 3'b111
        //STATEX            = 3'bXXX
    } state_struct;



    //========================
    // Internal Signals
    //========================
    // FSM
    state_struct curr_state, next_state;    //enum declared before CHANGE to pkg

    // Latched inputs
    logic mode, out_type, final_sign, n_sign, d_sign;
    logic [31:0] numerator, denominator, sel_mag;

    // Values connected to core
    logic [1:0] err_code;
    logic start_calc_int, done_calc_int;
    logic [31:0] numerator_abs, denominator_abs, quotient_abs, remainder_abs, quotient_int, remainder_int;

    // Calc path select (do this later)
    // logic calc_type; 
    logic div0, ovf;

    assign div0 = (denominator == 32'd0);
    assign ovf  = (!mode) && (numerator == 32'h8000_0000) && (denominator == 32'hFFFF_FFFF);


    logic armed;


    //sel_mag = out_type ? quotient_abs : remainder_abs;



    //========================
    // Divider core instantiation
    //========================
    divider_core_goldschmidt divider( // divider_core or divider_core_goldschmidt
        .clk(clk_i),
        .rst(rst_i),
        .start_calc(start_calc_int),
        .numerator(numerator_abs),
        .denominator(denominator_abs),
        .done_calc(done_calc_int),
        .div_output(quotient_int),
        .div_remainder(remainder_int)
    );


    //========================
    // State register
    //========================

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) curr_state <= IDLE;
        else       curr_state <= next_state;
    end


    always_comb begin
        next_state = curr_state; //default
        case (curr_state)

            // When reset is high and working is stopped and module is IDLE
            // When a new valid_i goes high operations start
            IDLE: begin
                if (valid_i) next_state = CAPTURE;
                else         next_state = IDLE;
            end

            // Latch the current "valid inputs" onto internal registers
            CAPTURE: begin
                next_state = PREPROCESS;
            end

            // Preprocess the inputs from signed to unsigned for divider core
            PREPROCESS: begin
                next_state = CHECK_ERRORS;
            end

            // Check for any errors (div by 0 or signed overflow)
            CHECK_ERRORS: begin
                if (div0 || ovf)  next_state = DONE_PULSE;
                else next_state = START_CORE;
            end

            // One cycle kick for the divder/shifter module
            START_CORE: begin
                next_state = WAIT_CORE;
            end

            // Wait for internal divider/shifter core to finish the divsion operations
            WAIT_CORE: begin
                if (armed && done_calc_int) next_state = POSTPROCESS;
                else               next_state = WAIT_CORE;
            end

            // Postprocess the q and r to be the result required for the RISC V Operation
            POSTPROCESS: begin
                next_state = DONE_PULSE;
            end

            // Pulse done for one cycle
            DONE_PULSE: begin
                next_state = IDLE;
            end


        endcase
    end

    //========================
    // Outputs & datapath regs
    //========================

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin

            // Port resets
            ready_o   <= 1'b0;
            result    <= '0;
            error_o   <= 2'b00;

            err_code <= 2'b00;

            // Local resets
            mode       <= 1'b0;
            out_type   <= 1'b0;
            final_sign <= 1'b0;

            numerator   <= '0;
            denominator <= '0;
            

            n_sign      <= 1'b0;
            d_sign      <= 1'b0;

            armed <= 1'b0;


            // Values connected to core
            start_calc_int <= 1'b0;

            numerator_abs   <= '0;
            denominator_abs <= '0;
            quotient_abs <= '0;
            remainder_abs <= '0;

        end else begin
            // Defaults each cycle (unless overwritten in a state)
            ready_o        <= 1'b0;          // pulse only
            start_calc_int <= 1'b0;          // only 1-cycle in START_CORE

            case (curr_state)

                IDLE: begin
                    // nothing; wait for valid in next_state logic
                    armed <= 1'b0;
                    err_code <= 2'b00;       // optional: clear when idle
                end

                CAPTURE: begin
                    // Latch request
                    mode       <= mode_i;
                    out_type   <= out_type_i;

                    numerator   <= n_i;
                    denominator <= d_i;

                    n_sign <= n_i[31];
                    d_sign <= d_i[31];

                    // clear error until checked
                    err_code    <= 2'b00;
                    error_o     <= 2'b00;

                    // (optional) clear result regs
                    // result <= result;
                end

                PREPROCESS: begin
                    // Compute magnitudes for the core
                    // Your mode: 1=unsigned, 0=signed
                    if (mode) begin
                        numerator_abs   <= numerator;
                        denominator_abs <= denominator;
                        final_sign      <= 1'b0;
                    end else begin
                        numerator_abs   <= (numerator[31]   == 1'b0) ? numerator   : (~numerator   + 32'd1);
                        denominator_abs <= (denominator[31] == 1'b0) ? denominator : (~denominator + 32'd1);

                        // final sign depends on output type
                        if (out_type) begin
                            // quotient
                            final_sign <= (n_sign ^ d_sign);
                        end else begin
                            // remainder: per your requirement, use denominator sign
                            final_sign <= n_sign;
                        end
                    end
                end

                CHECK_ERRORS: begin
                    // Division by zero
                    
                    if (denominator == 32'd0) begin
                        armed <= 1'b0;
                        err_code <= 2'b01;
                        error_o  <= 2'b01;

                        result <= (out_type ? 32'hFFFF_FFFF : numerator);

                    end
                    // Signed overflow: only in signed mode (mode==0)
                    else if (!mode && (numerator == 32'h8000_0000) && (denominator == 32'hFFFF_FFFF)) begin
                        armed <= 1'b0;
                        err_code <= 2'b10;
                        error_o  <= 2'b10;
                        result   <= out_type ? 32'h8000_0000 : 32'd0;
                    end


                    else begin
                        // no error
                        err_code <= 2'b00;
                        error_o  <= 2'b00;
                    end
                end

                START_CORE: begin
                    // One-cycle kick
                    start_calc_int <= 1'b1;
                    armed <= 1'b1;

                end

                WAIT_CORE: begin
                    // Wait; latch outputs when done goes high
                    if (done_calc_int) begin
                        armed <= 1'b0;

                        quotient_abs   <= quotient_int;
                        remainder_abs  <= remainder_int;
                    end
                end

                POSTPROCESS: begin
                    
                    
                    // Apply sign if needed
                    if (final_sign) result <= ~(out_type ? quotient_abs : remainder_abs) + 32'd1;
                    else            result <=  (out_type ? quotient_abs : remainder_abs);


                    // error_o already set from err_code path
                    error_o <= err_code;
                end

                DONE_PULSE: begin
                    ready_o <= 1'b1;  // one-cycle pulse
                end

                default: begin
                    // safe recovery
                    err_code <= 2'b00;
                    error_o  <= 2'b00;
                    ready_o  <= 1'b0;
                    start_calc_int <= 1'b0;
                end

            endcase
        end


    end

endmodule