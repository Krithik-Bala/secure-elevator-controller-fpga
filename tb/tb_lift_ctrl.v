`timescale 1ns/1ps
// Self-checking testbench for rtl/lift_ctrl.v. Every time the doors open, the floor is
// logged, so each scenario can check the exact order in which floors were served.
module tb_lift_ctrl;
    reg        clk, rst_n, pin_ok, overload, fire;
    reg  [3:0] floor_call, cabin_call;
    reg  [1:0] div;
    wire       tick = (div == 2'd3);            // one floor of travel every 4 clocks
    wire [1:0] cur_floor;
    wire       dir_up, moving, door_open, express;
    wire [3:0] pending;
    integer    errors = 0;

    lift_ctrl #(.DOOR_TICKS(2)) dut (
        .clk(clk), .rst_n(rst_n), .tick(tick), .floor_call(floor_call), .cabin_call(cabin_call),
        .pin_ok(pin_ok), .overload(overload), .fire(fire), .cur_floor(cur_floor),
        .dir_up(dir_up), .moving(moving), .door_open(door_open), .pending(pending),
        .express(express));

    initial clk = 1'b0;
    always #5 clk = ~clk;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) div <= 2'd0; else div <= div + 2'd1;

    // Stop log: the floor at every door opening
    reg     door_q;
    integer stops [0:7];
    integer n_stops;
    always @(posedge clk) begin
        if (door_open && !door_q && n_stops < 8) begin
            stops[n_stops] = cur_floor;
            n_stops = n_stops + 1;
        end
        door_q <= door_open;
    end

    task check(input ok, input [8*80-1:0] what);
        begin
            if (!ok) begin
                errors = errors + 1;
                $display("FAIL  %0s (floor=%0d door=%b moving=%b pending=%b express=%b)",
                         what, cur_floor, door_open, moving, pending, express);
            end else
                $display("PASS  %0s", what);
        end
    endtask

    task clocks(input integer k);
        integer i;
        begin
            for (i = 0; i < k; i = i + 1) begin @(posedge clk); #1; end
        end
    endtask

    task press(input [3:0] at_floor, input [3:0] in_cabin, input pin);   // held for one clock
        begin
            floor_call = at_floor; cabin_call = in_cabin; pin_ok = pin;
            @(posedge clk); #1;
            floor_call = 4'd0; cabin_call = 4'd0; pin_ok = 1'b0;
        end
    endtask

    task wait_floor(input [1:0] f);
        integer n;
        begin
            n = 0;
            while (cur_floor !== f && n < 200) begin @(posedge clk); #1; n = n + 1; end
        end
    endtask

    task wait_stops(input integer k);
        integer n;
        begin
            n = 0;
            while (n_stops < k && n < 400) begin @(posedge clk); #1; n = n + 1; end
        end
    endtask

    task wait_idle;                               // doors closed and not moving
        integer n;
        begin
            n = 0;
            while ((door_open || moving) && n < 400) begin @(posedge clk); #1; n = n + 1; end
            clocks(2);
        end
    endtask

    initial begin
        rst_n = 1'b0; pin_ok = 0; overload = 0; fire = 0; floor_call = 0; cabin_call = 0;
        door_q = 1'b0; n_stops = 0;
        clocks(2);
        check(cur_floor == 0 && !door_open && !moving, "reset: lift idle at the ground floor, doors closed");
        rst_n = 1'b1;
        clocks(1);

        // 1. Stop on the way: floor 3 calls; floor 2 calls while the lift passes floor 1
        n_stops = 0;
        press(4'b1000, 4'b0000, 1'b0);
        wait_floor(2'd1);
        press(4'b0100, 4'b0000, 1'b0);
        wait_stops(2);
        check(n_stops == 2 && stops[0] == 2 && stops[1] == 3, "stops at floor 2 on the way up, then floor 3");
        wait_idle;

        // 2. Keep direction, then turn around: going down to 0; calls at 1 (ahead) and 3 (behind)
        n_stops = 0;
        press(4'b0000, 4'b0001, 1'b0);
        wait_floor(2'd2);
        press(4'b1010, 4'b0000, 1'b0);
        wait_stops(3);
        check(n_stops == 3 && stops[0] == 1 && stops[1] == 0 && stops[2] == 3,
              "serves 1 and 0 going down, then turns around for 3");
        wait_idle;

        // 3. PIN express: calls waiting at 2 and 1; PIN user inside goes to 0 non-stop
        n_stops = 0;
        press(4'b0110, 4'b0001, 1'b1);
        check(express, "PIN accepted: express trip started");
        wait_stops(3);
        check(n_stops == 3 && stops[0] == 0 && stops[1] == 1 && stops[2] == 2,
              "express skips 2 and 1, then the lift serves them");
        check(!express, "express ends at the PIN floor");
        wait_idle;

        // 4. Overload beats PIN: doors stay open, lift does not leave
        overload = 1'b1;
        press(4'b0000, 4'b1000, 1'b1);
        clocks(20);
        check(cur_floor == 2 && door_open && express, "overloaded: doors held open at floor 2, express waits");
        n_stops = 0;
        overload = 1'b0;
        wait_stops(1);
        check(n_stops == 1 && stops[0] == 3, "load removed: express continues to floor 3");
        wait_idle;

        // 5. Fire alarm beats everything: PIN trip to floor 1 is cancelled, lift recalled
        n_stops = 0;
        press(4'b0000, 4'b0010, 1'b1);
        wait_floor(2'd2);
        fire = 1'b1;
        wait_floor(2'd0);
        press(4'b0100, 4'b0100, 1'b0);            // buttons pressed during the alarm
        clocks(12);
        check(cur_floor == 0 && door_open && pending == 4'd0 && !express,
              "fire: non-stop to ground, doors open, calls cancelled and ignored");
        check(n_stops == 1 && stops[0] == 0, "fire: doors did not open at floor 1 on the way");
        fire = 1'b0;
        clocks(3);
        check(!door_open && !moving && pending == 4'd0, "alarm cleared: lift back in service, idle");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
