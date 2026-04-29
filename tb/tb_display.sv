`timescale 1ns / 1ps

module tb_display ();
    logic        clk;
    logic        reset;
    logic [2:0]  sys_state;
    logic [2:0]  prompt_type;
    logic [3:0]  current_row;
    logic [3:0]  current_col;
    logic [31:0] display_data;
    logic        error_flag;
    logic        ready_flag;

    logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0;
    logic [7:0]  left, right;
    logic        red, green, blue;

    // Instantiate DUT with a scaled-down frequency for faster simulation
    // 100,000 ticks = 1 second in this simulation context
    display #(
        .CLK_FREQ(100_000) 
    ) dut (.*);

    always #5 clk = ~clk;

    initial begin
        clk          = 0;
        reset        = 1;
        sys_state    = 0;
        prompt_type  = 0;
        current_row  = 0;
        current_col  = 0;
        display_data = 0;
        error_flag   = 0;
        ready_flag   = 0;

        #20 reset = 0;

        $display("Testing ROW prompt and Error LED (Red)...");
        sys_state   = 1;
        prompt_type = 1; // ROW
        error_flag  = 1;
        #1500000; 

        $display("Testing Coordinate Entry and Ready LED (Green)...");
        sys_state    = 2;
        prompt_type  = 6;
        current_row  = 1;
        current_col  = 2;
        display_data = 32'h00000125;
        error_flag   = 0;
        ready_flag   = 1; 
        #500000; 

        $display("Testing Processing Animation and In-Progress LED (Blue)...");
        sys_state   = 3;
        prompt_type = 4;
        ready_flag  = 0;
        #1500000; 

        $display("All visual states simulated.");
        $finish;
    end
endmodule
