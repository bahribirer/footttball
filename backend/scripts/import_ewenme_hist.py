import csv
import sqlite3
import requests

# Mappings
# Use ALL available leagues in ewenme to get maximum historical coverage (1992+)
# But filter by year for those we already have (2000+)
LEAGUE_URLS = {
    # New Leagues (Full History needed)
    "PO1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/liga-nos.csv",
    "RU1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/premier-liga.csv",
    "GB2": "https://raw.githubusercontent.com/ewenme/transfers/master/data/championship.csv",
    
    # Existing Leagues (Only need < 2000 history)
    "NL1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/eredivisie.csv",
    "GB1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/premier-league.csv",
    "ES1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/primera-division.csv",
    "L1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/1-bundesliga.csv",
    "IT1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/serie-a.csv",
    "FR1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/ligue-1.csv"
}

LEAGUE_NAMES = {
    "PO1": "Liga NOS",
    "RU1": "Premier Liga",
    "GB2": "Championship",
    "NL1": "Eredivisie",
    "GB1": "Premier League",
    "ES1": "La Liga",
    "L1": "Bundesliga",
    "IT1": "Serie A",
    "FR1": "Ligue 1"
}

# Leagues we already have data for > 2000
EXISTING_LEAGUES = ["NL1", "GB1", "ES1", "L1", "IT1", "FR1"]

def import_ewenme_data_historical():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    for league_code, url in LEAGUE_URLS.items():
        print(f"Downloading {LEAGUE_NAMES[league_code]} from {url}...")
        try:
            response = requests.get(url)
            if response.status_code != 200:
                print(f"Failed to download {url}")
                continue
            
            # Decode content
            lines = response.text.splitlines()
            reader = csv.DictReader(lines)
            
            records = list(reader)
            print(f"  Loaded {len(records)} records.")
            
            count = 0
            skipped = 0
            
            for row in records:
                club_name = row['club_name']
                player_name = row['player_name']
                year = int(row['year']) if row['year'] and row['year'].isdigit() else 0
                season = row['season']
                movement = row['transfer_movement']
                
                if not player_name or not club_name: continue
                
                # Filtering Logic
                if league_code in EXISTING_LEAGUES:
                    # Only import if OLDER than 2000
                    if year >= 2000:
                        skipped += 1
                        continue
                
                # Check for "Alex" and rename if needed (HACK for known issue)
                # Or relying on future fixes.
                
                # 1. Insert Club (if new)
                cursor.execute("INSERT OR IGNORE INTO clubs (name) VALUES (?)", (club_name,))
                
                # 2. Insert Player Record
                if movement == 'in':
                    # Generate ID
                    generated_pid = (abs(hash(player_name)) % 10000000) + 10000000 # 10M+ range
                    
                    cursor.execute("""
                        INSERT INTO players (
                            player_id, 
                            name, 
                            last_season, 
                            current_club_name, 
                            current_club_domestic_competition_id, 
                            country_of_citizenship,
                            image_url
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (
                        generated_pid, 
                        player_name, 
                        year, 
                        club_name, 
                        league_code, 
                        "", # Nationality unknown
                        ""  # Image URL unknown
                    ))
                    count += 1

            print(f"  Imported {count} player-season records. Skipped {skipped} (already covered).")
            conn.commit()

        except Exception as e:
            print(f"Error processing {league_code}: {e}")
            import traceback
            traceback.print_exc()
            
    conn.close()
    print("Historical data import complete.")

if __name__ == '__main__':
    import_ewenme_data_historical()
