`timescale 1ns/1ps
// Self-checking testbench for the original lab design (lab/el.v).
// i_f is the present-floor sensor input. Like a real floor sensor, the testbench
// feeds the car's position (c_f) back into i_f after every move.
module tb_el;
    reg  [1:0] i_f, f_f, pin;
    reg        clk, ov, fa;
    wire       direction;
    wire [1:0] c_f;
    integer    errors = 0;
    integer    n;

    el dut (.i_f(i_f), .f_f(f_f), .clk(clk), .ov(ov), .fa(fa), .pin(pin),
            .direction(direction), .c_f(c_f));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task step;                       // one rising edge, then let outputs settle
        begin
            @(posedge clk); #1;
        end
    endtask

    task check(input [1:0] floor, input dir, input [8*56-1:0] what);
        begin
            if (c_f !== floor || direction !== dir) begin
                errors = errors + 1;
                $display("FAIL  %0s: c_f=%b direction=%b, expected c_f=%b direction=%b",
                         what, c_f, direction, floor, dir);
            end else
                $display("PASS  %0s", what);
        end
    endtask

    initial begin
        ov = 0; fa = 0; pin = 2'b00; i_f = 2'b00; f_f = 2'b00;

        // There is no reset: the fire alarm is the first thing that gives c_f a known value.
        fa = 1; step; check(2'b00, 1'b0, "fire alarm puts the car at the ground floor");
        fa = 0;

        // Normal travel up, one floor per clock, i_f following the car
        f_f = 2'b11; i_f = c_f;
        step; check(2'b01, 1'b1, "normal travel up: floor 1");
        i_f = c_f; step; check(2'b10, 1'b1, "normal travel up: floor 2");
        i_f = c_f; step; check(2'b11, 1'b1, "normal travel up: floor 3");
        i_f = c_f; step; check(2'b11, 1'b0, "arrived at floor 3, direction cleared");

        // Normal travel down
        f_f = 2'b01; i_f = c_f;
        step; check(2'b10, 1'b0, "normal travel down: floor 2");
        i_f = c_f; step; check(2'b01, 1'b0, "normal travel down: floor 1");
        i_f = c_f; step; check(2'b01, 1'b0, "arrived at floor 1");

        // Overload holds the car even with a pending request
        ov = 1; f_f = 2'b11; i_f = c_f;
        for (n = 0; n < 3; n = n + 1) step;
        check(2'b01, 1'b0, "overload holds the car for 3 clocks");
        ov = 0;

        // Correct PIN: express travel straight to the requested floor
        pin = 2'b10; i_f = 2'b01; f_f = 2'b11;
        step; check(2'b11, 1'b1, "correct PIN: express 1 -> 3 in one clock");
        i_f = 2'b11; f_f = 2'b00;
        step; check(2'b00, 1'b0, "correct PIN: express 3 -> 0 in one clock");

        // Wrong PIN: normal one-floor step instead
        pin = 2'b01; i_f = 2'b00; f_f = 2'b10;
        step; check(2'b01, 1'b1, "wrong PIN: normal one-floor step");

        // Priority order as implemented: overload > PIN > fire alarm > normal
        ov = 1; pin = 2'b10; i_f = 2'b10; f_f = 2'b00;
        step; check(2'b10, 1'b0, "overload has priority over the PIN");
        ov = 0; fa = 1; i_f = 2'b10; f_f = 2'b11;
        step; check(2'b11, 1'b1, "PIN has priority over the fire alarm (see README)");
        pin = 2'b00; i_f = 2'b11;
        step; check(2'b00, 1'b0, "fire alarm without PIN returns to ground");
        fa = 0;

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
