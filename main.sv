module main (
    input  logic        clk,
    input  logic        reset,
    input  logic [20:0] pb,         // Raw keypad input
    
    // Physical Display Pins
    output logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
    output logic [7:0]  left, right,
    output logic        red, green, blue
);

    // Keypad Mapping
    localparam int KEY_Y = 18, KEY_X = 17, KEY_Z = 19;
    localparam int KEY_A = 10, KEY_B = 11, KEY_C = 12, KEY_D = 13;
    localparam int KEY_W = 16, KEY_F = 15;

    // Memory Base Addresses (Max 81 elements each)
    localparam logic [31:0] BASE_M1  = 32'h000;
    localparam logic [31:0] BASE_M2  = 32'h080;
    localparam logic [31:0] BASE_OUT = 32'h100;

    // Sub-module Interfaces & Signals
    logic [20:0] pb_pulse;
    mem_if mem_bus(clk, ~reset); // Invert reset if mem_if uses active-low nRst

    // Display Registers
    logic [2:0]  sys_state, prompt_type;
    logic [3:0]  curr_r, curr_c;
    logic [31:0] display_data;
    logic        error_flag, ready_flag;

    // Internal FSM Data
    logic [3:0] m1_r, m1_c, m2_r, m2_c, out_r, out_c;
    logic [11:0] input_buf;
    logic [2:0] op_type; // 1: ADD, 2: MUL, 3: TRA
    
    // Module Instantiations
    debouncer #(.KEYS(21)) btn_sync (
        .clk(clk), .reset(reset), .pb_in(pb), .pb_pulse(pb_pulse)
    );

    display disp_ctrl (
        .clk(clk), .reset(reset), .sys_state(sys_state), .prompt_type(prompt_type),
        .current_row(curr_r), .current_col(curr_c), .display_data(display_data),
        .error_flag(error_flag), .ready_flag(ready_flag),
        .ss7(ss7), .ss6(ss6), .ss5(ss5), .ss4(ss4), .ss3(ss3), .ss2(ss2), .ss1(ss1), .ss0(ss0),
        .left(left), .right(right), .red(red), .green(green), .blue(blue)
    );

    memory sys_mem (
        .clk(clk), .nRst(~reset), .mif(mem_bus.memory_mp)
    );

    // Number Key Decoder
    logic valid_num;
    logic [3:0] num_val;
    always_comb begin
        valid_num = 1'b0; num_val = 4'd0;
        for (int i = 0; i <= 9; i++) begin
            if (pb_pulse[i]) begin
                valid_num = 1'b1; num_val = i[3:0];
            end
        end
    end

    // FSM States
    typedef enum logic [4:0] {
        S_INIT, S_DIM_M1_COL,
        S_LOAD_M1, S_LOAD_M1_ACK,
        S_OP_SELECT,
        S_DIM_M2_COL, 
        S_LOAD_M2, S_LOAD_M2_ACK,
        S_CALC, S_CALC_DONE,
        S_OUT_FETCH, S_OUT_FETCH_ACK, S_OUT_IDLE,
        S_SPECIFY_R, S_SPECIFY_C
    } state_t;
    state_t state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_INIT;
            input_buf <= '0; error_flag <= 1'b0; ready_flag <= 1'b0;
            mem_bus.wen <= 1'b0; mem_bus.ren <= 1'b0;
        end else if (pb_pulse[KEY_X]) begin
            state <= S_INIT; // Global Abort
            input_buf <= '0; error_flag <= 1'b0; ready_flag <= 1'b0;
        end else begin
            case (state)
                S_INIT: begin
                    sys_state <= 3'd1; prompt_type <= 3'd1; // ROW
                    mem_bus.wen <= 1'b0; mem_bus.ren <= 1'b0;
                    display_data <= {20'd0, input_buf};

                    if (valid_num) input_buf[3:0] <= num_val;

                    if (pb_pulse[KEY_Y]) begin
                        if (input_buf[3:0] == 0 || input_buf[3:0] > 9) error_flag <= 1'b1;
                        else begin
                            m1_r <= input_buf[3:0];
                            input_buf <= '0; error_flag <= 1'b0;
                            state <= S_DIM_M1_COL;
                        end
                    end
                end

                S_DIM_M1_COL: begin
                    prompt_type <= 3'd2; // COL
                    display_data <= {20'd0, input_buf};

                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Y]) begin
                        if (input_buf[3:0] == 0 || input_buf[3:0] > 9) error_flag <= 1'b1;
                        else begin
                            m1_c <= input_buf[3:0];
                            input_buf <= '0; error_flag <= 1'b0;
                            curr_r <= 4'd1; curr_c <= 4'd1;
                            state <= S_LOAD_M1;
                        end
                    end
                end

                S_LOAD_M1: begin
                    sys_state <= 3'd2; prompt_type <= 3'd6; // Coord Entry
                    display_data <= {20'd0, input_buf};

                    // Input logic: Press num -> overwrites LSB. Press Z -> shifts left.
                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Z]) input_buf <= {input_buf[7:0], 4'h0};

                    if (pb_pulse[KEY_Y]) begin
                        // Memory Write Setup
                        mem_bus.addr  <= BASE_M1 + ((curr_r - 1) * m1_c) + (curr_c - 1);
                        mem_bus.wdata <= {20'd0, input_buf}; // Store as BCD
                        mem_bus.wen   <= 1'b1;
                        state <= S_LOAD_M1_ACK;
                    end
                end

                S_LOAD_M1_ACK: begin
                    // Wait for memory to acknowledge write
                    if (mem_bus.ready) begin
                        mem_bus.wen <= 1'b0;
                        input_buf <= '0;
                        
                        // Matrix Coordinate Tracking
                        if (curr_c == m1_c) begin
                            if (curr_r == m1_r) begin
                                ready_flag <= 1'b1; // Trigger fast blink
                                state <= S_OP_SELECT;
                            end else begin
                                curr_r <= curr_r + 1;
                                curr_c <= 4'd1;
                                state <= S_LOAD_M1;
                            end
                        end else begin
                            curr_c <= curr_c + 1;
                            state <= S_LOAD_M1;
                        end
                    end
                end

                S_OP_SELECT: begin
                    prompt_type <= 3'd0;
                    
                    if (pb_pulse[KEY_A]) op_type <= 3'd1; // ADD
                    if (pb_pulse[KEY_B]) op_type <= 3'd2; // MUL
                    if (pb_pulse[KEY_C]) op_type <= 3'd3; // TRA

                    if (pb_pulse[KEY_Y] && op_type != 0) begin
                        ready_flag <= 1'b0;
                        curr_r <= 4'd1; curr_c <= 4'd1;
                        
                        if (op_type == 3'd1) begin // ADD
                            m2_r <= m1_r; m2_c <= m1_c; out_r <= m1_r; out_c <= m1_c;
                            state <= S_LOAD_M2;
                        end else if (op_type == 3'd2) begin // MUL
                            m2_r <= m1_c; out_r <= m1_r;
                            state <= S_DIM_M2_COL;
                        end else begin // TRA
                            out_r <= m1_c; out_c <= m1_r;
                            state <= S_CALC;
                        end
                    end
                end

                // (S_DIM_M2_COL, S_LOAD_M2, S_LOAD_M2_ACK are identical in structure to M1, 
                // just routing to BASE_M2. Omitted for brevity to focus on Output navigation)
                // ...

                S_CALC: begin
                    sys_state <= 3'd3; // Blinking animation
                    if (op_type == 3'd1) prompt_type <= 3'd3; // ADD
                    else if (op_type == 3'd2) prompt_type <= 3'd4; // MUL
                    else prompt_type <= 3'd5; // TRA

                    // NOTE: This is where you will interface with matrix_add, vector, and transpose modules.
                    // The FSM acts as DMA here: it reads from M1/M2, pushes to math module, reads result, writes to OUT.
                    // For now, we simulate calculation completion:
                    curr_r <= 4'd1; curr_c <= 4'd1;
                    state <= S_OUT_FETCH; 
                end

                S_OUT_FETCH: begin
                    sys_state <= 3'd4; prompt_type <= 3'd0; // Data output mode
                    mem_bus.addr <= BASE_OUT + ((curr_r - 1) * out_c) + (curr_c - 1);
                    mem_bus.ren  <= 1'b1;
                    state <= S_OUT_FETCH_ACK;
                end

                S_OUT_FETCH_ACK: begin
                    if (mem_bus.ready) begin
                        mem_bus.ren <= 1'b0;
                        display_data <= mem_bus.rdata;
                        state <= S_OUT_IDLE;
                    end
                end

                S_OUT_IDLE: begin
                    // Structural bounds checking for WASD navigation
                    if (pb_pulse[KEY_W] && curr_r > 1)     begin curr_r <= curr_r - 1; state <= S_OUT_FETCH; end
                    if (pb_pulse[KEY_B] && curr_r < out_r) begin curr_r <= curr_r + 1; state <= S_OUT_FETCH; end
                    if (pb_pulse[KEY_A] && curr_c > 1)     begin curr_c <= curr_c - 1; state <= S_OUT_FETCH; end
                    if (pb_pulse[KEY_D] && curr_c < out_c) begin curr_c <= curr_c + 1; state <= S_OUT_FETCH; end
                end

            endcase
        end
    end
endmodule
