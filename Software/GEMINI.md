# BitNet b1.58 SystemVerilog Hardware Co-Design

## Purpose
This project provides the PyTorch Quantization-Aware Training (QAT) model and the weight packing compiler needed to test a SystemVerilog hardware accelerator custom designed for the BitNet b1.58 architecture. 

## Stack
- Framework: PyTorch, torchvision
- Processing: numpy
- Hardware Focus: Ternary weights {-1, 0, 1}, 8-bit activations

## Usage
1. First, set up your Python environment with the required dependencies:
   `pip install torch torchvision numpy`
2. Run the MLP training script for the QAT model:
   `python bitnet_mnist.py`
3. Upon success, this will generate `bitnet_mnist.pth`. Then run the packer:
   `python weight_packer.py`
4. The output `packed_weights.bin` can now be loaded via your FPGA's AXI DMA.
