// Headless CPC runner built on floooh/chips (zlib licence) - used to test and
// profile the game without a GUI emulator.
//   cpcrun <464|6128> [file.sna|file.dsk] cmd cmd ...
// cmds: run:N (frames)  shot:file.ppm  joy:MASK  key:CODE  keyup:CODE  type:TEXT
//       idle:LO:HI (hex, pc range of the wait loop)  prof:N  peek:ADDR:LEN  wav:file
#define CHIPS_IMPL
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "chips/chips_common.h"
#include "chips/z80.h"
#include "chips/ay38910.h"
#include "chips/i8255.h"
#include "chips/mc6845.h"
#include "chips/am40010.h"
#include "chips/upd765.h"
#include "chips/clk.h"
#include "chips/kbd.h"
#include "chips/mem.h"
#include "chips/fdd.h"
#include "chips/fdd_cpc.h"
#include "systems/cpc.h"
#include "cpc-roms.h"

static cpc_t sys;
static bool stopped = false;
static unsigned idle_lo = 0xFFFF, idle_hi = 0;
static int in_idle = 1;
static unsigned long busy_ticks = 0, nper = 0, maxb = 0, sumb = 0, prof_on = 0, total_ticks = 0;
static unsigned long hist[64];
static unsigned mark_addr[8]; static unsigned long mark_t[8], mark_sum[8], mark_n[8]; static int nmark=0;
static unsigned long pc_ticks[65536];
static unsigned pc_cur[65536], pc_max[65536];
static unsigned ign_lo = 0xFFFF, ign_hi = 0, cnt_addr[4], ncnt = 0, last_pc = 0; static unsigned long cnt_n[4];
static FILE* wav = 0; static long wav_n = 0; static int wav_on = 0;

