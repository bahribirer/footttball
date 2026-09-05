import csv
import sqlite3
import requests
import io

# URLs for transfer data
DATA_SOURCES = {}
LEAGUES = {
    "GB1": "premier_league",
    "ES1": "laliga",
    "L1": "bundesliga",
    "IT1": "serie_a",
    "FR1": "ligue_1",
    "TR1": "super_lig",
    "NL1": "eredivisie"
}

# Generate URLs for 2000-2025
for league_code, league_name in LEAGUES.items():
    for year in range(2000, 2026):
        DATA_SOURCES[(league_code, year)] = f"https://raw.githubusercontent.com/eordo/transfermarkt-data/master/{league_name}/{year}.csv"

# League ID mapping for checks
VALID_LEAGUES = ["GB1", "ES1", "L1", "IT1", "FR1", "TR1", "NL1"]

def update_db():
    con = sqlite3.connect("tikitakapi.db")
    cur = con.cursor()
    
    print("Loading existing players (latest info)...")
    cur.execute("SELECT * FROM players GROUP BY player_id HAVING max(last_season)")
    col_names = [description[0] for description in cur.description]
    col_idx = {name: i for i, name in enumerate(col_names)}
    
    # Dictionary: player_id -> dict of attributes
    # We use this to track the CURRENT state of a player as we process years
    player_states = {}
    
    for row in cur.fetchall():
        pid = row[col_idx['player_id']]
        if pid not in player_states:
             # Store as mutable list to update league/club/season
            player_states[pid] = list(row)

    print(f"Loaded {len(player_states)} unique players.")

    transfers_processed = 0
    promotions_processed = 0
    
    # Sort keys to process 2024 then 2025
    sorted_sources = sorted(DATA_SOURCES.items(), key=lambda x: x[0][1])
    
    # Track who moved in 2024/2025 to know who stays
    moved_players = set()

    # 1. Process Transfers (2024 & 2025)
    for (league_code, season), url in sorted_sources:
        print(f"Processing {league_code} {season}...")
        try:
            response = requests.get(url)
            if response.status_code != 200:
                print(f"Error fetching {url}: {response.status_code}")
                continue
                
            csv_file = io.StringIO(response.text)
            reader = csv.DictReader(csv_file)
            
            for row in reader:
                try:
                    pid = int(row['player_id'])
                    
                    # 1. Handle incoming transfers (Player joins 'club')
                    if row['movement'] == 'in':
                        new_club = row['club'].strip()
                        
                        if pid in player_states:
                            moved_players.add(pid)
                            base_row = player_states[pid] # Get their previous state
                            
                            # Update state
                            base_row[col_idx['last_season']] = season
                            base_row[col_idx['current_club_domestic_competition_id']] = league_code
                            base_row[col_idx['current_club_name']] = new_club
                            
                            # Insert this NEW state into DB
                            placeholders = ','.join(['?'] * len(base_row))
                            # Check existence to avoiddupes
                            check = cur.execute("SELECT 1 FROM players WHERE player_id=? AND last_season=? AND current_club_name=?", (pid, season, new_club)).fetchone()
                            if not check:
                                cur.execute(f"INSERT INTO players VALUES ({placeholders})", base_row)
                                transfers_processed += 1
                                
                                # Update player_states so if they move again in 2025, we use this new info
                                player_states[pid] = base_row
                    
                    # 2. Handle outgoing transfers (Player leaves 'club')
                    # This captures their presence at the club BEFORE they left
                    elif row['movement'] == 'out':
                        old_club = row['club'].strip()
                        
                        # Determine last season at this club
                        # If summer transfer, they played the previous season. 
                        # If winter, they played the first half of current season.
                        # (Simplification: treating winter departure as part of that season)
                        effective_season = season - 1 if row['window'] == 'summer' else season
                        
                        if "Beckham" in row['player_name']:
                             print(f"  ---> FOUND: {row['player_name']} leaving {old_club} -> Added for season {effective_season}")

                        if pid in player_states:
                             # We don't necessarily update 'player_states' here because this is HISTORY,
                             # not their *current* location for the forward pass.
                             # But we MUST record that they were at 'old_club' in 'effective_season'.
                             
                             base_row = list(player_states[pid]) # Copy
                             base_row[col_idx['last_season']] = effective_season
                             base_row[col_idx['current_club_domestic_competition_id']] = league_code
                             base_row[col_idx['current_club_name']] = old_club
                             
                             placeholders = ','.join(['?'] * len(base_row))
                             check = cur.execute("SELECT 1 FROM players WHERE player_id=? AND last_season=? AND current_club_name=?", (pid, effective_season, old_club)).fetchone()
                             if not check:
                                 cur.execute(f"INSERT INTO players VALUES ({placeholders})", base_row)
                                 transfers_processed += 1

                except ValueError:
                    continue
        except Exception as e:
            print(f"Failed to process {url}: {e}")

    # 2. Promote Active Players (Cloning 2023 -> 2025)
    # If a player was in a top league in 2023/2024 and didn't move in 2025,
    # we assume they are still there and add a 2025 row.
    print("Promoting stable players to 2025...")
    
    for pid, row in player_states.items():
        current_league = row[col_idx['current_club_domestic_competition_id']]
        current_season = row[col_idx['last_season']]
        current_club = row[col_idx['current_club_name']]
        
        # If they are already updated to 2025 via transfer, skip
        if current_season == 2025:
            continue
            
        # If they are in a valid league and their last known season was recent (2023 or 2024)
        if current_league in VALID_LEAGUES and current_season >= 2023:
            # Clone to 2025
            new_row = list(row)
            new_row[col_idx['last_season']] = 2025
            
            # Check existence
            check = cur.execute("SELECT 1 FROM players WHERE player_id=? AND last_season=? AND current_club_name=?", (pid, 2025, current_club)).fetchone()
            if not check:
                placeholders = ','.join(['?'] * len(new_row))
                cur.execute(f"INSERT INTO players VALUES ({placeholders})", new_row)
                promotions_processed += 1

    print(f"Transfers inserted: {transfers_processed}")
    print(f"stable players promoted: {promotions_processed}")
    
    con.commit()
    
    # 3. Fix Missing Nationalities (Backfill)
    print("Backfilling missing nationalities...")
    cur.execute("SELECT name, max(country_of_citizenship) FROM players WHERE country_of_citizenship != '' GROUP BY name")
    name_to_nat = dict(cur.fetchall())
    
    count = 0
    for name, nat in name_to_nat.items():
        if not nat: continue
        cur.execute("UPDATE players SET country_of_citizenship = ? WHERE name = ? AND country_of_citizenship = ''", (nat, name))
        count += cur.rowcount
            
    print(f"Backfilled nationality for {count} rows.")
    con.commit()
    
    con.close()
    print("Database update complete.")

if __name__ == "__main__":
    update_db()
