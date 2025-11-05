import numpy as np
from scipy.signal import convolve2d
import matplotlib.pyplot as plt

IMG_W = 24
IMG_H = 24

# --- Load input image (flattened 0/1)
img = np.loadtxt("tests/plus.txt")
if img.ndim == 1:
    img = img.reshape(IMG_H, IMG_W)

# --- Define same 3×3 filter (match Verilog)
filt = np.array([[ 1, 0,-1],
                 [ 1, 0,-1],
                 [ 1, 0,-1]])

# --- Convolution (same padding)
conv = convolve2d(img, filt, mode='same', boundary='fill', fillvalue=0)

# --- ReLU
relu = np.maximum(conv, 0)

# --- 2×2 Max Pool
pooled = relu.reshape(IMG_H//2, 2, IMG_W//2, 2).max(axis=(1,3))

# --- Load RTL output
rtl_out = np.loadtxt("C:\\Users\\reetr\\cnn\\cnn.sim\\sim_1\\behav\\xsim\\rtl_output.txt")
rtl_img = rtl_out.reshape(11, 11)

# --- Compare
diff = np.abs(pooled[:11, :11] - rtl_img)
print("Mean absolute difference:", np.mean(diff))

# --- Visualize
fig, axs = plt.subplots(1,3,figsize=(9,3))
axs[0].imshow(img, cmap='gray');  axs[0].set_title('Input')
axs[1].imshow(pooled, cmap='gray'); axs[1].set_title('Python Output')
axs[2].imshow(rtl_img, cmap='gray'); axs[2].set_title('RTL Output')
for a in axs: a.axis('off')
plt.tight_layout(); plt.show()
