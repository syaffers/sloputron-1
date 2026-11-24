# sloputron-1 build flow. Run `make help` for the targets.
SHELL := bash
.SHELLFLAGS := -eo pipefail -c
.DELETE_ON_ERROR:
.SECONDEXPANSION:
.SECONDARY:

ROOT  := $(abspath .)
TOOLS ?= $(ROOT)/tools/oss-cad-suite
ifneq ($(wildcard $(TOOLS)/bin),)
export PATH := $(TOOLS)/bin:$(PATH)
endif

B      := build
PCF    := board/icestick.pcf
# SEEDS: nextpnr seeds for sweeps (project rule: >= 16)
# SEED:  seed for the bitstream you flash
# FREQ:  nextpnr timing target in MHz (same for every design and baseline)
# BUDGET: 95% of 1280 logic cells
# D:     design for `make bit` / `make prog`
SEEDS  ?= 16
SEED   ?= 1
FREQ   ?= 100
BUDGET ?= 1216
# UART device: Linux ttyUSB1 (FT2232H channel B); macOS picks the last /dev/cu.usbserial-*
ifeq ($(shell uname -s),Darwin)
PORT   ?= $(lastword $(sort $(wildcard /dev/cu.usbserial-*)))
else
PORT   ?= /dev/ttyUSB1
endif
D      ?= blinky
NOTE   ?=

# ---- design registry: top module = design name ---------------------------------
DESIGNS := blinky uart_echo

blinky_SRC    := rtl/board/blinky.sv
uart_echo_SRC := rtl/board/uart_echo.sv rtl/lib/uart_rx.sv rtl/lib/uart_tx.sv
uart_echo_TB  := sim/uart_echo_tb.sv

# ---- units: shared RTL with its own testbench, linted and simulated but not built ------
UNITS := stack_bram skel_f1 skel_f2 skel_f3 skel_f4 skel_f5 r_f1 r_f5

stack_bram_SRC := rtl/lib/stack_bram.sv
stack_bram_TB  := sim/stack_bram_tb.sv

# Phase 2 datapath skeletons (skel/): the testbench runs a CRC program assembled by skel/asm.py
SKEL_SRC := skel/rtl/skel_top.sv skel/rtl/skel_alu.sv skel/rtl/skel_f1.sv skel/rtl/skel_f2.sv \
            skel/rtl/skel_f3.sv skel/rtl/skel_f4.sv skel/rtl/skel_f5.sv rtl/lib/stack_bram.sv
$(foreach f,1 2 3 4 5,$(eval skel_f$(f)_SRC := $(SKEL_SRC)) $(eval skel_f$(f)_TB := skel/sim/skel_tb.sv))
$(foreach f,1 2 3 4 5,sim-skel_f$(f)): $(B)/skel/data.hex
$(B)/skel/data.hex: skel/asm.py
	python3 skel/asm.py $(@D) > /dev/null

# Phase 3 benchmarks on F1 and F5 (bench/, D-005): the four D-002 kernels, checked against
# bench/kernels.py's reference interpreter
BENCH_SRC := bench/rtl/bench_top.sv bench/rtl/r_alu.sv bench/rtl/r_f1.sv bench/rtl/r_f5.sv
$(foreach u,r_f1 r_f5,$(eval $(u)_SRC := $(BENCH_SRC)) $(eval $(u)_TB := bench/sim/bench_tb.sv))
sim-r_f1 sim-r_f5: $(B)/bench/crc16.hex
$(B)/bench/crc16.hex: bench/kernels.py
	python3 bench/kernels.py $(@D) > /dev/null

# GNU make 3.81 (macOS default) ignores .SHELLFLAGS, so recipes with pipes set pipefail
# themselves; `timeout` is optional (coreutils `gtimeout` on macOS).
TIMEOUT := $(shell command -v timeout || command -v gtimeout)
RUN_TIMEOUT = $(if $(TIMEOUT),$(TIMEOUT) $(1))

# ---- tool flags -------------------------------------------------------------------
PNR_FLAGS := --hx1k --package tq144 --pcf $(PCF) --freq $(FREQ) --timing-allow-fail
VWARN     := -Wall -Wno-DECLFILENAME -Wno-PROCASSINIT
VSIMFLAGS := $(VWARN) -Wno-UNUSEDSIGNAL -Wno-ZERODLY --binary --timing -j 0

