// divider_core.sv
// Sequential repeated-subtraction divider (NOT combinational)
//
// Behavior:
// - Assert start_calc for 1 cycle to begin (while idle)
// - Module raises done_calc for 1 cycle when result is ready
// - If denominator==0: quotient=0, remainder=numerator, done next cycle
//
// Notes:
// - Unsigned 32-bit
// - Worst-case latency: quotient cycles (can be up to 2^32-1, so very slow)
//   This is educational, not practical for performance.
module divider_core (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start_calc,
    input  logic [31:0] numerator,
    input  logic [31:0] denominator,

    output logic        done_calc,
    output logic [31:0] div_output,
    output logic [31:0] div_remainder
);

  typedef enum logic [1:0] {IDLE, RUN, DONE} state_t;
  state_t state;

  logic [31:0] rem;
  logic [31:0] den_latched;
  logic [31:0] quot;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= IDLE;
      done_calc     <= 1'b0;
      div_output    <= 32'd0;
      div_remainder <= 32'd0;
      rem           <= 32'd0;
      den_latched   <= 32'd0;
      quot          <= 32'd0;
    end else begin
      // default: done is a 1-cycle pulse
      done_calc <= 1'b0;

      case (state)
        IDLE: begin
          // hold outputs stable (optional); or clear them:
          // div_output    <= 32'd0;
          // div_remainder <= 32'd0;

          if (start_calc) begin
            // latch inputs
            den_latched <= denominator;
            rem         <= numerator;
            quot        <= 32'd0;

            if (denominator == 32'd0) begin
              // divide-by-zero: finish next cycle
              div_output    <= 32'd0;
              div_remainder <= numerator;
              state         <= DONE;
            end else begin
              state <= RUN;
            end
          end
        end

        RUN: begin
          // repeated subtraction: one subtract (and quotient increment) per cycle
          if (rem >= den_latched) begin
            rem  <= rem - den_latched;
            quot <= quot + 32'd1;
          end else begin
            // finished
            div_output    <= quot;
            div_remainder <= rem;
            state         <= DONE;
          end
        end

        DONE: begin
          done_calc <= 1'b1;   // pulse for 1 cycle
          state     <= IDLE;   // return to idle
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
