// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vrf_hiscore.h for the primary calling header

#include "Vrf_hiscore__pch.h"

VL_ATTR_COLD void Vrf_hiscore___024root___eval_static(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_static\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
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
    vlSelfRef.__Vtrigprevexpr___TOP__clk__1 = vlSelfRef.clk;
}

VL_ATTR_COLD void Vrf_hiscore___024root___eval_initial(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_initial\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vrf_hiscore___024root___eval_final(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_final\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrf_hiscore___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vrf_hiscore___024root___eval_phase__stl(Vrf_hiscore___024root* vlSelf);

VL_ATTR_COLD void Vrf_hiscore___024root___eval_settle(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_settle\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00002710U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vrf_hiscore___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("../rtl/rf_hiscore.sv", 50, "", "DIDNOTCONVERGE: Settle region did not converge after '--converge-limit' of 10000 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        vlSelfRef.__VstlPhaseResult = Vrf_hiscore___024root___eval_phase__stl(vlSelf);
        vlSelfRef.__VstlFirstIteration = 0U;
    } while (vlSelfRef.__VstlPhaseResult);
}

VL_ATTR_COLD bool Vrf_hiscore___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrf_hiscore___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vrf_hiscore___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vrf_hiscore___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___trigger_anySet__stl\n"); );
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

VL_ATTR_COLD bool Vrf_hiscore___024root___eval_phase__stl(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___eval_phase__stl\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    {
        // Inlined CFunc: _eval_triggers_vec__stl
        vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                          & vlSelfRef.__VstlTriggered[0U]) 
                                         | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vrf_hiscore___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
    __VstlExecute = Vrf_hiscore___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        {
            // Inlined CFunc: _eval_stl
            if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
                {
                    // Inlined CFunc: _stl_sequent__TOP__0
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
                    vlSelfRef.sv_data = vlSelfRef.rf_hiscore__DOT__sv_q;
                    vlSelfRef.rf_hiscore__DOT__sh_byte 
                        = (0x000000ffU & ((1U & (IData)(vlSelfRef.rf_hiscore__DOT__sh_idx))
                                           ? (vlSelfRef.rf_hiscore__DOT__shadow
                                              [(0x0000003fU 
                                                & ((IData)(vlSelfRef.rf_hiscore__DOT__sh_idx) 
                                                   >> 1U))] 
                                              >> 8U)
                                           : vlSelfRef.rf_hiscore__DOT__shadow
                                          [(0x0000003fU 
                                            & ((IData)(vlSelfRef.rf_hiscore__DOT__sh_idx) 
                                               >> 1U))]));
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
    return (__VstlExecute);
}

bool Vrf_hiscore___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 2> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrf_hiscore___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 2> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ (IData)(Vrf_hiscore___024root___trigger_anySet__ico(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @( clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @( reset)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 2U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 2 is active: @( game_id)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 3U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 3 is active: @( run)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 4U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 4 is active: @( vbl_rise)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 5U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 5 is active: @( ld_wr)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 6U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 6 is active: @( ld_word)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 7U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 7 is active: @( ld_data)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 8U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 8 is active: @( sv_word)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 9U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 9 is active: @( ioctl_upload)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 0x0000000aU)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 10 is active: @( hs_q)\n");
    }
    if ((1U & (IData)(triggers[1U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 64 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

bool Vrf_hiscore___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrf_hiscore___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vrf_hiscore___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vrf_hiscore___024root___ctor_var_reset(Vrf_hiscore___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrf_hiscore___024root___ctor_var_reset\n"); );
    Vrf_hiscore__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->reset = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9928399931838511862ull);
    vlSelf->game_id = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 6678011599430058016ull);
    vlSelf->run = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13300848193037734645ull);
    vlSelf->vbl_rise = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16044695573093704522ull);
    vlSelf->ld_wr = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7198313328865192981ull);
    vlSelf->ld_word = VL_SCOPED_RAND_RESET_I(6, __VscopeHash, 14951366609021296922ull);
    vlSelf->ld_data = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 434205969899107805ull);
    vlSelf->sv_word = VL_SCOPED_RAND_RESET_I(6, __VscopeHash, 10006013162265618410ull);
    vlSelf->sv_data = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 15760176952386534357ull);
    vlSelf->ioctl_upload = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5131890115284243544ull);
    vlSelf->hs_pause = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5345034027745920948ull);
    vlSelf->hs_addr = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 9693263547362087676ull);
    vlSelf->hs_wdata = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 3859472251075413568ull);
    vlSelf->hs_be = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 13884560964592304707ull);
    vlSelf->hs_we = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16560107816316505177ull);
    vlSelf->hs_q = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 15029252714400468127ull);
    vlSelf->save_ready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2889306492566467124ull);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->rf_hiscore__DOT__gv[__Vi0] = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 12209537256144053631ull);
    }
    vlSelf->rf_hiscore__DOT__total = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 6722920411862239912ull);
    for (int __Vi0 = 0; __Vi0 < 64; ++__Vi0) {
        vlSelf->rf_hiscore__DOT__shadow[__Vi0] = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 4293441190640409387ull);
    }
    vlSelf->rf_hiscore__DOT__ld_pend = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17954585125666012493ull);
    vlSelf->rf_hiscore__DOT__ld_pw = VL_SCOPED_RAND_RESET_I(6, __VscopeHash, 14620957061590099576ull);
    vlSelf->rf_hiscore__DOT__ld_pd = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 6685290191768375564ull);
    vlSelf->rf_hiscore__DOT__sv_q = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 12754811701364864250ull);
    vlSelf->rf_hiscore__DOT__sh_idx = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 18363893015304587758ull);
    vlSelf->rf_hiscore__DOT__sh_byte = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 2099775375144653675ull);
    vlSelf->rf_hiscore__DOT__hst = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 5558038945115471654ull);
    vlSelf->rf_hiscore__DOT__poll_done = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 8794109520743523033ull);
    vlSelf->rf_hiscore__DOT__inj_left = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 17153091176823437888ull);
    vlSelf->rf_hiscore__DOT__capturing = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14423091434172742952ull);
    vlSelf->rf_hiscore__DOT__sh_ok = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15356177182025684222ull);
    vlSelf->rf_hiscore__DOT__idx = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 357953266835107652ull);
    vlSelf->rf_hiscore__DOT__gph = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 5242494002638954000ull);
    vlSelf->rf_hiscore__DOT__settle = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 15349895183697392276ull);
    vlSelf->rf_hiscore__DOT__rd_ph = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 15266986500063378221ull);
    vlSelf->rf_hiscore__DOT__upload_d = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2215141177275489436ull);
    vlSelf->rf_hiscore__DOT__cap_lo = VL_SCOPED_RAND_RESET_I(16, __VscopeHash, 15785065389876890197ull);
    vlSelf->rf_hiscore__DOT__cur_b = VL_SCOPED_RAND_RESET_I(17, __VscopeHash, 11502177935742206694ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 2; ++__Vi0) {
        vlSelf->__VicoTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__reset__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__game_id__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__run__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__vbl_rise__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__ld_wr__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__ld_word__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__ld_data__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__sv_word__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__ioctl_upload__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__hs_q__0 = 0;
    vlSelf->__VicoDidInit = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__1 = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
}
