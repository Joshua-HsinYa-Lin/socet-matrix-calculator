`timescale 1ns / 1ps

module tb_scalar ();

    logic clk;
    logic nRst;

    matrix_if mif(clk, nRst);

    logic [31:0] scalar;
    logic [31:0] scalar_out;
    logic        scalar_valid;
    logic        scalar_ready;
    logic        operation_done;

    matrix_scalar dut (
        .clk(clk),
        .nRst(nRst),
        .mif(mif.module_mp),
        .scalar(scalar),
        .scalar_out(scalar_out),
        .scalar_valid(scalar_valid),
        .scalar_ready(scalar_ready),
        .operation_done(operation_done)
    );

    always #5 clk = ~clk;

    task automatic send_word(input logic [31:0] data_word);
        wait(mif.ready == 1'b1);
        @(posedge clk);

        mif.data  = data_word;
        mif.valid = 1'b1;

        @(posedge clk);
        mif.valid = 1'b0;
        mif.data  = 'x;
    endtask

    task automatic send_matrix_size(input int rows, input int cols);
        wait(mif.ready == 1'b1);
        @(posedge clk);

        mif.rsize = rows;
        mif.csize = cols;
        mif.valid = 1'b1;

        @(posedge clk);
        mif.valid = 1'b0;
    endtask

    task automatic test_scalar_mult(
        input logic [31:0] A [],
        input logic [31:0] Expected [],
        input logic [31:0] scalar_value,
        input int          rows,
        input int          cols,
        input string       test_name
    );
        int total_elements;
        int errors;

        total_elements = rows * cols;
        errors = 0;
        scalar = scalar_value;

        $display("Starting Test: %s (%0dx%0d Matrix, scalar = %0d)", test_name, rows, cols, scalar_value);

        send_matrix_size(rows, cols);

        for (int i = 0; i < total_elements; i++) begin
            send_word(A[i]);

            do begin
                @(posedge clk);
            end while (!scalar_valid);

            if (scalar_out !== Expected[i]) begin
                $display("  [ERROR] Index %0d: Expected %0d, Got %0d", i, Expected[i], scalar_out);
                errors++;
            end

            scalar_ready = 1'b1;
            @(posedge clk);
            scalar_ready = 1'b0;
        end

        wait(operation_done == 1'b1);
        @(posedge clk);

        if (errors == 0) begin
            $display("[PASS] %s completed successfully.", test_name);
        end else begin
            $display("[FAIL] %s had %0d errors.", test_name, errors);
        end

        mif.valid = 1'b0;
        @(posedge clk);
        @(posedge clk);
    endtask

    initial begin
        clk          = 0;
        nRst         = 0;
        mif.valid    = 0;
        mif.data     = 0;
        mif.rsize    = 0;
        mif.csize    = 0;
        scalar       = 0;
        scalar_ready = 0;

        #20;
        nRst = 1;
        #20;

        test_scalar_mult('{1, 2, 3, 4},
                         '{3, 6, 9, 12},
                         3, 2, 2, "2x2 times 3");

        test_scalar_mult('{10, 20, 30},
                         '{0, 0, 0},
                         0, 1, 3, "1x3 times 0");

        test_scalar_mult('{5, 0, 7, 8, 9, 2},
                         '{10, 0, 14, 16, 18, 4},
                         2, 2, 3, "2x3 times 2");

        $display("All scalar multiplication tests completed.");
        $finish;
    end

endmodule
