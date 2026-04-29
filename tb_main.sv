`timescale 1ns / 1ps

module tb_main ();

    logic        clk;
    logic        reset;
    logic [20:0] pb;

    logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0;
    logic [7:0]  left, right;
    logic        red, green, blue;

    main dut (.*);

    always #5 clk = ~clk;

    localparam int KEY_Y = 18, KEY_X = 17, KEY_Z = 19;
    localparam int KEY_A = 10, KEY_B = 11, KEY_C = 12, KEY_D = 13;
    localparam int KEY_W = 16, KEY_F = 15;

    task press_key(input int key_idx);
        $display("  -> Pressing Key Index %0d", key_idx);
        pb[key_idx] = 1'b1;
        #15_000_000; // 15 ms
        pb[key_idx] = 1'b0;
        #5_000_000;  // 5 ms
    endtask

    initial begin
        clk   = 0;
        reset = 1;
        pb    = '0;

        #100 reset = 0;
        #100;

        $display("Starting UI & FSM Flow Test...");

        $display("Entering M1 ROW (1)...");
        press_key(1);     // Press '1'
        press_key(KEY_Y); // Press 'Y' to confirm

        $display("Entering M1 COL (1)...");
        press_key(1);     // Press '1'
        press_key(KEY_Y); // Press 'Y' to confirm

        $display("Entering M1 Element (Value: 9)...");
        press_key(9);     // Press '9'
        press_key(KEY_Y); // Press 'Y' to confirm and write to memory

        $display("Selecting Transposition...");
        press_key(KEY_C); // Press 'C' for TRA
        press_key(KEY_Y); // Press 'Y' to confirm

        #20_000_000;

        $display("Simulation Complete. Check waveforms for Memory Base 0x000 and Output States.");
        $finish;
    end

endmodule
