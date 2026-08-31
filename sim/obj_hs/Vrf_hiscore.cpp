// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vrf_hiscore__pch.h"

//============================================================
// Constructors

Vrf_hiscore::Vrf_hiscore(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vrf_hiscore__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , reset{vlSymsp->TOP.reset}
    , game_id{vlSymsp->TOP.game_id}
    , run{vlSymsp->TOP.run}
    , vbl_rise{vlSymsp->TOP.vbl_rise}
    , ld_wr{vlSymsp->TOP.ld_wr}
    , ld_word{vlSymsp->TOP.ld_word}
    , sv_word{vlSymsp->TOP.sv_word}
    , ioctl_upload{vlSymsp->TOP.ioctl_upload}
    , hs_pause{vlSymsp->TOP.hs_pause}
    , hs_be{vlSymsp->TOP.hs_be}
    , hs_we{vlSymsp->TOP.hs_we}
    , save_ready{vlSymsp->TOP.save_ready}
    , ld_data{vlSymsp->TOP.ld_data}
    , sv_data{vlSymsp->TOP.sv_data}
    , hs_addr{vlSymsp->TOP.hs_addr}
    , hs_wdata{vlSymsp->TOP.hs_wdata}
    , hs_q{vlSymsp->TOP.hs_q}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vrf_hiscore::Vrf_hiscore(const char* _vcname__)
    : Vrf_hiscore(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vrf_hiscore::~Vrf_hiscore() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vrf_hiscore___024root___eval_debug_assertions(Vrf_hiscore___024root* vlSelf);
#endif  // VL_DEBUG
void Vrf_hiscore___024root___eval_static(Vrf_hiscore___024root* vlSelf);
void Vrf_hiscore___024root___eval_initial(Vrf_hiscore___024root* vlSelf);
void Vrf_hiscore___024root___eval_settle(Vrf_hiscore___024root* vlSelf);
void Vrf_hiscore___024root___eval(Vrf_hiscore___024root* vlSelf);

void Vrf_hiscore::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vrf_hiscore::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vrf_hiscore___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vrf_hiscore___024root___eval_static(&(vlSymsp->TOP));
        Vrf_hiscore___024root___eval_initial(&(vlSymsp->TOP));
        Vrf_hiscore___024root___eval_settle(&(vlSymsp->TOP));
        vlSymsp->__Vm_didInit = true;
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vrf_hiscore___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vrf_hiscore::eventsPending() { return false; }

uint64_t Vrf_hiscore::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vrf_hiscore::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vrf_hiscore___024root___eval_final(Vrf_hiscore___024root* vlSelf);

VL_ATTR_COLD void Vrf_hiscore::final() {
    contextp()->executingFinal(true);
    Vrf_hiscore___024root___eval_final(&(vlSymsp->TOP));
    contextp()->executingFinal(false);
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vrf_hiscore::hierName() const { return vlSymsp->name(); }
const char* Vrf_hiscore::modelName() const { return "Vrf_hiscore"; }
unsigned Vrf_hiscore::threads() const { return 1; }
void Vrf_hiscore::prepareClone() const { contextp()->prepareClone(); }
void Vrf_hiscore::atClone() const {
    contextp()->threadPoolpOnClone();
}
