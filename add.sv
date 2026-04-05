module matrix_add (
    input  logic        clk,
    input  logic        nRst,
    matrix_if.module_mp mif,
    output logic [31:0] sum_out,
    output logic        sum_valid,
    input  logic        sum_ready,
    output logic        operation_done
);

    logic [31:0] reg_A;
    logic [31:0] reg_B;
    logic [31:0] element_counter;
    logic [31:0] total_elements;

    typedef enum logic [2:0] {
        IDLE,
        FETCH_A,
        FETCH_B,
        SEND_SUM,
        DONE
    } state_t;
    
    state_t state;

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            state           <= IDLE;
            reg_A           <= '0;
            reg_B           <= '0;
            element_counter <= '0;
            total_elements  <= '0;
            mif.ready       <= 1'b0;
            sum_out         <= '0;
            sum_valid       <= 1'b0;
            operation_done  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    mif.ready      <= 1'b1; 
                    operation_done <= 1'b0;
                    sum_valid      <= 1'b0;
                    
                    if (mif.valid) begin
                        element_counter <= '0;
                        total_elements  <= mif.rsize * mif.csize; 
                        mif.ready       <= 1'b0;      
                        state           <= FETCH_A;
                    end
                end

                FETCH_A: begin
                    mif.ready <= 1'b1; 
                    
                    if (mif.valid) begin
                        reg_A     <= mif.data;
                        mif.ready <= 1'b0; 
                        state     <= FETCH_B;
                    end
                end

                FETCH_B: begin
                    mif.ready <= 1'b1; 
                    
                    if (mif.valid) begin
                        reg_B     <= mif.data;
                        mif.ready <= 1'b0; 
                        state     <= SEND_SUM;
                    end
                end

                SEND_SUM: begin
                    sum_out   <= reg_A + reg_B;
                    sum_valid <= 1'b1;
                    
                    if (sum_ready) begin
                        sum_valid       <= 1'b0;
                        element_counter <= element_counter + 1;
                        
                        if (element_counter + 1 == total_elements) begin
                            state <= DONE;
                        end else begin
                            state <= FETCH_A;
                        end
                    end
                end

                DONE: begin
                    operation_done <= 1'b1;
                    
                    if (!mif.valid) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
