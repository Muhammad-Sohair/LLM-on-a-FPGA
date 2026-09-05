# BitNet b1.58 Hardware Accelerator
A ternary (1.58-bit) LLM inference engine for the Xilinx Zynq-7000 SoC — **validated on real silicon**.

## 🚀 Overview
This project implements a hardware-accelerated inference engine for BitNet b1.58, a ternary Large Language Model architecture. Unlike standard neural networks that use FP16 or INT8, BitNet b1.58 restricts weights to {-1, 0, 1}.

By leveraging this ternary logic, the accelerator replaces power-hungry multiplications with additions and subtractions. The whole 512×512 matmul engine consumes **2 DSP slices out of 220** — the arithmetic is essentially free, and the cost moves to memory bandwidth instead.

The target is a **Digilent/Avnet ZedBoard (Zynq-7000 `xc7z020clg484-1`)** — a deliberately constrained 7-series part, chosen to show that ternary LLM inference is viable on low-cost hardware rather than only on large MPSoC devices.

## ✅ Status — running on hardware
* **Timing closed:** post-implementation **WNS +0.111 ns @ 100 MHz**, 0 failing endpoints out of 77,618, all user timing constraints met.
* **Bit-exact:** the on-board self-check reports `PASS: hardware matches reference on all 512 outputs` over UART, matching the C/Python reference model exactly.
* **Throughput:** a 512×512 `COMPUTE`+`DRAIN` takes **77,349 cycles** (0.77 ms @ 100 MHz) with the weight fetch pipelined to 1 byte/cycle — down from 183,321 cycles before pipelining.
* **Two models run on it end to end:** a character-level LM, and a **BPE + self-attention Transformer** (~10.5M params, TinyStories) that generates coherent prose over the serial console.

## 🏗️ Architecture
A custom AXI peripheral in the PL, driven bare-metal by the Zynq PS.

### Core components
* **Ternary systolic array** (`ternary_systolic_array.sv`, `ternary_pe.sv`) — the compute fabric; ternary weights select add / subtract / skip instead of multiplying.
* **Weight decoder** (`weight_decoder.sv`) — unpacks base-3 packed weights (5 ternary values per byte) on the fly.
* **Weight buffer** (`weight_buffer.sv`) — dual-port BRAM tile store with a look-ahead read pipeline sustaining **1 byte/cycle**.
* **RMSNorm & SiLU pipeline** (`rmsnorm.sv`, `silu_activation.sv`) — fixed-point normalization and a LUT-based activation (`silu_lut.mem`).
* **AXI wrapper** (`bitnet_axi_wrapper.v`) — Verilog-2001 top holding the control FSM, an **AXI4-Lite** register file, and the AXI4-Stream data path.

### System integration
* **Control:** AXI4-Lite slave at base `0x4000_0000` on the PS `M_AXI_GP0` port.
* **Data:** AXI DMA over `S_AXI_HP0`, streaming tiles from PS DDR3 to the PL with no CPU involvement.
* **Width bridge:** AXI DMA 7.1 ties its stream width to the 32-bit memory-map side, but the accelerator streams **8-bit**. Two `axis_dwidth_converter` cores (32→8 in, 8→32 out) bridge them, with `TLAST`/`TKEEP` enabled and transfer sizes kept a multiple of 4.
* **Op-modes:** mode 0 applies `SiLU(RMSNorm16(·))` in hardware (the char-LM path); mode 1 is a "clean" requantized matmul (`sat8(acc >>> req_shift)`) used by the Transformer, selected via an `OPMODE` register at offset `0x30`.

### HW/SW split (Transformer)
Config: `vocab=2048` (byte-level BPE) · `ctx=128` · `d_model=512` · 4 layers · 8 heads · `d_ff=1024`.

| Runs on the PL (ternary) | Runs on the ARM Cortex-A9 |
| --- | --- |
| Q, K, V, O projections | Residual stream, RMSNorm, RoPE |
| FFN up / down (SW-tiled to 512×512 blocks) | Attention scores, softmax, KV-cache |
| | FFN SiLU, int8 LM head, temperature/top-k sampling |

The output head is **int8, not ternary, deliberately** — the hidden layers are each followed by a scale-invariant RMSNorm so only the weight signs matter, but the head feeds the sampler directly and a ternary head is too weak to preserve softmax ordering.

## 🛠️ Technical specifications
* **FPGA part:** Xilinx Zynq-7000 `xc7z020clg484-1` (ZedBoard)
* **PS:** dual-core ARM Cortex-A9 @ 666.66 MHz, 512 MB DDR3 (`MT41J128M16 HA-15E`, 32-bit, 533.33 MHz)
* **Clock:** single 100 MHz PL domain from `FCLK_CLK0`, one BUFG, `proc_sys_reset`
* **Interfaces:** AXI4-Lite (control) + AXI4-Stream master/slave with `TLAST` packet boundaries
* **Console:** UART1 on MIO 48/49 @ 115200

### Post-implementation utilization (full block design, not just the core)

| Resource | Used | Available | Util |
| --- | ---: | ---: | ---: |
| Slice LUTs | 30,252 | 53,200 | 56.9% |
| Slice registers | 33,791 | 106,400 | 31.8% |
| Block RAM tiles | 38 | 140 | 27.1% |
| DSP slices | **2** | 220 | **0.9%** |

