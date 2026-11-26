/* sloputron-1 instruction-set simulator: see iss.h. Every case follows rtl/core/f1_core.sv. */
#include "iss.h"

#include <stdio.h>
#include <string.h>

#define PC_MASK ((1u << PC_BITS) - 1u)
#define DA_MASK ((1u << DATA_BITS) - 1u)

void slp_init(slp *s, slp_map map)
{
    unsigned t;
    memset(s, 0, sizeof *s);
    s->map = map;
    for (t = 0; t < THREADS; t++)
        s->r[t][REGISTERS - 1] = (uint16_t)t;
}

int slp_read_hex(const char *path, uint16_t *mem, unsigned words)
{
    FILE *f = fopen(path, "r");
    unsigned v, n = 0;
    if (!f)
        return -1;
    while (n < words && fscanf(f, "%x", &v) == 1)
        mem[n++] = (uint16_t)v;
    fclose(f);
    return (int)n;
}

static unsigned load(slp *s, unsigned a)
{
    if (s->map == SLP_MAP_FLAT)
        return s->ram[a];
    if (a & 0x800u)
        return s->io_load ? s->io_load(s->io_ctx, a) & 0xFFFFu : 0;
    return s->ram[a & (SLP_BOARD_RAM - 1u)];
}

static void store(slp *s, unsigned a, unsigned v)
{
    if (s->map == SLP_MAP_FLAT)
        s->ram[a] = (uint16_t)v;
    else if (a & 0x800u) {
        if (s->io_store)
            s->io_store(s->io_ctx, a, v);
    } else
        s->ram[a & (SLP_BOARD_RAM - 1u)] = (uint16_t)v;
}

static int cond(unsigned cc, unsigned v, unsigned c)
{
    switch (cc) {
    case CC_AL:   return 1;
    case CC_Z:    return v == 0;
    case CC_NZ:   return v != 0;
    case CC_NEG:  return (v >> 15) & 1u;
    case CC_NNEG: return !((v >> 15) & 1u);
    case CC_CC:   return !c;
    case CC_CS:   return c != 0;
    default:      return v & 1u;               /* CC_ODD */
    }
}

void slp_step_thread(slp *s, unsigned t, slp_retire *o)
{
    uint16_t *R = s->r[t];
    unsigned pc = s->pc[t], w = s->rom[pc], c = s->c[t];
    unsigned d = (w >> 8) & 15u, rs = (w >> 4) & 15u;
    unsigned x = R[d], xs = R[rs];
    unsigned next = (pc + 1u) & PC_MASK;

    memset(o, 0, sizeof *o);
    o->thread = t;
    o->pc = pc;
    o->insn = w;

    if ((w & FMT_ALU_IMM_MASK) == FMT_ALU_IMM_MATCH || (w & FMT_ALU_REG_MASK) == FMT_ALU_REG_MATCH) {
        int reg = (w & FMT_ALU_REG_MASK) == FMT_ALU_REG_MATCH;
        unsigned op = reg ? w & 7u : (w >> 12) & 7u;
        unsigned y = reg ? xs : (w & 0x80u ? (w & 0xFFu) | 0xFF00u : w & 0xFFu);
        unsigned ci = (reg && (w & 0x10u)) ? c : 0u;          /* rcl / rcr: rs bit 0 */
        unsigned out = 0;
        switch (op) {
        case ALU_ADD: out = x + y;  c = out > 0xFFFFu; break;
        case ALU_SUB: out = x - y;  c = x >= y;        break;
        case ALU_AND: out = x & y;  break;
        case ALU_OR:  out = x | y;  break;
        case ALU_XOR: out = x ^ y;  break;
        case ALU_PASS: out = y;     break;
        case ALU_SHL: out = (x << 1) | ci;         c = (x >> 15) & 1u; break;
        default:      out = (x >> 1) | (ci << 15); c = x & 1u;         break;  /* ALU_SHR */
        }
        out &= 0xFFFFu;
        if (!reg || !(w & 8u)) {                               /* w = 1: no write (cmp) */
            o->rd_we = 1;
            o->rd_wdata = out;
        }
    } else if ((w & FMT_LOAD_MASK) == FMT_LOAD_MATCH) {
        o->mem_re = 1;
        o->mem_addr = (xs + (w & 15u)) & DA_MASK;
        o->mem_rdata = load(s, o->mem_addr);
        o->rd_we = 1;
        o->rd_wdata = o->mem_rdata;
    } else if ((w & FMT_STORE_MASK) == FMT_STORE_MATCH) {
        o->mem_we = 1;
        o->mem_addr = (xs + (w & 15u)) & DA_MASK;
        o->mem_wdata = x;
        store(s, o->mem_addr, x);
    } else if ((w & FMT_LDHI_MASK) == FMT_LDHI_MATCH) {
        o->rd_we = 1;
        o->rd_wdata = ((w & 0xFFu) << 8) | (x & 0xFFu);
    } else if ((w & FMT_SKIP_MASK) == FMT_SKIP_MATCH) {
        if (cond(w & 7u, x, c))
            next = (pc + 2u) & PC_MASK;
    } else if ((w & FMT_JAL_MASK) == FMT_JAL_MATCH) {
        o->rd_we = 1;
        o->rd_wdata = next;                                    /* PC + 1, zero-extended */
        next = xs & PC_MASK;
    } else {                                                   /* jump: bits 12..11 */
        unsigned b = (w >> 11) & 3u;                           /* 0 jmp, 1 bcs, 2 bcc, 3 jumps */
        if (b == 0 || b == 3 || (b == 1) == (c != 0))
            next = w & PC_MASK;
    }

    if (o->rd_we) {
        o->rd = d;
        R[d] = (uint16_t)o->rd_wdata;
    }
    s->c[t] = (uint8_t)c;
    s->pc[t] = (uint16_t)next;
    o->c = c;
    o->pc_next = next;
    s->clock++;
    s->count[t]++;
    s->next = (t + 1u) % THREADS;
}

void slp_step(slp *s, slp_retire *o)
{
    slp_step_thread(s, s->next, o);
}

void slp_format(const slp_retire *r, char *buf, unsigned size)
{
    int n = snprintf(buf, size, "t%u pc %03x insn %04x -> pc %03x C %u", r->thread, r->pc,
                     r->insn, r->pc_next, r->c);
    if (r->rd_we && n > 0 && (unsigned)n < size)
        n += snprintf(buf + n, size - (unsigned)n, "  r%u = %04x", r->rd, r->rd_wdata);
    if (r->mem_re && n > 0 && (unsigned)n < size)
        n += snprintf(buf + n, size - (unsigned)n, "  ld [%03x] = %04x", r->mem_addr, r->mem_rdata);
    if (r->mem_we && n > 0 && (unsigned)n < size)
        snprintf(buf + n, size - (unsigned)n, "  st [%03x] = %04x", r->mem_addr, r->mem_wdata);
}
