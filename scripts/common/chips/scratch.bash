#!/bin/bash
python3 -c "from get_cookie import get_cookie;get_cookie()"
session_cookie=`more session_cookie`

# ESP-r
#curl "https://h2g-platform-core.nobatek.com/api/v0/events/?application=6a720b48-d222-11e8-8c8e-525400ae9f4a" --cookie "session=${session_cookie}" > response.json

# Calibro
#curl "https://h2g-platform-core.nobatek.com/api/v0/events/?application=6a83eb2e-d222-11e8-858b-525400ae9f4a" --cookie "session=${session_cookie}" > response.json

# Application X
#curl "https://h2g-platform-core.nobatek.com/api/v0/events/?application=6a1ff4a2-d222-11e8-8c8e-525400ae9f4a" --cookie "session=${session_cookie}" > response.json
# curl "https://h2g-platform-core.nobatek.com/api/v0/events/?category=comfort" --cookie "session=${session_cookie}" > response.json


#curl -X GET https://h2g-platform-core.nobatek.com/api/v0/sites/ --cookie "session=${session_cookie}"  > response.json





# Get models
#curl "https://h2g-platform-core.nobatek.com/api/v0/models/?page_size=100" --cookie "session=${session_cookie}" > response.json
curl "https://h2g-platform-core.nobatek.com/api/v0/outputs/events/?module_id=6a720b48-d222-11e8-8c8e-525400ae9f4a" --cookie "session=${session_cookie}" > response.json
# authorise models to generate events
#curl "https://h2g-platform-core.nobatek.com/api/v0/outputs/events/?page_size=100" --cookie "session=${session_cookie}" > response.json

# Get events
#curl "https://h2g-platform-core.nobatek.com/api/v0/events/?page_size=20&page=4" --cookie "session=${session_cookie}" > response.json

jq . response.json | more
