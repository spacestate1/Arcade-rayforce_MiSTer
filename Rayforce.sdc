derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
#
# clk_ram (97.04 MHz, PLL outclk_0) and clk_sys (53.372 MHz, outclk_1) come
# off the same PLL but are not commensurate, and every cpu<->ram crossing is
# a held level, a toggle through 2FF/3FF, or data stable until acknowledged
# (rf_prog_bus, the download loader). Declaring the pair asynchronous states
# the design rather than hiding a violation -- the raiden-inherited
# multicycle exceptions legalized skew INSIDE 2FF synchronizer chains and
# killed handshakes on silicon (Propcycle, 2026-08-11).
set_clock_groups -asynchronous \
    -group [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -group [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]

# ---------------------------------------------------------------------------
# TG68K advances only on clkena_in, driven as a gated pulse by rf_cpu_spike:
# every kernel register is enable-gated, so a path that both launches from
# and lands in a kernel register has two full clk_sys cycles by construction.
# Declaring that is describing the hardware, not hiding a violation. Paths
# INTO the kernel and out of it into the capture registers stay single-cycle.
set_multicycle_path -setup 2 \
    -from [get_registers {*TG68KdotC_Kernel*}] \
    -to   [get_registers {*TG68KdotC_Kernel*}]
set_multicycle_path -hold 1 \
    -from [get_registers {*TG68KdotC_Kernel*}] \
    -to   [get_registers {*TG68KdotC_Kernel*}]
