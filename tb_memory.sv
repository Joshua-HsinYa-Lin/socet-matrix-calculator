`timescale 1ns / 1ps

module tb_memory ();
    logic clk;
    logic nRst;

    mem_if mif(clk, nRst);

    memory dut (
        .clk(clk),
        .nRst(nRst),
        .mif(mif.memory_mp)
    );

    always #5 clk = ~clk;

    // Standardized Write Task
    task write_mem(input logic [31:0] target_addr, input logic [31:0] data);
        mif.addr  = target_addr;
        mif.wdata = data;
        mif.wen   = 1'b1;
        
        do begin
            @(posedge clk);
        end while (!mif.ready);
        
        mif.wen = 1'b0;
        @(posedge clk);
    endtask

    // Standardized Read Task
    task read_mem(input logic [31:0] target_addr, output logic [31:0] data);
        mif.addr = target_addr;
        mif.ren  = 1'b1;
        
        do begin
            @(posedge clk);
        end while (!mif.ready);
        
        data = mif.rdata;
        mif.ren = 1'b0;
        @(posedge clk);
    endtask

    logic [31:0] read_val;

    initial begin
        clk       = 0;
        nRst      = 0;
        mif.wen   = 0;
        mif.ren   = 0;
        mif.addr  = 0;
        mif.wdata = 0;

        #20;
        nRst = 1;
        #20;

        $display("Starting Memory Handshake Tests...");

        // Write Test Matrix 1 Data (Base 0x000)
        write_mem(32'h0000_0000, 32'd125);
        write_mem(32'h0000_0001, 32'd999);

        // Write Test Result Data (Base 0x100 = 256)
        write_mem(32'h0000_0100, 32'd4096);

        // Verify Data Integrity
        read_mem(32'h0000_0000, read_val);
        if (read_val !== 32'd125) $display("[FAIL] Addr 0x000: Expected 125, Got %0d", read_val);
        else $display("[PASS] Addr 0x000 read matched.");

        read_mem(32'h0000_0001, read_val);
        if (read_val !== 32'd999) $display("[FAIL] Addr 0x001: Expected 999, Got %0d", read_val);
        else $display("[PASS] Addr 0x001 read matched.");

        read_mem(32'h0000_0100, read_val);
        if (read_val !== 32'd4096) $display("[FAIL] Addr 0x100: Expected 4096, Got %0d", read_val);
        else $display("[PASS] Addr 0x100 read matched.");

        $display("Memory tests completed.");
        $finish;
    end
endmodule
