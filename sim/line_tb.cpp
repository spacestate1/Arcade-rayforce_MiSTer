//============================================================================
//  Bench for rf_video_line -- the F3 per-scanline effect decoder.
//
//  Walks all 256 screen lines of a dumped frame the way render_frame does
//  (flipscreen, so the line RAM index counts DOWN as the raster goes down)
//  and writes the decoded register set per line. sim/check_line.py diffs that
//  against sim/gen_line_ref.py, which runs the same walk through
//  tools/f3_render.py -- the model that reproduces MAME's frames pixel-exact.
//
//  Line RAM is served here with the same one-cycle read latency as the BRAM
//  port in rf_main, because that latency is exactly what the decoder's wait
//  states exist for.
//============================================================================
#include "Vrf_video_line.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>

static std::vector<uint16_t> lram;

// 20-bit fields inside an 80-bit packed array arrive as three uint32
static uint32_t widefield(const VlWide<3>& w, int words, int idx, int width) {
    unsigned bit = (unsigned)idx * width;
    unsigned wi = bit / 32, sh = bit % 32;
    uint64_t win = (uint64_t)w[wi];
    if ((int)wi + 1 < words) win |= (uint64_t)w[wi + 1] << 32;
    return (uint32_t)((win >> sh) & ((1ull << width) - 1));
}
static uint32_t field64(uint64_t v, int idx, int width) {
    return (uint32_t)((v >> (idx * width)) & ((1ull << width) - 1));
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const char* lrpath = argc > 1 ? argv[1] : "../dump/f3_01800_line_ram.bin";
    int extend = argc > 2 ? atoi(argv[2]) : 1;
    const char* outp = argc > 3 ? argv[3] : "line_out.txt";

    FILE* f = fopen(lrpath, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", lrpath); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> raw(n);
    if (fread(raw.data(), 1, n, f) != (size_t)n) return 2;
    fclose(f);
    lram.resize(n / 2);
    for (size_t i = 0; i < lram.size(); i++)          // big-endian, CPU's view
        lram[i] = (raw[2 * i] << 8) | raw[2 * i + 1];

    Vrf_video_line* t = new Vrf_video_line;
    t->reset = 1; t->frame_start = 0; t->line_start = 0; t->extend = extend;
    uint16_t lq = 0;

    auto tick = [&]() {
        t->lr_q = lq;
        t->clk = 1; t->eval();
        lq = (t->lr_addr < lram.size()) ? lram[t->lr_addr] : 0;  // 1-cycle read
        t->clk = 0; t->eval();
    };

    for (int i = 0; i < 8; i++) tick();
    t->reset = 0;
    t->frame_start = 1; tick(); t->frame_start = 0; tick();

    FILE* out = fopen(outp, "w");
    long long worst = 0, total = 0;
    for (int sy = 0; sy < 256; sy++) {
        int y = 255 - sy;                       // flipscreen walk
        t->y = y;
        t->line_start = 1; tick();
        t->line_start = 0;
        long long c = 0;
        while (t->busy && c < 10000) { tick(); c++; }
        if (c > worst) worst = c;
        total += c;

        fprintf(out, "%d %d", sy, y);
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->clip_l, i, 9));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->clip_r, i, 9));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->blend, i, 4));
        fprintf(out, " %u %u %u", t->x_sample, t->fx_6400, t->bg_palette);
        fprintf(out, " %u %u %u %u %u", t->pivot_control, t->pivot_bsel,
                t->pivot_enable, t->pivot_mix, t->pivot_mosaic);
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->sp_mix, i, 16));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", (t->sp_bsel >> i) & 1);
        fprintf(out, " %u", t->sp_mosaic);
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->pf_colscroll, i, 9));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", (t->pf_alt_tilemap >> i) & 1);
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->pf_x_scale, i, 9));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->pf_y_scale, i, 9));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->pf_pal_add, i, 16));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", widefield(t->pf_rowscroll, 3, i, 20));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", field64(t->pf_mix, i, 16));
        for (int i = 0; i < 4; i++) fprintf(out, " %u", (t->pf_mosaic >> i) & 1);
        fprintf(out, "\n");
    }
    fclose(out);
    printf("decoded 256 lines, mean %lld / worst %lld clocks per line\n", total / 256, worst);
    return 0;
}
