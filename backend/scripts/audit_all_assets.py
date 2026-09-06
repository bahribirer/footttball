import sqlite3
import requests
import concurrent.futures

# Flutter App User-Agent
HEADERS = {"User-Agent": "TikiTaka/1.0"}

def check_url(item):
    name, url, type_ = item
    if not url:
        return (name, "MISSING URL", type_)
    
    try:
        r = requests.head(url, headers=HEADERS, timeout=5)
        if r.status_code != 200:
             # Try GET if HEAD fails (some servers block HEAD)
             r = requests.get(url, headers=HEADERS, stream=True, timeout=5)
             r.close()
        
        if r.status_code == 200:
            return None # Success
        else:
            return (name, f"Status {r.status_code}", type_)
    except Exception as e:
        return (name, f"Error {str(e)}", type_)

def audit_assets():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    print("--- Fetching Data ---")
    # 1. Clubs
    cursor.execute("SELECT name, logo_url FROM clubs")
    clubs = [(row[0], row[1], "CLUB") for row in cursor.fetchall()]
    
    # 2. Countries (Flags)
    # Note: Logic is complex (frontend mapping). 
    # For audit, we'll check the 'country_of_citizenship' against a known map or just check standard ISOs if we had them.
    # Actually, let's look at what the backend sends. 
    # The frontend constructs URL: https://flagsapi.com/[ISO]/flat/64.png
    # We need to simulate the ISO mapping.
    
    # Let's import the mapping logic if possible, or just re-implement a basic one for audit.
    # Ideally we check the distinct countries in DB.
    cursor.execute("SELECT DISTINCT country_of_citizenship FROM players WHERE country_of_citizenship IS NOT NULL AND country_of_citizenship != ''")
    countries = [row[0] for row in cursor.fetchall()]
    
    # We need to know valid ISOs. 
    # For this audit, let's focus HEAVILY on Clubs as that's the user's main complaint ("takım logoları eksiksiz istiyorum").
    # We will do a basic check on flags later or now if we can import the mapping.
    
    conn.close()
    
    print(f"Auditing {len(clubs)} Clubs...")
    
    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        results = executor.map(check_url, clubs)
        for res in results:
            if res:
                failed.append(res)
                
    print("\n--- FAILED ASSETS ---")
    if not failed:
        print("ALL CLUBS PASSED!")
    else:
        for name, reason, type_ in failed:
            print(f"[{type_}] {name}: {reason}")

if __name__ == '__main__':
    audit_assets()
