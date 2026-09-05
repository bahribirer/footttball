from PIL import Image
import numpy as np
import os

input_path = "/Users/bahribirer/Desktop/tikitakatoe/footttball/images/app_logo.png"

try:
    print(f"Opening {input_path}...")
    img = Image.open(input_path).convert("RGBA")
    
    # 1. Trim transparency first (standard bbox)
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
        print(f"BBox crop: {bbox}")

    # 2. Aggressive bottom crop to remove 'reflection/glow'
    width, height = img.size
    # Crop off the bottom 15% which likely contains the 'chin' or 'glow'
    new_height = int(height * 0.85) 
    
    box = (0, 0, width, new_height)
    img = img.crop(box)
    print(f"Bottom trim: Keeping top {new_height}px of {height}px")

    img.save(input_path)
    print("Success! Logo trimmed and saved.")

except Exception as e:
    print(f"Error: {e}")
