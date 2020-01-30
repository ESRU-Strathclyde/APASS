import requests
import json
from get_cookie import get_cookie

protocol = 'https://'
server      = 'h2g-platform-core.nobatek.com/'
server_path = 'api/v0/timeseries/NUIG_AspectGroup_Weather_Current_Temperature'
url = protocol + server + server_path

with open('data2upload') as json_file:
    payload = json.load(json_file)

cookies = get_cookie()
r = requests.patch(url, cookies=cookies, json=payload)
















##
