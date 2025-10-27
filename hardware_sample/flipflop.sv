module flip_flop (
    input logic clk_i, reset_i, d_i,
    output logic q_o
);

    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i) begin
            q_o <= 1'b0;
        end else begin
            q_o <= d_i;
        end
    end

endmodule
