# BitNet b1.58 Hardware Accelerator
A Ternary (1.58-bit) LLM Inference Engine for Xilinx Zynq UltraScale+ FPGAs.

## 🚀 Overview
This project implements a hardware-accelerated inference engine for BitNet b1.58, a ternary Large Language Model (LLM) architecture. Unlike standard neural networks that use FP16 or INT8, BitNet b1.58 restricts weights to {-1, 0, 1}.

By leveraging this ternary logic, this accelerator replaces power-hungry floating-point multiplications with simple additions and subtractions, drastically reducing power consumption and silicon area while maintaining LLM performance.

## 🏗️ Architecture
The system is designed as a custom IP core integrated into a Xilinx Zynq UltraScale+ MPSoC environment.

### Core Components:
* **Ternary Systolic Array:** A high-performance compute fabric designed specifically for ternary weight decoding and accumulation.
* **Weight Decoder:** On-the-fly unpacking of compressed 1.58-bit weights from system memory.
* **RMSNorm & SiLU Pipeline:** Hardware-optimized normalization and activation layers implemented in SystemVerilog.
* **AXI4-Stream Interface:** Full protocol compliance for high-speed data movement.
* **AXI DMA Integration:** Uses Direct Memory Access to stream weights and activations from DDR4 to the PL (Programmable Logic) without CPU overhead.

## 🛠️ Technical Specifications
* **FPGA Part:** Xilinx Zynq UltraScale+ (xczu7ev-ffvc1156-2-e)
* **Clock Frequency:** 100 MHz (Synchronized PL Fabric Clock)
* **Data Widths:** 
  * **Activations:** 128-bit AXI-Stream
  * **Weights:** 104-bit packed ternary
  * **Output:** 16-bit SiLU-activated results
* **Interface:** AXI4-Stream (Master/Slave) with TLAST-based packet boundary detection.

## 📂 Project Structure
```plaintext
├── src/                        # SystemVerilog Source Files
│   ├── ternary_accelerator_top.sv  # Top-level Accelerator logic
│   ├── systolic_array.sv       # Ternary compute fabric
│   ├── rmsnorm.sv              # RMS Normalization module
│   ├── silu_activation.sv      # SiLU Activation module
│   └── weight_decoder.sv       # 1.58-bit Weight Unpacker
├── wrapper/                    # Verilog HDL Wrappers for Vivado
├── constraints/                # XDC Timing and IO Constraints
└── vivado/                     # Project scripts and Block Design exports
```

## ⚡ Getting Started
### Prerequisites
* Xilinx Vivado 2025.2 (or newer)
* Target Board: Zynq UltraScale+ ZCU102 or similar MPSoC.

### Build Instructions
1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/BitNet-FPGA-Accelerator.git
   ```
2. Open Vivado and create a new project using the `xczu7ev` part.
3. Add the files in `/src` and `/wrapper` to the project.
4. Set `bitnet_bd_wrapper` as the Top module.
5. In the IP Integrator, use the Module Reference flow to add the `ternary_accelerator_wrapper`.
6. Connect the AXI DMA and Zynq UltraScale+ PS as per the provided system topology.
7. Run Synthesis, Implementation, and Generate Bitstream.

## 📝 Lessons Learned (Troubleshooting)
During development, several SoC integration hurdles were overcome:

* **TLAST Handshaking:** Ensured the AXI-Stream Master correctly asserts TLAST to prevent DMA hang-ups during memory-to-stream transfers.
* **IP Cache Management:** Resolved `[Synth 8-11365]` errors by clearing stale IP cache stubs during Zynq PS re-configurations.
* **Module Reference Flow:** Utilized the Module Reference flow instead of the standard IP Packager to allow for more agile SystemVerilog RTL iterations.

## 🤝 Acknowledgements
* Inspired by the Microsoft Research BitNet b1.58 paper.
* Built as part of a Computer Engineering research project into low-power AI architectures.

## 📬 Contact
If you're interested in Ternary computing or FPGA-based LLM acceleration, feel free to reach out or open an issue!
