

import requests
import json
from urllib.parse import quote

BASE_URL = "https://api.dotgg.gg"

def get_cards(game):
    response = requests.get(f"{BASE_URL}/cgfw/getcards?game={game}")
    return response.json()

def get_deck(game, slug):
    response = requests.get(f"{BASE_URL}/cgfw/getdeck?game={game}&slug={slug}")
    return response.json()



def search_decks(game, search_term="", current_page=1):
    request = {
        "page": current_page,
        "limit": 30,
        "srt": "date",
        "direct": "desc",
        "type": "",
        "my": 0,
        "myarchive": 0,
        "fav": 0,
        "getdecks": {
            "hascrd": [],
            "nothascrd": [],
            "youtube": 0,
            "smartsrch": search_term,
            "date": "",
            "color": [],
            "collection": 0,
            "topset": "",
            "at": 0,
            "format": "",
            "is_tournament": ""
        }
    }

    url = f"{BASE_URL}/cgfw/getdecks?game={game}&rq={quote(json.dumps(request))}"
    response = requests.get(url)
    return response.json()
 
import time

def search_decks_all_pages(game, search_term=""):
    """Fetch all deck pages and return as a single flattened list."""
    all_decks = []
    page = 1
    
    while True:
        result = search_decks(game, search_term, page)
        
        # Check if result has decks; adjust based on API response structure
        if isinstance(result, list) and len(result) > 0:
            all_decks.extend(result)
            print(f"Page {page}: Fetched {len(result)} decks (Total: {len(all_decks)})")
            page += 1
        elif isinstance(result, dict) and 'data' in result and len(result['data']) > 0:
            all_decks.extend(result['data'])
            print(f"Page {page}: Fetched {len(result['data'])} decks (Total: {len(all_decks)})")
            page += 1
        else:
            print(f"Page {page}: No more decks found. Finished.")
            break
        
        # Wait 1 second before next API call
        time.sleep(1)
    
    return all_decks

# One-line execution with auto-pagination
all_nami_decks = search_decks_all_pages('onepiece', 'nami')
with open("Decks/nami.json", "w", encoding="utf-8") as f:
    json.dump(all_nami_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_nami_decks)}")

all_buggy_decks = search_decks_all_pages('onepiece', 'buggy')
with open("Decks/buggy.json", "w", encoding="utf-8") as f:
    json.dump(all_buggy_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_buggy_decks)}")

all_shanks_decks = search_decks_all_pages('onepiece', 'shanks')
with open("Decks/shanks.json", "w", encoding="utf-8") as f:
    json.dump(all_shanks_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_shanks_decks)}")

all_boa_decks = search_decks_all_pages('onepiece', 'boa')
with open("Decks/boa.json", "w", encoding="utf-8") as f:
    json.dump(all_boa_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_boa_decks)}")

all_yamato_decks = search_decks_all_pages('onepiece', 'yamato')
with open("Decks/yamato.json", "w", encoding="utf-8") as f:
    json.dump(all_yamato_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_yamato_decks)}")

all_betty_decks = search_decks_all_pages('onepiece', 'betty')
with open("Decks/betty.json", "w", encoding="utf-8") as f:
    json.dump(all_betty_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_betty_decks)}")

all_teach_decks = search_decks_all_pages('onepiece', 'teach')
with open("Decks/teach.json", "w", encoding="utf-8") as f:
    json.dump(all_teach_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_teach_decks)}")

all_sanji_decks = search_decks_all_pages('onepiece', 'sanji')
with open("Decks/sanji.json", "w", encoding="utf-8") as f:
    json.dump(all_sanji_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_sanji_decks)}")

all_lim_decks = search_decks_all_pages('onepiece', 'lim')
with open("Decks/lim.json", "w", encoding="utf-8") as f:
    json.dump(all_lim_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_lim_decks)}")


all_rayleigh_decks = search_decks_all_pages('onepiece', 'rayleigh')
with open("Decks/rayleigh.json", "w", encoding="utf-8") as f:
    json.dump(all_rayleigh_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_rayleigh_decks)}")

all_sabo_decks = search_decks_all_pages('onepiece', 'sabo')
with open("Decks/sabo.json", "w", encoding="utf-8") as f:
    json.dump(all_sabo_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_sabo_decks)}")

all_roger_decks = search_decks_all_pages('onepiece', 'roger')
with open("Decks/roger.json", "w", encoding="utf-8") as f:
    json.dump(all_roger_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_roger_decks)}")

all_bonney_decks = search_decks_all_pages('onepiece', 'bonney')
with open("Decks/bonney.json", "w", encoding="utf-8") as f:
    json.dump(all_bonney_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_bonney_decks)}")

all_mihawk_decks = search_decks_all_pages('onepiece', 'mihawk')
with open("Decks/mihawk.json", "w", encoding="utf-8") as f:
    json.dump(all_mihawk_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_mihawk_decks)}")

all_zoro_decks = search_decks_all_pages('onepiece', 'zoro')
with open("Decks/zoro.json", "w", encoding="utf-8") as f:
    json.dump(all_zoro_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_zoro_decks)}")

all_luffy_decks = search_decks_all_pages('onepiece', 'luffy')
with open("Decks/luffy.json", "w", encoding="utf-8") as f:
    json.dump(all_luffy_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_luffy_decks)}")

all_ace_decks = search_decks_all_pages('onepiece', 'ace')
with open("Decks/ace.json", "w", encoding="utf-8") as f:
    json.dump(all_ace_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_ace_decks)}")

all_imu_decks = search_decks_all_pages('onepiece', 'IMU')
with open("Decks/imu.json", "w", encoding="utf-8") as f:
    json.dump(all_imu_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_imu_decks)}")

all_jinbe_decks = search_decks_all_pages('onepiece', 'jinbe')
with open("Decks/jinbe.json", "w", encoding="utf-8") as f:
    json.dump(all_jinbe_decks, f, indent=4, ensure_ascii=False)

print(f"\nTotal decks saved: {len(all_jinbe_decks)}")


# Usage
cards = get_cards('lorcana')
deck = get_deck('lorcana', 'my-deck-slug')
decks = search_decks('onepiece', 'IMU')


with open("imu1.json", "w", encoding="utf-8") as f: json.dump(decks, f, indent=4, ensure_ascii=False)
