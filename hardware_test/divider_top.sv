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

  //import divider_pkg::*;

  // ---- helpers (no 'logic'( ) casts; use $unsigned only) ----
  function automatic logic [31:0] as_u32(input logic [31:0] x);
    as_u32 = $unsigned(x);
  endfunction

  function automatic logic [31:0] neg32(input logic [31:0] x);
    // two's complement negate as unsigned 32-bit
    neg32 = $unsigned((~x) + 32'd1);
  endfunction

  typedef enum logic [3:0] {
    RESET          = 4'b0000,
    READ           = 4'b0001,
    CHECK          = 4'b0010,
    ERROR_ST       = 4'b0011,
    PREP_INPUT     = 4'b0100,
    INIT           = 4'b0101,
    SHIFT_COMPUTE  = 4'b0110,   // placeholder (not used in this minimal fix)
    DIVIDE_COMPUTE = 4'b0111,
    NORMALIZE      = 4'b1000,   // placeholder (not used in this minimal fix)
    PREP_OUTPUT    = 4'b1001,
    DONE           = 4'b1010,
    STATEX         = 4'bXXXX
  } state_struct;


  // FSM
  state_struct curr_state, next_state;  // enum from divider_pkg

  // Latched inputs
  logic        mode, out_type, final_sign;
  logic [31:0] numerator, denominator;

  // Magnitudes fed to core (unsigned)
  logic [31:0] num_mag, den_mag;

  // Core interface
  logic        start_calc, done_calc;
  logic [31:0] div_output, div_remainder;

  // Optional calc path select (kept simple here: always use divider)
  logic        calc_type; // 1=shift, 0=divider

  // Core instance: feed magnitudes
  divider_core u_divider (
    .start_calc    (start_calc),
    .numerator     (num_mag),
    .denominator   (den_mag),
    .done_calc     (done_calc),
    .div_output    (div_output),
    .div_remainder (div_remainder)
  );

  //========================
  // State register
  //========================
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) curr_state <= RESET;
    else       curr_state <= next_state;
  end

  always_comb begin
    next_state = STATEX; // default
    case (curr_state)
        RESET: begin
        if (valid_i) next_state = READ;
        else         next_state = RESET;
        end
        READ:           next_state = CHECK;

        // TIP: compute the same condition here instead of using error_o
        CHECK: begin
        if ((denominator == 32'd0) ||
            (!mode && (numerator == 32'h8000_0000) && (denominator == 32'hFFFF_FFFF)))
            next_state = ERROR_ST;
        else
            next_state = PREP_INPUT;
        end

        PREP_INPUT:     next_state = INIT;

        INIT: begin
        if (calc_type) next_state = SHIFT_COMPUTE;
        else           next_state = DIVIDE_COMPUTE;
        end
        SHIFT_COMPUTE: begin
        if (done_calc) next_state = PREP_OUTPUT;
        else           next_state = SHIFT_COMPUTE;
        end
        DIVIDE_COMPUTE: begin
        if (done_calc) next_state = PREP_OUTPUT;
        else           next_state = DIVIDE_COMPUTE;
        end
        PREP_OUTPUT:    next_state = DONE;

        DONE: begin
        if (valid_i) next_state = READ;
        else         next_state = DONE;
        end

        ERROR_ST: begin
        if (valid_i) next_state = READ;
        else         next_state = ERROR_ST;
        end

        default:        next_state = RESET;
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

      // Local resets
      mode        <= 1'b0;
      out_type    <= 1'b0;
      final_sign  <= 1'b0;
      numerator   <= '0;
      denominator <= '0;

      num_mag     <= '0;
      den_mag     <= '0;

      start_calc  <= 1'b0;
      calc_type   <= 1'b0;
    end else begin
      // Defaults each cycle (overridden per-state below)
      start_calc <= 1'b0;
      ready_o    <= 1'b0;

      case (curr_state)

        RESET: begin
          error_o <= 2'b00;
        end

        READ: begin
          // Latch inputs
          mode        <= mode_i;
          out_type    <= out_type_i;
          numerator   <= as_u32(n_i);
          denominator <= as_u32(d_i);
          error_o     <= 2'b00; // clear previous errors
        end

        CHECK: begin
          if (denominator == 32'd0) begin
            error_o <= 2'b01; // divide-by-zero
            if (out_type) result <= 32'd0;
            else          result <= as_u32(numerator);
          end
          else if (!mode &&
                   (numerator   == 32'h8000_0000) &&
                   (denominator == 32'hFFFF_FFFF)) begin
            error_o <= 2'b10; // overflow
            if (out_type) result <= 32'hFFFF_FFFF;
            else          result <= 32'd0;
          end
          else begin
            error_o <= 2'b00;
          end
        end

        PREP_INPUT: begin
          if (mode) begin // unsigned
            final_sign <= 1'b0;
            num_mag    <= as_u32(numerator);
            den_mag    <= as_u32(denominator);
          end else begin // signed
            final_sign <= (numerator[31] ^ denominator[31]);
            if (numerator[31])   num_mag <= neg32(numerator);
            else                 num_mag <= as_u32(numerator);
            if (denominator[31]) den_mag <= neg32(denominator);
            else                 den_mag <= as_u32(denominator);
          end
          calc_type <= 1'b0; // divider path
        end

        INIT: begin
          start_calc <= 1'b1; // one-cycle kick
        end

        DIVIDE_COMPUTE: begin
          // wait for done_calc if core ever becomes multi-cycle
        end

        PREP_OUTPUT: begin
          if (out_type) begin
            if (final_sign) result <= neg32(div_output);
            else            result <= as_u32(div_output);
          end else begin
            if (final_sign) result <= neg32(div_remainder);
            else            result <= as_u32(div_remainder);
          end
        end

        DONE:      ready_o <= 1'b1;
        ERROR_ST:  ready_o <= 1'b1;

        default: /* do nothing */ ;

      endcase
    end
  end

endmodule