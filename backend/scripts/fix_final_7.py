import sqlite3

def fix_final():
    # Manual mappings for historical/complex names
    updates = {
        "CD Logroñés": "https://upload.wikimedia.org/wikipedia/en/7/77/CD_Logrones_logo.png",
        "CF Extremadura (- 2010)": "https://upload.wikimedia.org/wikipedia/en/9/9b/CF_Extremadura_logo.png",
        "VfB Leipzig (- 2004)": "https://upload.wikimedia.org/wikipedia/commons/e/e6/1._FC_Lokomotive_Leipzig_logo.svg",
        "AC Venezia 1907": "https://upload.wikimedia.org/wikipedia/commons/4/42/Venezia_FC_logo.svg", # Modern Venezia
        "Union Sportive Valenciennes-Anzin Arrondissement": "https://upload.wikimedia.org/wikipedia/en/d/d4/Valenciennes_FC_logo.svg",
        "Sporting Club de Toulon et du Var": "https://upload.wikimedia.org/wikipedia/commons/a/aa/SC_Toulon_logo.svg",
        "Association Troyes Aube Champagne": "https://upload.wikimedia.org/wikipedia/commons/b/b5/ESTAC_Troyes_Logo.svg"
    }
    
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("--- Fixing Final 7 ---")
    for name, url in updates.items():
        # Match by name exactly first
        cursor.execute("UPDATE clubs SET logo_url = ? WHERE name = ?", (url, name))
        if cursor.rowcount == 0:
            # Try fuzzy if exact fails (e.g. slight spacing diff)
            print(f"Exact match failed for {name}, trying LIKE...")
            cursor.execute("UPDATE clubs SET logo_url = ? WHERE name LIKE ?", (url, name + "%"))
            
        print(f"Updated {name}: {cursor.rowcount} rows")
        
    conn.commit()
    conn.close()

if __name__ == '__main__':
    fix_final()
