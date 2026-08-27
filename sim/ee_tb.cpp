// 93C46 protocol check: EWEN, WRITE 0x1234 to word 5, READ it back and
// confirm the dummy 0 precedes the 16 data bits; READ an erased word too.
#include "Vrf_eeprom_93c46.h"
#include "verilated.h"
#include <cstdio>
static Vrf_eeprom_93c46* t;
static void clk() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }
static void bit(int d) { t->di = d; t->sk = 0; clk(); clk(); t->sk = 1; clk(); clk(); }
static int rbit(int d) { t->di = d; t->sk = 0; clk(); clk(); t->sk = 1; clk(); clk(); return t->do_out; }
static void cmd(int op, int addr) {            // start bit, 2 op, 6 addr
    t->cs = 1; clk(); bit(1); bit(op >> 1); bit(op & 1);
    for (int i = 5; i >= 0; i--) bit((addr >> i) & 1);
}
static void done() { t->sk = 0; clk(); t->cs = 0; clk(); clk(); }
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    t = new Vrf_eeprom_93c46; t->reset = 1; t->cs = 0; t->sk = 0; t->di = 0;
    clk(); clk(); t->reset = 0; clk();
    cmd(0, 0x30); done();                                  // EWEN = 00 11xxxx
    cmd(1, 5); for (int i = 15; i >= 0; i--) bit((0x1234 >> i) & 1); done();
    int fails = 0;
    for (int pass = 0; pass < 2; pass++) {
        int addr = pass ? 6 : 5, expect = pass ? 0xFFFF : 0x1234;
        cmd(2, addr);
        int dummy = t->do_out;                              // after last addr bit
        int v = 0; for (int i = 0; i < 16; i++) v = (v << 1) | rbit(0);
        done();
        printf("READ word %d: dummy=%d data=0x%04X (expect 0x%04X) %s\n",
               addr, dummy, v, expect, (dummy == 0 && v == expect) ? "ok" : "FAIL");
        fails += !(dummy == 0 && v == expect);
    }
    printf("idle DO=%d (expect 1)\n", t->do_out); fails += (t->do_out != 1);
    return fails;
}
