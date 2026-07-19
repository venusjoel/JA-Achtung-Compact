`timescale 1ns/1ps

// Exhaustively drives both 12-bit controller halves through the real PMOD
// pins and synchronizers in the compact 1x1 top. This guards the optimized
// all-ones/disconnected mask without duplicating the decoder under test.
module tb_decoder_exhaustive;
    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    integer raw;
    integer cases_checked;
    integer failures;
    reg [11:0] p1_raw;
    reg [11:0] p2_raw;
    reg [23:0] frame_bits;
    reg         expected_start;
    reg  [1:0] expected_l;
    reg  [1:0] expected_r;

    tt_um_ja_achtung_1x1 dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic wait_cycles(input integer count);
        integer n;
        begin
            for (n = 0; n < count; n = n + 1)
                @(posedge clk);
        end
    endtask

    task automatic drive_pmod(
        input reg latch_value,
        input reg clock_value,
        input reg data_value,
        input integer settle_cycles
    );
        begin
            @(negedge clk);
            ui_in = {1'b0, data_value, clock_value, latch_value, 4'b0000};
            wait_cycles(settle_cycles);
        end
    endtask

    task automatic send_frame(
        input reg [11:0] player1_raw,
        input reg [11:0] player2_raw
    );
        integer bit_index;
        begin
            // Serial order is P2 bits 0..11, followed by P1 bits 0..11.
            frame_bits = {player1_raw, player2_raw};
            drive_pmod(1'b1, 1'b1, 1'b0, 3);
            for (bit_index = 0; bit_index < 24; bit_index = bit_index + 1) begin
                drive_pmod(1'b1, 1'b1, frame_bits[bit_index], 3);
                drive_pmod(1'b1, 1'b0, frame_bits[bit_index], 3);
                drive_pmod(1'b1, 1'b1, frame_bits[bit_index], 3);
            end
            // The RTL commits on the synchronized return of LATCH to idle-high.
            drive_pmod(1'b0, 1'b1, 1'b0, 4);
            drive_pmod(1'b1, 1'b1, 1'b0, 4);
        end
    endtask

    task automatic check_outputs(
        input reg         wanted_start,
        input reg  [1:0] wanted_l,
        input reg  [1:0] wanted_r,
        input reg  [11:0] player1_raw,
        input reg  [11:0] player2_raw
    );
        begin
            cases_checked = cases_checked + 1;
            if ((dut.pad_start !== wanted_start) ||
                (dut.pad_l !== wanted_l) ||
                (dut.pad_r !== wanted_r)) begin
                failures = failures + 1;
                if (failures <= 20) begin
                    $display("MISMATCH case=%0d p1=%03h p2=%03h got start=%b l=%b r=%b expected start=%b l=%b r=%b",
                             cases_checked, player1_raw, player2_raw,
                             dut.pad_start, dut.pad_l, dut.pad_r,
                             wanted_start, wanted_l, wanted_r);
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        ena = 1'b1;
        ui_in = 8'b0011_0000;
        uio_in = 8'b0000_0000;
        cases_checked = 0;
        failures = 0;

        wait_cycles(12);
        @(negedge clk);
        rst_n = 1'b1;
        wait_cycles(4);

        // Sweep P1 while P2 is connected and idle.
        for (raw = 0; raw < 4096; raw = raw + 1) begin
            p1_raw = raw[11:0];
            p2_raw = 12'h000;
            expected_start = (p1_raw != 12'hfff) && p1_raw[3];
            expected_l = {1'b0, ((p1_raw != 12'hfff) &&
                                  (p1_raw[6] || p1_raw[10]))};
            expected_r = {1'b0, ((p1_raw != 12'hfff) &&
                                  (p1_raw[7] || p1_raw[11]))};
            send_frame(p1_raw, p2_raw);
            check_outputs(expected_start, expected_l, expected_r, p1_raw, p2_raw);
        end

        // Sweep P2 while P1 is connected and idle.
        for (raw = 0; raw < 4096; raw = raw + 1) begin
            p1_raw = 12'h000;
            p2_raw = raw[11:0];
            expected_start = (p2_raw != 12'hfff) && p2_raw[3];
            expected_l = {((p2_raw != 12'hfff) &&
                           (p2_raw[6] || p2_raw[10])), 1'b0};
            expected_r = {((p2_raw != 12'hfff) &&
                           (p2_raw[7] || p2_raw[11])), 1'b0};
            send_frame(p1_raw, p2_raw);
            check_outputs(expected_start, expected_l, expected_r, p1_raw, p2_raw);
        end

        // Explicitly cover both halves unplugged.
        p1_raw = 12'hfff;
        p2_raw = 12'hfff;
        send_frame(p1_raw, p2_raw);
        check_outputs(1'b0, 2'b00, 2'b00, p1_raw, p2_raw);

        if (failures == 0) begin
            $display("PASS compact decoder exhaustive: cases=%0d failures=%0d",
                     cases_checked, failures);
            $finish;
        end

        $display("FAIL compact decoder exhaustive: cases=%0d failures=%0d",
                 cases_checked, failures);
        $fatal(1);
    end
endmodule
