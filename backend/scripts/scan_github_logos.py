import requests

def scan_repos():
    repos = [
        "https://raw.githubusercontent.com/kadocolak/turkey-football-super-league-json-data-set/main/logos/",
        "https://raw.githubusercontent.com/luukhopman/football-logos/master/logos/TR1/"
    ]
    
    teams = {
        "Eyüpspor": ["Eyüpspor.png", "Eyupspor.png", "eyupspor.png", "Ey%C3%BCpspor.png"],
        "Göztepe": ["Göztepe.png", "Goztepe.png", "goztepe.png", "G%C3%B6ztepe.png"],
        "Rizespor": ["Çaykur Rizespor.png", "Caykur Rizespor.png", "Rizespor.png", "risespor.png", "CaykurRizespor.png", "%C3%87aykur%20Rizespor.png"]
    }
    
    headers = {"User-Agent": "Mozilla/5.0"}
    
    print("--- Scanning GitHub Repos ---")
    for team, filenames in teams.items():
        found = False
        for repo in repos:
            if found: break
            for fname in filenames:
                url = repo + fname
                try:
                    r = requests.head(url, headers=headers, timeout=3)
                    if r.status_code == 200:
                        print(f"FOUND {team}: {url}")
                        found = True
                        break
                except:
                    pass
        if not found:
            print(f"NOT FOUND: {team}")

if __name__ == '__main__':
    scan_repos()
