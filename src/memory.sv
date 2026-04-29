module memory (
    input logic clk,
    input logic nRst,
    mem_if.memory_mp mif
);

    // 512 words, 32-bit 
    logic [31:0] ram [0:511];

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            mif.rdata <= '0;
            mif.ready <= 1'b0;
        end else begin
            if ((mif.wen || mif.ren) && !mif.ready) begin
                if (mif.wen) begin
                    ram[mif.addr[8:0]] <= mif.wdata;
                end
                
                if (mif.ren) begin
                    mif.rdata <= ram[mif.addr[8:0]];
                end
                
                mif.ready <= 1'b1;
            end else begin
                mif.ready <= 1'b0;
            end
        end
    end

endmodule
