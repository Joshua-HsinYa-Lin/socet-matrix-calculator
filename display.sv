module display #(
    parameter int CLK_FREQ = 100_000_000 // Adjust this to the board's actual clock frequency
)(
    input  logic        clk,        // Main system clock
    input  logic        reset,      // Active-high reset
    
    // Abstract Interface from Main Controller
    input  logic [2:0]  sys_state,    // 0: Init, 1: Prompt DIM, 2: Input Elements, 3: Processing, 4: Output
    input  logic [3:0]  prompt_type,  // 0: NONE/DATA, 1: ROW, 2: COL, 3: ADD, 4: MUL, 5: TRA, 6: R_C_ (Coord)
    input  logic [3:0]  current_row,  // 1-9
    input  logic [3:0]  current_col,  // 1-9
    input  logic [31:0] display_data, // 8-digit BCD data (e.g., [3:0] is the rightmost digit)
    input  logic        error_flag,   // Triggers slow blink (RED)
    input  logic        ready_flag,   // Triggers fast blink (GREEN)

    // Physical Hardware Pins
    output logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
    output logic [7:0]  left, right,
    output logic        red, green, blue
);

    // --------------------------------------------------------
    // 7-Segment Encoding Definitions (Active High)
    // --------------------------------------------------------
    localparam [7:0] CHAR_BLANK = 8'b00000000;
    localparam [7:0] CHAR_R     = 8'b01010000; 
    localparam [7:0] CHAR_O     = 8'b00111111; 
    localparam [7:0] CHAR_W     = 8'b00111110; 
    localparam [7:0] CHAR_C     = 8'b00111001; 
    localparam [7:0] CHAR_L     = 8'b00111000; 
    localparam [7:0] CHAR_A     = 8'b01110111; 
    localparam [7:0] CHAR_D     = 8'b01011110; 
    localparam [7:0] CHAR_M     = 8'b01010100; 
    localparam [7:0] CHAR_U     = 8'b00111110; 
    localparam [7:0] CHAR_T     = 8'b01111000;
    localparam [7:0] CHAR_S     = 8'b01101101; 

    // Replaced 'return' with function name assignment for older Yosys compatibility
    function [7:0] decode_bcd(input logic [3:0] bcd);
        case (bcd)
            4'd0: decode_bcd = 8'b00111111;
            4'd1: decode_bcd = 8'b00000110;
            4'd2: decode_bcd = 8'b01011011;
            4'd3: decode_bcd = 8'b01001111;
            4'd4: decode_bcd = 8'b01100110;
            4'd5: decode_bcd = 8'b01101101;
            4'd6: decode_bcd = 8'b01111101;
            4'd7: decode_bcd = 8'b00000111;
            4'd8: decode_bcd = 8'b01111111;
            4'd9: decode_bcd = 8'b01101111;
            default: decode_bcd = CHAR_BLANK;
        endcase
    endfunction

    // --------------------------------------------------------
    // Blinking Timers (Driven by system clk)
    // --------------------------------------------------------
    logic [31:0] tick_1hz;
    logic [31:0] tick_4hz;
    logic [31:0] tick_seq;
    
    logic       blink_1hz;
    logic       blink_4hz;
    logic [2:0] seq_counter;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tick_1hz    <= '0;
            tick_4hz    <= '0;
            tick_seq    <= '0;
            blink_1hz   <= 1'b0;
            blink_4hz   <= 1'b0;
            seq_counter <= '0;
        end else begin
            // 1 Hz blink (toggles every half second)
            if (tick_1hz >= (CLK_FREQ / 2) - 1) begin
                tick_1hz  <= '0;
                blink_1hz <= ~blink_1hz;
            end else begin
                tick_1hz <= tick_1hz + 1;
            end

            // 4 Hz blink (toggles 8 times a second)
            if (tick_4hz >= (CLK_FREQ / 8) - 1) begin
                tick_4hz  <= '0;
                blink_4hz <= ~blink_4hz;
            end else begin
                tick_4hz <= tick_4hz + 1;
            end

            // Sequence counter for LED animation (updates 10 times a second)
            if (tick_seq >= (CLK_FREQ / 10) - 1) begin
                tick_seq    <= '0;
                seq_counter <= seq_counter + 1;
            end else begin
                tick_seq <= tick_seq + 1;
            end
        end
    end

    // --------------------------------------------------------
    // RGB LED Multiplexer
    // --------------------------------------------------------
    always_comb begin
        red   = 1'b0;
        green = 1'b0;
        blue  = 1'b0;

        // Priority encoder for center RGB indicator
        if (error_flag) begin
            red = blink_1hz;              // Error: Slow blinking red
        end else if (ready_flag) begin
            green = blink_4hz;            // Ready: Fast blinking green
        end else if (sys_state != 0) begin
            blue = 1'b1;                  // In Progress: Solid blue
        end
    end

    // --------------------------------------------------------
    // Left and Right LED arrays
    // --------------------------------------------------------
    always_comb begin
        if (sys_state == 3'd3) begin 
            // Processing Animation
            left  = (8'b00000001 << seq_counter);
            right = (8'b10000000 >> seq_counter);
        end else begin 
            // Thermometer code based on current_row / col
            left  = (1 << current_row) - 1;
            right = (1 << current_col) - 1;
        end
    end


    // Convert binary output values into BCD only during output mode.
    // This fixes display issues after arithmetic operations, because memory stores binary results.
    logic [31:0] display_bcd;
    bin_to_bcd8 disp_bcd_converter (
        .bin(display_data),
        .bcd(display_bcd)
    );

    logic [31:0] shown_digits;
    always_comb begin
        if (sys_state == 3'd4 && prompt_type == 4'd0) begin
            shown_digits = display_bcd;
        end else begin
            shown_digits = display_data;
        end
    end

    // --------------------------------------------------------
    // 7-Segment Display Multiplexer
    // --------------------------------------------------------
    always_comb begin
        // Default: blank all
        ss7 = CHAR_BLANK; ss6 = CHAR_BLANK; ss5 = CHAR_BLANK; ss4 = CHAR_BLANK;
        ss3 = CHAR_BLANK; ss2 = CHAR_BLANK; ss1 = CHAR_BLANK; ss0 = CHAR_BLANK;

        case (prompt_type)
            4'd0: begin // Show BCD Data
                ss7 = decode_bcd(shown_digits[31:28]);
                ss6 = decode_bcd(shown_digits[27:24]);
                ss5 = decode_bcd(shown_digits[23:20]);
                ss4 = decode_bcd(shown_digits[19:16]);
                ss3 = decode_bcd(shown_digits[15:12]);
                ss2 = decode_bcd(shown_digits[11:8]);
                ss1 = decode_bcd(shown_digits[7:4]);
                ss0 = decode_bcd(shown_digits[3:0]);
            end
            4'd1: begin // "ROW     "
                ss7 = CHAR_R; ss6 = CHAR_O; ss5 = CHAR_W;
            end
            4'd2: begin // "COL     "
                ss7 = CHAR_C; ss6 = CHAR_O; ss5 = CHAR_L;
            end
            4'd3: begin // "ADD     "
                ss7 = CHAR_A; ss6 = CHAR_D; ss5 = CHAR_D;
            end
            4'd4: begin // "MUL     "
                ss7 = CHAR_M; ss6 = CHAR_U; ss5 = CHAR_L;
            end
            4'd5: begin // "TRA     "
                ss7 = CHAR_T; ss6 = CHAR_R; ss5 = CHAR_A;
            end
            4'd6: begin // "r X c Y " (Coordinate Entry)
                ss7 = CHAR_R; 
                ss6 = decode_bcd(current_row);
                ss5 = CHAR_C;
                ss4 = decode_bcd(current_col);
                ss3 = decode_bcd(display_data[15:12]);
                ss2 = decode_bcd(display_data[11:8]);
                ss1 = decode_bcd(display_data[7:4]);
                ss0 = decode_bcd(display_data[3:0]);
            end
            4'd7: begin // "SCL     " scalar mode
                ss7 = CHAR_S; ss6 = CHAR_C; ss5 = CHAR_L;
                ss3 = decode_bcd(display_data[15:12]);
                ss2 = decode_bcd(display_data[11:8]);
                ss1 = decode_bcd(display_data[7:4]);
                ss0 = decode_bcd(display_data[3:0]);
            end
            default: begin
                ss7 = CHAR_BLANK; ss6 = CHAR_BLANK; ss5 = CHAR_BLANK; ss4 = CHAR_BLANK;
                ss3 = CHAR_BLANK; ss2 = CHAR_BLANK; ss1 = CHAR_BLANK; ss0 = CHAR_BLANK;
            end
        endcase
    end

endmodule


module bin_to_bcd8 (
    input  logic [31:0] bin,
    output logic [31:0] bcd
);
    integer i;
    logic [63:0] shift;

    always_comb begin
        shift = 64'd0;
        shift[31:0] = bin;

        for (i = 0; i < 32; i = i + 1) begin
            if (shift[35:32] >= 4'd5) shift[35:32] = shift[35:32] + 4'd3;
            if (shift[39:36] >= 4'd5) shift[39:36] = shift[39:36] + 4'd3;
            if (shift[43:40] >= 4'd5) shift[43:40] = shift[43:40] + 4'd3;
            if (shift[47:44] >= 4'd5) shift[47:44] = shift[47:44] + 4'd3;
            if (shift[51:48] >= 4'd5) shift[51:48] = shift[51:48] + 4'd3;
            if (shift[55:52] >= 4'd5) shift[55:52] = shift[55:52] + 4'd3;
            if (shift[59:56] >= 4'd5) shift[59:56] = shift[59:56] + 4'd3;
            if (shift[63:60] >= 4'd5) shift[63:60] = shift[63:60] + 4'd3;
            shift = shift << 1;
        end

        bcd = shift[63:32];
    end
endmodule
