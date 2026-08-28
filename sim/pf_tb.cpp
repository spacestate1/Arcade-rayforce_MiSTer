//============================================================================
//  Bench for rf_video_pf: a whole frame of playfield lines through the real
//  line decoder, builder and SDRAM tile fetch, sampled the way the mixer
//  will sample them, for sim/check_pf.py to diff against sim/gen_pf_ref.py.
//
//    ./obj_dir/pftb <dump_dir> <frame> <out> [mosaic_sample]
//============================================================================
#include "Vpf_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static std::vector<uint8_t> mem;        // SDRAM image
static std::vector<uint16_t> lram, pram; // line RAM, playfield RAM (CPU view)

static std::vector<uint8_t> load(const std::string& p) {
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> v(n);
    if (fread(v.data(), 1, n, f) != (size_t)n) exit(2);
    fclose(f);
    return v;
}
static std::vector<uint16_t> be16(const std::vector<uint8_t>& b) {
    std::vector<uint16_t> v(b.size() / 2);
    for (size_t i = 0; i < v.size(); i++) v[i] = (b[2 * i] << 8) | b[2 * i + 1];
    return v;
}
static uint16_t rd16(uint32_t wa) {
    uint32_t b = wa * 2;
    return (b + 1 < mem.size()) ? (mem[b] | (mem[b + 1] << 8)) : 0;
}
struct Chan {
    int prev = 0, delay = -1, ready = 0; uint32_t addr = 0; uint64_t dout = 0;
    void tick(int req, uint32_t a, int lat) {
        ready = 0;
        if (req && !prev) { delay = lat; addr = a; }
        prev = req;
        if (delay > 0) delay--;
        else if (delay == 0) {
            delay = -1; uint64_t d = 0;
            for (int k = 0; k < 4; k++) d |= (uint64_t)rd16(addr + k) << (16 * k);
            dout = d; ready = 1;
        }
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string dir = argc > 1 ? argv[1] : "../dump";
    int frame = argc > 2 ? atoi(argv[2]) : 1800;
    const char* outp = argc > 3 ? argv[3] : "pf_out.txt";
    int mosaic = argc > 4 ? atoi(argv[4]) : 0;

    char pre[64]; snprintf(pre, sizeof pre, "/f3_%05d_", frame);
    mem.assign(0x1280000, 0);
    struct { const char* n; uint32_t off; } regs[] = {
        {"rgn_tilemap.bin", 0x880000}, {"rgn_tilemap_hi.bin", 0xC80000}};
    for (auto& r : regs) { auto v = load(dir + "/" + r.n); memcpy(&mem[r.off], v.data(), v.size()); }
    lram = be16(load(dir + pre + "line_ram.bin"));
    pram = be16(load(dir + pre + "pf_ram.bin"));

    uint16_t ctrl[16] = {0};
    { FILE* f = fopen((dir + pre + "ctrl.txt").c_str(), "r");
      int i; unsigned v; while (f && fscanf(f, "%d %x", &i, &v) == 2) ctrl[i] = v; if (f) fclose(f); }

    Vpf_top* t = new Vpf_top;
    Chan lo, hi;
    uint32_t ra_l = 0, ra_p = 0;
    long long cyc = 0;

    auto step = [&]() {                   // one cpu edge + ram edges between
        for (int r = 0; r < 2; r++) {
            if ((cyc * 2 + r) % 11 == 0) continue;   // incommensurate ram clock
            lo.tick(t->ch_lo_req, t->ch_lo_addr, 14);
            hi.tick(t->ch_hi_req, t->ch_hi_addr, 9);
            t->ch_lo_dout = lo.dout; t->ch_lo_ready = lo.ready;
            t->ch_hi_dout = hi.dout; t->ch_hi_ready = hi.ready;
            t->clk_ram = 1; t->eval(); t->clk_ram = 0; t->eval();
        }
        // registered-address BRAM: q is mem[address presented last cycle]
        t->lr_q = ra_l < lram.size() ? lram[ra_l] : 0;
        t->pf_q = ra_p < pram.size() ? pram[ra_p] : 0;
        uint32_t nl = t->lr_addr, np = t->pf_addr;
        t->clk = 1; t->eval();
        ra_l = nl; ra_p = np;
        t->clk = 0; t->eval();
        cyc++;
    };

    t->reset = 1; t->frame_start = 0; t->line_start = 0; t->rd_start = 0; t->rd_step = 0;
    t->flip = 1; t->extend = 1;
    t->force_mosaic = mosaic != 0; t->force_sample = mosaic;
    // ctrl0 is a packed [7:0][15:0] port: 128 bits, four 32-bit words, two
    // registers per word -- NOT an array of eight
    for (int w = 0; w < 4; w++) t->ctrl0[w] = ctrl[2 * w] | ((uint32_t)ctrl[2 * w + 1] << 16);
    for (int i = 0; i < 8; i++) step();
    t->reset = 0; step();
    t->frame_start = 1; step(); t->frame_start = 0; step();

    FILE* out = fopen(outp, "w");
    fprintf(out, "# frame %d mosaic %d\n", frame, mosaic);
    long long worst = 0, total = 0;
    for (int sy = 0; sy < 256; sy++) {
        t->screen_y = sy; t->lr_y = 255 - sy;
        t->line_start = 1; step(); t->line_start = 0;
        long long c = 0;
        while (t->busy && c < 100000) { step(); c++; }
        if (c > worst) worst = c;
        total += c;

        // read the line back the way the mixer will
        std::vector<uint32_t> v[4];
        t->rd_start = 1; step(); t->rd_start = 0; step();
        int used = t->rd_used;
        for (int x = 0; x < 320; x++) {
            step();                                   // BRAM latency
            for (int p = 0; p < 4; p++) {
                uint32_t q = (uint32_t)((t->rd_q >> (16 * p)) & 0xFFFF);   // packed [3:0][15:0]
                uint32_t pal = (q >> 6) & 0x1FF, pen = q & 0x3F, bsel = (q >> 15) & 1;
                uint32_t color = ((pal << 4) | pen) & 0x1FFF;
                v[p].push_back(color | ((pen != 0) << 13) | (bsel << 14));
            }
            t->rd_step = 1; step(); t->rd_step = 0;
        }
        for (int p = 0; p < 4; p++) {
            fprintf(out, "%d %d %d", sy, p, (used >> p) & 1);
            for (auto s : v[p]) fprintf(out, " %u", s);
            fprintf(out, "\n");
        }
    }
    fclose(out);
    printf("built 256 lines, mean %lld / worst %lld clocks per line (decode+build)\n",
           total / 256, worst);
    return 0;
}
