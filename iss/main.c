/* slp-iss: run a sloputron-1 program in the C instruction-set simulator.
 *
 * usage: slp-iss [options] ROM.hex
 *   --clocks N        stop after N clocks (default 1000000)
 *   --rx TEXT         bytes the UART receives, one at a time as the program reads them
 *   --flat DATA.hex   benchmark map (bench/rtl/bench_top.sv): 4096 words of RAM loaded
 *                     from DATA.hex, no I/O; stops when every thread has stored to 0xFFF
 *   --threads N       with --flat: how many threads must store to 0xFFF (default 4)
 *   --expect EXP.hex  with --flat: compare RAM (except 0xFFF) with EXP.hex at the end
 *   --trace           print every instruction to stderr
 * Board map (default): prints what the program sends on the UART to stdout. The UART is
 * instantaneous: the transmitter is never busy, and a byte waits in UART_RX until read.
 * At the end it prints the clock count and the instructions per thread to stderr.
 * Exit status: 0, or 1 on a --flat run that did not finish or whose RAM differs. */
#include "iss.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *rx;
    unsigned led;
} board_io;

static unsigned io_load(void *ctx, unsigned a)
{
    board_io *io = ctx;
    switch (a & 3u) {
    case IO_UART_STATUS & 3u: return (io->rx && *io->rx) ? 2u : 0u;   /* tx never busy */
    case IO_UART_RX & 3u:     return (io->rx && *io->rx) ? (unsigned char)*io->rx++ : 0u;
    default:                  return 0u;
    }
}

static void io_store(void *ctx, unsigned a, unsigned v)
{
    board_io *io = ctx;
    if ((a & 3u) == (IO_UART_TX & 3u))
        putchar((int)(v & 0xFFu));
    else if ((a & 3u) == (IO_LED & 3u))
        io->led = v & 0x1Fu;
}

static int usage(void)
{
    fprintf(stderr, "usage: slp-iss [--clocks N] [--rx TEXT] [--flat DATA.hex [--threads N] "
                    "[--expect EXP.hex]] [--trace] ROM.hex\n");
    return 2;
}

int main(int argc, char **argv)
{
    static slp s;
    static uint16_t expect[SLP_DATA_WORDS];
    board_io io = {0, 0};
    const char *rom = 0, *flat = 0, *exp = 0;
    unsigned long long clocks = 1000000ull;
    unsigned threads = THREADS, done = 0, t, wrong = 0;
    int trace = 0, i, status = 0;
    char line[160];
    slp_retire r;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--clocks") && i + 1 < argc) clocks = strtoull(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "--rx") && i + 1 < argc) io.rx = argv[++i];
        else if (!strcmp(argv[i], "--flat") && i + 1 < argc) flat = argv[++i];
        else if (!strcmp(argv[i], "--threads") && i + 1 < argc) threads = (unsigned)atoi(argv[++i]);
        else if (!strcmp(argv[i], "--expect") && i + 1 < argc) exp = argv[++i];
        else if (!strcmp(argv[i], "--trace")) trace = 1;
        else if (argv[i][0] == '-' || rom) return usage();
        else rom = argv[i];
    }
    if (!rom || threads < 1 || threads > THREADS)
        return usage();

    slp_init(&s, flat ? SLP_MAP_FLAT : SLP_MAP_BOARD);
    s.io_load = io_load;
    s.io_store = io_store;
    s.io_ctx = &io;
    if (slp_read_hex(rom, s.rom, SLP_ROM_WORDS) < 0 ||
        (flat && slp_read_hex(flat, s.ram, SLP_DATA_WORDS) < 0) ||
        (exp && slp_read_hex(exp, expect, SLP_DATA_WORDS) < 0)) {
        perror("slp-iss");
        return 2;
    }

    while (s.clock < clocks) {
        slp_step(&s, &r);
        if (trace) {
            slp_format(&r, line, sizeof line);
            fprintf(stderr, "%8llu %s\n", (unsigned long long)s.clock - 1, line);
        }
        /* Benchmark harness: a thread is done at its first store to 0xFFF; it may go on */
        if (flat && r.mem_we && r.mem_addr == SLP_DATA_WORDS - 1u && r.thread < threads &&
            !(done & (1u << r.thread))) {
            done |= 1u << r.thread;
            if (done == (1u << threads) - 1u)
                break;
        }
    }
    fflush(stdout);

    fprintf(stderr, "slp-iss: %llu clocks; instructions per thread:",
            (unsigned long long)s.clock);
    for (t = 0; t < THREADS; t++)
        fprintf(stderr, " %llu", (unsigned long long)s.count[t]);
    fprintf(stderr, "\n");
    if (flat) {
        if (done != (1u << threads) - 1u) {
            fprintf(stderr, "slp-iss: not every thread stored to 0x%03x\n", SLP_DATA_WORDS - 1u);
            status = 1;
        }
        if (exp)
            for (t = 0; t < SLP_DATA_WORDS - 1u; t++)
                if (s.ram[t] != expect[t]) {
                    if (wrong++ < 5)
                        fprintf(stderr, "slp-iss: D[%03x] = %04x, expected %04x\n", t, s.ram[t], expect[t]);
                }
        if (wrong) {
            fprintf(stderr, "slp-iss: %u words wrong\n", wrong);
            status = 1;
        }
    }
    return status;
}
