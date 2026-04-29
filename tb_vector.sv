`timescale 1ns / 1ps

module tb_vector();
    logic clk;
    logic nRST;
    matrix_if mif(clk, nRST);
    logic done;
    logic [63:0] product;

    vector dut(
        .clk(clk),
        .nRST(nRST),
        .mif(mif.module_mp),
        .product(product),
        .done(done)
    );

    always #5 clk = ~clk;

    task automatic send_word(input logic [31:0] word);
        while (!mif.ready) @(posedge clk);
        
        @(negedge clk);
        mif.data = word;
        mif.valid = 1'b1;
        
        @(negedge clk);
        mif.valid = 1'b0;
        mif.data = '0;
    endtask

    task automatic test_dot(
        input logic [31:0] A[],
        input logic [31:0] B[],
        input logic [63:0] expected
    );
        int len = A.size();
        int test_num = 0;
        
        $display("Test %0d: begin ...", test_num);
        
        while (!mif.ready) @(posedge clk);
        
        @(negedge clk);
        mif.csize = len;
        mif.valid = 1'b1;
        
        @(negedge clk);
        mif.valid = 1'b0;

        for(int i = 0; i < len; i = i + 1) begin
            send_word(A[i]);
            send_word(B[i]);
        end

        wait(done == 1'b1);
        @(posedge clk);
        
        if(product == expected) begin
            $display("Passed, expected %0d, got %0d", expected, product);
        end else begin
            $display("Failed, expected %0d, got %0d", expected, product);
        end

        @(negedge clk);
        mif.valid = 1'b0;
    endtask

    initial begin
        clk       = 0;
        nRST      = 0;
        mif.valid = 0;
        mif.data  = 0;
        mif.csize = 0;

        #20;
        nRST = 1;
        #20;
        
        test_dot('{1, 2, 3}, '{4, 5, 6}, 64'd32);
        test_dot('{0, 5, 0, 10}, '{99, 2, 99, 3}, 64'd40);
        test_dot('{1000, 2000}, '{1000, 2000}, 64'd5000000);
        
        $display("All tests completed.");
        $finish;
    end
endmodule
