/*
 * SPDX-FileCopyrightText: 2026 Joel Kaplan and Amit Elmaliach
 * SPDX-License-Identifier: Apache-2.0
 */

module game_fsm #(
    parameter integer FRAME_W  = 640,
    parameter integer FRAME_H  = 480,
    parameter integer START1_X = 100,
    parameter integer START2_X = 540,
    parameter integer START_Y  = 240
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        p1_left,
    input  wire        p1_right,
    input  wire        p2_left,
    input  wire        p2_right,
    input  wire        restart,
    input  wire        vblank,
    input  wire        frame_start,

    output wire        game_req,
    output wire        game_we,
    output wire [16:0] game_addr,
    output wire [7:0]  game_wdata,
    input  wire [7:0]  game_rdata,
    input  wire        game_ack,

    output wire [7:0]  p1_head_x,
    output wire [6:0]  p1_head_y,
    output wire [7:0]  p2_head_x,
    output wire [6:0]  p2_head_y,
    output wire        clear_active
);

    // Movement is tracked on a 4x4 pixel grid to shrink coordinate math.
    localparam [7:0] CELL_W = FRAME_W / 4;
    localparam [6:0] CELL_H = FRAME_H / 4;
    localparam [7:0] WALL_T = (FRAME_W == 64) ? 8'd1 : 8'd2;
    localparam [7:0] WALL_MAX_X = CELL_W - WALL_T;
    localparam [6:0] WALL_MAX_Y = CELL_H - WALL_T[6:0];
    localparam [13:0] FRAME_BYTES_COUNT = (FRAME_W == 64) ? 14'd192 : 14'd9600;

    // FSM states. Minimal 1x1 mode keeps two players but uses cardinal
    // movement instead of curved fixed-point movement.
    localparam [2:0] S_OVER  = 3'd1;
    localparam [2:0] IDLE    = 3'd2;
    localparam [2:0] ANGLE   = 3'd3;
    localparam [2:0] CHECK   = 3'd4;
    localparam [2:0] READ    = 3'd5;
    localparam [2:0] WRITE   = 3'd6;
    localparam [2:0] S_CLEAR = 3'd7;

    reg [2:0]  state;
    reg [13:0] clear_byte;

    reg [7:0] p1_x;
    reg [6:0] p1_y;
    reg [7:0] p2_x;
    reg [6:0] p2_y;

    // 0=right, 1=down, 2=left, 3=up.
    reg [1:0] p1_dir;
    reg [1:0] p2_dir;
    reg       p1_turn_prev;
    reg       p2_turn_prev;
    reg       active_player;  // 0 = player 1, 1 = player 2
    reg [1:0] paint_row;

    wire state_read  = (state == READ);
    wire state_write = (state == WRITE);
    wire state_clear = (state == S_CLEAR);

    assign clear_active = state_clear;
    assign p1_head_x = p1_x;
    assign p1_head_y = p1_y;
    assign p2_head_x = p2_x;
    assign p2_head_y = p2_y;
    assign game_we = (state_write && vblank) ||
                     (state_clear && (clear_byte != FRAME_BYTES_COUNT));
    assign game_req = (state_read && vblank) || game_we;

    // -------------------------------------------------------------------------
    // Shared cardinal movement
    // -------------------------------------------------------------------------
    wire [1:0] active_dir = active_player ? p2_dir : p1_dir;
    wire [7:0] active_x = active_player ? p2_x : p1_x;
    wire [6:0] active_y = active_player ? p2_y : p1_y;
    wire [7:0] calc_next_x =
        (active_dir == 2'd0) ? (active_x + 8'd1) :
        (active_dir == 2'd2) ? (active_x - 8'd1) : active_x;
    wire [6:0] calc_next_y =
        (active_dir == 2'd1) ? (active_y + 7'd1) :
        (active_dir == 2'd3) ? (active_y - 7'd1) : active_y;
    wire hit_wall =
        (calc_next_x < WALL_T || calc_next_x >= WALL_MAX_X ||
         calc_next_y < WALL_T[6:0] || calc_next_y >= WALL_MAX_Y);

    // -------------------------------------------------------------------------
    // PSRAM packed-cell address calculation
    // -------------------------------------------------------------------------
    // Store one bit per 4 horizontal pixels, and paint four physical rows.
    // The display streamer expands each stored bit back to four VGA pixels.
    wire [8:0] target_y = {calc_next_y, 2'b00} + {7'd0, paint_row};
    wire [16:0] target_row_byte_addr =
        (FRAME_W == 64) ? {6'd0, target_y, 2'b00} :
                          ({4'b0000, target_y, 4'b0000} +
                           {6'b000000, target_y, 2'b00});
    wire [16:0] target_byte_addr =
        target_row_byte_addr + {12'd0, calc_next_x[7:3]};
    wire [2:0] target_bit_sel = calc_next_x[2:0];

    assign game_addr = state_clear ? {3'b000, clear_byte} :
                                     target_byte_addr;

    function pixel_from_byte;
        input [7:0] byte_data;
        input [2:0] bit_sel;
        begin
            pixel_from_byte = byte_data[bit_sel];
        end
    endfunction

    function [7:0] patch_pixel_byte;
        input [7:0] byte_data;
        input [2:0] bit_sel;
        begin
            patch_pixel_byte = byte_data;
            patch_pixel_byte[bit_sel] = 1'b1;
        end
    endfunction

    wire target_pixel_data = pixel_from_byte(game_rdata, target_bit_sel);
    wire p2_groove_cell = calc_next_x[0] ^ calc_next_y[0];
    // P2 skips most rows in some cells, making a thick black groove.
    wire p2_groove_row = |paint_row;
    wire paint_this_row = !active_player || !p2_groove_cell || !p2_groove_row;
    assign game_wdata = state_clear ? 8'b0 :
                        paint_this_row ? patch_pixel_byte(game_rdata, target_bit_sel) :
                        game_rdata;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_CLEAR;
            clear_byte          <= 14'd0;
            paint_row           <= 2'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (frame_start) begin
                        if (paint_row == 2'd3) begin
                            paint_row <= 2'd0;
                            active_player <= 1'b0;
                            state <= ANGLE;
                        end else begin
                            paint_row <= paint_row + 2'd1;
                        end
                    end
                end

                ANGLE: begin
                    if (!vblank) begin
                        state <= IDLE;
                    end else begin
                        // Edge-detect per player so holding a button makes one
                        // 90-degree turn instead of rotating every frame.
                        if (!active_player) begin
                            if ((p1_left | p1_right) && !p1_turn_prev)
                                p1_dir <= p1_right ? (p1_dir + 2'd1) : (p1_dir - 2'd1);
                            p1_turn_prev <= p1_left | p1_right;
                        end else begin
                            if ((p2_left | p2_right) && !p2_turn_prev)
                                p2_dir <= p2_right ? (p2_dir + 2'd1) : (p2_dir - 2'd1);
                            p2_turn_prev <= p2_left | p2_right;
                        end
                        state <= CHECK;
                    end
                end

                CHECK: begin
                    if (!vblank) begin
                        state <= IDLE;
                    end else begin
                        if (hit_wall) begin
                            state <= S_OVER;
                        end else begin
                            paint_row <= 2'd0;
                            state <= READ;
                        end
                    end
                end

                READ: begin
                    if (!vblank) begin
                        state    <= IDLE;
                    end else begin
                        if (game_ack) begin
                            if (target_pixel_data) begin
                                state <= S_OVER;
                            end else begin
                                state      <= WRITE;
                            end
                        end
                    end
                end

                WRITE: begin
                    if (!vblank) begin
                        state    <= IDLE;
                    end else begin
                        if (game_ack) begin
                            if (paint_row != 2'd3) begin
                                paint_row <= paint_row + 2'd1;
                                state <= READ;
                            end else begin
                                paint_row <= 2'd0;
                                if (!active_player) begin
                                    p1_x <= calc_next_x;
                                    p1_y <= calc_next_y;
                                    active_player <= 1'b1;
                                    state <= ANGLE;
                                end else begin
                                    p2_x <= calc_next_x;
                                    p2_y <= calc_next_y;
                                    active_player <= 1'b0;
                                    state <= IDLE;
                                end
                            end
                        end
                    end
                end

                S_OVER: begin
                    if (restart) begin
                        clear_byte <= 14'd0;
                        paint_row <= 2'd0;
                        state <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    // Zero every framebuffer byte before the game starts.
                    if (clear_byte != FRAME_BYTES_COUNT) begin
                        if (game_ack) begin
                            clear_byte <= clear_byte + 1'b1;
                        end
                    end else begin
                        clear_byte <= 14'd0;
                        p1_x <= START1_X[9:2];
                        p1_y <= START_Y[8:2];
                        p2_x <= START2_X[9:2];
                        p2_y <= START_Y[8:2];
                        p1_dir <= 2'd0;
                        p2_dir <= 2'd2;
                        p1_turn_prev <= 1'b0;
                        p2_turn_prev <= 1'b0;
                        active_player <= 1'b0;
                        paint_row <= 2'd0;
                        state <= IDLE;
                    end
                end

                default: begin
                    state    <= IDLE;
                end
            endcase
        end
    end

endmodule
