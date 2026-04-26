`default_nettype none

module top (
    // Physical Simulator I/O
    input  logic        hz100, reset,
    input  logic [20:0] pb, 
    output logic [7:0]  left, right, 
    output logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
    output logic        red, green, blue,
    
    // UART ports (Unused in this project)
    output logic [7:0]  txdata,
    input  logic [7:0]  rxdata,
    output logic        txclk, rxclk,
    input  logic        txready, rxready
);

    // Instantiate the Main FSM Controller
    // Mapping the simulator's hardware clock (hz100) to the system clk
    main soc_controller (
        .clk(hz100),
        .reset(reset),
        .pb(pb),
        .ss7(ss7), .ss6(ss6), .ss5(ss5), .ss4(ss4), 
        .ss3(ss3), .ss2(ss2), .ss1(ss1), .ss0(ss0),
        .left(left), .right(right),
        .red(red), .green(green), .blue(blue)
    );

    // Tie off unused UART outputs to prevent floating logic errors
    assign txdata = 8'd0;
    assign txclk  = 1'b0;
    assign rxclk  = 1'b0;

endmodule
