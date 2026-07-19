/*
 * SPDX-FileCopyrightText: 2026 Joel Kaplan and Amit Elmaliach
 * SPDX-License-Identifier: Apache-2.0
 */

module tt_um_ja_achtung_1x1 (
    input  wire [7:0] ui_in,    // Dedicated inputs (Buttons)
    output wire [7:0] uo_out,   // Dedicated outputs (VGA)
    input  wire [7:0] uio_in,   // Bidirectional inputs (QSPI MISO)
    output wire [7:0] uio_out,  // Bidirectional outputs (QSPI CS, CLK, MOSI)
    output wire [7:0] uio_oe,   // Bidirectional enables
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // System clock
    input  wire       rst_n     // reset_n - low to reset
);

`ifdef COCOTB_SIM
`ifdef FULL_VGA_SIM
    localparam integer FRAME_W  = 640;
    localparam integer FRAME_H  = 480;
    localparam integer START1_X = 100;
    localparam integer START2_X = 540;
    localparam integer START_Y  = 240;
`elsif FAST_COMPARE_SIM
    localparam integer FRAME_W  = 640;
    localparam integer FRAME_H  = 480;
    localparam integer START1_X = 100;
    localparam integer START2_X = 540;
    localparam integer START_Y  = 240;
`else
    localparam integer FRAME_W  = 64;
    localparam integer FRAME_H  = 48;
    localparam integer START1_X = 10;
    localparam integer START2_X = 53;
    localparam integer START_Y  = 24;
`endif
`else
    localparam integer FRAME_W  = 640;
    localparam integer FRAME_H  = 480;
    localparam integer START1_X = 100;
    localparam integer START2_X = 540;
    localparam integer START_Y  = 240;
