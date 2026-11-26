/* sloputron-1 instruction-set simulator (C99). ISA from isa/isa.toml, via isa_gen.h.
 *
 * It models the 4-thread barrel exactly: each clock one thread finishes one instruction,
 * the threads in turn. A skipped instruction is never fetched, so it takes no clock. The
 * simulator therefore counts clocks: thread t's k-th instruction finishes on clock
 * 4k + (t - first thread) mod 4.
 *
 * It decodes every 16-bit word as f1_core does, including the encodings the spec calls
 * reserved, so it can follow random programs in lockstep with the RTL (sim/lockstep_tb.sv).
 *
 * Two data maps:
 *   SLP_MAP_BOARD  the board (rtl/board/sloputron.sv): RAM at addresses with bit 11 clear,
 *                  1024 words (bits 9..0); I/O at bit 11 set, through the io_load/io_store
 *                  hooks (registers decoded from bits 1..0)
 *   SLP_MAP_FLAT   the benchmark harness (bench/rtl/bench_top.sv): 4096 words of RAM, no I/O
 */
#ifndef SLP_ISS_H
#define SLP_ISS_H

#include <stdint.h>
#include "isa_gen.h"

#define SLP_ROM_WORDS (1u << PC_BITS)
#define SLP_DATA_WORDS (1u << DATA_BITS)
#define SLP_BOARD_RAM 1024u

typedef enum { SLP_MAP_BOARD, SLP_MAP_FLAT } slp_map;

/* What one instruction did: the fields of the RTL's retirement port (f1_core rvfi_*). */
typedef struct {
    unsigned thread, pc, insn, pc_next, c;      /* c: the carry flag after the instruction */
    int rd_we;
    unsigned rd, rd_wdata;
    int mem_re, mem_we;
    unsigned mem_addr, mem_rdata, mem_wdata;
} slp_retire;

typedef unsigned (*slp_io_load_fn)(void *ctx, unsigned addr);
typedef void (*slp_io_store_fn)(void *ctx, unsigned addr, unsigned value);

typedef struct {
    uint16_t rom[SLP_ROM_WORDS];
    uint16_t ram[SLP_DATA_WORDS];
    slp_map map;
    uint16_t r[THREADS][REGISTERS];
    uint16_t pc[THREADS];
    uint8_t c[THREADS];
    uint64_t clock;                  /* instructions finished = clocks since the first one */
    uint64_t count[THREADS];         /* instructions per thread */
    unsigned next;                   /* the thread whose turn it is */
    slp_io_load_fn io_load;          /* board map: loads with address bit 11 set */
    slp_io_store_fn io_store;        /* board map: stores with address bit 11 set */
    void *io_ctx;
} slp;

/* Configuration state: every thread at PC 0 with C = 0, registers 0 except r15 = thread
   number, RAM 0, ROM 0. */
void slp_init(slp *s, slp_map map);

/* Read a $readmemh image (one hex word per line) into mem[0..words-1]. Returns the number
   of words read, or -1 if the file cannot be opened. */
int slp_read_hex(const char *path, uint16_t *mem, unsigned words);

/* Thread t finishes its next instruction. The turn moves to t + 1. */
void slp_step_thread(slp *s, unsigned t, slp_retire *out);

/* The thread whose turn it is finishes its next instruction. */
void slp_step(slp *s, slp_retire *out);

/* One line: "t2 pc 01a insn 9213 ..."; buf needs 128 bytes. */
void slp_format(const slp_retire *r, char *buf, unsigned size);

#endif
