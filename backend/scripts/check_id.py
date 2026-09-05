import sqlite3
con = sqlite3.connect("tikitakapi.db")
cur = con.cursor()
try:
    cur.execute("SELECT * FROM players WHERE player_id = 463605")
    row = cur.fetchone()
    if row:
        print(f"Found: {row}")
    else:
        print("Not Found")
    
    # Check a known player like Messi or Ronaldo to see their ID
    cur.execute("SELECT player_id, name, current_club_name FROM players WHERE name LIKE '%Messi%' LIMIT 1")
    print(f"Messi: {cur.fetchone()}")
except Exception as e:
    print(e)
con.close()
