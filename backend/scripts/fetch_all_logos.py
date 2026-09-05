import sqlite3
import requests
import time
import re
from duckduckgo_search import DDGS

def create_clubs_table():
    con = sqlite3.connect("tikitakapi.db")
    cur = con.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS clubs (name TEXT PRIMARY KEY, logo_url TEXT)")
    con.commit()
    con.close()

def get_unique_clubs():
    con = sqlite3.connect("tikitakapi.db")
    cur = con.cursor()
    # Get all clubs from players table
    cur.execute("SELECT DISTINCT current_club_name FROM players WHERE current_club_name IS NOT NULL AND current_club_name != ''")
    clubs = [row[0] for row in cur.fetchall()]
    con.close()
    return clubs

def search_logo(club_name):
    query = f"{club_name} football logo png transparent wikipedia"
    try:
        with DDGS() as ddgs:
            # Search for images
            results = list(ddgs.images(
                query,
                max_results=3,
                safesearch="off",
                size="Medium",
                type_image="Transparent"
            ))
            
            for res in results:
                url = res.get("image")
                if not url: continue
                
                # Prioritize wikimedia or pure pngs
                if "upload.wikimedia.org" in url or url.endswith(".png"):
                   return url
            
            # Fallback to first result
            if results:
                return results[0].get("image")
                
    except Exception as e:
        print(f"Error searching for {club_name}: {e}")
    return None

def main():
    create_clubs_table()
    clubs = get_unique_clubs()
    print(f"Found {len(clubs)} unique clubs.")
    
    # Prioritize BIG_TEAMS
    from functions import BIG_TEAMS
    priority_teams = set()
    for league_teams in BIG_TEAMS.values():
        priority_teams.update(league_teams)
        
    # Sort: Priority teams first, then alphabetical
    clubs.sort(key=lambda x: (0 if x in priority_teams else 1, x))
    
    con = sqlite3.connect("tikitakapi.db")
    cur = con.cursor()
    
    updated_count = 0
    
    for i, club in enumerate(clubs):
        # Check if already exists
        cur.execute("SELECT logo_url FROM clubs WHERE name = ?", (club,))
        if cur.fetchone():
            continue
            
        print(f"[{i+1}/{len(clubs)}] Searching logo for: {club}...")
        
        logo_url = None
        retries = 3
        
        for attempt in range(retries):
            logo_url = search_logo(club)
            if logo_url:
                break
            
            # If not found or error, maybe wait longer?
            # But search_logo catches exception. 
            # If it was a rate limit print was shown.
            # Let's simple wait more if we failed.
            time.sleep(2 * (attempt + 1))
        
        if logo_url:
            print(f"  -> Found: {logo_url}")
            cur.execute("INSERT OR REPLACE INTO clubs (name, logo_url) VALUES (?, ?)", (club, logo_url))
            con.commit()
            updated_count += 1
        else:
            print(f"  -> NOT FOUND (Skipping)")
            
        # Generous sleep to avoid rate limits
        time.sleep(3.0)
        
    con.close()
    print(f"Done! Updated {updated_count} logos.")

if __name__ == "__main__":
    main()
