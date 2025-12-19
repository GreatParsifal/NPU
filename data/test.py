import torch

x = [255]
print(x)
x = torch.tensor(x, dtype=torch.uint8)

x = x.to(torch.int32)
print(x)