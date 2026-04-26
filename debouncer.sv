module debouncer #(
    parameter int KEYS = 21,
    parameter int CLK_FREQ = 100_000_000,
    parameter int DEBOUNCE_TIME_MS = 10
)(
    input  logic            clk,
    input  logic            reset,
    input  logic [KEYS-1:0] pb_in,
    output logic [KEYS-1:0] pb_pulse
);
    localparam int MAX_COUNT = (CLK_FREQ / 1000) * DEBOUNCE_TIME_MS;
    
    logic [KEYS-1:0] sync_0, sync_1;
    logic [31:0]     counters [KEYS-1:0];
    logic [KEYS-1:0] state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_0   <= '0;
            sync_1   <= '0;
            state    <= '0;
            pb_pulse <= '0;
            for (int i = 0; i < KEYS; i++) counters[i] <= '0;
        end else begin
            // 2-stage synchronizer to prevent metastability
            sync_0 <= pb_in;
            sync_1 <= sync_0;

            for (int i = 0; i < KEYS; i++) begin
                pb_pulse[i] <= 1'b0; // Default to 0

                if (sync_1[i] == ~state[i]) begin
                    if (counters[i] == MAX_COUNT) begin
                        state[i] <= ~state[i];
                        counters[i] <= '0;
                        if (~state[i] == 1'b1) pb_pulse[i] <= 1'b1; // Trigger pulse on rising edge
                    end else begin
                        counters[i] <= counters[i] + 1;
                    end
                end else begin
                    counters[i] <= '0;
                end
            end
        end
    end
endmodule
