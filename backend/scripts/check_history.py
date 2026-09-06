import sqlite3

con = sqlite3.connect("tikitakapi.db")
cur = con.cursor()

# Check for Dembele
print("--- Checking for Dembele ---")
cur.execute("SELECT name, current_club_name, last_season, player_id, current_club_domestic_competition_id FROM players WHERE name LIKE ?", ('%Dembélé%',))
rows = cur.fetchall()
for row in rows:
    print(row)

print("\n--- Checking for Messi ---")
cur.execute("SELECT name, current_club_name, last_season, player_id, current_club_domestic_competition_id FROM players WHERE name LIKE ?", ('%Messi%',))
rows = cur.fetchall()
for row in rows:
    print(row)

con.close()
