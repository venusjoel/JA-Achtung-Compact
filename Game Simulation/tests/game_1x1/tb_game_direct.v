`timescale 1ns/1ps
// Direct-RAM harness for the 1x1 game engine. The PSRAM controller, QSPI
// pins, VGA sync, and gamepad decoder are all bypassed: the game FSM talks to
// a behavioral framebuffer with a short fixed-latency handshake, and vblank /
// frame_start are driven straight from the cocotb test. This keeps the exact
// game semantics (one ack per transaction, ANGLE..WRITE only during vblank)
// while running hundreds of times faster than the QSPI path.
module tb_game_direct #(
    parameter integer FRAME_W  = 64,
    parameter integer FRAME_H  = 48,
    parameter integer START1_X = 10,
    parameter integer START2_X = 53,
    parameter integer START_Y  = 24
);
    localparam integer MEM_BYTES = (FRAME_W == 64) ? 192 : 9600;

    reg clk;
    reg rst_n;
    reg p1_left;
    reg p1_right;
    reg p2_left;
    reg p2_right;
    reg restart;
    reg vblank;
    reg frame_start;

    wire        game_req;
    wire        game_we;
    wire [16:0] game_addr;
    wire [7:0]  game_wdata;
    reg  [7:0]  game_rdata;
    reg         game_ack;

    wire [7:0] p1_head_x;
    wire [6:0] p1_head_y;
    wire [7:0] p2_head_x;
    wire [6:0] p2_head_y;
    wire       clear_active;

    game_fsm #(
        .FRAME_W(FRAME_W),
        .FRAME_H(FRAME_H),
        .START1_X(START1_X),
        .START2_X(START2_X),
        .START_Y(START_Y)
    ) u_engine (
        .clk(clk),
        .rst_n(rst_n),
        .p1_left(p1_left),
        .p1_right(p1_right),
        .p2_left(p2_left),
        .p2_right(p2_right),
        .restart(restart),
        .vblank(vblank),
        .frame_start(frame_start),
        .game_req(game_req),
        .game_we(game_we),
        .game_addr(game_addr),
        .game_wdata(game_wdata),
        .game_rdata(game_rdata),
        .game_ack(game_ack),
        .p1_head_x(p1_head_x),
        .p1_head_y(p1_head_y),
        .p2_head_x(p2_head_x),
        .p2_head_y(p2_head_y),
        .clear_active(clear_active)
    );

    // Behavioral framebuffer with the same one-transaction-per-ack handshake
    // as the PSRAM controller: request seen on one edge, data/ack on the next.
    reg [7:0] mem [0:MEM_BYTES-1];
    reg pending;

    integer i;
    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1)
            mem[i] = 8'h00;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            game_ack <= 1'b0;
            pending  <= 1'b0;
        end else begin
            game_ack <= 1'b0;
            if (pending) begin
                if (game_we)
                    mem[game_addr] <= game_wdata;
                else
                    game_rdata <= mem[game_addr];
                game_ack <= 1'b1;
                pending  <= 1'b0;
            end else if (game_req && !game_ack) begin
                pending <= 1'b1;
            end
        end
    end
endmodule
