import sqlite3
con = sqlite3.connect("tikitakapi.db")
cur = con.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = cur.fetchall()
print("Tables:", tables)
for table in tables:
    print(f"\nSchema for {table[0]}:")
    cur.execute(f"PRAGMA table_info({table[0]})")
    print(cur.fetchall())
    cur.execute(f"SELECT COUNT(*) FROM {table[0]}")
    print("Count:", cur.fetchone()[0])
con.close()
