// Lift controller for a 4-floor building (ground + 3 floors), written as a Moore FSM.
//
// It remembers every button press and serves them the way real lifts do
// ("collective control", also known as the elevator or SCAN algorithm):
//   - keep travelling in one direction, stopping at every floor that has a call,
//   - turn around only when no calls are left ahead,
//   - go idle when no calls are left at all.
//
// Priority, highest first:
//   1. Fire alarm : cancel all calls, go non-stop to the ground floor, open the doors,
//                   ignore every button until the alarm clears (fire recall).
//   2. Overload   : doors stay open and the lift does not leave.
//   3. PIN express: an authorised user's floor is served non-stop; calls skipped on the
//                   way stay remembered and are served afterwards.
//   4. Normal collective service.
//
// "tick" is a slow timing pulse from a clock divider: one tick = time to travel one floor,
// and the doors stay open for DOOR_TICKS ticks. Buttons are expected to be synchronised
// and debounced before they reach this module.
module lift_ctrl #(
    parameter DOOR_TICKS = 3
) (
    input  wire       clk,
    input  wire       rst_n,        // active-low reset: lift at the ground floor, idle
    input  wire       tick,
    input  wire [3:0] floor_call,   // call button outside the lift on each floor
    input  wire [3:0] cabin_call,   // floor buttons inside the lift
    input  wire       pin_ok,       // correct PIN entered on the cabin keypad
    input  wire       overload,     // load sensor
    input  wire       fire,         // fire alarm
    output reg  [1:0] cur_floor,    // where the lift is (0 = ground)
    output reg        dir_up,       // direction of travel
    output wire       moving,
    output wire       door_open,
    output reg  [3:0] pending,      // remembered calls, one bit per floor (for indicator LEDs)
    output reg        express       // PIN express trip in progress
);
    localparam IDLE = 2'd0, MOVE = 2'd1, DOOR = 2'd2, FIRE = 2'd3;

    reg [1:0] state, exp_target;
    reg [2:0] door_cnt;

    function [1:0] first_set(input [3:0] v);         // lowest floor button pressed
        first_set = v[0] ? 2'd0 : v[1] ? 2'd1 : v[2] ? 2'd2 : 2'd3;
    endfunction

    wire [3:0] above_mask = 4'b1110 << cur_floor;          // floors above the lift
    wire [3:0] below_mask = (4'b0001 << cur_floor) - 4'd1; // floors below the lift

    // Where the lift has work: the express floor, or any remembered call
    wire want_up   = express ? (exp_target > cur_floor)  : |(pending & above_mask);
    wire want_down = express ? (exp_target < cur_floor)  : |(pending & below_mask);
    wire stop_here = express ? (exp_target == cur_floor) : pending[cur_floor];
    wire go_on     = dir_up ? want_up : want_down;         // more work in the current direction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            cur_floor  <= 2'd0;
            dir_up     <= 1'b1;
            pending    <= 4'd0;
            express    <= 1'b0;
            exp_target <= 2'd0;
            door_cnt   <= 3'd0;
        end else if (fire || state == FIRE) begin
            // 1. Fire recall
            pending  <= 4'd0;
            express  <= 1'b0;
            door_cnt <= 3'd0;
            dir_up   <= 1'b0;
            if (state != FIRE)
                state <= FIRE;
            else if (cur_floor != 2'd0) begin
                if (tick) cur_floor <= cur_floor - 2'd1;
            end else if (!fire)
                state <= IDLE;                              // back in service
        end else begin
            // Remember new presses; forget this floor's call once its doors are open
            pending <= (pending | floor_call | cabin_call)
                       & ~((state == DOOR) ? (4'b0001 << cur_floor) : 4'b0000);

            case (state)
                IDLE:
                    if (overload || stop_here) begin        // open the doors here
                        state    <= DOOR;
                        door_cnt <= 3'd0;
                    end else if (want_up) begin
                        dir_up <= 1'b1;
                        state  <= MOVE;
                    end else if (want_down) begin
                        dir_up <= 1'b0;
                        state  <= MOVE;
                    end
                MOVE:
                    if (stop_here) begin                    // a call at this floor: stop
                        state    <= DOOR;
                        door_cnt <= 3'd0;
                    end else if (!go_on) begin              // nothing left ahead
                        if (want_up || want_down) dir_up <= ~dir_up;   // calls behind: turn around
                        else                      state  <= IDLE;
                    end else if (tick)
                        cur_floor <= dir_up ? cur_floor + 2'd1 : cur_floor - 2'd1;
                DOOR: begin
                    if (express && exp_target == cur_floor)
                        express <= 1'b0;                    // express trip done
                    if (overload)
                        door_cnt <= 3'd0;                   // 2. overload: doors stay open
                    else if (door_cnt == DOOR_TICKS) begin  // close the doors
                        door_cnt <= 3'd0;
                        state    <= (want_up || want_down) ? MOVE : IDLE;
                    end else if (tick)
                        door_cnt <= door_cnt + 3'd1;
                end
                default:
                    state <= IDLE;
            endcase

            // 3. PIN express: the floor pressed inside the lift becomes a non-stop target
            if (pin_ok && cabin_call != 4'd0 && !express) begin
                express    <= 1'b1;
                exp_target <= first_set(cabin_call);
            end
        end
    end

    assign door_open = (state == DOOR) || (state == FIRE && cur_floor == 2'd0);
    assign moving    = (state == MOVE) || (state == FIRE && cur_floor != 2'd0);
endmodule
