import sqlite3

def fix_nationality():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("Finding players with missing nationality...")
    
    # 1. Get all players who have at least one record WITH a valid nationality
    # Store in a dictionary: name -> nationality (prioritize most recent?)
    # Group by name, get the most frequent or max?
    # Simple approach: max(nationality) for each name
    
    cursor.execute("SELECT name, max(country_of_citizenship) FROM players WHERE country_of_citizenship != '' GROUP BY name")
    name_to_nat = dict(cursor.fetchall())
    
    print(f"Found {len(name_to_nat)} unique players with known nationality.")
    
    # 2. Find records with missing nationality and update them
    count = 0
    # Iterate over our known map (it's safe)
    for name, nat in name_to_nat.items():
        if not nat: continue
        
        # Check if this player has rows with empty strings
        cursor.execute("UPDATE players SET country_of_citizenship = ? WHERE name = ? AND country_of_citizenship = ''", (nat, name))
        if cursor.rowcount > 0:
            count += cursor.rowcount
            # print(f"Updated {cursor.rowcount} rows for {name} -> {nat}")
            
    print(f"Total rows updated: {count}")
    
    # Verify Burak Yilmaz
    cursor.execute("SELECT * FROM players WHERE name LIKE '%Burak Yilmaz%'")
    for row in cursor.fetchall():
        print(row)
        
    conn.commit()
    conn.close()

fix_nationality()
