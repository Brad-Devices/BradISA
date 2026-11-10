# Makefile for BradISA V1 FPGA Builds

# Tools
VIVADO   ?= vivado
QUARTUS  ?= quartus_sh
GHDL     ?= ghdl
VERILATOR ?= verilator
YOSYS    ?= yosys
IVERILOG ?= iverilog
VVP      ?= vvp

# Directories
VERILOG_DIR = ../verilog
VHDL_DIR    = ../vhdl
FPGA_DIR    = .
GOWIN_DIR   = tangnano9k

# Sources (Verilog)
VERILOG_SRCS = \
    $(VERILOG_DIR)/bradisa_defines.v \
    $(VERILOG_DIR)/brad_regfile.v \
    $(VERILOG_DIR)/brad_alu.v \
    $(VERILOG_DIR)/brad_core.v \
    $(VERILOG_DIR)/tb_brad_core.v

# Sources (VHDL)
VHDL_SRCS = \
    $(VHDL_DIR)/bradisa_pkg.vhd \
    $(VHDL_DIR)/brad_regfile.vhd \
    $(VHDL_DIR)/brad_alu.vhd \
    $(VHDL_DIR)/brad_core.vhd \
    $(VHDL_DIR)/tb_brad_core.vhd

.PHONY: all vivado quartus gowin gowin_fit sim_board sim_gate lint_verilog \
        lint_vhdl clean boot_rom boot_rom_check

all: lint_verilog lint_vhdl

# ─── bradasm: the board's boot program ───────────────────────
# boot.s is the source of truth for the machine code the Tang Nano
# 9K runs.  bradasm assembles it into a Verilog include that the
# board top `include`s, so the program on the board is written in
# assembly and its encodings are the ones the assembler's self-test
# checks against simulated RTL.
#
# The generated header is checked in so the tree simulates without a
# C compiler; CI regenerates it and fails on a diff, so it cannot go
# stale without somebody noticing.
ASM       ?= ../../tools/bradasm/build/bradasm
BRADASM_DIR ?= ../../tools/bradasm
BOOT_SRC  = $(GOWIN_DIR)/boot.s
BOOT_VH   = $(GOWIN_DIR)/boot_rom.vh

$(ASM):
	$(MAKE) -C $(BRADASM_DIR)

$(BOOT_VH): $(BOOT_SRC) $(ASM)
	$(ASM) -V $@ $<

# Force a refresh, for people who just want their tree updated.
boot_rom:
	$(ASM) -V $(BOOT_VH) $(BOOT_SRC)

# Re-generate into a temp file and fail if the checked-in header does not
# match.  This is the step that makes the include trustworthy: it is only a
# convenience if CI proves it is identical to what boot.s assembles to.
# cmp rather than git diff, so the check works on a fresh checkout whether
# or not the header has been committed yet.
boot_rom_check: $(BOOT_VH)
	$(ASM) -V /tmp/boot_rom.check.vh $(BOOT_SRC)
	@cmp -s /tmp/boot_rom.check.vh $(BOOT_VH) || { \
	   echo "ERROR: $(BOOT_VH) is stale; re-run 'make boot_rom' and commit"; \
	   rm -f /tmp/boot_rom.check.vh; \
	   exit 1; }
	@rm -f /tmp/boot_rom.check.vh
	@echo "boot_rom.vh matches boot.s"

# Anything that builds or simulates the board needs the ROM present.
gowin: $(BOOT_VH)
sim_board: $(BOOT_VH)

# ─── Vivado (Xilinx) ───────────────────────────────────────────
vivado:
	cd $(FPGA_DIR) && $(VIVADO) -mode batch -source vivado_build.tcl

# ─── Quartus (Intel) ───────────────────────────────────────────
quartus:
	cd $(FPGA_DIR) && $(QUARTUS) -t quartus_build.tcl

# ─── Gowin: Tang Nano 9K (GW1NR-9C) ───────────────────────────
# Synthesises the board top onto Gowin primitives and reports real
# cell counts.  This is a synthesis receipt, not a bitstream: GW1N
# place-and-route needs nextpnr-himbaechel, Apicula, or Gowin EDA,
# and "runs on real gates" needs the board in hand.  Measured on the
# V2 design (2026-11-10): 1,250 of the part's 8,640 LUT4 and 374 of
# 6,480 FFs under -nowidelut; `make gowin_fit` re-measures on every
# run.  See tangnano9k/README.md for the full resource breakdown.
gowin: $(BOOT_VH)
	cd $(FPGA_DIR)/$(GOWIN_DIR) && $(YOSYS) -s synth_gowin.ys

# ─── Gowin: does it actually fit the part? ──────────────────────
# -nowidelut turns the whole design into plain LUT4s, so the count is
# directly comparable to the GW1NR-9C's 8640 LUT4 / 6480 FF budget.
# This is the guard against misreading a cell count as a fabric count.
GOWIN_LUT_BUDGET ?= 8640
GOWIN_FF_BUDGET  ?= 6480

