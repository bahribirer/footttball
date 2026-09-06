import requests

LEAGUES = {
    "premier_league": "GB1",
    "laliga": "ES1",
    "bundesliga": "L1",
    "serie_a": "IT1",
    "ligue_1": "FR1",
    "super_lig": "TR1"
}

YEARS = range(2000, 2027)

for league_name, code in LEAGUES.items():
    print(f"\nChecking {league_name} ({code})...")
    for year in YEARS:
        url = f"https://raw.githubusercontent.com/eordo/transfermarkt-data/master/{league_name}/{year}.csv"
        try:
            head = requests.head(url)
            if head.status_code == 200:
                print(f"  ✅ {year} exists")
            else:
                print(f"  ❌ {year} missing ({head.status_code})")
        except Exception as e:
            print(f"  ❌ {year} error: {e}")
