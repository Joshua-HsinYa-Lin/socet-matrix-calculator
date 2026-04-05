`timescale 1ns / 1ps

module tb_addition ();

    logic clk;
    logic nRst;

    matrix_if mif(clk, nRst);
    logic [31:0] sum_out;
    logic        sum_valid;
    logic        sum_ready;
    logic        operation_done;

    matrix_add dut (
        .clk(clk),
        .nRst(nRst),
        .mif(mif.module_mp),
        .sum_out(sum_out),
        .sum_valid(sum_valid),
        .sum_ready(sum_ready),
        .operation_done(operation_done)
    );

    always #5 clk = ~clk;

    task send_word(input logic [31:0] data_word);
        mif.data  = data_word;
        mif.valid = 1'b1;
        
        do begin
            @(posedge clk);
        end while (!mif.ready);
        
        mif.valid = 1'b0;
        mif.data  = '0;
    endtask

    task test_matrix_add(
        input logic [31:0] A [], 
        input logic [31:0] B [], 
        input logic [31:0] Expected [],
        input int          rows,
        input int          cols,
        input string       test_name
    );
        int total_elements = rows * cols;
        int errors = 0;

        $display("Starting Test: %s (%0dx%0d Matrix)", test_name, rows, cols);

        mif.rsize = rows;
        mif.csize = cols;
        mif.valid = 1'b1;
        do begin
            @(posedge clk);
        end while (!mif.ready);
        mif.valid = 1'b0;

        for (int i = 0; i < total_elements; i++) begin
            send_word(A[i]); 
            send_word(B[i]); 

            do begin
                @(posedge clk);
            end while (!sum_valid);

            if (sum_out !== Expected[i]) begin
                $display("  [ERROR] Index %0d: Expected %0d, Got %0d", i, Expected[i], sum_out);
                errors++;
            end

            sum_ready = 1'b1;
            @(posedge clk);
            sum_ready = 1'b0;
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
        clk       = 0;
        nRst      = 0;
        mif.valid = 0;
        mif.data  = 0;
        mif.rsize = 0;
        mif.csize = 0;
        sum_ready = 0;

        #20;
        nRst = 1;
        #20;

        test_matrix_add(
            '{1, 2, 3, 4}, 
            '{5, 6, 7, 8}, 
            '{6, 8, 10, 12}, 
            2, 2, 
            "2x2 Matrix Addition"
        );

        test_matrix_add(
            '{10, 20, 30}, 
            '{15, 25, 35}, 
            '{25, 45, 65}, 
            1, 3, 
            "1x3 Vector Addition"
        );

        test_matrix_add(
            '{1, 0, 0, 0, 1, 0, 0, 0, 1}, 
            '{0, 0, 0, 0, 0, 0, 0, 0, 0}, 
            '{1, 0, 0, 0, 1, 0, 0, 0, 1}, 
            3, 3, 
            "3x3 Identity + Zero Matrix"
        );

        $display("All tests completed.");
        $finish;
    end

endmodule
