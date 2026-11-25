/* DPI-C glue for lockstep checking (sim/lockstep_tb.sv): one ISS per CPU under test.
 *
 * The testbench calls iss_retire() for every instruction the RTL finishes (f1_core's
 * rvfi_* port). The ISS executes the same thread's next instruction and compares every
 * field. The RTL decides two things the ISS cannot know:
 *   - the thread order: the first instruction after the start-up hold sets the ISS's turn,
 *     and from then on every retirement must be the next thread in rotation;
 *   - what an I/O load returns (UART status and data depend on bit timing): the ISS takes
 *     the RTL's value. RAM loads are not taken from the RTL; they are checked.
 */
#include "iss.h"

#include <stdio.h>
#include <stdlib.h>

/* Verilator compiles this file as C++: keep it valid C and C++, with C linkage for DPI. */
#ifdef __cplusplus
extern "C" {
#endif
int iss_open(const char *rom);
int iss_retire(int h, int thread, int pc, int insn, int pc_next, int c, int rd_we, int rd,
               int rd_wdata, int mem_re, int mem_we, int mem_addr, int mem_rdata, int mem_wdata);
int iss_checked(int h);
int iss_errors(int h);
#ifdef __cplusplus
}
#endif

#define MAX_ISS 32
#define MAX_REPORTS 10

typedef struct {
    slp s;
    unsigned io_rdata;
    int started;
    int checked, errors;
} lockstep;

static lockstep *iss[MAX_ISS];
static int n_iss;

static unsigned lk_load(void *ctx, unsigned a)
{
    (void)a;
    return ((const lockstep *)ctx)->io_rdata;
}

static void lk_store(void *ctx, unsigned a, unsigned v)
{
    (void)ctx; (void)a; (void)v;
}

/* Returns a handle, or -1 if the ROM image cannot be read. */
int iss_open(const char *rom)
{
    lockstep *l;
    if (n_iss == MAX_ISS || !(l = (lockstep *)calloc(1, sizeof *l)))
        return -1;
    slp_init(&l->s, SLP_MAP_BOARD);
    if (slp_read_hex(rom, l->s.rom, SLP_ROM_WORDS) < 0) {
        fprintf(stderr, "iss_open: cannot read %s\n", rom);
        free(l);
        return -1;
    }
    l->s.io_load = lk_load;
    l->s.io_store = lk_store;
    l->s.io_ctx = l;
    iss[n_iss] = l;
    return n_iss++;
}

/* One RTL retirement. Returns 0 when the ISS did the same, 1 when not (and prints why). */
int iss_retire(int h, int thread, int pc, int insn, int pc_next, int c, int rd_we, int rd,
               int rd_wdata, int mem_re, int mem_we, int mem_addr, int mem_rdata, int mem_wdata)
{
    lockstep *l = iss[h];
    slp_retire e;
    int bad = 0;
    char want[160];

    if (!l->started) {
        l->s.next = (unsigned)thread;
        l->started = 1;
    }
    if ((unsigned)thread != l->s.next)
        bad = 1;                                   /* out of rotation */
    l->io_rdata = (unsigned)mem_rdata;
    slp_step_thread(&l->s, (unsigned)thread, &e);
    l->checked++;

    bad |= e.pc != (unsigned)pc || e.insn != (unsigned)insn || e.pc_next != (unsigned)pc_next ||
           e.c != (unsigned)c || e.rd_we != rd_we || e.mem_re != mem_re || e.mem_we != mem_we;
    if (e.rd_we && rd_we)
        bad |= e.rd != (unsigned)rd || e.rd_wdata != (unsigned)rd_wdata;
    if (e.mem_re || e.mem_we)
        bad |= e.mem_addr != (unsigned)mem_addr;
    if (e.mem_re && mem_re)
        bad |= e.mem_rdata != (unsigned)mem_rdata;
    if (e.mem_we && mem_we)
        bad |= e.mem_wdata != (unsigned)mem_wdata;

    if (bad && l->errors++ < MAX_REPORTS) {
        slp_format(&e, want, sizeof want);
        fprintf(stderr, "lockstep %d, instruction %d:\n  RTL: t%d pc %03x insn %04x -> pc %03x C %d"
                "  we %d r%d = %04x  re %d we %d [%03x] rd %04x wd %04x\n  ISS: %s\n",
                h, l->checked, thread, pc, insn, pc_next, c, rd_we, rd, rd_wdata, mem_re, mem_we,
                mem_addr, mem_rdata, mem_wdata, want);
    }
    return bad;
}

int iss_checked(int h) { return iss[h]->checked; }
int iss_errors(int h) { return iss[h]->errors; }
