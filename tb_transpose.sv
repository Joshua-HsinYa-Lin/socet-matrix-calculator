`timescale 1ns / 1ps

module tb_transpose ();

    logic clk;
    logic nRst;

    matrix_if mif(clk, nRst);
    
    logic [31:0] trans_out;
    logic [31:0] dest_ridx;
    logic [31:0] dest_cidx;
    logic        trans_valid;
    logic        trans_ready;
    logic        operation_done;

    matrix_transpose dut (
        .clk(clk),
        .nRst(nRst),
        .mif(mif.module_mp),
        .trans_out(trans_out),
        .dest_ridx(dest_ridx),
        .dest_cidx(dest_cidx),
        .trans_valid(trans_valid),
        .trans_ready(trans_ready),
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

    task test_transpose(
        input logic [31:0] Matrix [], 
        input int          rows,
        input int          cols,
        input string       test_name
    );
        int total_elements = rows * cols;
        int errors = 0;
        int expected_ridx;
        int expected_cidx;

        $display("Starting Test: %s (%0dx%0d Matrix)", test_name, rows, cols);

        mif.rsize = rows;
        mif.csize = cols;
        mif.valid = 1'b1;
        
        do begin
            @(posedge clk);
        end while (!mif.ready);
        mif.valid = 1'b0;

        for (int i = 0; i < total_elements; i++) begin
            send_word(Matrix[i]);

            do begin
                @(posedge clk);
            end while (!trans_valid);

            // Mathematical check for transposition indices
            expected_ridx = i % cols;
            expected_cidx = i / cols;

            if (trans_out !== Matrix[i] || dest_ridx !== expected_ridx || dest_cidx !== expected_cidx) begin
                $display("  [ERROR] Index %0d: Expected Val %0d at dest(%0d,%0d), Got Val %0d at dest(%0d,%0d)", 
                    i, Matrix[i], expected_ridx, expected_cidx, trans_out, dest_ridx, dest_cidx);
                errors++;
            end

            trans_ready = 1'b1;
            @(posedge clk);
            trans_ready = 1'b0;
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
        clk         = 0;
        nRst        = 0;
        mif.valid   = 0;
        mif.data    = 0;
        mif.rsize   = 0;
        mif.csize   = 0;
        trans_ready = 0;

        #20;
        nRst = 1;
        #20;

        // Test 1: Asymmetrical Matrix
        test_transpose(
            '{1, 2, 3, 4, 5, 6}, // 2x3 matrix
            2, 3, 
            "2x3 Matrix Transposition"
        );

        // Test 2: Symmetrical Matrix
        test_transpose(
            '{10, 20, 30, 40}, // 2x2 matrix
            2, 2, 
            "2x2 Matrix Transposition"
        );

        $display("All tests completed.");
        $finish;
    end

endmodule
