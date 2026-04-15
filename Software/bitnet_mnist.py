import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import math

class BitNetQuantization(torch.autograd.Function):
    """
    Simulates BitNet b1.58 quantization:
    Forward: scales weights by gamma, rounds to integer, clamps to [-1, 1].
    Backward: Straight-Through Estimator (STE).
    """
    @staticmethod
    def forward(ctx, weight):
        # Calculate gamma (mean absolute value)
        # Adding a small clamp or epsilon prevents division by zero initially
        gamma = weight.abs().mean().clamp(min=1e-8)
        
        # Scale weights
        scaled_weight = weight / gamma
        
        # Round to nearest integer and clamp precisely to [-1, 1]
        quantized_weight = torch.clamp(torch.round(scaled_weight), min=-1.0, max=1.0)
        
        return quantized_weight
        
    @staticmethod
    def backward(ctx, grad_output):
        # Straight-Through Estimator: gradients flow unchanged
        return grad_output

class BitLinear(nn.Module):
    def __init__(self, in_features, out_features, bias=True):
        super(BitLinear, self).__init__()
        self.in_features = in_features
        self.out_features = out_features
        self.weight = nn.Parameter(torch.Tensor(out_features, in_features))
        
        # Kaiming uniform initialization
        nn.init.kaiming_uniform_(self.weight, a=math.sqrt(5))
        
        if bias:
            self.bias = nn.Parameter(torch.Tensor(out_features))
            bound = 1 / math.sqrt(in_features)
            nn.init.uniform_(self.bias, -bound, bound)
        else:
            self.register_parameter('bias', None)
            
    def forward(self, x):
        # Apply the BitNet b1.58 quantization function solely to weights
        quant_weight = BitNetQuantization.apply(self.weight)
        return F.linear(x, quant_weight, self.bias)

class BitNetMLP(nn.Module):
    def __init__(self):
        super(BitNetMLP, self).__init__()
        # MNIST is 28x28 = 784, hidden is 128, output is 10 classes
        self.fc1 = BitLinear(784, 128, bias=True)
        self.fc2 = BitLinear(128, 10, bias=True)
        
    def forward(self, x):
        x = x.view(-1, 784)
        x = self.fc1(x)
        x = F.relu(x)
        x = self.fc2(x)
        return x

def main():
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.5,), (0.5,))
    ])
    
    print("Downloading/Loading MNIST Dataset...")
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)
    
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Training on: {device}")
    
    model = BitNetMLP().to(device)
    optimizer = optim.Adam(model.parameters(), lr=1e-3)
    criterion = nn.CrossEntropyLoss()
    
    epochs = 3
    print("Starting QAT Training...")
    
    for epoch in range(epochs):
        model.train()
        total_loss = 0
        correct = 0
        total = 0
        
        for batch_idx, (data, target) in enumerate(train_loader):
            data, target = data.to(device), target.to(device)
            
            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
            _, predicted = output.max(1)
            total += target.size(0)
            correct += predicted.eq(target).sum().item()
            
            if batch_idx % 200 == 0:
                acc = 100. * correct / total
                print(f"Epoch [{epoch+1}/{epochs}] Batch [{batch_idx}/{len(train_loader)}] Loss: {loss.item():.4f} Acc: {acc:.2f}%")
                
        avg_loss = total_loss / len(train_loader)
        overall_acc = 100. * correct / total
        print(f"==== Epoch {epoch+1} Completed: Avg Loss: {avg_loss:.4f} | Overall Acc: {overall_acc:.2f}% ====")

    save_path = 'bitnet_mnist.pth'
    print(f"Saving quantized hardware weights to {save_path}...")
    torch.save(model.state_dict(), save_path)
    print("Training finished seamlessly.")

if __name__ == "__main__":
    main()
