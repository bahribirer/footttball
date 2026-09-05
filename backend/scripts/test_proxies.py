import requests
import urllib.parse

def test_proxies():
    # Wikipedia Sources (Official, High Res)
    wiki_urls = {
        "Eyup": "https://upload.wikimedia.org/wikipedia/commons/6/62/Eyüpspor_Logosu.png",
        "Goztepe": "https://upload.wikimedia.org/wikipedia/tr/f/fe/Göztepe.png",
        "Rize": "https://upload.wikimedia.org/wikipedia/tr/a/a8/Caykur_Rizespor_2015.png"
    }

    # Fotmob Sources (High Res)
    fotmob_urls = {
        "Eyup": "https://images.fotmob.com/image_resources/logo/teamlogo/13606.png",
        "Goztepe": "https://images.fotmob.com/image_resources/logo/teamlogo/5233.png",
        "Rize": "https://images.fotmob.com/image_resources/logo/teamlogo/126.png"
    }
    
    print("--- Testing Weserv Proxy with Wiki ---")
    for name, url in wiki_urls.items():
        # Encode the target URL
        encoded_url = urllib.parse.quote(url, safe='')
        weserv_url = f"https://images.weserv.nl/?url={encoded_url}"
        try:
            r = requests.head(weserv_url, timeout=5)
            print(f"{name} Wiki->Weserv: {r.status_code}")
        except Exception as e:
            print(f"{name} Wiki->Weserv Error: {e}")

    print("\n--- Testing Weserv Proxy with Fotmob ---")
    for name, url in fotmob_urls.items():
        encoded_url = urllib.parse.quote(url, safe='')
        weserv_url = f"https://images.weserv.nl/?url={encoded_url}"
        try:
            r = requests.head(weserv_url, timeout=5)
            print(f"{name} Fotmob->Weserv: {r.status_code}")
        except Exception as e:
            print(f"{name} Fotmob->Weserv Error: {e}")

if __name__ == '__main__':
    test_proxies()