`endif

    localparam integer BURST_BYTES = 4;
    localparam integer DATA_WIDTH  = 8 * BURST_BYTES;

    // Serial Gamepad PMOD on ui_in[4]=LATCH, ui_in[5]=CLK, ui_in[6]=DATA.
    // The 1x1 game only needs L/R, so this tiny decoder keeps just four
    // button bits instead of the full controller state.
    (* async_reg = "true" *) reg [1:0] pad_data_sync;
    (* async_reg = "true" *) reg [1:0] pad_clk_sync;
    (* async_reg = "true" *) reg [1:0] pad_latch_sync;
    reg       pad_clk_prev;
    reg       pad_latch_prev;
    reg [4:0] pad_bit_count;
    reg [1:0] pad_next_start;
    reg [1:0] pad_next_l;
    reg [1:0] pad_next_r;
    reg       pad_half_present;
    reg       pad_start;
    reg [1:0] pad_l;
    reg [1:0] pad_r;

    wire pad_latch_rise = pad_latch_sync[1] & ~pad_latch_prev;
    wire pad_clk_rise   = pad_clk_sync[1] & ~pad_clk_prev;

    wire p1_left  = pad_l[0];
    wire p1_right = pad_r[0];
    wire p2_left  = pad_l[1];
    wire p2_right = pad_r[1];
    wire restart_game = pad_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pad_data_sync    <= 2'b00;
            pad_clk_sync     <= 2'b00;
            pad_latch_sync   <= 2'b00;
            pad_clk_prev     <= 1'b0;
            pad_latch_prev   <= 1'b0;
            pad_bit_count    <= 5'd0;
            pad_next_start   <= 2'b00;
            pad_next_l       <= 2'b00;
            pad_next_r       <= 2'b00;
            pad_half_present <= 1'b0;
            pad_start        <= 1'b0;
            pad_l            <= 2'b00;
            pad_r            <= 2'b00;
        end else begin
            pad_data_sync  <= {pad_data_sync[0], ui_in[6]};
            pad_clk_sync   <= {pad_clk_sync[0], ui_in[5]};
            pad_latch_sync <= {pad_latch_sync[0], ui_in[4]};
            pad_clk_prev   <= pad_clk_sync[1];
            pad_latch_prev <= pad_latch_sync[1];

            if (pad_latch_rise) begin
                if (pad_bit_count == 5'd24) begin
                    pad_start <= |pad_next_start;
                    pad_l <= pad_next_l;
                    pad_r <= pad_next_r;
                end
                pad_bit_count    <= 5'd0;
                pad_next_start   <= 2'b00;
                pad_next_l       <= 2'b00;
                pad_next_r       <= 2'b00;
                pad_half_present <= 1'b0;
            end else if (pad_clk_rise) begin
                if (pad_bit_count != 5'd24) begin
                    // Decode Start plus turn inputs with the smallest extra
                    // state we can get away with in the 1x1 build.
                    case (pad_bit_count)
                        5'd6,  5'd10: if (pad_data_sync[1]) pad_next_l[1] <= 1'b1;
                        5'd7,  5'd11: if (pad_data_sync[1]) pad_next_r[1] <= 1'b1;
                        5'd3:          if (pad_data_sync[1]) pad_next_start[1] <= 1'b1;
                        5'd15:         if (pad_data_sync[1]) pad_next_start[0] <= 1'b1;
                        5'd18, 5'd22: if (pad_data_sync[1]) pad_next_l[0] <= 1'b1;
                        5'd19, 5'd23: if (pad_data_sync[1]) pad_next_r[0] <= 1'b1;
                        default: begin end
                    endcase

                    // A disconnected controller half is twelve ones. Mask
                    // its optimistic button accumulation at the boundary and
                    // reuse this single presence bit for the second half.
                    if (pad_bit_count == 5'd11) begin
                        if (!(pad_half_present || !pad_data_sync[1])) begin
                            pad_next_start[1] <= 1'b0;
                            pad_next_l[1] <= 1'b0;
                            pad_next_r[1] <= 1'b0;
                        end
                        pad_half_present <= 1'b0;
                    end else if (pad_bit_count == 5'd23) begin
                        if (!(pad_half_present || !pad_data_sync[1])) begin
                            pad_next_start[0] <= 1'b0;
                            pad_next_l[0] <= 1'b0;
                            pad_next_r[0] <= 1'b0;
                        end
                        pad_half_present <= 1'b0;
                    end else if (!pad_data_sync[1]) begin
                        pad_half_present <= 1'b1;
                    end

                    pad_bit_count <= pad_bit_count + 5'd1;
                end
            end
        end
    end

    reg pixel_div;
    reg vblank_prev_top;
    wire pixel_tick = pixel_div; //the VGA 25MHz pixel clock is derived by dividing the 50MHz system clock

    //current pixel coordinates and sync signals from the VGA timing generator
    wire [9:0] h_count;
    wire [9:0] v_count;
    //VGA sync pulses and active video signal
    wire       hsync;
    wire       vsync;
    //active_video is high when the current pixel coordinates are within the visible display area
    wire       active_video;
    //true during blanking
    wire       vblank;
    wire       frame_start = vblank && !vblank_prev_top;
    wire       pixel_occupied;

    //this is for the game engine
    wire        game_req;    // Game wants a PSRAM transaction (read or write)
    wire        game_we;    //1 means write transaction, 0 means read transaction
    wire        game_ack;   // PSRAM transaction is complete
    wire        clear_active;
    wire [7:0]  p1_head_x;
    wire [6:0]  p1_head_y;
    wire [7:0]  p2_head_x;
    wire [6:0]  p2_head_y;
    wire [16:0] game_addr;   // byte address for game transactions
    wire [7:0]  game_wdata;  // one patched occupancy byte for game writes
    wire [7:0]  game_rdata;  // one occupancy byte from PSRAM for game reads

    //this is for the display streamer
    wire        disp_req;
    wire        disp_ack;
    wire [16:0] disp_addr;
    wire [DATA_WIDTH-1:0] disp_rdata;

    //these connect to the PSRAM controller, which multiplexes access between the game and display streamer
    wire        psram_ce_n;
    wire        psram_sclk;
    wire [3:0]  psram_sio_out;
    wire [3:0]  psram_sio_oe;
    wire [3:0]  psram_sio_in;
    wire        psram_valid;
    wire        psram_busy;
    wire [DATA_WIDTH-1:0] psram_rdata;
    wire [7:0]  psram_wdata;

    //who uses ram this cycle? During active video the display streamer has priority, during vblank the game has priority. The display streamer can only use leftover vblank cycles when the game isn't requesting access.
    wire        actual_qspi_req;
    wire        actual_qspi_we;
    wire [16:0] actual_qspi_addr;
    wire        actual_qspi_byte;
    reg         txn_is_game;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_div          <= 1'b0;
            vblank_prev_top    <= 1'b0;
            txn_is_game        <= 1'b0;
        end else begin
            // Divide the 50MHz clock to get a 25MHz pixel clock for VGA timing
            pixel_div <= ~pixel_div;
            vblank_prev_top <= vblank;
            if (!psram_busy && actual_qspi_req) begin
                //first display then game, but the game can use any leftover cycles in vblank
                // when the display streamer isn't requesting access
                txn_is_game <= (vblank && game_req);
            end
        end
    end

    vga_sync sync_inst (
        .clk(clk),
        .pixel_tick(pixel_tick),
        .rst_n(rst_n),
        .h_count(h_count),
        .v_count(v_count),
        .hsync(hsync),
        .vsync(vsync),
        .active_video(active_video),
        .vblank(vblank)
    );

    game_fsm #(
        .FRAME_W(FRAME_W),
        .FRAME_H(FRAME_H),
        .START1_X(START1_X),
        .START2_X(START2_X),
        .START_Y(START_Y)
    ) engine_inst (
        .clk(clk),
        .rst_n(rst_n),
        .p1_left(p1_left),
        .p1_right(p1_right),
        .p2_left(p2_left),
        .p2_right(p2_right),
        .restart(restart_game),
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

`ifdef FAST_COMPARE_SIM
    assign disp_req = 1'b0;
    assign disp_addr = 17'd0;
    assign pixel_occupied = 1'b0;
