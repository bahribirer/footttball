import sqlite3
con = sqlite3.connect("tikitakapi.db")
cur = con.cursor()

# Check if player_id is unique
try:
    cur.execute("SELECT count(*) FROM players")
    total_rows = cur.fetchone()[0]
    cur.execute("SELECT count(DISTINCT player_id) FROM players")
    unique_ids = cur.fetchone()[0]
    
    print(f"Total rows: {total_rows}")
    print(f"Unique player_ids: {unique_ids}")
    
    if total_rows > unique_ids:
        print("Table supports history (multiple rows per player).")
    else:
        print("Table currently has unique player_ids (1 row per player).")
        
    # Check if there is a unique index on player_id
    cur.execute("PRAGMA index_list('players')")
    indexes = cur.fetchall()
    print("\nIndexes:")
    for idx in indexes:
        print(idx)
        
except Exception as e:
    print(e)
con.close()
