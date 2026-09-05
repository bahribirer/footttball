import sqlite3

def debug_man_utd():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("--- 1. Search for 'Manchester United' variations ---")
    cursor.execute("SELECT DISTINCT current_club_name FROM players WHERE current_club_name LIKE '%Manchester%' LIMIT 10")
    for row in cursor.fetchall():
        print(row)

    print("\n--- 2. Search for Beckham in 2000-2002 ---")
    cursor.execute("SELECT * FROM players WHERE name LIKE '%Beckham%' AND last_season BETWEEN 2000 AND 2002")
    rows = cursor.fetchall()
    if not rows:
        print("No Beckham records in 2000-2002.")
    else:
        for row in rows:
            print(row)

    print("\n--- 3. Count Man Utd players in 2001 ---")
    cursor.execute("SELECT count(*) FROM players WHERE current_club_name = 'Manchester United' AND last_season = 2001")
    print(cursor.fetchone())

    conn.close()

debug_man_utd()
