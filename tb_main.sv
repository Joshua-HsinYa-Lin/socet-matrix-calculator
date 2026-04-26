`timescale 1ns / 1ps

module tb_main ();

    logic        clk;
    logic        reset;
    logic [20:0] pb;

    logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0;
    logic [7:0]  left, right;
    logic        red, green, blue;

    // Instantiate Main Controller
    main dut (.*);

    // 100 MHz Clock
    always #5 clk = ~clk;

    // Keypad Index Mapping
    localparam int KEY_Y = 18, KEY_X = 17, KEY_Z = 19;
    localparam int KEY_A = 10, KEY_B = 11, KEY_C = 12, KEY_D = 13;
    localparam int KEY_W = 16, KEY_F = 15;

    // Task to simulate a human button press
    // Holds the button high for 15ms to bypass the 10ms debouncer, then releases for 5ms
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

        // ---------------------------------------------------------
        // STEP 1: Enter Matrix 1 Dimensions (1x1 Matrix to keep test short)
        // ---------------------------------------------------------
        $display("Entering M1 ROW (1)...");
        press_key(1);     // Press '1'
        press_key(KEY_Y); // Press 'Y' to confirm

        $display("Entering M1 COL (1)...");
        press_key(1);     // Press '1'
        press_key(KEY_Y); // Press 'Y' to confirm

        // ---------------------------------------------------------
        // STEP 2: Enter Matrix 1 Elements
        // ---------------------------------------------------------
        $display("Entering M1 Element (Value: 9)...");
        press_key(9);     // Press '9'
        press_key(KEY_Y); // Press 'Y' to confirm and write to memory

        // ---------------------------------------------------------
        // STEP 3: Select Operation (Transposition)
        // ---------------------------------------------------------
        $display("Selecting Transposition...");
        press_key(KEY_C); // Press 'C' for TRA
        press_key(KEY_Y); // Press 'Y' to confirm

        // ---------------------------------------------------------
        // STEP 4: Observe state transitions
        // ---------------------------------------------------------
        // Since it's a 1x1 matrix and we selected TRA, the FSM should jump 
        // to S_CALC, then immediately to S_OUT_FETCH, then S_OUT_IDLE.
        #20_000_000;

        $display("Simulation Complete. Check waveforms for Memory Base 0x000 and Output States.");
        $finish;
    end

endmodule
