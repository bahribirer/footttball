import sqlite3
import os

def update_logos():
    # Canonical URLs found via JSON-LD
    updates = {
        "Eyüpspor": "https://upload.wikimedia.org/wikipedia/commons/6/62/Ey%C3%BCpspor_Logosu.png",
        "Göztepe": "https://upload.wikimedia.org/wikipedia/tr/f/fe/G%C3%B6ztepe.png",
        "Çaykur Rizespor": "https://upload.wikimedia.org/wikipedia/tr/a/a8/Caykur_Rizespor_2015.png"
        # Note: Rizespor might be stored as "Çaykur Rizespor" or "Rizespor" in DB. 
        # I'll update using LIKE to be safe.
    }
    
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    for name, url in updates.items():
        print(f"Updating {name} -> {url}")
        # Use LIKE to match "Göztepe" or "Göztepe S.K." or "Caykur Rizespor"
        # For Eyupspor, distinct.
        if name == "Eyüpspor":
            cursor.execute("UPDATE clubs SET logo_url = ? WHERE name LIKE 'Ey%'", (url,))
        elif name == "Göztepe":
            cursor.execute("UPDATE clubs SET logo_url = ? WHERE name LIKE 'Göztepe%'", (url,))
        elif name == "Çaykur Rizespor":
             cursor.execute("UPDATE clubs SET logo_url = ? WHERE name LIKE '%Rizespor%'", (url,))
        
        print(f"Rows affected: {cursor.rowcount}")

    conn.commit()
    conn.close()
    
    # Cleanup
    for f in ["tff_eyup.html", "tff_goztepe.html", "tff_rizespor.html", "fetch_tff_logos.py", "parse_tff_html.py", "check_logo_hosts.py", "find_working_urls.py"]:
        if os.path.exists(f):
            os.remove(f)
    print("Cleanup done.")

if __name__ == '__main__':
    update_logos()