## 📂 Project structure
```plaintext
├── src/                          # Synthesizable RTL — one module per file
│   ├── bitnet_axi_wrapper.v      # Verilog-2001 top: FSM + AXI-Lite regs + AXI-Stream
│   ├── ternary_systolic_array.sv # Ternary compute fabric
│   ├── ternary_pe.sv             # Processing element
│   ├── weight_decoder.sv         # Base-3 packed-weight unpacker
│   ├── weight_buffer.sv          # BRAM tile store, 1 byte/cycle read pipeline
│   ├── rmsnorm.sv                # Fixed-point RMS normalization
│   ├── silu_activation.sv        # LUT-based SiLU
│   └── silu_lut.mem              # Generated activation LUT
├── sim/                          # Self-checking xsim testbenches
│   └── tb_bitnet_axi_wrapper.sv  # Integration regression guard (AXI-Lite BFM + streams)
├── app_src/                      # Bare-metal C: driver, reference model, demo apps
├── scripts/                      # build.tcl, export_xsa.tcl, jtag_*.tcl, zedboard.xdc,
│                                 # Vitis/board PowerShell drivers, model exporters
└── output/                       # bitnet_zedboard.{bit,hwh}, bitnet.xsa
```
Constraints live in `scripts/zedboard.xdc`. The design is entirely PS-clocked with no PL top-level I/O, so the XDC does **not** `create_clock` — the PS7 supplies FCLK timing.

## ⚡ Getting started
### Prerequisites
* Xilinx **Vivado + Vitis 2025.2**
* A ZedBoard (`xc7z020clg484-1`) and a JTAG cable. No ZedBoard board files are required — the PS7 is configured explicitly in `scripts/build.tcl`.
* A serial terminal on the ZedBoard USB-UART @ 115200.

### Build
```bash
git clone https://github.com/Muhammad-Sohair/LLM-on-a-FPGA.git
cd LLM-on-a-FPGA

# 1. PL: block design, synthesis, implementation, bitstream  (~30 min)
vivado -mode batch -source scripts/build.tcl
#    BD-only sanity check (validate, no synth):
#    vivado -mode batch -source scripts/build.tcl -tclargs bd

# 2. Hardware handoff for Vitis
vivado -mode batch -source scripts/export_xsa.tcl        # -> output/bitnet.xsa

# 3. Bare-metal software
powershell -File scripts/build_app_empyro.ps1            # -> bitnet_app.elf
```
`build.tcl` only *warns* on negative WNS — read the post-implementation WNS in the log rather than trusting the exit status.

### Deployment
The flow is **bare-metal over JTAG** — no SD card image, PYNQ, or Petalinux needed. `ps7_init.tcl` handles PS bring-up, so no FSBL is required either.

```bash
# Optional smoke test: program the PL and read the VERSION register (expect 0x00010000)
xsdb scripts/jtag_smoke.tcl

# Program, download the ELF, run, and capture the UART console
powershell -File scripts/run_on_board.ps1
```
On some hosts a standalone `xsdb` cannot see the Digilent cable. In that case open the target in the Vivado Hardware Manager (Auto Connect) and leave it open, then attach to its `hw_server`:
```bash
powershell -File scripts/run_on_board.ps1 -Tcl scripts/jtag_run_attach.tcl -Seconds 240
```

### Simulation
Per-module self-checking testbenches run under `xsim`. `tb_bitnet_axi_wrapper.sv` is the integration regression guard and covers both op-modes — run it after any change to the wrapper, before re-synthesizing.
```bash
xvlog -sv src/weight_buffer.sv src/weight_decoder.sv src/ternary_pe.sv \
          src/ternary_systolic_array.sv src/rmsnorm.sv src/silu_activation.sv
xvlog src/bitnet_axi_wrapper.v
xvlog -sv sim/tb_bitnet_axi_wrapper.sv
xelab tb_bitnet_axi_wrapper -s tb_w
xsim tb_w -R                                # silu_lut.mem must be in the working directory
```

## 📝 Lessons learned
Each of these cost a real debug cycle and is documented so it doesn't cost another one.

* **Registered BRAM reads are one cycle late.** `weight_buffer.sv` Port B latches `rd_data` the cycle *after* the address is presented. An FSM that samples in the same cycle gets stale data — corrupted weights, wrong results, and neither synthesis nor timing analysis will flag it. Only the integration testbench caught it. The fix is a look-ahead pipeline that issues the next address every cycle and captures the previous one.
* **A default PS7 configuration will not run code from DDR.** Without the correct DDR3 part number, bus width, and timing, the application takes a data abort and there is no UART console at all. The PS7 must be configured for the actual board, not left on defaults.
* **AXI DMA has no independent stream width.** Its stream width follows the 32-bit memory-map side, so an 8-bit accelerator needs explicit `axis_dwidth_converter` cores on both directions with `TLAST`/`TKEEP` enabled.
* **TLAST handshaking:** the stream master must assert `TLAST` on the final beat or the DMA's S2MM channel never completes and the transfer hangs.
* **32-bit `long` on ARM32.** The fixed-point reference model must use `int64_t` — the sum-of-squares inside RMSNorm overflows 32 bits, so host and target silently disagree unless the widths are pinned.
* **Verification is a host parity harness, not just simulation.** One shared C forward pass is compiled for both the board and the host, so the only difference is the matmul backend. That harness caught an embedding-quantization scale bug *before* it reached hardware, where it would have looked like a vague accuracy regression.

## 🤝 Acknowledgements
* Inspired by the Microsoft Research BitNet b1.58 paper.
* Built as part of a Computer Engineering research project into low-power AI architectures, co-supervised at NED University's ESCV Lab.

## 📬 Contact
If you're interested in ternary computing or FPGA-based LLM acceleration, feel free to reach out or open an issue.
