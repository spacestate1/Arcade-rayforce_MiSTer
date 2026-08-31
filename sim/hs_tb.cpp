// rf_hiscore standalone bench: a fake 64Kx16 main RAM, a loaded snapshot,
// and the three things the module must do -- refuse to inject until BOTH
// the file and the game's RAM pass the guard bytes, inject exactly the
// dat's layout when they do, and capture the same bytes back for upload.
#include "Vrf_hiscore.h"
#include "verilated.h"
#include <cstdio>
#include <cstring>
static uint16_t ram[65536];
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vrf_hiscore* t = new Vrf_hiscore;
    auto wr8 = [&](uint32_t b, uint8_t v){ uint16_t& w=ram[b>>1]; if(b&1) w=(w&0xFF00)|v; else w=(w&0x00FF)|(v<<8); };
    auto rd8 = [&](uint32_t b){ return (b&1)? (ram[b>>1]&0xFF) : (ram[b>>1]>>8); };
    auto step = [&](){
        // one clk with the RAM model behind hs_addr/hs_q (registered q)
        static uint16_t q=0;
        t->hs_q = q; t->clk=1; t->eval();
        if (t->hs_we) { if(t->hs_be&2) { uint16_t&w=ram[t->hs_addr]; w=(w&0x00FF)|(t->hs_wdata&0xFF00);} 
                        if(t->hs_be&1) { uint16_t&w=ram[t->hs_addr]; w=(w&0xFF00)|(t->hs_wdata&0x00FF);} }
        q = ram[t->hs_addr];
        t->clk=0; t->eval();
    };
    t->game_id=0; t->reset=1; t->run=0; t->vbl_rise=0; t->ld_wr=0; t->ioctl_upload=0;
    for(int i=0;i<4;i++) step();
    t->reset=0;

    // load a valid snapshot: guards 0x41..0x00 / 0x01..0x00, payload = i
    uint8_t snap[128]; memset(snap,0,sizeof snap);
    for(int i=0;i<68;i++) snap[i]=0x80+i;
    snap[0]=0x41; snap[0x3f]=0x00; snap[0x40]=0x01; snap[0x43]=0x00;
    for(int w=0;w<64;w++){ t->ld_wr=1; t->ld_word=w; t->ld_data=snap[2*w] | (snap[2*w+1]<<8); step(); }
    t->ld_wr=0; for(int i=0;i<8;i++) step();

    t->run=1;
    // 1) RAM not initialised: guards absent -> no inject over many vblanks
    for(int v=0;v<4;v++){ t->vbl_rise=1; step(); t->vbl_rise=0; for(int i=0;i<800;i++) step(); }
    int dirty=0; for(uint32_t b=0;b<0x20000;b++) if(rd8(b)) dirty++;
    if(dirty){ printf("FAIL: injected into uninitialised RAM (%d bytes)\n",dirty); return 1; }

    // 2) game initialises its table -> inject must happen, exactly at the offsets
    wr8(0xeff4,0x41); wr8(0xeff4+0x3f,0x00); wr8(0x22fa,0x01); wr8(0x22fa+3,0x00);
    for(int v=0;v<4;v++){ t->vbl_rise=1; step(); t->vbl_rise=0;
        int pau=0,wes=0; for(int i=0;i<800;i++){ step(); pau+=t->hs_pause; wes+=t->hs_we; }
        printf("  vbl %d: pause_cycles=%d writes=%d save_ready=%d\n",v,pau,wes,(int)t->save_ready); }
    int bad=0;
    for(int i=0;i<0x40;i++) if(rd8(0xeff4+i)!=snap[i]) bad++;
    for(int i=0;i<4;i++)    if(rd8(0x22fa+i)!=snap[0x40+i]) bad++;
    if(bad){ printf("FAIL: inject wrote %d wrong bytes\n",bad);
        for(int i=0;i<8;i++) printf("  r0[%d]: ram=%02x want=%02x\n", i, rd8(0xeff4+i), snap[i]);
        for(int i=0;i<4;i++) printf("  r1[%d]: ram=%02x want=%02x\n", i, rd8(0x22fa+i), snap[0x40+i]);
        return 1; }
    if(!t->save_ready){ printf("FAIL: save_ready not raised\n"); return 1; }

    // 3) the game beats a score; capture on upload must return the new table
    wr8(0xeff4+5, 0xAA); wr8(0x22fa+1, 0xBB);
    t->ioctl_upload=1; step(); for(int i=0;i<1200;i++) step();
    auto svrd=[&](int w){ t->sv_word=w; step(); step(); step(); return (int)t->sv_data; };
    int w2=svrd(2), w32=svrd(32);
    t->ioctl_upload=0;
    if(((w2>>8)&0xFF)!=0xAA){ printf("FAIL: capture byte5=%02x want AA\n",(w2>>8)&0xFF); return 1; }
    if(((w32>>8)&0xFF)!=0xBB){ printf("FAIL: capture 22fb=%02x want BB\n",(w32>>8)&0xFF); return 1; }
    printf("HISCORE OK: no premature inject, exact inject, live capture\n");
    return 0;
}
