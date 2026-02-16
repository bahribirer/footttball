import shutil
import os

src_dir = "/Users/bahribirer/.gemini/antigravity/brain/57366e59-0be3-4252-b287-d7f22599665a/"
dst_dir = "/Users/bahribirer/Desktop/tikitakatoe/footttball/images/"

files = [
    ("onboarding_football_1771164748534.png", "onboarding_football.png"),
    ("onboarding_board_1771164762530.png", "onboarding_board.png"),
    ("onboarding_trophy_1771164777817.png", "onboarding_trophy.png")
]

if not os.path.exists(dst_dir):
    print(f"Destination directory {dst_dir} does not exist!")
    exit(1)

for src_file, dst_file in files:
    src_path = os.path.join(src_dir, src_file)
    dst_path = os.path.join(dst_dir, dst_file)
    try:
        shutil.copy(src_path, dst_path)
        print(f"Copied {src_file} to {dst_file}")
    except Exception as e:
        print(f"Error copying {src_file}: {e}")
