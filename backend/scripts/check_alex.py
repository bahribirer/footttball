import sqlite3

def check_alex():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("Checking for Alex de Souza variants...")
    variants = ["Alex", "Alexsandro de Souza", "Alex de Souza"]
    
    for v in variants:
        cursor.execute("SELECT * FROM players WHERE name LIKE ?", (f"%{v}%",))
        rows = cursor.fetchall()
        for r in rows:
            print(r)
            
    conn.close()

check_alex()
