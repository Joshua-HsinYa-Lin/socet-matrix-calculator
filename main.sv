module main (
    input  logic        clk,
    input  logic        reset,
    input  logic [20:0] pb,         
    
    output logic [7:0]  ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
    output logic [7:0]  left, right,
    output logic        red, green, blue
);
    //pressboard
    localparam int KEY_W = 16, KEY_X = 17, KEY_Y = 18, KEY_Z = 19;
    localparam int KEY_A = 10, KEY_B = 11, KEY_C = 12, KEY_D = 13, KEY_E = 14, KEY_F = 15;
    logic [20:0] pb_pulse;

    //virtual memory address
    localparam [31:0] BASE_M1  = 32'h000;
    localparam [31:0] BASE_M2  = 32'h080;
    localparam [31:0] BASE_OUT = 32'h100;

    mem_if mem_bus(clk, ~reset);
    matrix_if add_if(clk, ~reset);
    matrix_if vec_if(clk, ~reset);
    matrix_if tra_if(clk, ~reset);

    //state tracking variable
    logic [2:0] sys_state, prompt_type;
    logic [3:0] curr_r, curr_c; //row / col
    logic [31:0] display_data;
    logic error_flag, ready_flag;

    //matrix dimensions
    logic [3:0] m1_r, m1_c, m2_r, m2_c, out_r, out_c;
    logic [11:0] input_buf; //current keypad
    logic [2:0] op_type; //operation type
    
    // loop control var
    logic [31:0] calc_i, calc_j, calc_k;
    logic [31:0] temp_rdata;

    //multiplication by shifting to avoid the yosys error ($macc_v2 crashes)
    function [31:0] mult_by_dim(input logic [31:0] val, input logic [31:0] dim);
        case(dim[3:0])
            4'd0: mult_by_dim = 32'd0;
            4'd1: mult_by_dim = val;
            4'd2: mult_by_dim = val << 1;
            4'd3: mult_by_dim = (val << 1) + val;
            4'd4: mult_by_dim = val << 2;
            4'd5: mult_by_dim = (val << 2) + val;
            4'd6: mult_by_dim = (val << 2) + (val << 1);
            4'd7: mult_by_dim = (val << 3) - val;
            4'd8: mult_by_dim = val << 3;
            4'd9: mult_by_dim = (val << 3) + val;
            default: mult_by_dim = 32'd0;
        endcase
    endfunction

    // 0 indexed matrix
    logic [31:0] cr_minus_1, cc_minus_1;
    assign cr_minus_1 = 32'(curr_r) - 32'd1;
    assign cc_minus_1 = 32'(curr_c) - 32'd1;

    //matrix boundaries
    logic [31:0] m1_offset_mult, m2_offset_mult, out_offset_mult;
    assign m1_offset_mult  = mult_by_dim(cr_minus_1, 32'(m1_c));
    assign m2_offset_mult  = mult_by_dim(cr_minus_1, 32'(m2_c));
    assign out_offset_mult = mult_by_dim(cr_minus_1, 32'(out_c));

    //index pointer to current element
    logic [31:0] calc_a_mult, calc_b_mult, vec_res_mult, tra_res_mult;
    assign calc_a_mult  = mult_by_dim(calc_i, 32'(m1_c));
    assign calc_b_mult  = mult_by_dim(calc_k, 32'(m2_c));
    assign vec_res_mult = mult_by_dim(calc_i, 32'(out_c));
    assign tra_res_mult = mult_by_dim(dest_ridx, 32'(out_c));
    //maximum element size
    logic [31:0] size_limit_mult;
    assign size_limit_mult = mult_by_dim(32'(m1_r), 32'(m1_c));

    logic [20:0] pb_prev;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) pb_prev <= '0;
        else       pb_prev <= pb;
    end
    assign pb_pulse = pb & ~pb_prev;

    display disp_ctrl (
        .clk(clk), .reset(reset), .sys_state(sys_state), .prompt_type(prompt_type),
        .current_row(curr_r), .current_col(curr_c), .display_data(display_data),
        .error_flag(error_flag), .ready_flag(ready_flag),
        .ss7(ss7), .ss6(ss6), .ss5(ss5), .ss4(ss4), .ss3(ss3), .ss2(ss2), .ss1(ss1), .ss0(ss0),
        .left(left), .right(right), .red(red), .green(green), .blue(blue)
    );

    memory sys_mem (.clk(clk), .nRst(~reset), .mif(mem_bus.memory_mp));

    logic [31:0] sum_out; 
    logic sum_valid, sum_ready, add_done;
    matrix_add m_add(.clk(clk), .nRst(~reset), .mif(add_if.module_mp), .sum_out(sum_out), .sum_valid(sum_valid), .sum_ready(sum_ready), .operation_done(add_done));

    logic [63:0] vec_product; 
    logic vec_done;
    vector m_vec(.clk(clk), .nRST(~reset), .mif(vec_if.module_mp), .product(vec_product), .done(vec_done));

    logic [31:0] trans_out, dest_ridx, dest_cidx; 
    logic trans_valid, trans_ready, tra_done;
    matrix_transpose m_tra(.clk(clk), .nRst(~reset), .mif(tra_if.module_mp), .trans_out(trans_out), .dest_ridx(dest_ridx), .dest_cidx(dest_cidx), .trans_valid(trans_valid), .trans_ready(trans_ready), .operation_done(tra_done));

    logic valid_num; //0-9 on keypad
    logic [3:0] num_val; //what is pressed 0-19
    always_comb begin
        valid_num = 1'b0; num_val = 4'd0;
        for (int i = 0; i <= 9; i++) begin
            if (pb_pulse[i]) begin
                valid_num = 1'b1; num_val = i[3:0];
            end
        end
    end

    //FSM definition for main
    typedef enum logic [5:0] {
        S_INIT, //initialize
        S_DIM_M1_COL, //waits for user to input
        S_LOAD_M1, S_LOAD_M1_ACK, //load input
        S_OP_SELECT, //select mode
        S_DIM_M2_COL, S_LOAD_M2, S_LOAD_M2_ACK, S_CALC_SETUP, 
        
        // modules handshake
        S_CALC_START, S_CALC_START_WAIT_LOW, S_CALC_START_WAIT_HIGH,
        
        // fetch and write to memory
        S_CALC_FETCH_A, S_CALC_WAIT_A, S_CALC_LATCH_A, 
        S_CALC_SEND_A, S_CALC_ACK_A_LOW, S_CALC_ACK_A_HIGH,
        
        S_CALC_FETCH_B, S_CALC_WAIT_B, S_CALC_LATCH_B, 
        S_CALC_SEND_B, S_CALC_ACK_B_LOW, S_CALC_ACK_B_HIGH,
        
        // wait for calculation
        S_CALC_WAIT_RES, S_CALC_WRITE_RES, S_CALC_NEXT_WAIT_HIGH, S_CALC_DONE_WAIT,
        
        S_OUT_IDLE_SETUP, S_OUT_FETCH, S_OUT_FETCH_WAIT, S_OUT_FETCH_ACK, S_OUT_IDLE
    } state_t;
    
    state_t state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_INIT; 
            input_buf <= '0; 
            error_flag <= 1'b0; 
            ready_flag <= 1'b0; 
            op_type <= '0;
            mem_bus.wen <= 1'b0; 
            mem_bus.ren <= 1'b0; 
            temp_rdata <= '0;
            add_if.valid <= 0; 
            vec_if.valid <= 0; 
            tra_if.valid <= 0;
            sum_ready <= 0; 
            trans_ready <= 0;
        end else if (pb_pulse[KEY_X]) begin
            state <= S_INIT; 
            input_buf <= '0; 
            error_flag <= 1'b0; 
            ready_flag <= 1'b0; 
            op_type <= '0;
            mem_bus.wen <= 1'b0; 
            mem_bus.ren <= 1'b0; 
            temp_rdata <= '0;
            add_if.valid <= 0; 
            vec_if.valid <= 0; 
            tra_if.valid <= 0;
            sum_ready <= 0; 
            trans_ready <= 0;
        end else begin
            case (state)
                S_INIT: begin
                    sys_state <= 3'd1; 
                    prompt_type <= 3'd1; 
                    mem_bus.wen <= 1'b0; 
                    mem_bus.ren <= 1'b0; 
                    display_data <= {20'd0, input_buf};
                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Y]) begin
                        if (input_buf[3:0] == 0 || input_buf[3:0] > 9) error_flag <= 1'b1;
                        else begin 
                            m1_r <= input_buf[3:0]; 
                            input_buf <= '0; 
                            error_flag <= 1'b0; 
                            state <= S_DIM_M1_COL; 
                        end
                    end
                end

                S_DIM_M1_COL: begin
                    prompt_type <= 3'd2; display_data <= {20'd0, input_buf};
                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Y]) begin
                        if (input_buf[3:0] == 0 || input_buf[3:0] > 9) error_flag <= 1'b1;
                        else begin 
                            m1_c <= input_buf[3:0]; 
                            input_buf <= '0; 
                            error_flag <= 1'b0; 
                            curr_r <= 4'd1; 
                            curr_c <= 4'd1; 
                            state <= S_LOAD_M1; 
                        end
                    end
                end

                S_LOAD_M1: begin
                    sys_state <= 3'd2; 
                    prompt_type <= 3'd6; 
                    display_data <= {20'd0, input_buf};
                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Z]) input_buf <= {input_buf[7:0], 4'h0};
                    if (pb_pulse[KEY_Y]) begin
                        mem_bus.addr  <= BASE_M1 + m1_offset_mult + cc_minus_1;
                        mem_bus.wdata <= {20'd0, input_buf}; 
                        mem_bus.wen <= 1'b1; 
                        state <= S_LOAD_M1_ACK;
                    end
                end

                S_LOAD_M1_ACK: begin
                    mem_bus.wen <= 1'b0; 
                    input_buf <= '0;
                    if (curr_c == m1_c) begin
                        if (curr_r == m1_r) begin 
                            ready_flag <= 1'b1; 
                            state <= S_OP_SELECT; 
                        end 
                        else begin 
                            curr_r <= curr_r + 1; 
                            curr_c <= 4'd1; 
                            state <= S_LOAD_M1; 
                        end
                    end else begin 
                        curr_c <= curr_c + 1; 
                        state <= S_LOAD_M1; 
                    end
                end

                S_OP_SELECT: begin
                    sys_state <= 3'd1; 
                    display_data <= '0;
                    if (op_type == 3'd1) prompt_type <= 3'd3; 
                    else if (op_type == 3'd2) prompt_type <= 3'd4; 
                    else if (op_type == 3'd3) prompt_type <= 3'd5; 
                    else prompt_type <= 3'd0;

                    if (pb_pulse[KEY_A]) op_type <= 3'd1; 
                    if (pb_pulse[KEY_B]) op_type <= 3'd2; 
                    if (pb_pulse[KEY_C]) op_type <= 3'd3; 

                    if (pb_pulse[KEY_Y] && op_type != 0) begin
                        ready_flag <= 1'b0; 
                        curr_r <= 4'd1; 
                        curr_c <= 4'd1; 
                        input_buf <= '0;
                        if (op_type == 3'd1) begin 
                            m2_r <= m1_r; 
                            m2_c <= m1_c; 
                            out_r <= m1_r; 
                            out_c <= m1_c; 
                            state <= S_LOAD_M2; 
                        end 
                        else if (op_type == 3'd2) begin 
                            m2_r <= m1_c; 
                            out_r <= m1_r; 
                            state <= S_DIM_M2_COL; 
                        end 
                        else begin 
                            out_r <= m1_c; 
                            out_c <= m1_r; 
                            state <= S_CALC_SETUP; 
                        end
                    end
                end

                S_DIM_M2_COL: begin
                    prompt_type <= 3'd2; display_data <= {20'd0, input_buf};
                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Y]) begin
                        if (input_buf[3:0] == 0 || input_buf[3:0] > 9) error_flag <= 1'b1;
                        else begin 
                            m2_c <= input_buf[3:0]; 
                            out_c <= input_buf[3:0]; 
                            input_buf <= '0; 
                            error_flag <= 1'b0; 
                            curr_r <= 4'd1; 
                            curr_c <= 4'd1; 
                            state <= S_LOAD_M2; 
                        end
                    end
                end

                S_LOAD_M2: begin
                    sys_state <= 3'd2; 
                    prompt_type <= 3'd6; 
                    display_data <= {20'd0, input_buf};
                    if (valid_num) input_buf[3:0] <= num_val;
                    if (pb_pulse[KEY_Z]) input_buf <= {input_buf[7:0], 4'h0};
                    if (pb_pulse[KEY_Y]) begin
                        mem_bus.addr <= BASE_M2 + m2_offset_mult + cc_minus_1;
                        mem_bus.wdata <= {20'd0, input_buf}; 
                        mem_bus.wen <= 1'b1; 
                        state <= S_LOAD_M2_ACK;
                    end
                end

                S_LOAD_M2_ACK: begin
                    mem_bus.wen <= 1'b0; 
                    input_buf <= '0;
                    if (curr_c == m2_c) begin
                        if (curr_r == m2_r) begin 
                            ready_flag <= 1'b1; 
                            state <= S_CALC_SETUP; 
                        end 
                        else begin 
                            curr_r <= curr_r + 1; 
                            curr_c <= 4'd1; 
                            state <= S_LOAD_M2; 
                        end
                    end else begin 
                        curr_c <= curr_c + 1; 
                        state <= S_LOAD_M2; 
                    end
                end

                S_CALC_SETUP: begin 
                    calc_i <= '0; 
                    calc_j <= '0; 
                    calc_k <= '0; 
                    state <= S_CALC_START; 
                end

                S_CALC_START: begin
                    sys_state <= 3'd3; 
                    if (op_type == 3'd1) prompt_type <= 3'd3; 
                    else if (op_type == 3'd2) prompt_type <= 3'd4; 
                    else prompt_type <= 3'd5; 

                    add_if.rsize <= {28'd0, m1_r}; 
                    add_if.csize <= {28'd0, m1_c};
                    vec_if.rsize <= {28'd0, m1_r}; 
                    vec_if.csize <= {28'd0, m1_c}; 
                    tra_if.rsize <= {28'd0, m1_r}; 
                    tra_if.csize <= {28'd0, m1_c};
                    
                    add_if.valid <= (op_type == 3'd1); 
                    vec_if.valid <= (op_type == 3'd2); 
                    tra_if.valid <= (op_type == 3'd3);
                    state <= S_CALC_START_WAIT_LOW;
                end

                S_CALC_START_WAIT_LOW: begin
                    if ((op_type == 1 && !add_if.ready) || (op_type == 2 && !vec_if.ready) || (op_type == 3 && !tra_if.ready)) begin
                        add_if.valid <= 1'b0; 
                        vec_if.valid <= 1'b0; 
                        tra_if.valid <= 1'b0;
                        state <= S_CALC_START_WAIT_HIGH;
                    end
                end

                S_CALC_START_WAIT_HIGH: begin
                    if ((op_type == 1 && add_if.ready) || (op_type == 2 && vec_if.ready) || (op_type == 3 && tra_if.ready)) begin
                        state <= S_CALC_FETCH_A;
                    end
                end

                S_CALC_FETCH_A: begin
                    mem_bus.ren <= 1'b1; 
                    if (op_type == 1 || op_type == 3) mem_bus.addr <= BASE_M1 + calc_i;
                    else if (op_type == 2) mem_bus.addr <= BASE_M1 + calc_a_mult + calc_k;
                    state <= S_CALC_WAIT_A;
                end

                S_CALC_WAIT_A: begin 
                    mem_bus.ren <= 1'b0; 
                    state <= S_CALC_LATCH_A; 
                end
                
                S_CALC_LATCH_A: begin
                    temp_rdata <= mem_bus.rdata;
                    state <= S_CALC_SEND_A;
                end

                S_CALC_SEND_A: begin
                    if (op_type == 1) add_if.data <= temp_rdata; 
                    if (op_type == 2) vec_if.data <= temp_rdata; 
                    if (op_type == 3) tra_if.data <= temp_rdata; 
                    
                    add_if.valid <= (op_type == 3'd1); 
                    vec_if.valid <= (op_type == 3'd2); 
                    tra_if.valid <= (op_type == 3'd3);
                    state <= S_CALC_ACK_A_LOW;
                end

                S_CALC_ACK_A_LOW: begin
                    if ((op_type == 1 && !add_if.ready) || (op_type == 2 && !vec_if.ready) || (op_type == 3 && !tra_if.ready)) begin
                        add_if.valid <= 1'b0; 
                        vec_if.valid <= 1'b0; 
                        tra_if.valid <= 1'b0;
                        if (op_type == 3) state <= S_CALC_WAIT_RES; 
                        else state <= S_CALC_ACK_A_HIGH;
                    end
                end

                S_CALC_ACK_A_HIGH: begin
                    if ((op_type == 1 && add_if.ready) || (op_type == 2 && vec_if.ready)) begin
                        state <= S_CALC_FETCH_B;
                    end
                end

                S_CALC_FETCH_B: begin
                    mem_bus.ren <= 1'b1; 
                    if (op_type == 1) mem_bus.addr <= BASE_M2 + calc_i;
                    else if (op_type == 2) mem_bus.addr <= BASE_M2 + calc_b_mult + calc_j;
                    state <= S_CALC_WAIT_B;
                end

                S_CALC_WAIT_B: begin 
                    mem_bus.ren <= 1'b0; 
                    state <= S_CALC_LATCH_B; 
                end
                
                S_CALC_LATCH_B: begin
                    temp_rdata <= mem_bus.rdata; 
                    state <= S_CALC_SEND_B;
                end

                S_CALC_SEND_B: begin
                    if (op_type == 1) add_if.data <= temp_rdata; 
                    if (op_type == 2) vec_if.data <= temp_rdata; 
                    
                    add_if.valid <= (op_type == 3'd1); 
                    vec_if.valid <= (op_type == 3'd2); 
                    state <= S_CALC_ACK_B_LOW;
                end

                S_CALC_ACK_B_LOW: begin
                    if ((op_type == 1 && !add_if.ready) || (op_type == 2 && !vec_if.ready)) begin
                        add_if.valid <= 1'b0; 
                        vec_if.valid <= 1'b0;
                        if (op_type == 2) begin
                            if (calc_k + 32'd1 == 32'(m1_c)) state <= S_CALC_WAIT_RES;
                            else state <= S_CALC_ACK_B_HIGH;
                        end else state <= S_CALC_WAIT_RES;
                    end
                end

                S_CALC_ACK_B_HIGH: begin
                    if (op_type == 2 && vec_if.ready) begin
                        calc_k <= calc_k + 1;
                        state <= S_CALC_FETCH_A;
                    end
                end

                S_CALC_WAIT_RES: begin
                    sum_ready <= 1'b1; 
                    trans_ready <= 1'b1;
                    if (op_type == 1 && sum_valid) begin
                        sum_ready <= 1'b1; 
                        mem_bus.wdata <= sum_out; 
                        mem_bus.addr <= BASE_OUT + calc_i;
                        mem_bus.wen <= 1'b1; 
                        state <= S_CALC_WRITE_RES;
                    end
                    else if (op_type == 2 && vec_done) begin
                        mem_bus.wdata <= vec_product[31:0]; 
                        mem_bus.addr <= BASE_OUT + vec_res_mult + calc_j;
                        mem_bus.wen <= 1'b1; 
                        state <= S_CALC_WRITE_RES;
                    end
                    else if (op_type == 3 && trans_valid) begin
                        trans_ready <= 1'b1;
                        mem_bus.wdata <= trans_out; 
                        mem_bus.addr <= BASE_OUT + tra_res_mult + dest_cidx;
                        mem_bus.wen <= 1'b1; 
                        state <= S_CALC_WRITE_RES;
                    end
                end

                S_CALC_WRITE_RES: begin
                    if ((op_type == 1 && !sum_valid) || (op_type == 3 && !trans_valid) || (op_type == 2)) begin
                        sum_ready <= 1'b0; 
                        trans_ready <= 1'b0; 
                        mem_bus.wen <= 1'b0; 
                        
                        if (op_type == 1 || op_type == 3) begin
                            if (calc_i + 32'd1 == size_limit_mult) state <= S_CALC_DONE_WAIT; 
                            else begin 
                                calc_i <= calc_i + 1; 
                                state <= S_CALC_NEXT_WAIT_HIGH; 
                            end
                        end
                        else if (op_type == 2) begin
                            if (calc_j + 32'd1 == 32'(m2_c)) begin
                                calc_j <= 0;
                                if (calc_i + 32'd1 == 32'(m1_r)) state <= S_CALC_DONE_WAIT;
                                else begin 
                                    calc_i <= calc_i + 1; 
                                    calc_k <= 0; 
                                    state <= S_CALC_START; 
                                end
                            end else begin
                                calc_j <= calc_j + 1; 
                                calc_k <= 0; 
                                state <= S_CALC_START;
                            end
                        end
                    end
                end

                S_CALC_NEXT_WAIT_HIGH: begin
                    if ((op_type == 1 && add_if.ready) || (op_type == 3 && tra_if.ready)) begin
                        state <= S_CALC_FETCH_A;
                    end
                end

                S_CALC_DONE_WAIT: begin
                    if ((op_type == 1 && add_done) || (op_type == 3 && tra_done) || (op_type == 2 && vec_done)) begin
                        state <= S_OUT_IDLE_SETUP;
                    end
                end

                S_OUT_IDLE_SETUP: begin 
                    curr_r <= 4'd1; 
                    curr_c <= 4'd1; 
                    state <= S_OUT_FETCH; 
                end

                S_OUT_FETCH: begin
                    sys_state <= 3'd2; 
                    prompt_type <= 3'd6;
                    mem_bus.addr <= BASE_OUT + out_offset_mult + cc_minus_1;
                    mem_bus.ren  <= 1'b1; 
                    state <= S_OUT_FETCH_WAIT;
                end

                S_OUT_FETCH_WAIT: begin 
                    mem_bus.ren <= 1'b0; 
                    state <= S_OUT_FETCH_ACK; 
                end

                S_OUT_FETCH_ACK: begin 
                    display_data <= mem_bus.rdata; 
                    state <= S_OUT_IDLE; 
                end

                S_OUT_IDLE: begin
                    sys_state <= 3'd2; prompt_type <= 3'd6;
                    if (pb_pulse[KEY_W] && curr_r > 1)     begin 
                        curr_r <= curr_r - 1; 
                        state <= S_OUT_FETCH; 
                    end
                    if (pb_pulse[KEY_B] && curr_r < out_r) begin 
                        curr_r <= curr_r + 1; 
                        state <= S_OUT_FETCH; 
                    end
                    if (pb_pulse[KEY_A] && curr_c > 1)     begin 
                        curr_c <= curr_c - 1; 
                        state <= S_OUT_FETCH; 
                    end
                    if (pb_pulse[KEY_D] && curr_c < out_c) begin 
                        curr_c <= curr_c + 1;
                        state <= S_OUT_FETCH; 
                    end
                end

                default: state <= S_INIT;
            endcase
        end
    end

    logic [31:0] shadow_out [0:100];
    logic [5:0]  last_state; 

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            last_state <= 6'h3F;
        end else begin
            if (state != last_state) begin
                last_state <= state;
            end

            if (valid_num) $display("[DEBUG] Typed Number: %0d", num_val);
            
            if (mem_bus.wen) begin
                if (mem_bus.addr >= BASE_OUT) shadow_out[mem_bus.addr - BASE_OUT] = mem_bus.wdata;
            end

            if (state == S_OUT_IDLE_SETUP && last_state == S_CALC_DONE_WAIT) begin
                $display("\n");
                $display("COMPUTATION COMPLETE");
                $display("        Resulting %0dx%0d Matrix:", out_r, out_c);
                $display("\n");
                for (int r = 0; r < out_r; r++) begin
                    $write("   ");
                    for (int c = 0; c < out_c; c++) begin
                        $write("%0d\t", shadow_out[(r * out_c) + c]);
                    end
                    $display("");
                end
                $display("\n");
            end
        end
    end
endmodule