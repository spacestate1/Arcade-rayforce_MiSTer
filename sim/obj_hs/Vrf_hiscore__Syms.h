// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VRF_HISCORE__SYMS_H_
#define VERILATED_VRF_HISCORE__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vrf_hiscore.h"

// INCLUDE MODULE CLASSES
#include "Vrf_hiscore___024root.h"

// DPI TYPES for DPI Export callbacks (Internal use)

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vrf_hiscore__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vrf_hiscore* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vrf_hiscore___024root          TOP;

    // CONSTRUCTORS
    Vrf_hiscore__Syms(VerilatedContext* contextp, const char* namep, Vrf_hiscore* modelp);
    ~Vrf_hiscore__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
