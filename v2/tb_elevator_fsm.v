`timescale 1ns/1ps
// Self-checking testbench for v2/elevator_fsm.v.
module tb_elevator_fsm;
    reg        clk, rst_n, req_valid, overload, fire, pin_ok;
    reg  [1:0] req_floor;
    reg  [1:0] div;
    wire       tick      = (div == 2'd3);   // one travel tick every 4 clocks
    wire       fast_tick = 1'b1;            // authorised users: one floor per clock
    wire [1:0] cur_floor;
    wire       moving, dir_up;
    integer    errors = 0;
    integer    took, normal_took;

    elevator_fsm dut (.clk(clk), .rst_n(rst_n), .tick(tick), .fast_tick(fast_tick),
                      .req_floor(req_floor), .req_valid(req_valid), .overload(overload),
                      .fire(fire), .pin_ok(pin_ok), .cur_floor(cur_floor),
                      .moving(moving), .dir_up(dir_up));

    initial clk = 1'b0;
    always #5 clk = ~clk;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) div <= 2'd0; else div <= div + 2'd1;

    task check(input ok, input [8*56-1:0] what);
        begin
            if (!ok) begin
                errors = errors + 1;
                $display("FAIL  %0s (cur_floor=%0d moving=%b dir_up=%b)", what, cur_floor, moving, dir_up);
            end else
                $display("PASS  %0s", what);
        end
    endtask

    task request(input [1:0] f);     // press a floor button for one clock
        begin
            req_floor = f; req_valid = 1'b1;
            @(posedge clk); #1;
            req_valid = 1'b0;
        end
    endtask

    task wait_floor(input [1:0] f, input integer max_clk, output integer n);
        begin
            n = 0;
            while (cur_floor !== f && n < max_clk) begin
                @(posedge clk); #1;
                n = n + 1;
            end
        end
    endtask

    task wait_clk(input integer k);
        integer i;
        begin
            for (i = 0; i < k; i = i + 1) begin @(posedge clk); #1; end
        end
    endtask

    initial begin
        rst_n = 1'b0; req_valid = 0; overload = 0; fire = 0; pin_ok = 0; req_floor = 2'd0;
        wait_clk(2);
        check(cur_floor == 2'd0 && !moving, "reset: car idle at the ground floor");
        rst_n = 1'b1;
        wait_clk(1);

        // Normal travel at one floor per tick
        request(2'd3);
        check(moving && dir_up, "request floor 3: moving up");
        wait_floor(2'd3, 30, normal_took);
        check(cur_floor == 2'd3, "normal travel reaches floor 3");
        check(normal_took >= 8, "normal travel takes one tick per floor");
        wait_clk(2);
        check(!moving, "idle after arrival");

        // Overload in the middle of a trip holds the car
        request(2'd0);
        check(moving && !dir_up, "request floor 0: moving down");
        wait_floor(2'd2, 10, took);
        overload = 1'b1;
        wait_clk(12);
        check(cur_floor == 2'd2 && !moving, "overload holds the car at floor 2");
        overload = 1'b0;
        wait_floor(2'd0, 30, took);
        check(cur_floor == 2'd0, "trip resumes after overload clears");
        wait_clk(2);

        // Authorised user: fast travel
        pin_ok = 1'b1;
        request(2'd3);
        wait_floor(2'd3, 10, took);
        check(cur_floor == 2'd3 && took <= 4, "PIN user travels one floor per clock");
        pin_ok = 1'b0;
        wait_clk(2);

        // Fire alarm: back to ground, ignores requests while active
        request(2'd1);
        wait_floor(2'd2, 10, took);
        fire = 1'b1;
        wait_floor(2'd0, 30, took);
        check(cur_floor == 2'd0, "fire alarm returns the car to the ground floor");
        request(2'd3);
        wait_clk(12);
        check(cur_floor == 2'd0, "requests ignored while the fire alarm is on");
        fire = 1'b0;
        wait_clk(2);
        request(2'd2);
        wait_floor(2'd2, 30, took);
        check(cur_floor == 2'd2, "normal service after the alarm clears");
        wait_clk(2);

        // Fire alarm beats an authorised user
        pin_ok = 1'b1;
        request(2'd3);
        fire = 1'b1;
        wait_floor(2'd0, 30, took);
        check(cur_floor == 2'd0, "fire alarm has priority over the PIN");
        fire = 1'b0; pin_ok = 1'b0;

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
