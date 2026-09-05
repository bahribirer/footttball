import sqlite3
import requests
import re
import urllib.parse
import time

# Use the 'header fix' UA
HEADERS = {"User-Agent": "TikiTaka/1.0"}
BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def get_wiki_logo(club_name):
    # Try generic search or direct page guess
    # Search API is better
    search_url = f"https://en.wikipedia.org/w/api.php?action=opensearch&search={urllib.parse.quote(club_name)}&limit=1&namespace=0&format=json"
    try:
        r = requests.get(search_url, headers={"User-Agent": BROWSER_UA}, timeout=5)
        data = r.json()
        if data[1]:
            page_title = data[1][0]
            # Now fetch page info to get main image
            # We use the mobile props endpoint or parsing
            page_url = data[3][0]
            img_url = extract_logo_from_page(page_url)
            return img_url
    except Exception as e:
        print(f"Error searching {club_name}: {e}")
    return None

def extract_logo_from_page(url):
    try:
        r = requests.get(url, headers={"User-Agent": BROWSER_UA}, timeout=5)
        content = r.text
        
        # 1. Try JSON-LD (High Quality)
        match = re.search(r'"image":"([^"]+)"', content)
        if match:
            # decode unicode escapes if any, usually direct url
            clean_url = match.group(1).replace(r'\/', '/')
            # filter out non-logo images if possible, but usually main image is logo
            if 'logo' in clean_url.lower() or 'badge' in clean_url.lower() or 'crest' in clean_url.lower() or '.png' in clean_url or '.svg' in clean_url:
                return clean_url
        
        # 2. Try Infobox Image (vcard)
        # Look for infobox image
        soup_match = re.search(r'class="infobox-image"[^>]*src="//([^"]+)"', content)
        if soup_match:
            return "https://" + soup_match.group(1)
            
    except:
        pass
    return None

def fix_batch():
    conn = sqlite3.connect('tikitakapi.db')
    cursor = conn.cursor()
    
    # Get all NULL logos
    cursor.execute("SELECT name FROM clubs WHERE logo_url IS NULL OR logo_url = ''")
    missing = [row[0] for row in cursor.fetchall()]
    
    print(f"Found {len(missing)} clubs with missing logos.")
    
    updated_count = 0
    for club in missing:
        print(f"Searching for {club}...")
        
        # Search Queries Variants
        queries = [club, club + " football club", club + " FC"]
        
        found_url = None
        for q in queries:
            found_url = get_wiki_logo(q)
            if found_url:
                break
        
        if found_url:
            print(f"  -> Found: {found_url}")
            # Update DB
            cursor.execute("UPDATE clubs SET logo_url = ? WHERE name = ?", (found_url, club))
            updated_count += 1
        else:
            print("  -> NOT FOUND")
            # Mark as handled? No, keep empty for now or try another source later.
        
        time.sleep(0.5) # Be nice to Wiki API

    conn.commit()
    conn.close()
    print(f"Updated {updated_count} clubs.")

if __name__ == '__main__':
    fix_batch()
