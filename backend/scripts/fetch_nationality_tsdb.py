
import sqlite3
import requests
import time

TSDB_API = "https://www.thesportsdb.com/api/v1/json/3/searchplayers.php"
BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def fetch_missing_nationalities():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("Finding players with completely missing nationality...")
    
    # 1. Get players who have NO valid nationality record
    query = """
        SELECT DISTINCT name FROM players 
        WHERE name NOT IN (
            SELECT DISTINCT name FROM players WHERE country_of_citizenship != '' AND country_of_citizenship IS NOT NULL
        )
        AND (country_of_citizenship IS NULL OR country_of_citizenship = '')
    """
    cursor.execute(query)
    missing_players = [row[0] for row in cursor.fetchall()]
    
    print(f"Found {len(missing_players)} players with NO nationality record.")
    
    # Limit to top 50 for now or run in background fully later
    # The user specifically mentioned Henry, so let's start with him if present
    if "Thierry Henry" in missing_players:
        missing_players.remove("Thierry Henry")
        missing_players.insert(0, "Thierry Henry")
        
    count = 0
    updated = 0
    
    for name in missing_players:
        # Rate limit
        time.sleep(1.5) 
        
        try:
            print(f"Fetching for {name}...")
            r = requests.get(TSDB_API, params={"p": name}, headers={"User-Agent": BROWSER_UA}, timeout=10)
            
            if r.status_code == 200:
                data = r.json()
                player = data.get("player")
                if player:
                    # Get first result usually
                    nat = player[0].get("strNationality")
                    if nat:
                        print(f"  Found: {nat}")
                        cursor.execute("UPDATE players SET country_of_citizenship = ? WHERE name = ?", (nat, name))
                        updated += 1
                        if updated % 10 == 0:
                            conn.commit()
                            print("  Committed batch.")
                    else:
                        print("  No nationality in TSDB response.")
                else:
                        print("  Player not found in TSDB.")
            else:
                print(f"  TSDB Error: {r.status_code}")
                
        except Exception as e:
            print(f"  Error: {e}")
            
        count += 1
        if count >= 20: # Safety limit for first run, ensures Henry + a few others get fixed
            print("Reached batch limit of 20.")
            break
            
    conn.commit()
    print(f"Updated {updated} players.")
    conn.close()

if __name__ == "__main__":
    fetch_missing_nationalities()
