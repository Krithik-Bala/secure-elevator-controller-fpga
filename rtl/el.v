// Secure elevator controller: original Digital Systems Design lab design (as submitted).
// Target: Intel MAX 10 10M50DAF484C7G (Terasic DE10-Lite).
//   i_f       : present floor (floor-sensor input)      00 = ground ... 11 = 3rd floor
//   f_f       : requested (final) floor
//   ov        : overload sensor  -> hold the car
//   pin       : 2-bit access PIN -> 2'b10 gives express travel straight to f_f
//   fa        : fire alarm       -> return to the ground floor
//   c_f       : current floor of the car
//   direction : 1 = moving up, 0 = down / stopped
module el (
    input [1:0] i_f,
    input [1:0] f_f,
    input clk,
    input ov, fa,
    input [1:0] pin,
    output reg direction,
    output reg [1:0] c_f
);

always @(posedge clk) begin
    if (ov == 1) begin
        c_f = i_f;
        direction = 0;
    end
    else if (pin == 2'b10) begin
        case (f_f)
            2'b00: begin
                if (i_f == 2'b00) begin direction = 1'b0; c_f = 2'b00; end
                else if (i_f == 2'b01) begin direction = 1'b0; c_f = 2'b00; end
                else if (i_f == 2'b10) begin direction = 1'b0; c_f = 2'b00; end
                else if (i_f == 2'b11) begin direction = 1'b0; c_f = 2'b00; end
            end
            2'b01: begin
                if (i_f == 2'b00) begin direction = 1'b1; c_f = 2'b01; end
                else if (i_f == 2'b01) begin direction = 1'b0; c_f = 2'b01; end
                else if (i_f == 2'b10) begin direction = 1'b0; c_f = 2'b01; end
                else if (i_f == 2'b11) begin direction = 1'b0; c_f = 2'b01; end
            end
            2'b10: begin
                if (i_f == 2'b00) begin direction = 1'b1; c_f = 2'b10; end
                else if (i_f == 2'b01) begin direction = 1'b1; c_f = 2'b10; end
                else if (i_f == 2'b10) begin direction = 1'b0; c_f = 2'b10; end
                else if (i_f == 2'b11) begin direction = 1'b0; c_f = 2'b10; end
            end
            2'b11: begin
                if (i_f == 2'b00) begin direction = 1'b1; c_f = 2'b11; end
                else if (i_f == 2'b01) begin direction = 1'b1; c_f = 2'b11; end
                else if (i_f == 2'b10) begin direction = 1'b1; c_f = 2'b11; end
                else if (i_f == 2'b11) begin direction = 1'b0; c_f = 2'b11; end
            end
        endcase
    end
    else if (fa == 1) begin
        c_f = 2'b00;
        direction = 0;
    end
    else begin
        if (i_f < f_f) begin
            c_f <= c_f + 1;
            direction <= 1'b1;
        end
        else if (i_f > f_f) begin
            c_f <= c_f - 1;
            direction <= 1'b0;
        end
        else begin
            c_f <= i_f;
            direction <= 1'b0;
        end
    end
end

endmodule
