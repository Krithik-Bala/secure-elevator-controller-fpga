// Reworked elevator controller (written after the lab): explicit Moore FSM.
// Changes from rtl/el.v: active-low reset, non-blocking assignments only, the car's
// own floor register is compared with the target, fire alarm and overload take
// priority over everything (including authorised users), and travel is one floor
// per "tick" from a clock divider instead of one floor per clock.
// Inputs are expected to be synchronised and debounced before they reach this module.
module elevator_fsm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick,       // one-cycle pulse per floor of travel time
    input  wire       fast_tick,  // faster pulse used for authorised (PIN) users
    input  wire [1:0] req_floor,
    input  wire       req_valid,  // request button
    input  wire       overload,
    input  wire       fire,
    input  wire       pin_ok,     // correct PIN entered: fast travel
    output reg  [1:0] cur_floor,
    output wire       moving,
    output wire       dir_up
);
    localparam IDLE = 2'd0, MOVE = 2'd1, HOLD = 2'd2, FIRE = 2'd3;

    reg  [1:0] state, target;
    wire       step = pin_ok ? fast_tick : tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            cur_floor <= 2'd0;
            target    <= 2'd0;
        end else begin
            case (state)
                IDLE: if (fire) begin
                          target <= 2'd0;
                          state  <= FIRE;
                      end else if (!overload && req_valid && req_floor != cur_floor) begin
                          target <= req_floor;
                          state  <= MOVE;
                      end
                MOVE: if (fire) begin
                          target <= 2'd0;
                          state  <= FIRE;
                      end else if (overload)
                          state <= HOLD;
                      else if (cur_floor == target)
                          state <= IDLE;
                      else if (step)
                          cur_floor <= (target > cur_floor) ? cur_floor + 2'd1 : cur_floor - 2'd1;
                HOLD: if (fire) begin
                          target <= 2'd0;
                          state  <= FIRE;
                      end else if (!overload)
                          state <= MOVE;
                FIRE: if (cur_floor != 2'd0) begin
                          if (tick) cur_floor <= cur_floor - 2'd1;
                      end else if (!fire)
                          state <= IDLE;   // stay at the ground floor while the alarm is on
            endcase
        end
    end

    assign moving = (state == MOVE && cur_floor != target) || (state == FIRE && cur_floor != 2'd0);
    assign dir_up = (state == MOVE) && (target > cur_floor);
endmodule