.PHONY: help all bits bit prog sweep report check sim lint uart-test toolchain versions clean
help:
	@echo "make bits                  bitstreams for all designs -> build/<design>.bin (seed $(SEED))"
	@echo "make bit  D=uart_echo      one bitstream"
	@echo "make prog D=uart_echo      flash it with iceprog (board on this machine)"
	@echo "make uart-test PORT=...    loopback test against uart_echo on the board"
	@echo "make sim                   self-checking Verilator testbenches"
	@echo "make lint                  Verilator lint of every design"
	@echo "make sweep                 $(SEEDS)-seed nextpnr sweep of every design"
	@echo "make report NOTE='...'     sweep + append rows to results.csv (do this before committing hardware changes)"
	@echo "make check  [BASE=rev]     CI gate: budget, stale results.csv, silent regressions"
	@echo "make toolchain / versions  fetch the pinned OSS CAD Suite / print tool versions"
	@echo "(UART port: $(PORT))"

all: bits

# ---- synthesis ------------------------------------------------------------------
$(B)/%/synth.json: $$($$*_SRC)
	@mkdir -p $(@D)
	yosys -q -m slang -l $(@D)/yosys.log \
	  -p "read_slang $($*_SRC) --top $*; synth_ice40 -top $* -json $@"

# ---- place & route + bitstream (single seed) ---------------------------------------
$(B)/%/top.asc: $(B)/%/synth.json $(PCF)
	nextpnr-ice40 $(PNR_FLAGS) --seed $(SEED) --json $< --asc $@ \
	  --report $(@D)/pnr.json -l $(@D)/nextpnr.log -q
	@python3 -c "import json;r=json.load(open('$(@D)/pnr.json'));u=r['utilization'];\
	f=[v['achieved'] for k,v in r['fmax'].items()];\
	print('$*: %d/%d LC, %d BRAM, Fmax %.1f MHz (seed $(SEED))'%(u['ICESTORM_LC']['used'],u['ICESTORM_LC']['available'],u['ICESTORM_RAM']['used'],min(f) if f else 0))"

$(B)/%.bin: $(B)/%/top.asc
	icepack $< $@

bits: $(DESIGNS:%=$(B)/%.bin)
bit:  $(B)/$(strip $(D)).bin
prog: $(B)/$(strip $(D)).bin
	iceprog $<

# ---- multi-seed sweep, results.csv ---------------------------------------------
$(B)/%/sweep.json: $(B)/%/synth.json $(PCF)
	python3 scripts/pnr_sweep.py $* $< $(PCF) --seeds $(SEEDS) --freq $(FREQ) \
	  --out $@ --outdir $(@D)/seeds > /dev/null

sweep: $(DESIGNS:%=$(B)/%/sweep.json)
	@cat $^ | python3 -c "import sys,json;[print('%-12s %5d LC %3d BRAM  Fmax median %6.2f  worst %6.2f MHz'%(r['name'],r['lc'],r['ram'],r['fmax_median'],r['fmax_worst'])) for r in map(json.loads,sys.stdin.read().replace('}{','}\n{').splitlines())]"

report: $(DESIGNS:%=$(B)/%/sweep.json)
	python3 scripts/report.py --csv results.csv --note "$(NOTE)" $^

check: $(DESIGNS:%=$(B)/%/sweep.json)
	python3 scripts/check_results.py --csv results.csv --budget $(BUDGET) $(if $(BASE),--base $(BASE)) $^

# ---- simulation and lint --------------------------------------------------------
SIM_DESIGNS := $(foreach d,$(DESIGNS),$(if $($(d)_TB),$(d)))
sim: $(SIM_DESIGNS:%=sim-%) $(UNITS:%=sim-%)
sim-%:
	@mkdir -p $(B)/sim/$*
	verilator $(VSIMFLAGS) --top-module $*_tb -Mdir $(B)/sim/$* $($*_TB) $($*_SRC) > $(B)/sim-$*.log 2>&1 \
	  || { cat $(B)/sim-$*.log; exit 1; }
	set -o pipefail; $(call RUN_TIMEOUT,300) $(B)/sim/$*/V$*_tb | grep -v '^- '

lint: $(DESIGNS:%=lint-%) $(UNITS:%=lint-%)
lint-%:
	verilator --lint-only $(VWARN) --top-module $* $($*_SRC)

# ---- board ------------------------------------------------------------------------
uart-test:
	@test -n "$(PORT)" || { echo "no UART found; pass PORT=/dev/..."; exit 1; }
	python3 scripts/uart_test.py --port $(PORT)

# ---- toolchain ------------------------------------------------------------------
toolchain:
	scripts/fetch_toolchain.sh

versions:
	@yosys -V; nextpnr-ice40 --version 2>&1 | head -1; verilator --version; \
	 cat $(TOOLS)/VERSION 2>/dev/null || true

clean:
	rm -rf $(B)
