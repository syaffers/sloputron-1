#!/usr/bin/env bash
# Synthesize and place & route every baseline with the pinned toolchain.
# usage: ./build.sh [name ...]      (default: all)
# env:   SEEDS=16 FREQ=100 JOBS=<parallel seeds> CSV=<out> EXT=<repo>/ext TOOLS=<repo>/tools/oss-cad-suite
# setup: scripts/fetch_toolchain.sh && scripts/fetch_baselines.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
EXT=${EXT:-$HERE/../ext}
TOOLS=${TOOLS:-$HERE/../tools/oss-cad-suite}
[ -d "$TOOLS/bin" ] && export PATH=$TOOLS/bin:$PATH
SEEDS=${SEEDS:-16}; FREQ=${FREQ:-100}
B=$HERE/build; C=$HERE/common; CSV=${CSV:-$HERE/baselines.csv}   # override for trial runs
mkdir -p "$B"

synth_v() {   # name top-param-override files...
  local name=$1 chparam=$2; shift 2
  local fe=slang
  ( cd "$C" && yosys -q -m slang -l "$B/$name.yslog" -p "read_slang --allow-use-before-declare $chparam --top top $*; synth_ice40 -top top -json $B/$name.json" ) \
  || { fe=read_verilog; ( cd "$C" && yosys -q -l "$B/$name.yslog" -p "read_verilog -sv $* ; ${chparam:+chparam $chparam top;} synth_ice40 -top top -json $B/$name.json" ); }
  echo "$name frontend=$fe" >> "$B/frontends.txt"
}

pnr() { local pcf=$C/icestick.pcf; [[ " $* " == *" hx8k "* ]] && pcf=none
  python3 "$HERE/../scripts/pnr_sweep.py" "$1" "$B/$1.json" "$pcf" --seeds "$SEEDS" --freq "$FREQ" --csv "$CSV" ${JOBS:+--jobs "$JOBS"} "${@:2}"; }

S=$EXT/serv; F=$EXT/learn-fpga/FemtoRV/RTL/PROCESSOR
SERV_FILES="$HERE/serv/top.v $C/mem32.v $S/servile/*.v $S/rtl/serv_*.v"

build() {
  case $1 in
  j1a)   synth_v j1a "" "$HERE/j1a/top.v $EXT/swapforth/j1a/verilog/j1.v $EXT/swapforth/j1a/verilog/stack2.v"; pnr j1a ;;
  j1a_bram) synth_v j1a_bram "" "$HERE/j1a/top.v $EXT/swapforth/j1a/verilog/j1.v $HERE/j1a_bram/stack2.v $HERE/../rtl/lib/stack_bram.sv"; pnr j1a_bram ;;
  j4a)   synth_v j4a "" "$HERE/j4a/top.v $EXT/swapforth/j1a/verilog/j4.v $EXT/swapforth/j1a/verilog/stack2pipe4.v $EXT/swapforth/j1a/verilog/greycount.v"; pnr j4a || pnr j4a --device hx8k --package ct256 ;;
  serv)  synth_v serv "" "$SERV_FILES"; pnr serv ;;
  qerv)  ( cd "$C" && yosys -q -m slang -l "$B/qerv.yslog" -p "read_slang --allow-use-before-declare -G WIDTH=4 --top top $SERV_FILES; synth_ice40 -top top -json $B/qerv.json" ); echo "qerv frontend=slang" >> "$B/frontends.txt"; pnr qerv ;;
  femtorv_quark) synth_v femtorv_quark "" "$HERE/femtorv_quark/top.v $C/mem32.v $F/femtorv32_quark.v"; pnr femtorv_quark ;;
  minimax) synth_v minimax "" "$HERE/minimax/top.v $EXT/minimax/rtl/minimax.v"; pnr minimax ;;
  picorv32) synth_v picorv32 "" "$HERE/picorv32/top.v $C/mem32.v $EXT/picorv32/picorv32.v"; pnr picorv32 || pnr picorv32 --device hx8k --package ct256 ;;
  picorv32e) ( cd "$C" && yosys -q -m slang -l "$B/picorv32e.yslog" -p "read_slang --allow-use-before-declare -G REGS_16_31=0 --top top $HERE/picorv32/top.v $C/mem32.v $EXT/picorv32/picorv32.v; synth_ice40 -top top -json $B/picorv32e.json" ); pnr picorv32e || pnr picorv32e --device hx8k --package ct256 ;;
  fazyrv4|fazyrv8) local cs=${1#fazyrv}; local Z=$EXT/FazyRV/rtl
    ( cd "$C" && yosys -q -m slang -l "$B/$1.yslog" -p "read_slang --allow-use-before-declare -G CHUNKSIZE=$cs --top top $HERE/fazyrv/top.sv $C/mem32.v $Z/*.sv $Z/*.v; synth_ice40 -top top -json $B/$1.json" ); echo "$1 frontend=slang" >> "$B/frontends.txt"; pnr $1 ;;
  leros) ( cd "$HERE/leros" && L=$EXT/leros/vhdl/core && yosys -q -m ghdl -l "$B/leros.yslog" -p "ghdl --std=08 -fsynopsys leros_types.vhd leros_rom.vhd $L/leros_im.vhd $L/leros_decode.vhd leros_fedec.vhd leros_ex.vhd $L/leros.vhd top.vhd -e top; synth_ice40 -top top -json $B/leros.json" ); echo "leros frontend=ghdl" >> "$B/frontends.txt"; pnr leros ;;
  *) echo "unknown $1"; exit 1 ;;
  esac
}

for n in "${@:-j1a j1a_bram j4a serv qerv fazyrv4 fazyrv8 femtorv_quark minimax picorv32 picorv32e leros}"; do for m in $n; do build "$m"; done; done
