// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vrf_hiscore.h for the primary calling header

#ifndef VERILATED_VRF_HISCORE___024ROOT_H_
#define VERILATED_VRF_HISCORE___024ROOT_H_  // guard

#include "verilated.h"


class Vrf_hiscore__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vrf_hiscore___024root final {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    VL_IN8(reset,0,0);
    VL_IN8(game_id,1,0);
    VL_IN8(run,0,0);
    VL_IN8(vbl_rise,0,0);
    VL_IN8(ld_wr,0,0);
    VL_IN8(ld_word,5,0);
    VL_IN8(sv_word,5,0);
    VL_IN8(ioctl_upload,0,0);
    VL_OUT8(hs_pause,0,0);
    VL_OUT8(hs_be,1,0);
    VL_OUT8(hs_we,0,0);
    VL_OUT8(save_ready,0,0);
    CData/*7:0*/ rf_hiscore__DOT__total;
    CData/*0:0*/ rf_hiscore__DOT__ld_pend;
    CData/*5:0*/ rf_hiscore__DOT__ld_pw;
    CData/*7:0*/ rf_hiscore__DOT__sh_idx;
    CData/*7:0*/ rf_hiscore__DOT__sh_byte;
    CData/*2:0*/ rf_hiscore__DOT__hst;
    CData/*0:0*/ rf_hiscore__DOT__injected;
    CData/*0:0*/ rf_hiscore__DOT__poll_done;
    CData/*0:0*/ rf_hiscore__DOT__capturing;
    CData/*0:0*/ rf_hiscore__DOT__sh_ok;
    CData/*7:0*/ rf_hiscore__DOT__idx;
    CData/*1:0*/ rf_hiscore__DOT__gph;
    CData/*7:0*/ rf_hiscore__DOT__settle;
    CData/*1:0*/ rf_hiscore__DOT__rd_ph;
    CData/*0:0*/ rf_hiscore__DOT__upload_d;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VstlPhaseResult;
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__reset__0;
    CData/*1:0*/ __Vtrigprevexpr___TOP__game_id__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__run__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__vbl_rise__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__ld_wr__0;
    CData/*5:0*/ __Vtrigprevexpr___TOP__ld_word__0;
    CData/*5:0*/ __Vtrigprevexpr___TOP__sv_word__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__ioctl_upload__0;
    CData/*0:0*/ __VicoDidInit;
    CData/*0:0*/ __VicoPhaseResult;
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__1;
    CData/*0:0*/ __VactPhaseResult;
    CData/*0:0*/ __VnbaPhaseResult;
    VL_IN16(ld_data,15,0);
    VL_OUT16(sv_data,15,0);
    VL_OUT16(hs_addr,15,0);
    VL_OUT16(hs_wdata,15,0);
    VL_IN16(hs_q,15,0);
    SData/*15:0*/ rf_hiscore__DOT__ld_pd;
    SData/*15:0*/ rf_hiscore__DOT__sv_q;
    SData/*15:0*/ rf_hiscore__DOT__cap_lo;
    SData/*15:0*/ __Vtrigprevexpr___TOP__ld_data__0;
    SData/*15:0*/ __Vtrigprevexpr___TOP__hs_q__0;
    IData/*16:0*/ rf_hiscore__DOT__cur_b;
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<CData/*7:0*/, 4> rf_hiscore__DOT__gv;
    VlUnpacked<SData/*15:0*/, 64> rf_hiscore__DOT__shadow;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 2> __VicoTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vrf_hiscore__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vrf_hiscore___024root(Vrf_hiscore__Syms* symsp, const char* namep);
    ~Vrf_hiscore___024root();
    VL_UNCOPYABLE(Vrf_hiscore___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
