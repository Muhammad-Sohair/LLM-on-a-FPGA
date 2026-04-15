# SystemVerilog BitNet b1.58 Accelerator - Software Prototyping

## Completed Tasks
- **Quantization Logic Implementation:** Successfully constructed a custom PyTorch QAT module using Straight-Through Estimators (STE). The model trained as expected albeit with lower accuracy on standard initialization given severe 1.58-bit bottlenecks on a shallow MLP.
- **Hardware Compiler implementation:** Successfully generated the base-3 bit packing algorithm that remans ternary values {-1, 0, 1} to integers {0, 1, 2}. The padded logic functions correctly formatting memory transfers to FPGA limits.

## Key Takeaways
- Bias logic in the `BitLinear` matrix must be treated critically: I've opted to exclude biases from the `packed_weights.bin` out stream as they were not defined as ternary in the hardware specification. If the hardware needs integer biases streamed dynamically over AXI alongside these chunk-packed bytes, we'll need to expand the compiler.
- Due to the nature of 5-weight packing in an 8-bit `uint8`, a zero offset was applied when calculating `val_5 = len % 5` paddings. Since `0` equates to actual ternary `0`, this is computationally safe for padding dot-product accumulation architectures.