`else
    display_streamer #(
        .FRAME_W(FRAME_W),
        .FRAME_H(FRAME_H),
        .BURST_BYTES(BURST_BYTES),
        .DATA_WIDTH(DATA_WIDTH)
    ) disp_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_tick(pixel_tick),
        .pixel_idx(h_count[6:0]),
        .active_video(active_video),
        .vblank(vblank),
        .frame_start(frame_start),
        .disp_req(disp_req),
        .disp_addr(disp_addr),
        .disp_rdata(disp_rdata),
        .disp_ack(disp_ack),
        .pixel_occupied(pixel_occupied)
    );
`endif

    // During active video the display path owns PSRAM. During vertical blank
    // the game gets priority for its collision checks and writes, and the
    // display streamer can use any leftover blanking cycles to prefetch the
    // next frame's first bursts.
`ifdef FAST_COMPARE_SIM // In this mode we want to ignore the display streamer and just let the game have full access to PSRAM to maximize simulation speed
    assign actual_qspi_req  = game_req;
    assign actual_qspi_we   = game_we;
    assign actual_qspi_addr = game_addr;
    assign actual_qspi_byte = game_req;
`else // In normal operation, the display streamer has priority during active video, and the game has priority during vblank, but the display streamer can use leftover vblank cycles when the game isn't requesting access
    assign actual_qspi_req  = disp_req | (vblank & game_req);
    assign actual_qspi_we   = vblank & game_req & game_we;
    assign actual_qspi_addr = (vblank & game_req) ? game_addr : disp_addr;
    assign actual_qspi_byte = vblank & game_req;
`endif
    // The PSRAM controller always sees the combined requests from both the game and display streamer, and it will assert psram_valid when the transaction is complete. The game and display streamer can check psram_valid along with txn_is_game to determine if their transaction is complete.
    assign psram_wdata      = game_wdata;

    assign game_rdata = psram_rdata[7:0];
    assign disp_rdata = psram_rdata;
    assign game_ack   = psram_valid && txn_is_game;
    assign disp_ack   = psram_valid && !txn_is_game;

    psram_controller #(
        .CLK_FREQ_HZ  (50_000_000),
        .SCLK_FREQ_HZ (25_000_000),
        .BURST_BYTES  (BURST_BYTES),
        .DATA_WIDTH   (DATA_WIDTH)
    ) psram_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_we     (actual_qspi_req &&  actual_qspi_we),
        .i_re     (actual_qspi_req && !actual_qspi_we),
        .i_byte   (actual_qspi_byte),
        .i_addr   (actual_qspi_addr),
        .i_wdata  (psram_wdata),
        .o_rdata  (psram_rdata),
        .o_valid  (psram_valid),
        .o_busy   (psram_busy),
        .o_ce_n   (psram_ce_n),
        .o_sclk   (psram_sclk),
        .o_sio_out(psram_sio_out),
        .o_sio_oe (psram_sio_oe),
        .i_sio_in (psram_sio_in)
    );

    // VGA output: TT VGA PMOD bit layout
    // [0]=R1 [1]=G1 [2]=B1 [3]=VSYNC [4]=R0 [5]=G0 [6]=B0 [7]=HSYNC
    wire video_on = active_video && !clear_active;
    wire out_pixel = video_on && pixel_occupied;
    wire out_r = out_pixel;
    wire out_g = out_pixel;
    wire out_b = out_pixel;
    assign uo_out = {hsync, out_b, out_g, out_r, vsync, out_b, out_g, out_r};

    // uio: QSPI PSRAM PMOD
    // [0]=FLASH_CSn [1]=IO0 [2]=IO1 [3]=SCK [4]=IO2 [5]=IO3 [6]=PSRAM_A_CSn [7]=PSRAM_B_CSn
    assign psram_sio_in = {uio_in[5], uio_in[4], uio_in[2], uio_in[1]};
    assign uio_out = {1'b1, psram_ce_n, psram_sio_out[3], psram_sio_out[2],
                      psram_sclk, psram_sio_out[1], psram_sio_out[0], 1'b1};
    assign uio_oe  = {1'b1, 1'b1, psram_sio_oe[3], psram_sio_oe[2],
                      1'b1, psram_sio_oe[1], psram_sio_oe[0], 1'b1};

endmodule
