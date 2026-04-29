module matrix_scalar (
    input  logic        clk,
    input  logic        nRst,
    matrix_if.module_mp mif,

    input  logic [31:0] scalar,

    output logic [31:0] scalar_out,
    output logic        scalar_valid,
    input  logic        scalar_ready,
    output logic        operation_done
);

    logic [31:0] element_counter;
    logic [31:0] total_elements;
    logic [63:0] product_full;

    // rows/cols are max 9, so this avoids width warnings from rsize * csize
    function [31:0] mult_by_dim(input logic [31:0] val, input logic [31:0] dim);
        case (dim[3:0])
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

    always_comb begin
        product_full = mif.data * scalar;
    end

    typedef enum logic [1:0] {
        IDLE,
        FETCH_A,
        SEND_PRODUCT,
        DONE
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            state           <= IDLE;
            element_counter <= '0;
            total_elements  <= '0;
            mif.ready       <= 1'b0;
            scalar_out      <= '0;
            scalar_valid    <= 1'b0;
            operation_done  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    mif.ready      <= 1'b1;
                    scalar_valid   <= 1'b0;
                    operation_done <= 1'b0;

                    // First valid pulse gives the matrix dimensions.
                    if (mif.valid) begin
                        element_counter <= '0;
                        total_elements  <= mult_by_dim(mif.rsize, mif.csize);
                        mif.ready       <= 1'b0;
                        state           <= FETCH_A;
                    end
                end

                FETCH_A: begin
                    mif.ready <= 1'b1;

                    if (mif.valid) begin
                        scalar_out   <= product_full[31:0];
                        scalar_valid <= 1'b1;
                        mif.ready    <= 1'b0;
                        state        <= SEND_PRODUCT;
                    end
                end

                SEND_PRODUCT: begin
                    if (scalar_ready) begin
                        scalar_valid    <= 1'b0;
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

