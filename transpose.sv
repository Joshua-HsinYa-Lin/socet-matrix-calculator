module matrix_transpose (
    input  logic        clk,
    input  logic        nRst,
    matrix_if.module_mp mif,
    
    // Outputs to the Main Controller / Memory Interface
    output logic [31:0] trans_out,
    output logic [31:0] dest_ridx,
    output logic [31:0] dest_cidx,
    output logic        trans_valid,
    input  logic        trans_ready,
    output logic        operation_done
);

    logic [31:0] element_counter;
    logic [31:0] total_elements;
    
    // Internal coordinate trackers
    logic [31:0] row_cnt;
    logic [31:0] col_cnt;

    typedef enum logic [1:0] {
        IDLE,
        FETCH,
        SEND,
        DONE
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            state           <= IDLE;
            element_counter <= '0;
            total_elements  <= '0;
            row_cnt         <= '0;
            col_cnt         <= '0;
            mif.ready       <= 1'b0;
            trans_out       <= '0;
            dest_ridx       <= '0;
            dest_cidx       <= '0;
            trans_valid     <= 1'b0;
            operation_done  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    mif.ready      <= 1'b1;
                    operation_done <= 1'b0;
                    trans_valid    <= 1'b0;
                    if (mif.valid) begin
                        element_counter <= '0;
                        total_elements  <= mif.rsize * mif.csize;
                        row_cnt         <= '0;
                        col_cnt         <= '0;
                        mif.ready       <= 1'b0;
                        state           <= FETCH;
                    end
                end

                FETCH: begin
                    mif.ready <= 1'b1;
                    if (mif.valid) begin
                        trans_out <= mif.data;
                        
                        // Transposition mapping: Swap row and column
                        dest_ridx <= col_cnt;
                        dest_cidx <= row_cnt;
                        
                        mif.ready <= 1'b0;
                        state     <= SEND;
                    end
                end

                SEND: begin
                    trans_valid <= 1'b1;
                    
                    // Wait for main controller to acknowledge receipt
                    if (trans_ready) begin
                        trans_valid <= 1'b0;
                        element_counter <= element_counter + 1;
                        
                        // Update sequential read coordinate trackers
                        if (col_cnt + 1 == mif.csize) begin
                            col_cnt <= '0;
                            row_cnt <= row_cnt + 1;
                        end else begin
                            col_cnt <= col_cnt + 1;
                        end

                        if (element_counter + 1 == total_elements) begin
                            state <= DONE;
                        end else begin
                            state <= FETCH;
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
