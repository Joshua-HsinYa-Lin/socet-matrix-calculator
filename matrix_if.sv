interface matrix_if (
    input logic clk,
    input logic nRst
);
    logic        valid;
    logic        ready;
    logic [31:0] rsize;
    logic [31:0] csize;
    logic [31:0] data;

    modport controller_mp (
        output valid, rsize, csize, data,
        input  ready
    );

    modport module_mp (
        input  valid, rsize, csize, data,
        output ready
    );
endinterface