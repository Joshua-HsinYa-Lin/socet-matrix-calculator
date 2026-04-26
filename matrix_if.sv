interface matrix_if(
	input logic clk, 
	input logic nRST
);
	logic valid;
	logic ready;
	logic wen;
	logic ren;
	logic [31:0] data;
	logic [31:0] ridx;
	logic [31:0] cidx;
	logic [31:0] rsize;
	logic [31:0] csize;
	modport controller_mp (
		input ready,
		output valid, wen, ren, data, ridx, cidx, rsize, csize
	);

	modport module_mp (
        	input  valid, wen, ren, data, ridx, cidx, rsize, csize,
        	output ready
        );

endinterface
