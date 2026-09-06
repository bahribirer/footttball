import sqlite3

def check_player(name):
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print(f"--- Checking for {name} ---")
    cursor.execute("SELECT name, current_club_name, country_of_citizenship, last_season FROM players WHERE name LIKE ?", (f"%{name}%",))
    rows = cursor.fetchall()
    
    if not rows:
        print("No records found.")
    else:
        for row in rows:
            print(row)
            
    conn.close()

check_player("Beckham")
check_player("Rooney") 
