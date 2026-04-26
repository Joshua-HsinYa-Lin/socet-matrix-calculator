module main (
    input  logic        clk,
    input  logic        reset,
    input  logic [20:0] pb,         
    
    output logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
    output logic [7:0]  left, right,
    output logic        red, green, blue
);

    // Keypad Mapping
    localparam int KEY_Y = 18, KEY_X = 17, KEY_Z = 19;
    localparam int KEY_A = 10, KEY_B = 11, KEY_C = 12, KEY_D = 13;
    localparam int KEY_W = 16, KEY_F = 15;

    // Memory Base Addresses 
    localparam [31:0] BASE_M1  = 32'h000;
    localparam [31:0] BASE_M2  = 32'h080;
    localparam [31:0] BASE_OUT = 32'h100;

    // Sub-module Interfaces & Signals
    logic [20:0] pb_pulse;
    mem_if mem_bus(clk, ~reset);
    matrix_if add_if(clk, ~reset);
    matrix_if vec_if(clk, ~reset);
    matrix_if tra_if(clk, ~reset);

    // Display Registers
    logic [2:0]  sys_state, prompt_type;
    logic [3:0]  curr_r, curr_c;
    logic [31:0] display_data;
    logic        error_flag, ready_flag;

    // Internal FSM Data
    logic [3:0] m1_r, m1_c, m2_r, m2_c, out_r, out_c;
    logic [11:0] input_buf;
    logic [2:0] op_type; // 1: ADD, 2: MUL, 3: TRA
    
    // Calculation DMA Counters
    logic [31:0] calc_i, calc_j, calc_k;

    // --------------------------------------------------------
    // Module Instantiations
    // --------------------------------------------------------
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

    logic [31:0] sum_out; logic sum_valid, sum_ready, add_done;
    matrix_add m_add(.clk(clk), .nRst(~reset), .mif(add_if.module_mp), .sum_out(sum_out), .sum_valid(sum_valid), .sum_ready(sum_ready), .operation_done(add_done));

    logic [63:0] vec_product; logic vec_done;
    vector m_vec(.clk(clk), .nRST(~reset), .mif(vec_if.module_mp), .product(vec_product), .done(vec_done));

    logic [31:0] trans_out, dest_ridx, dest_cidx; logic trans_valid, trans_ready, tra_done;
    matrix_transpose m_tra(.clk(clk), .nRst(~reset), .mif(tra_if.module_mp), .trans_out(trans_out), .dest_ridx(dest_ridx), .dest_cidx(dest_cidx), .trans_valid(trans_valid), .trans_ready(trans_ready), .operation_done(tra_done));

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

    // --------------------------------------------------------
    // FSM States
    // --------------------------------------------------------
    typedef enum logic [5:0] {
        S_INIT, S_DIM_M1_COL,
        S_LOAD_M1, S_LOAD_M1_ACK,
        S_OP_SELECT,
        S_DIM_M2_COL, 
        S_LOAD_M2, S_LOAD_M2_ACK,
        
        // DMA Calculation States
        S_CALC_SETUP, S_CALC_START, S_CALC_START_ACK,
        S_CALC_FETCH_A, S_CALC_WAIT_A, S_CALC_PULSE_A,
        S_CALC_FETCH_B, S_CALC_WAIT_B, S_CALC_PULSE_B,
        S_CALC_WAIT_RES, S_CALC_WRITE_RES, S_CALC_DONE_WAIT,
        
        S_OUT_IDLE_SETUP, S_OUT_FETCH, S_OUT_FETCH_ACK, S_OUT_IDLE
    } state_t;
    state_t state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_INIT;
            input_buf <= '0; error_flag <= 1'b0; ready_flag <= 1'b0;
            mem_bus.wen <= 1'b0; mem_bus.ren <= 1'b0;
            add_if.valid <= 0; vec_if.valid <= 0; tra_if.valid <= 0;
            sum_ready <= 0; trans_ready <= 0;
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

                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Z]) input_buf <= {input_buf[7:0], 4'h0};

                    if (pb_pulse[KEY_Y]) begin
                        mem_bus.addr  <= BASE_M1 + ((32'(curr_r) - 32'd1) * 32'(m1_c)) + (32'(curr_c) - 32'd1);
                        mem_bus.wdata <= {20'd0, input_buf}; 
                        mem_bus.wen   <= 1'b1;
                        state <= S_LOAD_M1_ACK;
                    end
                end

                S_LOAD_M1_ACK: begin
                    if (mem_bus.ready) begin
                        mem_bus.wen <= 1'b0;
                        input_buf <= '0;
                        if (curr_c == m1_c) begin
                            if (curr_r == m1_r) begin
                                ready_flag <= 1'b1; 
                                state <= S_OP_SELECT;
                            end else begin
                                curr_r <= curr_r + 1; curr_c <= 4'd1;
                                state <= S_LOAD_M1;
                            end
                        end else begin
                            curr_c <= curr_c + 1; state <= S_LOAD_M1;
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
                        curr_r <= 4'd1; curr_c <= 4'd1; input_buf <= '0;
                        
                        if (op_type == 3'd1) begin // ADD
                            m2_r <= m1_r; m2_c <= m1_c; out_r <= m1_r; out_c <= m1_c;
                            state <= S_LOAD_M2;
                        end else if (op_type == 3'd2) begin // MUL
                            m2_r <= m1_c; out_r <= m1_r;
                            state <= S_DIM_M2_COL;
                        end else begin // TRA
                            out_r <= m1_c; out_c <= m1_r;
                            state <= S_CALC_SETUP;
                        end
                    end
                end

                S_DIM_M2_COL: begin
                    prompt_type <= 3'd2; // COL
                    display_data <= {20'd0, input_buf};
                    if (valid_num) input_buf[3:0] <= num_val;

                    if (pb_pulse[KEY_Y]) begin
                        if (input_buf[3:0] == 0 || input_buf[3:0] > 9) error_flag <= 1'b1;
                        else begin
                            m2_c <= input_buf[3:0]; out_c <= input_buf[3:0];
                            input_buf <= '0; error_flag <= 1'b0;
                            curr_r <= 4'd1; curr_c <= 4'd1;
                            state <= S_LOAD_M2;
                        end
                    end
                end

                S_LOAD_M2: begin
                    sys_state <= 3'd2; prompt_type <= 3'd6; 
                    display_data <= {20'd0, input_buf};

                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Z]) input_buf <= {input_buf[7:0], 4'h0};

                    if (pb_pulse[KEY_Y]) begin
                        mem_bus.addr  <= BASE_M2 + ((32'(curr_r) - 32'd1) * 32'(m2_c)) + (32'(curr_c) - 32'd1);
                        mem_bus.wdata <= {20'd0, input_buf};
                        mem_bus.wen   <= 1'b1;
                        state <= S_LOAD_M2_ACK;
                    end
                end

                S_LOAD_M2_ACK: begin
                    if (mem_bus.ready) begin
                        mem_bus.wen <= 1'b0; input_buf <= '0;
                        if (curr_c == m2_c) begin
                            if (curr_r == m2_r) begin
                                ready_flag <= 1'b1; 
                                state <= S_CALC_SETUP;
                            end else begin
                                curr_r <= curr_r + 1; curr_c <= 4'd1;
                                state <= S_LOAD_M2;
                            end
                        end else begin
                            curr_c <= curr_c + 1; state <= S_LOAD_M2;
                        end
                    end
                end

                // --------------------------------------------------------
                // DMA Calculation Engine
                // --------------------------------------------------------
                S_CALC_SETUP: begin
                    calc_i <= '0; calc_j <= '0; calc_k <= '0;
                    state <= S_CALC_START;
                end

                S_CALC_START: begin
                    sys_state <= 3'd3; // Blinking animation
                    if (op_type == 3'd1) prompt_type <= 3'd3; // ADD
                    else if (op_type == 3'd2) prompt_type <= 3'd4; // MUL
                    else prompt_type <= 3'd5; // TRA

                    add_if.valid <= (op_type == 3'd1);
                    vec_if.valid <= (op_type == 3'd2);
                    tra_if.valid <= (op_type == 3'd3);

                    add_if.rsize <= {28'd0, m1_r}; add_if.csize <= {28'd0, m1_c};
                    vec_if.rsize <= {28'd0, m1_r}; vec_if.csize <= {28'd0, m1_c}; 
                    tra_if.rsize <= {28'd0, m1_r}; tra_if.csize <= {28'd0, m1_c};
                    state <= S_CALC_START_ACK;
                end

                S_CALC_START_ACK: begin
                    add_if.valid <= 1'b0; vec_if.valid <= 1'b0; tra_if.valid <= 1'b0;
                    state <= S_CALC_FETCH_A;
                end

                S_CALC_FETCH_A: begin
                    if ((op_type == 1 && add_if.ready) || (op_type == 2 && vec_if.ready) || (op_type == 3 && tra_if.ready)) begin
                        mem_bus.ren <= 1'b1;
                        if (op_type == 1 || op_type == 3) mem_bus.addr <= BASE_M1 + calc_i;
                        else if (op_type == 2) mem_bus.addr <= BASE_M1 + (calc_i * 32'(m1_c)) + calc_k;
                        state <= S_CALC_WAIT_A;
                    end
                end

                S_CALC_WAIT_A: begin
                    if (mem_bus.ready) begin
                        mem_bus.ren <= 1'b0;
                        if (op_type == 1) begin add_if.data <= mem_bus.rdata; add_if.valid <= 1'b1; end
                        if (op_type == 2) begin vec_if.data <= mem_bus.rdata; vec_if.valid <= 1'b1; end
                        if (op_type == 3) begin tra_if.data <= mem_bus.rdata; tra_if.valid <= 1'b1; end
                        state <= S_CALC_PULSE_A;
                    end
                end

                S_CALC_PULSE_A: begin
                    add_if.valid <= 1'b0; vec_if.valid <= 1'b0; tra_if.valid <= 1'b0;
                    if (op_type == 3) state <= S_CALC_WAIT_RES; // TRA skips FETCH_B
                    else state <= S_CALC_FETCH_B;
                end

                S_CALC_FETCH_B: begin
                    if ((op_type == 1 && add_if.ready) || (op_type == 2 && vec_if.ready)) begin
                        mem_bus.ren <= 1'b1;
                        if (op_type == 1) mem_bus.addr <= BASE_M2 + calc_i;
                        else if (op_type == 2) mem_bus.addr <= BASE_M2 + (calc_k * 32'(m2_c)) + calc_j;
                        state <= S_CALC_WAIT_B;
                    end
                end

                S_CALC_WAIT_B: begin
                    if (mem_bus.ready) begin
                        mem_bus.ren <= 1'b0;
                        if (op_type == 1) begin add_if.data <= mem_bus.rdata; add_if.valid <= 1'b1; end
                        if (op_type == 2) begin vec_if.data <= mem_bus.rdata; vec_if.valid <= 1'b1; end
                        state <= S_CALC_PULSE_B;
                    end
                end

                S_CALC_PULSE_B: begin
                    add_if.valid <= 1'b0; vec_if.valid <= 1'b0;
                    if (op_type == 2) begin
                        if (calc_k + 32'd1 == 32'(m1_c)) state <= S_CALC_WAIT_RES;
                        else begin calc_k <= calc_k + 1; state <= S_CALC_FETCH_A; end
                    end else state <= S_CALC_WAIT_RES;
                end

                S_CALC_WAIT_RES: begin
                    if (op_type == 1 && sum_valid) begin
                        mem_bus.wdata <= sum_out;
                        mem_bus.addr <= BASE_OUT + calc_i;
                        mem_bus.wen <= 1'b1; sum_ready <= 1'b1; 
                        state <= S_CALC_WRITE_RES;
                    end
                    else if (op_type == 2 && vec_done) begin
                        mem_bus.wdata <= vec_product[31:0];
                        mem_bus.addr <= BASE_OUT + (calc_i * 32'(out_c)) + calc_j;
                        mem_bus.wen <= 1'b1;
                        state <= S_CALC_WRITE_RES;
                    end
                    else if (op_type == 3 && trans_valid) begin
                        mem_bus.wdata <= trans_out;
                        mem_bus.addr <= BASE_OUT + (dest_ridx * 32'(out_c)) + dest_cidx;
                        mem_bus.wen <= 1'b1; trans_ready <= 1'b1;
                        state <= S_CALC_WRITE_RES;
                    end
                end

                S_CALC_WRITE_RES: begin
                    sum_ready <= 1'b0; trans_ready <= 1'b0;
                    if (mem_bus.ready) begin
                        mem_bus.wen <= 1'b0;
                        
                        if (op_type == 1 || op_type == 3) begin
                            if (calc_i + 32'd1 == (32'(m1_r) * 32'(m1_c))) state <= S_CALC_DONE_WAIT; 
                            else begin calc_i <= calc_i + 1; state <= S_CALC_FETCH_A; end
                        end
                        else if (op_type == 2) begin
                            if (calc_j + 32'd1 == 32'(m2_c)) begin
                                calc_j <= 0;
                                if (calc_i + 32'd1 == 32'(m1_r)) state <= S_CALC_DONE_WAIT;
                                else begin calc_i <= calc_i + 1; calc_k <= 0; state <= S_CALC_START; end
                            end else begin
                                calc_j <= calc_j + 1; calc_k <= 0; state <= S_CALC_START;
                            end
                        end
                    end
                end

                S_CALC_DONE_WAIT: begin
                    if (op_type == 1 && add_done) state <= S_OUT_IDLE_SETUP;
                    else if (op_type == 3 && tra_done) state <= S_OUT_IDLE_SETUP;
                    else if (op_type == 2) state <= S_OUT_IDLE_SETUP;
                end

                // --------------------------------------------------------
                // Result Output Navigation
                // --------------------------------------------------------
                S_OUT_IDLE_SETUP: begin
                    curr_r <= 4'd1; curr_c <= 4'd1;
                    state <= S_OUT_FETCH; 
                end

                S_OUT_FETCH: begin
                    sys_state <= 3'd4; prompt_type <= 3'd0; // Data output mode
                    mem_bus.addr <= BASE_OUT + ((32'(curr_r) - 32'd1) * 32'(out_c)) + (32'(curr_c) - 32'd1);
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
                    if (pb_pulse[KEY_W] && curr_r > 1)     begin curr_r <= curr_r - 1; state <= S_OUT_FETCH; end
                    if (pb_pulse[KEY_B] && curr_r < out_r) begin curr_r <= curr_r + 1; state <= S_OUT_FETCH; end
                    if (pb_pulse[KEY_A] && curr_c > 1)     begin curr_c <= curr_c - 1; state <= S_OUT_FETCH; end
                    if (pb_pulse[KEY_D] && curr_c < out_c) begin curr_c <= curr_c + 1; state <= S_OUT_FETCH; end
                end

                default: state <= S_INIT;

            endcase
        end
    end
endmodule
