interface mem_if (
    input logic clk, 
    input logic nRst
);

	logic wen;
	logic ren;
	logic ready;
	
	logic[31:0] addr;
	logic[31:0] wdata;
	logic[31:0] rdata;

	modport controller_mp (
        	output wen, ren, addr, wdata,
        	input  rdata, ready
    	);

    	modport memory_mp (
        	input  wen, ren, addr, wdata,
        	output rdata, ready
    	);
endinterface
