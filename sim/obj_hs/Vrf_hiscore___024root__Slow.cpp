// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vrf_hiscore.h for the primary calling header

#include "Vrf_hiscore__pch.h"

void Vrf_hiscore___024root___ctor_var_reset(Vrf_hiscore___024root* vlSelf);

Vrf_hiscore___024root::Vrf_hiscore___024root(Vrf_hiscore__Syms* symsp, const char* namep)
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    Vrf_hiscore___024root___ctor_var_reset(this);
}

void Vrf_hiscore___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vrf_hiscore___024root::~Vrf_hiscore___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
