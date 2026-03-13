interface matrix_if(
	input logic clk, 
	input logic nRST
);
	logic valid;
	logic ready;
	logic wen;
	logic data [31:0] data;
	logic data [31:0] ridx;
	logic data [31:0] cidx;
	logic data [31:0] rsize;
	logic data [31:0] csize;

	modport controller_mp (
		input ready,
		output valid, wen, ren, data, ridx, cidx, rsize, csize
	);

	modport module_mp (
        	input  valid, wen, ren, data, ridx, cidx, rsize, csize,
        	output ready
        );

endinterface
