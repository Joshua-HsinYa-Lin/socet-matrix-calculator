`timescale 1ns/1ps

module tb_main();

    // 1. Declare Testbench Signals
    logic        clk;
    logic        reset;
    logic [20:0] pb;
    
    logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0;
    logic [7:0]  left, right;
    logic        red, green, blue;

    // Keypad Index Mappings (Matched exactly to your main.sv)
    localparam int KEY_A = 10;
    localparam int KEY_Y = 18;

    // 2. Instantiate the Top Module
    main DUT (
        .clk(clk), .reset(reset), .pb(pb),
        .ss7(ss7), .ss6(ss6), .ss5(ss5), .ss4(ss4), .ss3(ss3), .ss2(ss2), .ss1(ss1), .ss0(ss0),
        .left(left), .right(right), .red(red), .green(green), .blue(blue)
    );

    // 3. Generate 100MHz Clock (10ns period)
    always #5 clk = ~clk;

    // 4. Task to Fake a Button Press 
    // Holds the button for 20ns (2 clock cycles) to guarantee pb_pulse edge detection, 
    // then releases it for 40ns to simulate human typing delay.
    task press_key(input int key_index);
        begin
            pb[key_index] = 1'b1;
            #20; 
            pb[key_index] = 1'b0;
            #40; 
        end
    endtask

    // 5. Automated Stimulus
    initial begin
        // Initialize everything to 0
        clk = 0;
        reset = 1;
        pb = 21'b0;
        
        // Dump waveform traces for GTKWave/Questa
        $dumpfile("tb_traces.vcd");
        $dumpvars(0, tb_main);

        // Hold hardware reset for 20ns, then release it
        #20 reset = 0;
        #40;

        $display("[TB] Setting Matrix 1 Dimensions to 1x1...");
        press_key(1);     // Type '1' for Rows
        press_key(KEY_Y); // Press Enter
        press_key(1);     // Type '1' for Cols
        press_key(KEY_Y); // Press Enter

        $display("[TB] Loading Matrix 1 Data: Value = 2...");
        press_key(2);     // Type '2' for cell [0,0]
        press_key(KEY_Y); // Press Enter

        $display("[TB] Selecting Operation: ADD...");
        press_key(KEY_A); // Select Addition (op_type = 1)
        press_key(KEY_Y); // Press Enter to confirm

        $display("[TB] Loading Matrix 2 Data: Value = 3...");
        press_key(3);     // Type '3' for cell [0,0]
        press_key(KEY_Y); // Press Enter

        $display("[TB] Waiting for Calculation to Complete...");
        
        // Wait enough time to let the AXI handshake and SRAM memory writes finish
        #1000; 

        $display("[TB] Simulation Complete. Pausing GUI...");
        
        // MUST use $stop instead of $finish so QuestaSim doesn't instantly close!
        $stop; 
    end

endmodule
