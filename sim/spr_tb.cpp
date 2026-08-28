//============================================================================
//  Bench for rf_video_spr_list -- the sprite list walker vs the model.
//
//  Loads frame F-2's sprite RAM (the lag-2 source of frame F's sprites),
//  runs the walker, collects every emitted sprite, and compares the list
//  entry-for-entry against sim/gen_spr_ref.py (which runs get_sprite_info on
//  the same bytes). Pure logic: no graphics, no framebuffer.
//
//    ./obj_dir/sprtb <dump_dir> <frame> <ref>
//============================================================================
#include "Vrf_video_spr_list.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

struct Spr { long tx, ty; int sx, sy; long code; int color, fx, fy, pri; };

static std::vector<uint16_t> load_be16(const std::string& p) {
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> b(n);
    if (fread(b.data(), 1, n, f) != (size_t)n) exit(2);
    fclose(f);
    std::vector<uint16_t> v(n / 2);
    for (size_t i = 0; i < v.size(); i++) v[i] = (b[2 * i] << 8) | b[2 * i + 1];
    return v;
}

// sign-extend an 18-bit Verilator output to a C long
static long sext18(uint32_t v) { v &= 0x3FFFF; return (v & 0x20000) ? (long)v - 0x40000 : (long)v; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string dir = argc > 1 ? argv[1] : "../dump";
    int frame = argc > 2 ? atoi(argv[2]) : 1800;
    const char* refp = argc > 3 ? argv[3] : "spr_ref.txt";

    char pre[64]; snprintf(pre, sizeof pre, "/f3_%05d_spriteram.bin", frame - 2);
    std::vector<uint16_t> sram = load_be16(dir + pre);

    // reference list
    std::vector<Spr> ref;
    int exp_flip = 0, exp_extra = 0, exp_pen = 0;
    { FILE* f = fopen(refp, "r"); if (!f) { fprintf(stderr, "cannot open %s\n", refp); return 2; }
      char* line = nullptr; size_t cap = 0;
      while (getline(&line, &cap, f) > 0) {
          if (line[0] == '#') { sscanf(line, "# frame %*d src %*d flip %d extra %d penmask %x",
                                       &exp_flip, &exp_extra, &exp_pen); continue; }
          Spr s;
          if (sscanf(line, "S %ld %ld %d %d %ld %d %d %d %d", &s.tx, &s.ty, &s.sx, &s.sy,
                     &s.code, &s.color, &s.fx, &s.fy, &s.pri) == 9)
              ref.push_back(s);
      }
      free(line); fclose(f); }

    Vrf_video_spr_list* t = new Vrf_video_spr_list;
    std::vector<Spr> got;

    // registered-address BRAM: q is mem[address presented LAST cycle], the
    // contract rf_bram documents. A zero-latency model here would load every
    // entry's words shifted by one (the same trap the pipe benches hit).
    uint32_t ra = 0;
    auto tick = [&]() {
        t->spr_q = ra < sram.size() ? sram[ra] : 0;
        uint32_t na = t->spr_addr;
        t->clk = 1; t->eval();
        if (t->s_valid)
            got.push_back({sext18(t->s_tx), sext18(t->s_ty), (int)t->s_sx, (int)t->s_sy,
                           (long)t->s_code, (int)t->s_color, (int)t->s_fx, (int)t->s_fy,
                           (int)t->s_pri});
        ra = na;
        t->clk = 0; t->eval();
    };

    t->reset = 1; t->start = 0; t->start_bank = 0;
    for (int i = 0; i < 4; i++) tick();
    t->reset = 0;
    t->start = 1; tick(); t->start = 0;

    long guard = 0;
    while (!t->done && guard++ < 2000000) tick();
    for (int i = 0; i < 4; i++) tick();          // flush last s_valid

    int bad = 0;
    if ((int)got.size() != (int)ref.size()) {
        printf("COUNT MISMATCH: rtl %zu, ref %zu\n", got.size(), ref.size());
        bad = 1;
    }
    if (t->o_flip != exp_flip || t->o_extra != exp_extra || t->o_penmask != exp_pen) {
        printf("STATE MISMATCH: rtl flip %d extra %d pen %02x, ref flip %d extra %d pen %02x\n",
               t->o_flip, t->o_extra, t->o_penmask, exp_flip, exp_extra, exp_pen);
        bad = 1;
    }
    size_t n = got.size() < ref.size() ? got.size() : ref.size();
    int shown = 0;
    for (size_t i = 0; i < n; i++) {
        Spr& g = got[i]; Spr& r = ref[i];
        if (g.tx != r.tx || g.ty != r.ty || g.sx != r.sx || g.sy != r.sy ||
            g.code != r.code || g.color != r.color || g.fx != r.fx || g.fy != r.fy || g.pri != r.pri) {
            bad = 1;
            if (shown++ < 8)
                printf("  [%zu] rtl tx=%ld ty=%ld sx=%d sy=%d code=%ld col=%d fx=%d fy=%d pri=%d\n"
                       "      ref tx=%ld ty=%ld sx=%d sy=%d code=%ld col=%d fx=%d fy=%d pri=%d\n",
                       i, g.tx, g.ty, g.sx, g.sy, g.code, g.color, g.fx, g.fy, g.pri,
                       r.tx, r.ty, r.sx, r.sy, r.code, r.color, r.fx, r.fy, r.pri);
        }
    }
    printf("%zu/%zu sprites match the model (frame %d)\n", n - (bad ? shown : 0), ref.size(), frame);
    if (!bad) printf("SPRITE LIST OK: %zu sprites, flip %d extra %d penmask %02x\n",
                     got.size(), exp_flip, exp_extra, exp_pen);
    delete t;
    return bad ? 1 : 0;
}
