import torch
import numpy as np
import os

def main():
    model_path = 'bitnet_mnist.pth'
    if not os.path.exists(model_path):
        print(f"Error: {model_path} not found.")
        print("Please run `python bitnet_mnist.py` first to generate the weights.")
        return
        
    print(f"Loading weights from {model_path}...")
    state_dict = torch.load(model_path, map_location='cpu', weights_only=True)
    
    ternary_weights = []
    
    print("\nExtracting and strictly quantizing BitLinear weight tensors...")
    for name, tensor in state_dict.items():
        # Only process actual weights, disregarding bias vectors since they weren't defined as ternary in hardware
        if name.endswith('.weight'):
            print(f"  -> Quantizing {name} with shape {list(tensor.shape)}")
            
            # 1. Forward-pass quantization math
            gamma = tensor.abs().mean().clamp(min=1e-8)
            scaled_weight = tensor / gamma
            quantized_weight = torch.clamp(torch.round(scaled_weight), min=-1.0, max=1.0)
            
            # 2. Flatten and store
            flat_array = quantized_weight.flatten().detach().numpy()
            ternary_weights.append(flat_array)
            
    # Concatenate all layer weights into one massive 1D stream
    flattened_weights = np.concatenate(ternary_weights)
    total_weights = len(flattened_weights)
    print(f"\nTotal parameters extracted: {total_weights}")
    
    # 3. Pad the end with 0s if length is not perfectly divisible by 5
    remainder = total_weights % 5
    if remainder != 0:
        pad_len = 5 - remainder
        print(f"  -> Length not divisible by 5. Padding {pad_len} zeros to the end.")
        flattened_weights = np.pad(flattened_weights, (0, pad_len), 'constant', constant_values=0)
    else:
        print("  -> Length is cleanly divisible by 5. No padding required.")
        
    assert len(flattened_weights) % 5 == 0
    
    # 4. Map ternary values {-1, 0, 1} -> {0, 1, 2}
    print("Mapping values {-1, 0, 1} to {0, 1, 2} by adding 1...")
    mapped_array = (flattened_weights + 1.0).astype(np.int32)
    
    # 5. Take chunks of 5
    num_chunks = len(mapped_array) // 5
    chunks = mapped_array.reshape(num_chunks, 5)
    
    # Assign components
    w0 = chunks[:, 0]
    w1 = chunks[:, 1]
    w2 = chunks[:, 2]
    w3 = chunks[:, 3]
    w4 = chunks[:, 4]
    
    # 6. Calculate the packed byte
    print("Calculating packed byte via base-3 math...")
    # packed_byte = w_0 + (w_1 * 3) + (w_2 * 9) + (w_3 * 27) + (w_4 * 81)
    packed_integers = w0 + (w1 * 3) + (w2 * 9) + (w3 * 27) + (w4 * 81)
    
    # Basic sanity checks for byte limits
    assert np.max(packed_integers) <= 255, f"Found out-of-bounds byte: {np.max(packed_integers)}"
    assert np.min(packed_integers) >= 0, "Found negative byte value!"
    
    # 7. Cast to numpy.uint8
    packed_uint8_array = packed_integers.astype(np.uint8)
    
    # 8. Export to raw binary file
    out_bin_file = 'packed_weights.bin'
    packed_uint8_array.tofile(out_bin_file)
    
    print(f"\nHardware compilation successful!")
    print(f"Generated a {num_chunks} byte stream.")
    print(f"Outputs written to: {out_bin_file}")

if __name__ == "__main__":
    main()