static unsigned watch_addr = 0x10000, watch_hits = 0; static uint8_t watch_val; static unsigned trap_pc = 0x10000, trap_n = 0;
static int sodd_done = 1; static unsigned spmin = 0x200, spmin_pc = 0;
static unsigned ring[8192], ring_i = 0, ring_last = 0x10000;
static int crtclog = 0, scan_ln = 0; static unsigned pv = 0, pr = 0, ph = 0; static long ticks_total = 0;
static void dbg(void* ud, uint64_t pins) {
    (void)ud;
    if (crtclog) {
        ticks_total++;
        unsigned h = sys.crtc.h_ctr, v = sys.crtc.v_ctr, r = sys.crtc.r_ctr;
        if (h < ph) scan_ln++;
        if (v == 0 && r == 0 && (pv != 0 || pr != 0)) scan_ln = 0;
        if (v != pv && crtclog > 1) printf("  row %u starts at line %d (r9=%d)\n", v, scan_ln, sys.crtc.reg[9]);
        { static bool pvs=false; if (crtclog && sys.crtc.vs && !pvs) printf("VSYNC start at line %d\n", scan_ln); pvs = sys.crtc.vs; }
        pv = v; pr = r; ph = h;
        { static unsigned lpc = 0; if (sys.cpu.pc == 0x0038 && lpc != 0x38) printf("INT at line %d (h=%u) icnt=%u\n", scan_ln, h, mem_rd(&sys.mem, 0x3F00)); lpc = sys.cpu.pc; }
        if ((pins & (Z80_IORQ | Z80_WR)) == (Z80_IORQ | Z80_WR)) {
            unsigned addr = Z80_GET_ADDR(pins);
            if ((addr & 0x4000) == 0 && (addr & 0x0300) == 0x0100)
                printf("CRTC R%u <- %u  at line %d (h=%u, v=%u r=%u) pc=%04X\n", sys.crtc.sel & 31, Z80_GET_DATA(pins), scan_ln, h, v, r, sys.cpu.pc);
        }
    }
    if (sys.cpu.iff1 && sys.cpu.sp >= 0x100 && sys.cpu.sp <= 0x200 && sys.cpu.sp < spmin) { spmin = sys.cpu.sp; spmin_pc = sys.cpu.pc; }
    if (sys.cpu.pc != ring_last) { ring_last = sys.cpu.pc; ring[ring_i++ & 8191] = ring_last; }
    if (sys.cpu.pc == trap_pc && (!getenv("TRAPW") || (unsigned)(mem_rd(&sys.mem, sys.cpu.sp) | (mem_rd(&sys.mem, sys.cpu.sp + 1) << 8)) == (unsigned)strtol(getenv("TRAPW"), 0, 16)) && trap_n++ < 1) { printf("historique PC :"); for (int k = 0; k < 8192; k++) printf(" %04X", ring[(ring_i + k) & 8191]); printf("\n"); printf("trap %04X : SP=%04X IX=%04X IY=%04X BC=%04X DE=%04X HL=%04X pile :", trap_pc, sys.cpu.sp, sys.cpu.ix, sys.cpu.iy, sys.cpu.bc, sys.cpu.de, sys.cpu.hl); for (int k = 0; k < 12; k++) printf(" %04X", mem_rd(&sys.mem, sys.cpu.sp + 2 * k) | (mem_rd(&sys.mem, sys.cpu.sp + 2 * k + 1) << 8)); printf("\n"); }
    { if (!sodd_done && sys.cpu.iff1 && (sys.cpu.sp & 1)) { sodd_done = 1; printf("SP impair PC=%04X SP=%04X IX=%04X IY=%04X BC=%04X DE=%04X HL=%04X historique :", sys.cpu.pc, sys.cpu.sp, sys.cpu.ix, sys.cpu.iy, sys.cpu.bc, sys.cpu.de, sys.cpu.hl); for (int k = 0; k < 60; k++) printf(" %04X", ring[(ring_i + 8192 - 60 + k) & 8191]); printf("\n"); } }
    if (watch_addr < 0x10000) {
        uint8_t v = mem_rd(&sys.mem, watch_addr);
        if (v != watch_val) { if (watch_hits++ < 100000) { printf("watch %04X : %02X -> %02X, PC suivant = %04X (SP=%04X) IX=%04X BC=%04X DE=%04X HL=%04X pile :", watch_addr, watch_val, v, sys.cpu.pc, sys.cpu.sp, sys.cpu.ix, sys.cpu.bc, sys.cpu.de, sys.cpu.hl); for (int k = 0; k < 8; k++) printf(" %04X", mem_rd(&sys.mem, sys.cpu.sp + 2 * k) | (mem_rd(&sys.mem, sys.cpu.sp + 2 * k + 1) << 8)); printf("\n"); const char* wd = getenv("WATCH_DUMP"); if (wd) { unsigned da = strtol(wd, 0, 16); printf("  mem@%04X :", da); for (int k = 0; k < 192; k++) printf(" %02X", mem_rd(&sys.mem, da + k)); printf("\n"); } } watch_val = v; }
    }
    if (!prof_on) return;
    total_ticks++;
    unsigned pc = sys.cpu.pc;
    pc_ticks[pc]++;
    if (pc != last_pc) { for (unsigned i = 0; i < ncnt; i++) if (pc == cnt_addr[i] + 1) cnt_n[i]++; last_pc = pc; }
    if ((pc >= ign_lo && pc <= ign_hi) || pc < 0x40) return;
    pc_cur[pc]++;      // interrupt handler: neither idle nor busy
    int idle = (pc >= idle_lo && pc <= idle_hi);
    if (idle) {
        if (!in_idle) {
            nper++; sumb += busy_ticks; if (busy_ticks > maxb) { maxb = busy_ticks; memcpy(pc_max, pc_cur, sizeof(pc_max)); }
            memset(pc_cur, 0, sizeof(pc_cur));
            unsigned b = busy_ticks / 4000; if (b > 63) b = 63; hist[b]++;
            busy_ticks = 0;
        }
    } else busy_ticks++;
    in_idle = idle;
}
static void audio_cb(const float* s, int n, void* ud) {
    (void)ud; if (!wav || !wav_on) return;
    for (int i = 0; i < n; i++) { float f = s[i]; if (f > 1) f = 1; if (f < -1) f = -1; short v = (short)(f * 30000); fwrite(&v, 2, 1, wav); wav_n++; }
}
static void shot(const char* fn) {
    FILE* f = fopen(fn, "wb"); if (!f) { perror(fn); return; }
    fprintf(f, "P6\n%d %d\n255\n", AM40010_DISPLAY_WIDTH, AM40010_DISPLAY_HEIGHT * 2);
    for (int y = 0; y < AM40010_DISPLAY_HEIGHT * 2; y++)
        for (int x = 0; x < AM40010_DISPLAY_WIDTH; x++) {
            uint32_t c = sys.ga.hw_colors[sys.fb[(y / 2) * AM40010_FRAMEBUFFER_WIDTH + x]];
            fputc(c & 255, f); fputc((c >> 8) & 255, f); fputc((c >> 16) & 255, f);
        }
    fclose(f);
}
static int bot = 0; static unsigned bot_seed = 12345, bot_t = 0;
static void frames(int n) {
    for (int i = 0; i < n; i++) {
        if (bot && (bot_t++ % 18) == 0) {           // random walk + fire, deterministic
            bot_seed = bot_seed * 1103515245u + 12345u;
            static const uint8_t dirs[] = {1, 2, 4, 8, 5, 9, 6, 10, 0, 1, 8, 4};
            cpc_joystick(&sys, dirs[(bot_seed >> 16) % 12] | (((bot_seed >> 24) & 3) ? 16 : 0) | ((((bot_seed >> 26) & 7) == 0) ? 32 : 0));
        }
        cpc_exec(&sys, 19968);
    }
}
static uint8_t* slurp(const char* fn, size_t* sz) {
    FILE* f = fopen(fn, "rb"); if (!f) { perror(fn); exit(1); }
    fseek(f, 0, SEEK_END); *sz = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t* p = malloc(*sz); fread(p, 1, *sz, f); fclose(f); return p;
}
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    int is464 = !strcmp(argv[1], "464");
    cpc_desc_t d; memset(&d, 0, sizeof(d));
    d.type = is464 ? CPC_TYPE_464 : CPC_TYPE_6128;
    d.joystick_type = CPC_JOYSTICK_DIGITAL;
    d.debug.callback.func = dbg; d.debug.stopped = &stopped;
    d.audio.callback.func = audio_cb; d.audio.sample_rate = 44100;
    d.roms.cpc464.os = (chips_range_t){dump_cpc464_os_bin, 0x4000};
    d.roms.cpc464.basic = (chips_range_t){dump_cpc464_basic_bin, 0x4000};
    d.roms.cpc6128.os = (chips_range_t){dump_cpc6128_os_bin, 0x4000};
    d.roms.cpc6128.basic = (chips_range_t){dump_cpc6128_basic_bin, 0x4000};
    d.roms.cpc6128.amsdos = (chips_range_t){dump_cpc6128_amsdos_bin, 0x4000};
    cpc_init(&sys, &d);
    frames(150);                       // boot to BASIC prompt
    for (int a = 2; a < argc; a++) {
        char* c = argv[a]; char* p = strchr(c, ':'); char* v = p ? p + 1 : "";
        if (!strncmp(c, "run:", 4)) frames(atoi(v));
        else if (!strncmp(c, "shot:", 5)) shot(v);
        else if (!strncmp(c, "vshot:", 6)) { int g = 0; bool prev = sys.crtc.vs; while (g++ < 5000) { cpc_exec(&sys, 32); if (sys.crtc.vs && !prev) break; prev = sys.crtc.vs; } shot(v); }
        else if (!strncmp(c, "vbl:", 4)) { int g = 0; bool prev = sys.crtc.vs; while (g++ < 5000) { cpc_exec(&sys, 32); if (sys.crtc.vs && !prev) break; prev = sys.crtc.vs; } }
        else if (!strncmp(c, "crtclog:", 8)) crtclog = atoi(v);
        else if (!strncmp(c, "bot:", 4)) { bot = atoi(v); if (!bot) cpc_joystick(&sys, 0); }
        else if (!strncmp(c, "seed:", 5)) bot_seed = atoi(v);
        else if (!strncmp(c, "joy:", 4)) cpc_joystick(&sys, (uint8_t)strtol(v, 0, 0));
        else if (!strncmp(c, "key:", 4)) cpc_key_down(&sys, (int)strtol(v, 0, 0));
        else if (!strncmp(c, "keyup:", 6)) cpc_key_up(&sys, (int)strtol(v, 0, 0));
        else if (!strncmp(c, "type:", 5)) {
            for (char* t = v; *t; t++) { int k = (*t == '~') ? 0x0D : *t; cpc_key_down(&sys, k); frames(3); cpc_key_up(&sys, k); frames(3); }
        }
        else if (!strncmp(c, "idle:", 5)) { idle_lo = strtol(v, &p, 16); idle_hi = strtol(p + 1, 0, 16); }
        else if (!strncmp(c, "ign:", 4)) { ign_lo = strtol(v, &p, 16); ign_hi = strtol(p + 1, 0, 16); }
        else if (!strncmp(c, "spmin:", 6)) { if (v[0]=='r') spmin = 0x200; else printf("SP mini = %04X (profondeur %d octets) a PC=%04X\n", spmin, 0x200 - spmin, spmin_pc); }
        else if (!strncmp(c, "spodd:", 6)) { sodd_done = 0; }
        else if (!strncmp(c, "trap:", 5)) { trap_pc = strtol(v, 0, 16); }
        else if (!strncmp(c, "watch:", 6)) { watch_addr = strtol(v, 0, 16); watch_val = mem_rd(&sys.mem, watch_addr); }
        else if (!strncmp(c, "cnt:", 4)) { cnt_addr[ncnt] = strtol(v, 0, 16); cnt_n[ncnt++] = 0; }
        else if (!strncmp(c, "prof:", 5)) {
            for (unsigned i = 0; i < ncnt; i++) cnt_n[i] = 0;
            memset(hist, 0, sizeof(hist)); nper = maxb = sumb = busy_ticks = total_ticks = 0; in_idle = 1; prof_on = 1;
            frames(atoi(v)); prof_on = 0;
            printf("prof %s frames: loops=%lu (%.1f/s)  busy avg=%.2f ms  max=%.2f ms\n  hist(ms):", v, nper,
                   nper / (total_ticks / 4e6), nper ? sumb / 4000.0 / nper : 0, maxb / 4000.0);
            for (int i = 0; i < 64; i++) if (hist[i]) printf(" %d:%lu", i, hist[i]);
            printf("\n");
            for (unsigned i = 0; i < ncnt; i++) printf("  count@%04X = %lu (%.2f per frame)\n", cnt_addr[i], cnt_n[i], cnt_n[i] / (double)atoi(v));
        }
        else if (!strncmp(c, "sym:", 4)) {
            // per-routine time, from a rasm .sym file (global labels only)
            static char nm[2048][48]; static unsigned ad[2048]; int n = 0; char l[256];
            FILE* f = fopen(v, "r");
            while (f && fgets(l, 256, f) && n < 2047) { char b[128]; unsigned a_;
                if (sscanf(l, "%127s #%X", b, &a_) == 2 && !strchr(b, '.')) { strncpy(nm[n], b, 47); ad[n++] = a_; } }
            if (f) fclose(f);
            for (int i = 0; i < n; i++) for (int j = i + 1; j < n; j++) if (ad[j] < ad[i]) { unsigned t = ad[i]; ad[i] = ad[j]; ad[j] = t; char tb[48]; strcpy(tb, nm[i]); strcpy(nm[i], nm[j]); strcpy(nm[j], tb); }
            ad[n] = 0x10000;
            for (int i = 0; i < n; i++) { unsigned long t = 0; for (unsigned a_ = ad[i]; a_ < ad[i + 1]; a_++) t += pc_ticks[a_];
                if (t * 1000 > total_ticks * 3) printf("  %-18s %6.2f ms/frame  %5.1f%%\n", nm[i], t / 4000.0 / (total_ticks / 79872.0), 100.0 * t / total_ticks); }
            memset(pc_ticks, 0, sizeof(pc_ticks));
            printf("  -- worst frame --\n");
            for (int i = 0; i < n; i++) { unsigned long t = 0; for (unsigned a_ = ad[i]; a_ < ad[i + 1]; a_++) t += pc_max[a_];
                if (t > 400) printf("  %-18s %6.2f ms\n", nm[i], t / 4000.0); }
        }
        else if (!strncmp(c, "rec:", 4)) {      // rec:FILE:N  -> N raw RGB frames 768x272 appended to FILE
            char fn[256]; strncpy(fn, v, 255); char* q = strrchr(fn, ':'); int n = atoi(q + 1); *q = 0;
            static FILE* f = 0; if (!f) f = fopen(fn, "wb");
            wav_on = 1;
            for (int i = 0; i < n; i++) { frames(1);
                for (int y = 0; y < AM40010_DISPLAY_HEIGHT; y++) for (int x = 0; x < AM40010_DISPLAY_WIDTH; x++) {
                    uint32_t col = sys.ga.hw_colors[sys.fb[y * AM40010_FRAMEBUFFER_WIDTH + x]];
                    fputc(col & 255, f); fputc((col >> 8) & 255, f); fputc((col >> 16) & 255, f); } }
            fflush(f); wav_on = 0;
        }
        else if (!strncmp(c, "sync", 4)) { for (int i = 0; i < 20000000 && !(sys.cpu.pc >= idle_lo && sys.cpu.pc <= idle_hi); i++) cpc_exec(&sys, 4); }
        else if (!strncmp(c, "dump:", 5)) { FILE* f = fopen(v, "wb"); for (unsigned a_ = 0; a_ < 0x10000; a_++) fputc(mem_rd(&sys.mem, a_), f); fclose(f); }
        else if (!strncmp(c, "poke:", 5)) { unsigned ad = strtol(v, &p, 16); mem_wr(&sys.mem, ad, (uint8_t)strtol(p + 1, 0, 0)); }
        else if (!strncmp(c, "peek:", 5)) {
            unsigned ad = strtol(v, &p, 16), n = strtol(p + 1, 0, 0);
            printf("%04X:", ad); for (unsigned i = 0; i < n; i++) printf(" %02X", mem_rd(&sys.mem, ad + i)); printf("\n");
        }
        else if (!strncmp(c, "wav:", 4)) { wav = fopen(v, "wb"); char h[44] = {0}; fwrite(h, 1, 44, wav); }
        else if (!strncmp(c, "ay", 2)) { printf("AY:"); for (int i = 0; i < 14; i++) printf(" %02X", sys.psg.reg[i]); printf("\n"); }
        else if (!strncmp(c, "pc", 2)) printf("pc=%04X sp=%04X\n", sys.cpu.pc, sys.cpu.sp);
        else {
            size_t sz; uint8_t* data = slurp(c, &sz);
            if (strstr(c, ".dsk")) { if (!cpc_insert_disc(&sys, (chips_range_t){data, sz})) printf("disc insert failed\n"); }
            else if (!cpc_quickload(&sys, (chips_range_t){data, sz}, true)) printf("quickload failed\n");
        }
    }
    if (wav) {
        unsigned ds = wav_n * 2, v; fseek(wav, 0, SEEK_SET);
        fwrite("RIFF", 1, 4, wav); v = ds + 36; fwrite(&v, 4, 1, wav); fwrite("WAVEfmt ", 1, 8, wav);
        v = 16; fwrite(&v, 4, 1, wav); short s = 1; fwrite(&s, 2, 1, wav); fwrite(&s, 2, 1, wav);
        v = 44100; fwrite(&v, 4, 1, wav); v = 88200; fwrite(&v, 4, 1, wav); s = 2; fwrite(&s, 2, 1, wav); s = 16; fwrite(&s, 2, 1, wav);
        fwrite("data", 1, 4, wav); fwrite(&ds, 4, 1, wav); fclose(wav);
    }
    return 0;
}
