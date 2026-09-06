import sqlite3

def check_players():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    players_to_check = ["Burak Yilmaz", "Burak Yılmaz", "Sergio Oliveira", "Sérgio Oliveira"]
    
    print(f"--- Checking for {players_to_check} ---")
    
    for name in players_to_check:
        print(f"\nResults for '{name}':")
        cursor.execute("SELECT name, current_club_name, country_of_citizenship, last_season FROM players WHERE name LIKE ?", (f"%{name}%",))
        rows = cursor.fetchall()
        if not rows:
            print("  No records found.")
        else:
            for row in rows:
                print(f"  {row}")

    conn.close()

check_players()
