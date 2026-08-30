//============================================================================
//  Bench for rf_video_pipe under REAL raster timing.
//
//  Everything below the pipe is verified block by block; the pipe adds the
//  raster-driven sequencing -- which line is decoded, built and mixed during
//  which raster line, and which buffer bank the beam reads -- and that was
//  the one part that first met silicon untested. This drives the pipe with
//  the same div/hcnt/vcnt/blank counters as rayforce_video, samples rgb at
//  ce_pix exactly as arcade_video does, and compares the third frame (the
//  lookahead needs a frame to prime) against the model. pipe_top wraps the
//  pipe with rf_spr_ch_share, so the sprite planes fetch over ONE shared
//  channel exactly as they will from ch4 on the board.
//
//    ./obj_dir/pipetb <dump_dir> <frame> <ref> <out.ppm>
//============================================================================
#include "Vpipe_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

static std::vector<uint8_t> mem;
static std::vector<uint16_t> lram, pram, palram, tram, cram, vram, sram;

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
    const char* refp = argc > 3 ? argv[3] : "pipe_ref.txt";
    const char* outp = argc > 4 ? argv[4] : "pipe_out.ppm";
    int lat_lo = argc > 5 ? atoi(argv[5]) : 14;      // ram clocks; see run_pipe_lat
    // The SPRITE channel's latency, separately. On the board the playfield
    // planes are ch1/ch2 -- the controller's TOP two priorities -- while the
    // sprite planes share ch4, which is fifth of six, so the sprite path
    // waits several times longer than the playfields do. Raising `lat_lo`
    // alone cannot model that: it slows the playfield builder too, and the
    // frame then breaks everywhere instead of where the board breaks.
    //     F3_SPS_LAT=90 ./obj_dir/pipetb ../dump 2930 ...
    // is the operating point where the ONE-channel wiring loses the bottom of
    // the frame (305 late lines, 67325/71680) and this two-channel one does
    // not (0 late, 71680/71680). See "The sprite fetch path" in HANDOFF.md.
    int lat_sps = getenv("F3_SPS_LAT") ? atoi(getenv("F3_SPS_LAT")) : lat_lo;
    // Bus B's channel, separately. On the real controller ch7 sits BELOW ch4
    // in the fixed-priority scan, so bus B is served only when bus A is not
    // asking -- the two sprite channels are NOT symmetric the way this bench
    // assumed. The draw consumes records in strict alternation (q_cs), so
    // the SLOWER bus gates the pair. F3_SPS_LAT_B models that asymmetry.
    int lat_spsb = getenv("F3_SPS_LAT_B") ? atoi(getenv("F3_SPS_LAT_B")) : lat_sps;
    int rate60 = argc > 6 ? atoi(argv[6]) : 0;       // 1 = the 257-line 60 Hz frame

    char pre[64]; snprintf(pre, sizeof pre, "/f3_%05d_", frame);
    mem.assign(0x1280000, 0);
    struct { const char* n; uint32_t off; } regs[] = {
        {"rgn_tilemap.bin", 0x880000}, {"rgn_tilemap_hi.bin", 0xC80000},
        {"rgn_sprites.bin", 0x280000}, {"rgn_sprites_hi.bin", 0x680000}};
    for (auto& r : regs) { auto v = load(dir + "/" + r.n); memcpy(&mem[r.off], v.data(), v.size()); }
    lram   = be16(load(dir + pre + "line_ram.bin"));
    pram   = be16(load(dir + pre + "pf_ram.bin"));
    palram = be16(load(dir + pre + "paletteram.bin"));
    tram   = be16(load(dir + pre + "textram.bin"));
    cram   = be16(load(dir + pre + "charram.bin"));
    vram   = be16(load(dir + pre + "pivot_ram.bin"));
    { char s2[64]; snprintf(s2, sizeof s2, "/f3_%05d_spriteram.bin", frame - 2);
      sram = be16(load(dir + s2)); }
    uint16_t ctrl[16] = {0};
    { FILE* f = fopen((dir + pre + "ctrl.txt").c_str(), "r");
      int i; unsigned v; while (f && fscanf(f, "%d %x", &i, &v) == 2) ctrl[i] = v; if (f) fclose(f); }

    std::vector<std::vector<uint32_t>> ref(256);
    { FILE* f = fopen(refp, "r"); if (!f) { fprintf(stderr, "cannot open %s\n", refp); return 2; }
      char* buf = nullptr; size_t cap = 0;
      while (getline(&buf, &cap, f) > 0) {
          if (buf[0] == '#') continue;
          std::istringstream ss(buf); int sy; ss >> sy; std::string h;
          while (ss >> h) ref[sy].push_back(strtoul(h.c_str(), 0, 16));
      }
      free(buf); fclose(f); }

    Vpipe_top* t = new Vpipe_top;
    // two shared sprite channels, as on the board: each fetch bus has its
    // own, and rf_spr_ch_share serialises only the two planes behind it, so
    // the per-record cost here is the honest one
    Chan lo, hi, sps, spsb;
    uint32_t ra_l = 0, ra_p = 0, ra_c = 0, ra_t = 0, ra_h = 0, ra_v = 0, ra_spr = 0;
    long long cyc = 0;

    // rayforce_video's counters, verbatim
    // Ray Force's f3_224a window by default; Elevator Action Returns uses
    // the base f3 raster (232 lines from 24), so the window is settable --
    // otherwise a game's top and bottom lines are never compared.
    //     F3_V0=24 F3_V1=256 ./obj_dir/pipetb ../dump/ear ...
    const int H_TOTAL = 432, H_START = 46, H_END = 366;
    const int V_START = getenv("F3_V0") ? atoi(getenv("F3_V0")) : 31;
    const int V_END   = getenv("F3_V1") ? atoi(getenv("F3_V1")) : 255;
    const int V_H     = V_END - V_START;
    // the sprite cull inside the pipe needs the same window: 0 f3_224a,
    // 1 f3_224b, 2 f3_224c, 3 f3 (Elevator Action Returns)
    const int VIS_MODE = (V_START == 31) ? 0 : (V_START == 32) ? 1
                       : (V_END == 248)  ? 2 : 3;
    const int V_TOTAL = rate60 ? 257 : 262;
    int div = 0, hcnt = 0, vcnt = 0;

    std::vector<uint32_t> fb(320 * V_H, 0);
    int frames_done = 0;

    auto step = [&]() {
        for (int r = 0; r < 2; r++) {
            if ((cyc * 2 + r) % 11 == 0) continue;
            lo.tick(t->ch1_req, t->ch1_addr, lat_lo);
            hi.tick(t->ch2_req, t->ch2_addr, lat_lo - 5);
            sps.tick(t->sps_req, t->sps_addr, lat_sps);
            spsb.tick(t->sps_b_req, t->sps_b_addr, lat_spsb);
            t->ch1_dout = lo.dout; t->ch1_ready = lo.ready;
            t->ch2_dout = hi.dout; t->ch2_ready = hi.ready;
            t->sps_dout = sps.dout; t->sps_ready = sps.ready;
            t->sps_b_dout = spsb.dout; t->sps_b_ready = spsb.ready;
            t->clk_ram = 1; t->eval(); t->clk_ram = 0; t->eval();
        }
        t->div = div; t->hcnt = hcnt; t->vcnt = vcnt;
        t->hblank = (hcnt < H_START) || (hcnt >= H_END);
        t->vblank = (vcnt < V_START) || (vcnt >= V_END);
        // registered-address BRAM: q is mem[address presented last cycle]
        t->line_q = ra_l < lram.size()   ? lram[ra_l]   : 0;
        t->pf_q   = ra_p < pram.size()   ? pram[ra_p]   : 0;
        t->pal_q  = ra_c < palram.size() ? palram[ra_c] : 0;
        t->text_q  = ra_t < tram.size() ? tram[ra_t] : 0;
        t->char_q  = ra_h < cram.size() ? cram[ra_h] : 0;
        t->pivot_q = ra_v < vram.size() ? vram[ra_v] : 0;
        t->spr_q   = ra_spr < sram.size() ? sram[ra_spr] : 0;
        uint32_t nl = t->line_addr, np = t->pf_addr, nc = t->pal_addr;
        uint32_t nt = t->text_addr, nh = t->char_addr, nv = t->pivot_addr, ns = t->spr_addr;
        t->clk = 1; t->eval();
        ra_l = nl; ra_p = np; ra_c = nc; ra_t = nt; ra_h = nh; ra_v = nv; ra_spr = ns;
        t->clk = 0; t->eval();

        // arcade_video samples RGB_in on ce_pix, which is high during div 0
        if (div == 0) {
            int x = hcnt - H_START, y = vcnt - V_START;
            if (x >= 0 && x < 320 && y >= 0 && y < V_H) fb[y * 320 + x] = t->rgb;
        }
        // advance the raster the way rayforce_video does
        if (div == 7) {
            if (hcnt == H_TOTAL - 1) {
                hcnt = 0;
                if (vcnt == V_TOTAL - 1) { vcnt = 0; frames_done++; } else vcnt++;
            } else hcnt++;
        }
        div = (div + 1) & 7;
        cyc++;
    };

    t->vis_mode = VIS_MODE;

    t->reset = 1; t->flip = 1; t->rate_60 = rate60;
    for (int w = 0; w < 4; w++) { t->ctrl0[w] = ctrl[2 * w] | ((uint32_t)ctrl[2 * w + 1] << 16);
                                  t->ctrl1[w] = ctrl[8 + 2 * w] | ((uint32_t)ctrl[9 + 2 * w] << 16); }
    for (int i = 0; i < 16; i++) step();
    t->reset = 0;

    // Frames to run before the comparison. Three is enough for the picture
    // (frame 1 primes the sprite ring), but the pipe's own SPRLINE : LATE
    // counter is peak-HELD and only starts accumulating on the 16th frame
    // -- so reading it in this bench needs F3_FRAMES=20 or more. With the
    // VRAM static, every extra frame is the same frame again, which is
    // exactly what a steady-state timing reading wants.
    const int NFRAMES = getenv("F3_FRAMES") ? atoi(getenv("F3_FRAMES")) : 3;
    while (frames_done < NFRAMES) step();     // frame 1 primes, the rest are real
    // through frame_end (raster 0 of the next frame) so the diagnostics
    // printed are frame 3's -- the frame compared below -- not frame 2's
    for (int i = 0; i < 4; i++) step();
    printf("dbg_lines %08x dbg_fetch %08x dbg_max %08x dbg_nz %08x dbg_spr %08x dbg_rec %08x dbg_sfetch %08x  (mix:build fetch:pixnz maxfetch:maxbuild tilenz:pf:pal sprmax:late recs:dropped)\n",
           t->dbg_lines, t->dbg_fetch, t->dbg_max, t->dbg_nz, t->dbg_spr, t->dbg_rec, t->dbg_sfetch);

    FILE* o = fopen(outp, "wb");
    fprintf(o, "P6\n320 %d\n255\n", V_H);
    for (auto v : fb) { unsigned char p[3] = {(unsigned char)(v >> 16), (unsigned char)(v >> 8), (unsigned char)v}; fwrite(p, 1, 3, o); }
    fclose(o);

    int bad = 0, total = 0, shown = 0;
    for (int sy = V_START; sy < V_END; sy++) {
        if (ref[sy].size() != 320) continue;
        for (int x = 0; x < 320; x++) {
            total++;
            uint32_t got = fb[(sy - V_START) * 320 + x];
            if (got != ref[sy][x]) {
                bad++;
                if (shown < 6) { printf("  sy=%d x=%d: rtl %06x ref %06x\n", sy, x, got, ref[sy][x]); shown++; }
            }
        }
    }
    printf("%d/%d visible pixels identical to the model (3 frames of %d lines, %lld clocks)\n",
           total - bad, total, V_TOTAL, cyc);
    return bad ? 1 : 0;
}
