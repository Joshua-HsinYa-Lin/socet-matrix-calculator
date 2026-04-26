(* keep_hierarchy = 1 *)
module pure_multiplier(
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [63:0] p
);
    assign p = a * b;
endmodule

module vector(
    input logic clk,
    input logic nRST,
    matrix_if.module_mp mif,
    output logic [63:0] product,
    output logic done
);
    
    logic [63:0] accumulator;
    logic [31:0] idx, len, reg_A, reg_B;

    logic [63:0] mult_wire;
    pure_multiplier pm(.a(reg_A), .b(reg_B), .p(mult_wire));

    typedef enum logic [2:0]{
        IDLE, FETCH_A, FETCH_B, ACC, CHECK, DONE
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge nRST) begin
        if(!nRST) begin
            state       <= IDLE;
            accumulator <= '0;
            reg_A       <= '0;
            reg_B       <= '0;
            idx         <= '0;
            len         <= '0;
            mif.ready   <= 1'b0;
            done        <= 1'b0;
            product     <= '0;
        end else begin
            case(state)
                IDLE: begin
                    done <= 1'b0;
                    if(mif.valid) begin
                        accumulator <= '0; idx <= '0; len <= mif.csize;
                        mif.ready <= 1'b0; state <= FETCH_A;
                    end else mif.ready <= 1'b1;
                end
                
                FETCH_A: begin
                    if(mif.valid) begin
                        reg_A <= mif.data; mif.ready <= 1'b0; state <= FETCH_B;
                    end else mif.ready <= 1'b1;
                end
                
                FETCH_B: begin
                    if(mif.valid) begin
                        reg_B <= mif.data; mif.ready <= 1'b0; state <= ACC;
                    end else mif.ready <= 1'b1;
                end
                
                ACC: begin
                    // Adding the wire output from the locked sub-module
                    accumulator <= accumulator + mult_wire;
                    idx <= idx + 1;
                    state <= CHECK;
                end
                
                CHECK: begin
                    if(idx == len) begin product <= accumulator; state <= DONE; end 
                    else state <= FETCH_A;
                end
                
                DONE: begin
                    done <= 1'b1;
                    if(!mif.valid) state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule