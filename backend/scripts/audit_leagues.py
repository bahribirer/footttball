import sqlite3

def audit_leagues():
    con = sqlite3.connect("tikitakapi.db")
    cur = con.cursor()
    
    leagues = ["GB1", "ES1", "IT1", "L1", "FR1", "TR1"]
    
    for league in leagues:
        print(f"--- Auditing {league} ---")
        cur.execute("SELECT DISTINCT current_club_name FROM players WHERE current_club_domestic_competition_id = ?", (league,))
        clubs = [row[0] for row in cur.fetchall()]
        
        # Check if any of these clubs also appear in other leagues
        for club in clubs:
            cur.execute("SELECT DISTINCT current_club_domestic_competition_id FROM players WHERE current_club_name = ? AND current_club_domestic_competition_id != ?", (club, league))
            others = [row[0] for row in cur.fetchall()]
            if others:
                print(f"Club '{club}' belongs to {league} but also found in {others}")
                
    con.close()

if __name__ == "__main__":
    audit_leagues()
