// divider_core.sv
module divider_core (
    input  logic        start_calc,
    input  logic [31:0] numerator,
    input  logic [31:0] denominator,
    output logic        done_calc,
    output logic [31:0] div_output,
    output logic [31:0] div_remainder
);
  // Simple combinational divide core gated by start_calc
  always_comb begin
    // defaults
    div_output    = 32'd0;
    div_remainder = 32'd0;
    done_calc     = 1'b0;

    if (start_calc) begin
      done_calc = 1'b1;
      if (denominator != 32'd0) begin
        div_output    = numerator / denominator; // unsigned divide
        div_remainder = numerator % denominator; // unsigned remainder
      end else begin
        // divide-by-zero behavior: quotient=0, remainder=numerator
        div_output    = 32'd0;
        div_remainder = numerator;
      end
    end
  end
endmodule