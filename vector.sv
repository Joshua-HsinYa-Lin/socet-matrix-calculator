module vector(
	input logic clk,
	input logic nRST,
	matrix_if.module_mp mif,
	output logic [63:0] product,
	output logic done
);
	
	logic [63:0] accumulator;
	logic [31:0] idx, len, reg_A, reg_B;

	typedef enum logic [2:0]{
		IDLE,
		FETCH_A,
		FETCH_B,
		ACC,
		CHECK,
		DONE
	} state_t;

	state_t state;

	always_ff @(posedge clk or negedge nRST) begin
		if(!nRST) begin
			state <= IDLE;
			accumulator <= '0;
			reg_A <= '0;
			reg_B <= '0;
			idx <= '0;
			len <= '0;
			mif.ready <= 1'b0;
			done <= 1'b0;
			product <= 1'b0;
		end else begin
			case(state)
				IDLE: begin
					mif.ready <= 1'b1;
					done <= 1'b0;
					if(mif.valid) begin
						accumulator  <= '0;
						idx <= '0;
						len <= mif.csize;
						mif.ready <= 1b'0;
						state <= FETCH_A;
					end
				end

				FETCH_A: begin
					mif.ready <= 1b'1;
					if(mif.valid) begin
						reg_A <= mif.data;
						mif.ready <= 1b'0;
						state = FETCH_B;
					end
				end
				
				FETCH_B: begin
					mif.ready <= 1b'1;
					if(mif.valid) begin
						reg_B <= mif.data;
						mif.ready <= 1b'0;
						state = ACC;
					end
				end

				ACC: begin
					accumulator <= accumulator + (reg_A * reg_B);
					idx <= idx + 1;
					state <= CHECK;
				end

				CHECK: begin
					if(idx == len) begin
						product <= accumulator;
						state <= DONE;
					end else begin
						state <= FETCH_A
					end
				end

				DONE: begin
					done <= 1'b1;
					if(!mif.valid) begin
						state <= IDLE;
					end
				end

				default: state <= IDLE;
			endcase
		end
	end

endmodule