import sqlite3
import functions
from functions import LOGO_MAPPINGS

def test_data():
    print("Testing Data Integrity...")
    
    # 1. Check Grid Generation (2025 data)
    try:
        clubs = functions.getClubsFromCompetitionId("GB1")
        print(f"GB1 Clubs (2025): {len(clubs)}")
        if "AFC Bournemouth" in clubs:
            print("PASS: Found 'AFC Bournemouth' in 2025 grid.")
        else:
            print(f"FAIL: 'AFC Bournemouth' not found. Clubs: {clubs[:5]}...")
    except Exception as e:
        print(f"FAIL: Grid Gen Error: {e}")

    # 2. Check Logo Mapping
    if LOGO_MAPPINGS.get("AFC Bournemouth") == "Bournemouth":
        print("PASS: Logo mapping for Bournemouth correct.")
    else:
        print("FAIL: Logo mapping invalid.")

    # 3. Check History Guess
    # Messi (28003) - PSG (2022/2023) - Argentina
    # Grid: Argentina (AR), PSG
    if functions.playerGuess("Lionel Messi", "Argentina", "Paris Saint-Germain"):
        print("PASS: History guess (Messi -> PSG) worked.")
    else:
        print("FAIL: History guess (Messi -> PSG) failed.")

    # 4. Check New Transfer Guess
    # Mbappe (342229) - Real Madrid (2025) - France
    # Grid: France (FR), Real Madrid
    if functions.playerGuess("Kylian Mbappe", "France", "Real Madrid"):
        print("PASS: New guess (Mbappe -> Real Madrid) confirmed.")
    else:
        print("FAIL: New guess (Mbappe -> Real Madrid) failed.")

    # 4. Big Team Prioritization Test (TR1)
    print("\nTesting Big Team Prioritization (TR1)...")
    big_teams = ["Galatasaray", "Fenerbahce", "Besiktas", "Trabzonspor"]
    hit_count = 0
    test_runs = 5
    
    for i in range(test_runs):
        grid = functions.gridClubs("TR1")
        found_big = [team for team in grid if team in big_teams]
        print(f"Run {i+1}: {grid} -> Found Big Teams: {found_big}")
        if len(found_big) >= 1:
            hit_count += 1
            
    if hit_count == test_runs:
         print(f"PASS: Big teams found in all {test_runs} runs.")
    else:
         print(f"WARNING: Big teams found in {hit_count}/{test_runs} runs.")
    test_data()
