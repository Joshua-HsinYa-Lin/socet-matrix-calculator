VLOG = vlog
VLOG_FLAGS = -sv -work work
VSIM = vsim
VSIM_BATCH_FLAGS = -c -do "run -all; quit"
VSIM_GUI_FLAGS = -voptargs="+acc" -do "add wave -r /*; run -all"

SRC_DIR = src
TB_DIR = tb

SRCS = \
	$(SRC_DIR)/matrix_if.sv \
	$(SRC_DIR)/mem_if.sv \
	$(SRC_DIR)/add.sv \
	$(SRC_DIR)/vector.sv \
	$(SRC_DIR)/transpose.sv \
	$(SRC_DIR)/memory.sv \
	$(SRC_DIR)/display.sv \
	$(SRC_DIR)/happy.sv \
	$(SRC_DIR)/main.sv \
	$(SRC_DIR)/top.sv

TBS = $(wildcard $(TB_DIR)/*.sv)

TB_MODULES = $(patsubst $(TB_DIR)/%.sv, %, $(TBS))

all: compile

compile:
	@if [ ! -d "work" ]; then vlib work; fi
	$(VLOG) $(VLOG_FLAGS) $(SRCS) $(TBS)

testall: compile
	@for tb in $(TB_MODULES); do \
		echo "[TB] Running $$tb..."; \
		$(VSIM) $(VSIM_BATCH_FLAGS) $$tb; \
	done
	@echo "All testbenches completed!"

wave: compile
	$(VSIM) $(VSIM_GUI_FLAGS) tb_main &

clean:
	rm -rf work/ transcript *.wlf *.vcd

.PHONY: all compile testall wave clean
