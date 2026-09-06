import sqlite3
import sys

def check_player(search_term):
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print(f"Checking for players like '{search_term}'...")
    cursor.execute("SELECT * FROM players WHERE name LIKE ? LIMIT 20", (f"%{search_term}%",))
    rows = cursor.fetchall()
    
    if not rows:
        print("No players found.")
    else:
        for r in rows:
            print(r)
            
    conn.close()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        check_player(sys.argv[1])
    else:
        check_player("Alex de Souza")
