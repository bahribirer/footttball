import sqlite3

def fix_data():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("Fixing Burak Yilmaz...")
    # 1. Unify name to "Burak Yılmaz"
    cursor.execute("UPDATE players SET name = 'Burak Yılmaz' WHERE name = 'Burak Yilmaz'")
    print(f"  Renamed {cursor.rowcount} rows to 'Burak Yılmaz'.")
    
    # 2. Set Country to 'Turkey' for all Burak Yılmaz
    cursor.execute("UPDATE players SET country_of_citizenship = 'Turkey' WHERE name = 'Burak Yılmaz'")
    print(f"  Set nationality to 'Turkey' for {cursor.rowcount} rows.")
    
    print("\nFixing Sergio Oliveira...")
    # 3. Unify name to "Sérgio Oliveira"
    cursor.execute("UPDATE players SET name = 'Sérgio Oliveira' WHERE name = 'Sergio Oliveira'")
    print(f"  Renamed {cursor.rowcount} rows to 'Sérgio Oliveira'.")

    # 4. Set Country to 'Portugal'
    cursor.execute("UPDATE players SET country_of_citizenship = 'Portugal' WHERE name = 'Sérgio Oliveira'")
    print(f"  Set nationality to 'Portugal' for {cursor.rowcount} rows.")
    
    conn.commit()
    conn.close()
    print("Specific data fixes applied.")

fix_data()
