// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vrf_hiscore.h for the primary calling header

#include "Vrf_hiscore__pch.h"

void Vrf_hiscore___024root___eval_triggers_vec__ico(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_triggers_vec__ico\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VicoTriggered[0U] = (QData)((IData)(
                                                    (((((IData)(vlSelfRef.hs_q) 
                                                        != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__hs_q__0)) 
                                                       << 0x0000000aU) 
                                                      | ((((IData)(vlSelfRef.ioctl_upload) 
                                                           != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__ioctl_upload__0)) 
                                                          << 9U) 
                                                         | (((IData)(vlSelfRef.sv_word) 
                                                             != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__sv_word__0)) 
                                                            << 8U))) 
                                                     | (((((((IData)(vlSelfRef.ld_data) 
                                                             != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__ld_data__0)) 
                                                            << 3U) 
                                                           | (((IData)(vlSelfRef.ld_word) 
                                                               != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__ld_word__0)) 
                                                              << 2U)) 
                                                          | ((((IData)(vlSelfRef.ld_wr) 
                                                               != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__ld_wr__0)) 
                                                              << 1U) 
                                                             | ((IData)(vlSelfRef.vbl_rise) 
                                                                != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__vbl_rise__0)))) 
                                                         << 4U) 
                                                        | (((((IData)(vlSelfRef.run) 
                                                              != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__run__0)) 
                                                             << 3U) 
                                                            | (((IData)(vlSelfRef.game_id) 
                                                                != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__game_id__0)) 
                                                               << 2U)) 
                                                           | ((((IData)(vlSelfRef.reset) 
                                                                != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__reset__0)) 
                                                               << 1U) 
                                                              | ((IData)(vlSelfRef.clk) 
                                                                 != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__0))))))));
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__reset__0 = vlSelfRef.reset;
    vlSelfRef.__Vtrigprevexpr___TOP__game_id__0 = vlSelfRef.game_id;
    vlSelfRef.__Vtrigprevexpr___TOP__run__0 = vlSelfRef.run;
    vlSelfRef.__Vtrigprevexpr___TOP__vbl_rise__0 = vlSelfRef.vbl_rise;
    vlSelfRef.__Vtrigprevexpr___TOP__ld_wr__0 = vlSelfRef.ld_wr;
    vlSelfRef.__Vtrigprevexpr___TOP__ld_word__0 = vlSelfRef.ld_word;
    vlSelfRef.__Vtrigprevexpr___TOP__ld_data__0 = vlSelfRef.ld_data;
    vlSelfRef.__Vtrigprevexpr___TOP__sv_word__0 = vlSelfRef.sv_word;
    vlSelfRef.__Vtrigprevexpr___TOP__ioctl_upload__0 
        = vlSelfRef.ioctl_upload;
    vlSelfRef.__Vtrigprevexpr___TOP__hs_q__0 = vlSelfRef.hs_q;
    if (VL_UNLIKELY(((1U & (~ (IData)(vlSelfRef.__VicoDidInit)))))) {
        vlSelfRef.__VicoDidInit = 1U;
        vlSelfRef.__VicoTriggered[0U] = (1ULL | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (2ULL | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (4ULL | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (8ULL | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000010ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000020ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000040ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000080ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000100ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000200ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
        vlSelfRef.__VicoTriggered[0U] = (0x0000000000000400ULL 
                                         | vlSelfRef.__VicoTriggered[0U]);
    }
}

bool Vrf_hiscore___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 2> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___trigger_anySet__ico\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((2U > n));
    return (0U);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrf_hiscore___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 2> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool Vrf_hiscore___024root___eval_phase__ico(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_phase__ico\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VicoExecute;
    // Body
    Vrf_hiscore___024root___eval_triggers_vec__ico(vlSelf);
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vrf_hiscore___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
    __VicoExecute = Vrf_hiscore___024root___trigger_anySet__ico(vlSelfRef.__VicoTriggered);
    if (__VicoExecute) {
        {
            // Inlined CFunc: _eval_ico
            if ((4ULL & vlSelfRef.__VicoTriggered[0U])) {
                {
                    // Inlined CFunc: _ico_sequent__TOP__0
                    if ((1U == (IData)(vlSelfRef.game_id))) {
                        vlSelfRef.rf_hiscore__DOT__gv[0U] = 0U;
                        vlSelfRef.rf_hiscore__DOT__gv[1U] = 1U;
                        vlSelfRef.rf_hiscore__DOT__gv[2U] = 0xc3U;
                        vlSelfRef.rf_hiscore__DOT__gv[3U] = 0xc3U;
                    } else {
                        vlSelfRef.rf_hiscore__DOT__gv[0U] = 0x41U;
                        vlSelfRef.rf_hiscore__DOT__gv[1U] = 0U;
                        vlSelfRef.rf_hiscore__DOT__gv[2U] = 1U;
                        vlSelfRef.rf_hiscore__DOT__gv[3U] = 0U;
                    }
                    vlSelfRef.rf_hiscore__DOT__total 
                        = (0x000000ffU & (((1U == (IData)(vlSelfRef.game_id))
                                            ? 0x7cU
                                            : 0x40U) 
                                          + ((1U == (IData)(vlSelfRef.game_id))
                                              ? 1U : 4U)));
                    vlSelfRef.rf_hiscore__DOT__cur_b 
                        = (0x0001ffffU & ((2U == (IData)(vlSelfRef.rf_hiscore__DOT__hst))
                                           ? ((0U == (IData)(vlSelfRef.rf_hiscore__DOT__gph))
                                               ? ((1U 
                                                   == (IData)(vlSelfRef.game_id))
                                                   ? 0x0000ce3aU
                                                   : 0x0000eff4U)
                                               : ((1U 
                                                   == (IData)(vlSelfRef.rf_hiscore__DOT__gph))
                                                   ? 
                                                  ((((1U 
                                                      == (IData)(vlSelfRef.game_id))
                                                      ? 0x0000ce3aU
                                                      : 0x0000eff4U) 
                                                    + 
                                                    ((1U 
                                                      == (IData)(vlSelfRef.game_id))
                                                      ? 0x7cU
                                                      : 0x40U)) 
                                                   - (IData)(1U))
                                                   : 
                                                  ((2U 
                                                    == (IData)(vlSelfRef.rf_hiscore__DOT__gph))
                                                    ? 
                                                   ((1U 
                                                     == (IData)(vlSelfRef.game_id))
                                                     ? 0x0000ce3cU
                                                     : 0x000022faU)
                                                    : 
                                                   ((((1U 
                                                       == (IData)(vlSelfRef.game_id))
                                                       ? 0x0000ce3cU
                                                       : 0x000022faU) 
                                                     + 
                                                     ((1U 
                                                       == (IData)(vlSelfRef.game_id))
                                                       ? 1U
                                                       : 4U)) 
                                                    - (IData)(1U)))))
                                           : (((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                                               < ((1U 
                                                   == (IData)(vlSelfRef.game_id))
                                                   ? 0x7cU
                                                   : 0x40U))
                                               ? ((
                                                   (1U 
                                                    == (IData)(vlSelfRef.game_id))
                                                    ? 0x0000ce3aU
                                                    : 0x0000eff4U) 
                                                  + (IData)(vlSelfRef.rf_hiscore__DOT__idx))
                                               : ((
                                                   (1U 
                                                    == (IData)(vlSelfRef.game_id))
                                                    ? 0x0000ce3cU
                                                    : 0x000022faU) 
                                                  + 
                                                  ((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                                                   - 
                                                   ((1U 
                                                     == (IData)(vlSelfRef.game_id))
                                                     ? 0x7cU
                                                     : 0x40U))))));
                }
            }
        }
    }
    return (__VicoExecute);
}

bool Vrf_hiscore___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vrf_hiscore___024root___nba_sequent__TOP__0(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___nba_sequent__TOP__0\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*1:0*/ __Vfunc_rf_hiscore__DOT__lane_of__2__Vfuncout;
    __Vfunc_rf_hiscore__DOT__lane_of__2__Vfuncout = 0;
    IData/*16:0*/ __Vfunc_rf_hiscore__DOT__lane_of__2__b;
    __Vfunc_rf_hiscore__DOT__lane_of__2__b = 0;
    CData/*7:0*/ __Vfunc_rf_hiscore__DOT__guard_idx__3__Vfuncout;
    __Vfunc_rf_hiscore__DOT__guard_idx__3__Vfuncout = 0;
    CData/*1:0*/ __Vfunc_rf_hiscore__DOT__guard_idx__3__g;
    __Vfunc_rf_hiscore__DOT__guard_idx__3__g = 0;
    CData/*2:0*/ __Vdly__rf_hiscore__DOT__hst;
    __Vdly__rf_hiscore__DOT__hst = 0;
    CData/*0:0*/ __Vdly__rf_hiscore__DOT__poll_done;
    __Vdly__rf_hiscore__DOT__poll_done = 0;
    CData/*0:0*/ __Vdly__rf_hiscore__DOT__capturing;
    __Vdly__rf_hiscore__DOT__capturing = 0;
    CData/*0:0*/ __Vdly__rf_hiscore__DOT__ld_pend;
    __Vdly__rf_hiscore__DOT__ld_pend = 0;
    CData/*1:0*/ __Vdly__rf_hiscore__DOT__rd_ph;
    __Vdly__rf_hiscore__DOT__rd_ph = 0;
    SData/*9:0*/ __Vdly__rf_hiscore__DOT__inj_left;
    __Vdly__rf_hiscore__DOT__inj_left = 0;
    CData/*5:0*/ __Vdly__rf_hiscore__DOT__ld_pw;
    __Vdly__rf_hiscore__DOT__ld_pw = 0;
    SData/*15:0*/ __Vdly__rf_hiscore__DOT__ld_pd;
    __Vdly__rf_hiscore__DOT__ld_pd = 0;
    CData/*7:0*/ __Vdly__rf_hiscore__DOT__idx;
    __Vdly__rf_hiscore__DOT__idx = 0;
    CData/*0:0*/ __Vdly__rf_hiscore__DOT__sh_ok;
    __Vdly__rf_hiscore__DOT__sh_ok = 0;
    CData/*1:0*/ __Vdly__rf_hiscore__DOT__gph;
    __Vdly__rf_hiscore__DOT__gph = 0;
    CData/*7:0*/ __Vdly__rf_hiscore__DOT__settle;
    __Vdly__rf_hiscore__DOT__settle = 0;
    SData/*15:0*/ __VdlyVal__rf_hiscore__DOT__shadow__v0;
    __VdlyVal__rf_hiscore__DOT__shadow__v0 = 0;
    CData/*5:0*/ __VdlyDim0__rf_hiscore__DOT__shadow__v0;
    __VdlyDim0__rf_hiscore__DOT__shadow__v0 = 0;
    CData/*0:0*/ __VdlySet__rf_hiscore__DOT__shadow__v0;
    __VdlySet__rf_hiscore__DOT__shadow__v0 = 0;
    SData/*15:0*/ __VdlyVal__rf_hiscore__DOT__shadow__v1;
    __VdlyVal__rf_hiscore__DOT__shadow__v1 = 0;
    CData/*5:0*/ __VdlyDim0__rf_hiscore__DOT__shadow__v1;
    __VdlyDim0__rf_hiscore__DOT__shadow__v1 = 0;
    CData/*0:0*/ __VdlySet__rf_hiscore__DOT__shadow__v1;
    __VdlySet__rf_hiscore__DOT__shadow__v1 = 0;
    SData/*15:0*/ __VdlyVal__rf_hiscore__DOT__shadow__v2;
    __VdlyVal__rf_hiscore__DOT__shadow__v2 = 0;
    CData/*5:0*/ __VdlyDim0__rf_hiscore__DOT__shadow__v2;
    __VdlyDim0__rf_hiscore__DOT__shadow__v2 = 0;
    CData/*0:0*/ __VdlySet__rf_hiscore__DOT__shadow__v2;
    __VdlySet__rf_hiscore__DOT__shadow__v2 = 0;
    SData/*15:0*/ __VdlyVal__rf_hiscore__DOT__shadow__v3;
    __VdlyVal__rf_hiscore__DOT__shadow__v3 = 0;
    CData/*5:0*/ __VdlyDim0__rf_hiscore__DOT__shadow__v3;
    __VdlyDim0__rf_hiscore__DOT__shadow__v3 = 0;
    CData/*0:0*/ __VdlySet__rf_hiscore__DOT__shadow__v3;
    __VdlySet__rf_hiscore__DOT__shadow__v3 = 0;
    // Body
    __Vdly__rf_hiscore__DOT__poll_done = vlSelfRef.rf_hiscore__DOT__poll_done;
    __Vdly__rf_hiscore__DOT__capturing = vlSelfRef.rf_hiscore__DOT__capturing;
    __Vdly__rf_hiscore__DOT__ld_pend = vlSelfRef.rf_hiscore__DOT__ld_pend;
    __Vdly__rf_hiscore__DOT__rd_ph = vlSelfRef.rf_hiscore__DOT__rd_ph;
    __Vdly__rf_hiscore__DOT__inj_left = vlSelfRef.rf_hiscore__DOT__inj_left;
    __Vdly__rf_hiscore__DOT__ld_pw = vlSelfRef.rf_hiscore__DOT__ld_pw;
    __Vdly__rf_hiscore__DOT__ld_pd = vlSelfRef.rf_hiscore__DOT__ld_pd;
    __Vdly__rf_hiscore__DOT__sh_ok = vlSelfRef.rf_hiscore__DOT__sh_ok;
    __Vdly__rf_hiscore__DOT__settle = vlSelfRef.rf_hiscore__DOT__settle;
    __Vdly__rf_hiscore__DOT__hst = vlSelfRef.rf_hiscore__DOT__hst;
    __Vdly__rf_hiscore__DOT__idx = vlSelfRef.rf_hiscore__DOT__idx;
    __Vdly__rf_hiscore__DOT__gph = vlSelfRef.rf_hiscore__DOT__gph;
    __VdlySet__rf_hiscore__DOT__shadow__v0 = 0U;
    __VdlySet__rf_hiscore__DOT__shadow__v1 = 0U;
    __VdlySet__rf_hiscore__DOT__shadow__v2 = 0U;
    __VdlySet__rf_hiscore__DOT__shadow__v3 = 0U;
    vlSelfRef.rf_hiscore__DOT__sv_q = vlSelfRef.rf_hiscore__DOT__shadow
        [vlSelfRef.sv_word];
    vlSelfRef.hs_we = 0U;
    if (vlSelfRef.reset) {
        __Vdly__rf_hiscore__DOT__hst = 0U;
        vlSelfRef.hs_pause = 0U;
        __Vdly__rf_hiscore__DOT__poll_done = 0U;
        vlSelfRef.save_ready = 0U;
        __Vdly__rf_hiscore__DOT__capturing = 0U;
        __Vdly__rf_hiscore__DOT__ld_pend = 0U;
        __Vdly__rf_hiscore__DOT__rd_ph = 0U;
        __Vdly__rf_hiscore__DOT__inj_left = 0x0258U;
    } else {
        if (((IData)(vlSelfRef.ld_wr) & (4U != (IData)(vlSelfRef.rf_hiscore__DOT__hst)))) {
            __VdlyVal__rf_hiscore__DOT__shadow__v0 
                = vlSelfRef.ld_data;
            __VdlyDim0__rf_hiscore__DOT__shadow__v0 
                = vlSelfRef.ld_word;
            __VdlySet__rf_hiscore__DOT__shadow__v0 = 1U;
        } else if (vlSelfRef.ld_wr) {
            __Vdly__rf_hiscore__DOT__ld_pend = 1U;
            __Vdly__rf_hiscore__DOT__ld_pw = vlSelfRef.ld_word;
            __Vdly__rf_hiscore__DOT__ld_pd = vlSelfRef.ld_data;
        } else if (((IData)(vlSelfRef.rf_hiscore__DOT__ld_pend) 
                    & (4U != (IData)(vlSelfRef.rf_hiscore__DOT__hst)))) {
            __VdlyVal__rf_hiscore__DOT__shadow__v1 
                = vlSelfRef.rf_hiscore__DOT__ld_pd;
            __VdlyDim0__rf_hiscore__DOT__shadow__v1 
                = vlSelfRef.rf_hiscore__DOT__ld_pw;
            __VdlySet__rf_hiscore__DOT__shadow__v1 = 1U;
            __Vdly__rf_hiscore__DOT__ld_pend = 0U;
        }
        if ((4U & (IData)(vlSelfRef.rf_hiscore__DOT__hst))) {
            if ((2U & (IData)(vlSelfRef.rf_hiscore__DOT__hst))) {
                __Vdly__rf_hiscore__DOT__hst = 0U;
            } else if ((1U & (IData)(vlSelfRef.rf_hiscore__DOT__hst))) {
                vlSelfRef.hs_pause = 0U;
                __Vdly__rf_hiscore__DOT__hst = 0U;
            } else {
                if ((2U == (IData)(vlSelfRef.rf_hiscore__DOT__rd_ph))) {
                    __Vdly__rf_hiscore__DOT__rd_ph = 0U;
                    if ((1U & (IData)(vlSelfRef.rf_hiscore__DOT__idx))) {
                        __VdlyVal__rf_hiscore__DOT__shadow__v2 
                            = ((0x0000ff00U & (((1U 
                                                 & vlSelfRef.rf_hiscore__DOT__cur_b)
                                                 ? (IData)(vlSelfRef.hs_q)
                                                 : 
                                                ((IData)(vlSelfRef.hs_q) 
                                                 >> 8U)) 
                                               << 8U)) 
                               | (0x000000ffU & (IData)(vlSelfRef.rf_hiscore__DOT__cap_lo)));
                        __VdlyDim0__rf_hiscore__DOT__shadow__v2 
                            = (0x0000003fU & ((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                                              >> 1U));
                        __VdlySet__rf_hiscore__DOT__shadow__v2 = 1U;
                    } else {
                        vlSelfRef.rf_hiscore__DOT__cap_lo 
                            = ((0xff00U & (IData)(vlSelfRef.rf_hiscore__DOT__cap_lo)) 
                               | (0x000000ffU & ((1U 
                                                  & vlSelfRef.rf_hiscore__DOT__cur_b)
                                                  ? (IData)(vlSelfRef.hs_q)
                                                  : 
                                                 ((IData)(vlSelfRef.hs_q) 
                                                  >> 8U))));
                    }
                    if (((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                         == (0x000000ffU & ((IData)(vlSelfRef.rf_hiscore__DOT__total) 
                                            - (IData)(1U))))) {
                        if ((1U & (~ (IData)(vlSelfRef.rf_hiscore__DOT__idx)))) {
                            __VdlyVal__rf_hiscore__DOT__shadow__v3 
                                = (0x000000ffU & ((1U 
                                                   & vlSelfRef.rf_hiscore__DOT__cur_b)
                                                   ? (IData)(vlSelfRef.hs_q)
                                                   : 
                                                  ((IData)(vlSelfRef.hs_q) 
                                                   >> 8U)));
                            __VdlyDim0__rf_hiscore__DOT__shadow__v3 
                                = (0x0000003fU & ((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                                                  >> 1U));
                            __VdlySet__rf_hiscore__DOT__shadow__v3 = 1U;
                        }
                        __Vdly__rf_hiscore__DOT__hst = 5U;
                    } else {
                        __Vdly__rf_hiscore__DOT__idx 
                            = (0x000000ffU & ((IData)(1U) 
                                              + (IData)(vlSelfRef.rf_hiscore__DOT__idx)));
                    }
                } else {
                    __Vdly__rf_hiscore__DOT__rd_ph 
                        = (3U & ((IData)(1U) + (IData)(vlSelfRef.rf_hiscore__DOT__rd_ph)));
                }
                vlSelfRef.hs_addr = (0x0000ffffU & 
                                     (vlSelfRef.rf_hiscore__DOT__cur_b 
                                      >> 1U));
            }
        } else if ((2U & (IData)(vlSelfRef.rf_hiscore__DOT__hst))) {
            if ((1U & (IData)(vlSelfRef.rf_hiscore__DOT__hst))) {
                __Vfunc_rf_hiscore__DOT__lane_of__2__b 
                    = vlSelfRef.rf_hiscore__DOT__cur_b;
                __Vfunc_rf_hiscore__DOT__lane_of__2__Vfuncout 
                    = ((1U & __Vfunc_rf_hiscore__DOT__lane_of__2__b)
                        ? 1U : 2U);
                vlSelfRef.hs_addr = (0x0000ffffU & 
                                     (vlSelfRef.rf_hiscore__DOT__cur_b 
                                      >> 1U));
                vlSelfRef.hs_wdata = (0x0000ffffU & 
                                      (((IData)(vlSelfRef.rf_hiscore__DOT__sh_byte) 
                                        << 8U) | (IData)(vlSelfRef.rf_hiscore__DOT__sh_byte)));
                vlSelfRef.hs_be = __Vfunc_rf_hiscore__DOT__lane_of__2__Vfuncout;
                vlSelfRef.hs_we = 1U;
                if (((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                     == (0x000000ffU & ((IData)(vlSelfRef.rf_hiscore__DOT__total) 
                                        - (IData)(1U))))) {
                    __Vdly__rf_hiscore__DOT__inj_left 
                        = (0x000003ffU & ((IData)(vlSelfRef.rf_hiscore__DOT__inj_left) 
                                          - (IData)(1U)));
                    if ((1U == (IData)(vlSelfRef.rf_hiscore__DOT__inj_left))) {
                        __Vdly__rf_hiscore__DOT__poll_done = 1U;
                    }
                    __Vdly__rf_hiscore__DOT__hst = 5U;
                } else {
                    __Vdly__rf_hiscore__DOT__idx = 
                        (0x000000ffU & ((IData)(1U) 
                                        + (IData)(vlSelfRef.rf_hiscore__DOT__idx)));
                    vlSelfRef.rf_hiscore__DOT__sh_idx 
                        = (0x000000ffU & ((IData)(1U) 
                                          + (IData)(vlSelfRef.rf_hiscore__DOT__idx)));
                }
            } else {
                if ((2U == (IData)(vlSelfRef.rf_hiscore__DOT__rd_ph))) {
                    __Vdly__rf_hiscore__DOT__rd_ph = 0U;
                    if (((0x000000ffU & ((1U & vlSelfRef.rf_hiscore__DOT__cur_b)
                                          ? (IData)(vlSelfRef.hs_q)
                                          : ((IData)(vlSelfRef.hs_q) 
                                             >> 8U))) 
                         != vlSelfRef.rf_hiscore__DOT__gv
                         [vlSelfRef.rf_hiscore__DOT__gph])) {
                        vlSelfRef.hs_pause = 0U;
                        __Vdly__rf_hiscore__DOT__hst = 0U;
                    } else {
                        if (((IData)(vlSelfRef.rf_hiscore__DOT__sh_byte) 
                             != vlSelfRef.rf_hiscore__DOT__gv
                             [vlSelfRef.rf_hiscore__DOT__gph])) {
                            __Vdly__rf_hiscore__DOT__sh_ok = 0U;
                        }
                        if ((3U == (IData)(vlSelfRef.rf_hiscore__DOT__gph))) {
                            vlSelfRef.save_ready = 1U;
                            if ((((IData)(vlSelfRef.rf_hiscore__DOT__sh_ok) 
                                  & ((IData)(vlSelfRef.rf_hiscore__DOT__sh_byte) 
                                     == vlSelfRef.rf_hiscore__DOT__gv
                                     [vlSelfRef.rf_hiscore__DOT__gph])) 
                                 & (0U != (IData)(vlSelfRef.rf_hiscore__DOT__inj_left)))) {
                                __Vdly__rf_hiscore__DOT__idx = 0U;
                                vlSelfRef.rf_hiscore__DOT__sh_idx = 0U;
                                __Vdly__rf_hiscore__DOT__hst = 3U;
                            } else {
                                __Vdly__rf_hiscore__DOT__poll_done = 1U;
                                __Vdly__rf_hiscore__DOT__hst = 5U;
                            }
                        } else {
                            __Vdly__rf_hiscore__DOT__gph 
                                = (3U & ((IData)(1U) 
                                         + (IData)(vlSelfRef.rf_hiscore__DOT__gph)));
                            __Vfunc_rf_hiscore__DOT__guard_idx__3__g 
                                = (3U & ((IData)(1U) 
                                         + (IData)(vlSelfRef.rf_hiscore__DOT__gph)));
                            __Vfunc_rf_hiscore__DOT__guard_idx__3__Vfuncout 
                                = ((0U == (IData)(__Vfunc_rf_hiscore__DOT__guard_idx__3__g))
                                    ? 0U : (0x000000ffU 
                                            & ((1U 
                                                == (IData)(__Vfunc_rf_hiscore__DOT__guard_idx__3__g))
                                                ? (
                                                   ((1U 
                                                     == (IData)(vlSelfRef.game_id))
                                                     ? 0x7cU
                                                     : 0x40U) 
                                                   - (IData)(1U))
                                                : (
                                                   (2U 
                                                    == (IData)(__Vfunc_rf_hiscore__DOT__guard_idx__3__g))
                                                    ? 
                                                   ((1U 
                                                     == (IData)(vlSelfRef.game_id))
                                                     ? 0x7cU
                                                     : 0x40U)
                                                    : 
                                                   ((IData)(vlSelfRef.rf_hiscore__DOT__total) 
                                                    - (IData)(1U))))));
                            vlSelfRef.rf_hiscore__DOT__sh_idx 
                                = __Vfunc_rf_hiscore__DOT__guard_idx__3__Vfuncout;
                        }
                    }
                } else {
                    __Vdly__rf_hiscore__DOT__rd_ph 
                        = (3U & ((IData)(1U) + (IData)(vlSelfRef.rf_hiscore__DOT__rd_ph)));
                }
                vlSelfRef.hs_addr = (0x0000ffffU & 
                                     (vlSelfRef.rf_hiscore__DOT__cur_b 
                                      >> 1U));
            }
        } else if ((1U & (IData)(vlSelfRef.rf_hiscore__DOT__hst))) {
            __Vdly__rf_hiscore__DOT__settle = (0x000000ffU 
                                               & ((IData)(vlSelfRef.rf_hiscore__DOT__settle) 
                                                  - (IData)(1U)));
            if ((0U == (IData)(vlSelfRef.rf_hiscore__DOT__settle))) {
                __Vdly__rf_hiscore__DOT__hst = ((IData)(vlSelfRef.rf_hiscore__DOT__capturing)
                                                 ? 4U
                                                 : 2U);
            }
        } else if ((((IData)(vlSelfRef.ioctl_upload) 
                     & (~ (IData)(vlSelfRef.rf_hiscore__DOT__upload_d))) 
                    & (IData)(vlSelfRef.run))) {
            __Vdly__rf_hiscore__DOT__capturing = 1U;
            __Vdly__rf_hiscore__DOT__idx = 0U;
            vlSelfRef.rf_hiscore__DOT__cap_lo = 0U;
            vlSelfRef.hs_pause = 1U;
            __Vdly__rf_hiscore__DOT__settle = 0x40U;
            __Vdly__rf_hiscore__DOT__rd_ph = 0U;
            __Vdly__rf_hiscore__DOT__hst = 1U;
        } else if ((((IData)(vlSelfRef.run) & (~ (IData)(vlSelfRef.rf_hiscore__DOT__poll_done))) 
                    & (IData)(vlSelfRef.vbl_rise))) {
            __Vdly__rf_hiscore__DOT__capturing = 0U;
            __Vdly__rf_hiscore__DOT__gph = 0U;
            __Vdly__rf_hiscore__DOT__sh_ok = 1U;
            vlSelfRef.rf_hiscore__DOT__sh_idx = 0U;
            vlSelfRef.hs_pause = 1U;
            __Vdly__rf_hiscore__DOT__settle = 0x40U;
            __Vdly__rf_hiscore__DOT__rd_ph = 0U;
            __Vdly__rf_hiscore__DOT__hst = 1U;
        }
    }
    vlSelfRef.rf_hiscore__DOT__poll_done = __Vdly__rf_hiscore__DOT__poll_done;
    vlSelfRef.rf_hiscore__DOT__capturing = __Vdly__rf_hiscore__DOT__capturing;
    vlSelfRef.rf_hiscore__DOT__ld_pend = __Vdly__rf_hiscore__DOT__ld_pend;
    vlSelfRef.rf_hiscore__DOT__rd_ph = __Vdly__rf_hiscore__DOT__rd_ph;
    vlSelfRef.rf_hiscore__DOT__inj_left = __Vdly__rf_hiscore__DOT__inj_left;
    vlSelfRef.rf_hiscore__DOT__ld_pw = __Vdly__rf_hiscore__DOT__ld_pw;
    vlSelfRef.rf_hiscore__DOT__ld_pd = __Vdly__rf_hiscore__DOT__ld_pd;
    vlSelfRef.rf_hiscore__DOT__sh_ok = __Vdly__rf_hiscore__DOT__sh_ok;
    vlSelfRef.rf_hiscore__DOT__settle = __Vdly__rf_hiscore__DOT__settle;
    vlSelfRef.rf_hiscore__DOT__hst = __Vdly__rf_hiscore__DOT__hst;
    vlSelfRef.rf_hiscore__DOT__idx = __Vdly__rf_hiscore__DOT__idx;
    vlSelfRef.rf_hiscore__DOT__gph = __Vdly__rf_hiscore__DOT__gph;
    if (__VdlySet__rf_hiscore__DOT__shadow__v0) {
        vlSelfRef.rf_hiscore__DOT__shadow[__VdlyDim0__rf_hiscore__DOT__shadow__v0] 
            = __VdlyVal__rf_hiscore__DOT__shadow__v0;
    }
    if (__VdlySet__rf_hiscore__DOT__shadow__v1) {
        vlSelfRef.rf_hiscore__DOT__shadow[__VdlyDim0__rf_hiscore__DOT__shadow__v1] 
            = __VdlyVal__rf_hiscore__DOT__shadow__v1;
    }
    if (__VdlySet__rf_hiscore__DOT__shadow__v2) {
        vlSelfRef.rf_hiscore__DOT__shadow[__VdlyDim0__rf_hiscore__DOT__shadow__v2] 
            = __VdlyVal__rf_hiscore__DOT__shadow__v2;
    }
    if (__VdlySet__rf_hiscore__DOT__shadow__v3) {
        vlSelfRef.rf_hiscore__DOT__shadow[__VdlyDim0__rf_hiscore__DOT__shadow__v3] 
            = __VdlyVal__rf_hiscore__DOT__shadow__v3;
    }
    vlSelfRef.sv_data = vlSelfRef.rf_hiscore__DOT__sv_q;
    vlSelfRef.rf_hiscore__DOT__cur_b = (0x0001ffffU 
                                        & ((2U == (IData)(vlSelfRef.rf_hiscore__DOT__hst))
                                            ? ((0U 
                                                == (IData)(vlSelfRef.rf_hiscore__DOT__gph))
                                                ? (
                                                   (1U 
                                                    == (IData)(vlSelfRef.game_id))
                                                    ? 0x0000ce3aU
                                                    : 0x0000eff4U)
                                                : (
                                                   (1U 
                                                    == (IData)(vlSelfRef.rf_hiscore__DOT__gph))
                                                    ? 
                                                   ((((1U 
                                                       == (IData)(vlSelfRef.game_id))
                                                       ? 0x0000ce3aU
                                                       : 0x0000eff4U) 
                                                     + 
                                                     ((1U 
                                                       == (IData)(vlSelfRef.game_id))
                                                       ? 0x7cU
                                                       : 0x40U)) 
                                                    - (IData)(1U))
                                                    : 
                                                   ((2U 
                                                     == (IData)(vlSelfRef.rf_hiscore__DOT__gph))
                                                     ? 
                                                    ((1U 
                                                      == (IData)(vlSelfRef.game_id))
                                                      ? 0x0000ce3cU
                                                      : 0x000022faU)
                                                     : 
                                                    ((((1U 
                                                        == (IData)(vlSelfRef.game_id))
                                                        ? 0x0000ce3cU
                                                        : 0x000022faU) 
                                                      + 
                                                      ((1U 
                                                        == (IData)(vlSelfRef.game_id))
                                                        ? 1U
                                                        : 4U)) 
                                                     - (IData)(1U)))))
                                            : (((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                                                < (
                                                   (1U 
                                                    == (IData)(vlSelfRef.game_id))
                                                    ? 0x7cU
                                                    : 0x40U))
                                                ? (
                                                   ((1U 
                                                     == (IData)(vlSelfRef.game_id))
                                                     ? 0x0000ce3aU
                                                     : 0x0000eff4U) 
                                                   + (IData)(vlSelfRef.rf_hiscore__DOT__idx))
                                                : (
                                                   ((1U 
                                                     == (IData)(vlSelfRef.game_id))
                                                     ? 0x0000ce3cU
                                                     : 0x000022faU) 
                                                   + 
                                                   ((IData)(vlSelfRef.rf_hiscore__DOT__idx) 
                                                    - 
                                                    ((1U 
                                                      == (IData)(vlSelfRef.game_id))
                                                      ? 0x7cU
                                                      : 0x40U))))));
    vlSelfRef.rf_hiscore__DOT__upload_d = vlSelfRef.ioctl_upload;
    vlSelfRef.rf_hiscore__DOT__sh_byte = (0x000000ffU 
                                          & ((1U & (IData)(vlSelfRef.rf_hiscore__DOT__sh_idx))
                                              ? (vlSelfRef.rf_hiscore__DOT__shadow
                                                 [(0x0000003fU 
                                                   & ((IData)(vlSelfRef.rf_hiscore__DOT__sh_idx) 
                                                      >> 1U))] 
                                                 >> 8U)
                                              : vlSelfRef.rf_hiscore__DOT__shadow
                                             [(0x0000003fU 
                                               & ((IData)(vlSelfRef.rf_hiscore__DOT__sh_idx) 
                                                  >> 1U))]));
}

void Vrf_hiscore___024root___trigger_orInto__act_vec_vec(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___trigger_orInto__act_vec_vec\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((0U >= n));
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrf_hiscore___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool Vrf_hiscore___024root___eval_phase__act(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_phase__act\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    {
        // Inlined CFunc: _eval_triggers_vec__act
        vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                        ((IData)(vlSelfRef.clk) 
                                                         & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__1)))));
        vlSelfRef.__Vtrigprevexpr___TOP__clk__1 = vlSelfRef.clk;
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vrf_hiscore___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
    Vrf_hiscore___024root___trigger_orInto__act_vec_vec(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vrf_hiscore___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vrf_hiscore___024root___eval_phase__nba(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_phase__nba\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vrf_hiscore___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        {
            // Inlined CFunc: _eval_nba
            if ((1ULL & vlSelfRef.__VnbaTriggered[0U])) {
                Vrf_hiscore___024root___nba_sequent__TOP__0(vlSelf);
            }
        }
        Vrf_hiscore___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vrf_hiscore___024root___eval(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VicoIterCount;
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VicoIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00002710U < __VicoIterCount)))) {
#ifdef VL_DEBUG
            Vrf_hiscore___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
#endif
            VL_FATAL_MT("../rtl/rf_hiscore.sv", 50, "", "DIDNOTCONVERGE: Input combinational region did not converge after '--converge-limit' of 10000 tries");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
        vlSelfRef.__VicoPhaseResult = Vrf_hiscore___024root___eval_phase__ico(vlSelf);
    } while (vlSelfRef.__VicoPhaseResult);
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00002710U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vrf_hiscore___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("../rtl/rf_hiscore.sv", 50, "", "DIDNOTCONVERGE: NBA region did not converge after '--converge-limit' of 10000 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00002710U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vrf_hiscore___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("../rtl/rf_hiscore.sv", 50, "", "DIDNOTCONVERGE: Active region did not converge after '--converge-limit' of 10000 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
            vlSelfRef.__VactPhaseResult = Vrf_hiscore___024root___eval_phase__act(vlSelf);
        } while (vlSelfRef.__VactPhaseResult);
        vlSelfRef.__VnbaPhaseResult = Vrf_hiscore___024root___eval_phase__nba(vlSelf);
    } while (vlSelfRef.__VnbaPhaseResult);
}

#ifdef VL_DEBUG
void Vrf_hiscore___024root___eval_debug_assertions(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_debug_assertions\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.reset & 0xfeU)))) {
        Verilated::overWidthError("reset");
    }
    if (VL_UNLIKELY(((vlSelfRef.game_id & 0xfcU)))) {
        Verilated::overWidthError("game_id");
    }
    if (VL_UNLIKELY(((vlSelfRef.run & 0xfeU)))) {
        Verilated::overWidthError("run");
    }
    if (VL_UNLIKELY(((vlSelfRef.vbl_rise & 0xfeU)))) {
        Verilated::overWidthError("vbl_rise");
    }
    if (VL_UNLIKELY(((vlSelfRef.ld_wr & 0xfeU)))) {
        Verilated::overWidthError("ld_wr");
    }
    if (VL_UNLIKELY(((vlSelfRef.ld_word & 0xc0U)))) {
        Verilated::overWidthError("ld_word");
    }
    if (VL_UNLIKELY(((vlSelfRef.sv_word & 0xc0U)))) {
        Verilated::overWidthError("sv_word");
    }
    if (VL_UNLIKELY(((vlSelfRef.ioctl_upload & 0xfeU)))) {
        Verilated::overWidthError("ioctl_upload");
    }
}
#endif  // VL_DEBUG
