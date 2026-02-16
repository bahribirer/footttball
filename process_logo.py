from PIL import Image
import numpy as np

input_path = "images/app_logo.png"
output_path = "images/app_logo.png"

try:
    img = Image.open(input_path).convert("RGBA")
    data = np.array(img)

    # Assuming background is white or very light
    # Define threshold for white
    red, green, blue, alpha = data.T
    white_areas = (red > 240) & (green > 240) & (blue > 240)
    
    # Set alpha to 0 for white areas
    data[..., 3][white_areas.T] = 0

    img = Image.fromarray(data)
    
    # Crop transparent borders
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    
    img.save(output_path)
    print("Logo processed: background removed and cropped.")
except Exception as e:
    print(f"Error processing logo: {e}")
