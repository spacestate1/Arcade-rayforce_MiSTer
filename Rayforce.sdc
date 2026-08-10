derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
#
# clk_ram (96 MHz) and clk_sys (64 MHz) both come off the same PLL, so they are
# phase-related, not asynchronous -- there is no metastability to synchronise
# away, and TimeQuest analyses every crossing between them. But 96/64 is a 3:2
# ratio, and the two clocks only realign every 31.25 ns:
#
#   clk_sys edges   0        15.625            31.25 ns
#   clk_ram edges   0   10.416      20.833     31.25 ns
#
# so the tightest launch-to-capture pair is 15.625 -> 20.833, just 5.2 ns. That
# is half the clk_ram period, and constraining the SDRAM interface to it is both
# unachievable and unnecessary: nothing on this crossing is a single-cycle
# transfer. The req/ready protocol holds every address and data word stable for
# the whole transaction, and Raiden2.sv widens both directions' pulses so each
# is longer than the window relaxed below -- requests are two clk_sys cycles
# (31.25 ns), readys two clk_ram cycles (20.8 ns).
#
# Relaxing setup by one destination cycle therefore describes the hardware
# honestly rather than hiding a real violation. Hold moves with it, which is the
# standard pairing: without -hold 1 the analyser would check hold against the
# newly-relaxed capture edge and demand a hold time a full cycle too large.
#
# If clk_ram ever returns to an integer multiple of clk_sys these exceptions
# become harmless no-ops rather than wrong -- the tight edge pairs simply stop
# existing.

set clk_ram {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set clk_sys {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}

if {[llength [get_clocks -nowarn $clk_ram]] && [llength [get_clocks -nowarn $clk_sys]]} {
    set_multicycle_path -setup 2 -from [get_clocks $clk_sys] -to [get_clocks $clk_ram]
    set_multicycle_path -hold  1 -from [get_clocks $clk_sys] -to [get_clocks $clk_ram]

    set_multicycle_path -setup 2 -from [get_clocks $clk_ram] -to [get_clocks $clk_sys]
    set_multicycle_path -hold  1 -from [get_clocks $clk_ram] -to [get_clocks $clk_sys]
} else {
    post_message -type critical_warning \
        "Raiden2.sdc: PLL clock names not found -- SDRAM crossing is UNCONSTRAINED"
}