gowin_fit:
	@cd $(FPGA_DIR)/$(GOWIN_DIR) && $(YOSYS) -s check_fit.ys 2>&1 \
	  | tee /tmp/brad_fit.log | sed -n '/Printing statistics/,/Executing CHECK/p'
	@luts=$$(awk '/Printing statistics/{buf=""} {buf=buf $$0 "\n"} END{printf "%s", buf}' \
	          /tmp/brad_fit.log | grep -oE '^ +LUT[0-9] +[0-9]+' \
	          | awk '{s+=$$2} END {print s+0}'); \
	 ffs=$$(awk '/Printing statistics/{buf=""} {buf=buf $$0 "\n"} END{printf "%s", buf}' \
	          /tmp/brad_fit.log | grep -oE '^ +DFF[A-Z]* +[0-9]+' \
	          | awk '{s+=$$2} END {print s+0}'); \
	 echo ""; \
	 echo "GW1NR-9C fit: $$luts / $(GOWIN_LUT_BUDGET) LUT4, $$ffs / $(GOWIN_FF_BUDGET) FF"; \
	 if [ "$$luts" -gt "$(GOWIN_LUT_BUDGET)" ] || [ "$$ffs" -gt "$(GOWIN_FF_BUDGET)" ]; then \
	   echo "FAIL: over budget"; exit 1; \
	 else \
	   echo "PASS: fits"; \
	 fi

# ─── Board-level simulation: the boot program drives the LEDs ──
# The shipped board runs one core cycle per 0.5 s, which is right for
# hardware and unfinishable in simulation, so -DBRAD_FAST_SIM shrinks
# the clock divider.  Only the divider constant changes.
sim_board:
	$(IVERILOG) -g2012 -DBRAD_FAST_SIM -I$(VERILOG_DIR) \
	  -I$(FPGA_DIR)/$(GOWIN_DIR) \
	  -o /tmp/brad_top_sim.out -s tb_top_tangnano9k \
	  $(FPGA_DIR)/$(GOWIN_DIR)/tb_top_tangnano9k.v \
	  $(FPGA_DIR)/$(GOWIN_DIR)/top_tangnano9k.v \
	  $(VERILOG_DIR)/bradisa_defines.v \
	  $(VERILOG_DIR)/brad_regfile.v \
	  $(VERILOG_DIR)/brad_alu.v \
	  $(VERILOG_DIR)/brad_decode.v \
	  $(VERILOG_DIR)/brad_execute.v \
	  $(VERILOG_DIR)/brad_core.v
	$(VVP) /tmp/brad_top_sim.out

# ─── Gate-level simulation: the SYNTHESIZED netlist still counts ──
# The step that catches a synthesis bug instead of an RTL bug.  yosys
# emits a Verilog netlist (shrinking only the divider constant via
# chparam, so the logic is the shipping logic), and the netlist is then
# simulated against yosys's own behavioural models of the Gowin cells.
GOWIN_CELLS ?= $(firstword $(wildcard /usr/share/yosys/gowin/cells_sim.v))

sim_gate:
	cd $(FPGA_DIR)/$(GOWIN_DIR) && $(YOSYS) -s synth_gate.ys
	@test -n "$(GOWIN_CELLS)" || { \
	  echo "cannot find yosys's Gowin cell models (cells_sim.v)"; exit 1; }
	$(IVERILOG) -g2012 -s tb_gl_tangnano9k \
	  -I$(FPGA_DIR)/$(GOWIN_DIR) \
	  -o /tmp/brad_gate_sim.out \
	  $(FPGA_DIR)/$(GOWIN_DIR)/tb_gl_tangnano9k.v \
	  $(FPGA_DIR)/$(GOWIN_DIR)/tangnano9k_gate.v \
	  $(GOWIN_CELLS)
	$(VVP) /tmp/brad_gate_sim.out

# ─── Verilator lint ────────────────────────────────────────────
lint_verilog:
	$(VERILATOR) --lint-only -Wall $(VERILOG_SRCS)

# ─── GHDL lint / analyse ──────────────────────────────────────
lint_vhdl:
	cd $(VHDL_DIR) && $(GHDL) -s --std=08 bradisa_pkg.vhd brad_regfile.vhd brad_alu.vhd brad_core.vhd tb_brad_core.vhd

# ─── Clean ─────────────────────────────────────────────────────
clean:
	rm -rf $(FPGA_DIR)/brad_core $(FPGA_DIR)/*.rpt $(FPGA_DIR)/*.bit
	rm -rf $(GOWIN_DIR)/*.json $(GOWIN_DIR)/*.rpt $(GOWIN_DIR)/*_gate.v
	rm -rf /tmp/brad_top_sim.out /tmp/brad_gate_sim.out
	rm -rf $(VHDL_DIR)/*.o $(VHDL_DIR)/*.cf $(VHDL_DIR)/work-obj08.cf
	rm -rf $(VERILOG_DIR)/*.o
