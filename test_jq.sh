#!/bin/bash
LATEST_JSON=data/2026-03-24.json
jq -r '\. | to_entries | .[:30] | .[] | ("| " + (.key+1|tostring) + " | [" + .value.name + "](" + .value.url + ") | " + .value.stars + " | " + (.value.desc // "") + " |")' "$LATEST_JSON"
