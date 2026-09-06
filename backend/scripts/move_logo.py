import shutil
import os

src = '/Users/bahribirer/.gemini/antigravity/brain/57366e59-0be3-4252-b287-d7f22599665a/tiki_taka_toe_logo_icon_1771193658646.png'
dst = '/Users/bahribirer/Desktop/tikitakatoe/footttball/images/app_logo.png'

try:
    shutil.copyfile(src, dst)
    print(f"Successfully copied to {dst}")
except Exception as e:
    print(f"Error copying: {e}")
