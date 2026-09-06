import csv
import sqlite3
import requests

# Mappings
LEAGUE_URLS = {
    "PO1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/liga-nos.csv",
    "RU1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/premier-liga.csv",
    "NL1": "https://raw.githubusercontent.com/ewenme/transfers/master/data/eredivisie.csv",
    "GB2": "https://raw.githubusercontent.com/ewenme/transfers/master/data/championship.csv"
}

LEAGUE_NAMES = {
    "PO1": "Liga NOS",
    "RU1": "Premier Liga",
    "NL1": "Eredivisie",
    "GB2": "Championship"
}

def import_ewenme_data_csv():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    # Pre-load existing clubs to avoid constraint errors if needed, 
    # though INSERT OR IGNORE handles it for PK.
    
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
            clubs_added = 0
            
            # Track clubs we've seen in this batch to minimize DB hits if we wanted, 
            # but INSERT OR IGNORE is fast enough.
            
            for row in records:
                club_name = row['club_name']
                player_name = row['player_name']
                year = row['year']
                season = row['season'] # e.g. 1992/1993
                movement = row['transfer_movement']
                
                if not player_name or not club_name: continue
                
                # 1. Insert Club (if new)
                # Schema: clubs(name, logo_url)
                # We ignore logo_url for now.
                cursor.execute("INSERT OR IGNORE INTO clubs (name) VALUES (?)", (club_name,))
                if cursor.rowcount > 0:
                    clubs_added += 1
                    
                # 2. Insert Player / Season Record
                # We want to capture the player's presence in this league.
                # If 'movement' == 'in', they joined 'club_name' in 'year'.
                # So we add a record indicating they were at 'club_name' in 'year' (and presumably until they left).
                # But our DB structure stores "snapshots" per season basically.
                # e.g. row: (id, name, current_club_id, current_club_name, country, last_season)
                # 'last_season' here acts as "Season of this record".
                
                if movement == 'in':
                    # Generate a unique ID for this player-club-year combo to allow multiple entries per player
                    # (representing their history).
                    # The game uses `name` to search anyway.
                    # We create a composite ID.
                    
                    pid = f"{player_name}_{club_name}_{year}".lower().replace(" ", "_")
                    curr_club_id = club_name.lower().replace(" ", "_") # Not used by schema but maybe reliable for some checks? column is `current_club_id` integer usually?
                    # Wait, schema said `current_club_id integer`. 
                    # But update_db.py creates `player_id` as integer. 
                    # I am using TEXT for ID. 
                    # SQLite allows dynamic typing, but `integer` field might not like text if strict?
                    # Actually `update_db.py` uses `cur.execute... values(?,?,?,?,?,?)` matching the schema `players`.
                    # Schema: player_id integer, ..., current_club_id integer, ...
                    # If I insert string into integer column in sqlite it usually works (affinity).
                    # But let's look at `update_db.py`: `pid = int(row['player_id'])`.
                    # `ewenme` does NOT provide player_id. 
                    # I MUST generate an integer ID?
                    # Or I can use a high number range to avoid collision with Transfermarkt IDs (usually < 1000000).
                    # I'll hash the name to get a consistent integer ID?
                    # `abs(hash(player_name)) % 100000000` + 1000000000 (offset)
                    
                    generated_pid = (abs(hash(player_name)) % 10000000) + 10000000 # 10M+ range
                    
                    # Columns in `players` (based on `update_db.py` insert):
                    # It inserts `base_row` which matches the SELECT * FROM players order.
                    # Schema has MANY columns. `update_db.py` loads them all.
                    # I need to match that column structure! 
                    # "SELECT * FROM players ... col_names"
                    # Schema: player_id, first_name, last_name, name, last_season, current_club_id, player_code, country_of_birth, city_of_birth, country_of_citizenship, ...
                    
                    # I cannot easily match 23 columns if I don't have them.
                    # However, I can insert into SPECIFIC columns if I change the logic.
                    # But the game might crash if columns are null?
                    # Most keys seem optional possibly.
                    # Essential: `name`, `last_season`, `current_club_name`, `current_club_domestic_competition_id`, `country_of_citizenship`.
                    
                    # I will try to insert naming columns.
                    
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

            print(f"  Imported {count} player-season records. Added {clubs_added} clubs.")
            conn.commit()

        except Exception as e:
            print(f"Error processing {league_code}: {e}")
            import traceback
            traceback.print_exc()
            
    conn.close()
    print("Data import complete.")

if __name__ == '__main__':
    import_ewenme_data_csv()
