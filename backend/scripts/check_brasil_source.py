import csv
import sqlite3
import requests
import io

# URL for Brasileiro Dataset
# Using 'campeonato-brasileiro-full.csv' or similar. 
# Search result said: `adaoduque/Brasileirao_Dataset` has `campeonato-brasileiro-full.csv`.
# Checking structure: usually matches.
# But it might be match data, NOT player transfer data.
# Re-reading search result:
# "including several CSV files such as campeonato-brasileiro-full.csv[2][3]."
# "records typically containing match-related information[5]."

# If it's match data, it won't help with PLAYERS.
# I need ROSTERS or TRANSFERS.

# `saadism777/Transfermarkt-Data-Analysis` has `transfermarkt.csv`
# "includes information on Brazilian players in the transfer market for the 2022/2023 season"
# That's too recent. Alex de Souza retired 2015.

# `footballcsv/cache.footballdata` -> match data.

# I need PLAYER HISTORY.
# Kaggle might be best but I can't curl kaggle easily without auth.

# Let's try to verify if `campeonato-brasileiro-full.csv` has players.
# Usually these "full" csvs are match results (Home, Away, Score).

# I will try to find a list of players.
# Maybe I should search "github brasileirao players csv".

def check_structure():
    url = "https://raw.githubusercontent.com/adaoduque/Brasileirao_Dataset/master/campeonato-brasileiro-full.csv"
    try:
        r = requests.get(url)
        print(r.text[:200])
    except:
        print("Failed")

if __name__ == '__main__':
    check_structure()
