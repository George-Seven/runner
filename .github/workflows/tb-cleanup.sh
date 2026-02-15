name: TB Cleanup

on:
  schedule:
    - cron: "*/5 * * * *"   # every 5 minutes
  workflow_dispatch:

jobs:
  cleanup:
    runs-on: ubuntu-latest

    steps:
      - name: Run TorBox cleanup
        run: |
          set -euo pipefail

          API_KEY="${{ secrets.TB_API_TOKEN }}"
          BASE_URL="https://api.torbox.app/v1/api"
          MAX_IDLE_SECONDS=$((10 * 60))  # 10 minutes

          response=$(curl -s \
            -H "Authorization: Bearer $API_KEY" \
            "$BASE_URL/torrents/mylist")

          now=$(date +%s)

          echo "$response" | jq -c '.data[]' | while read -r torrent; do
              id=$(echo "$torrent" | jq -r '.id')
              status=$(echo "$torrent" | jq -r '.download_state')
              updated=$(echo "$torrent" | jq -r '.updated_at // empty')

              idle_time="unknown"
              if [[ -n "$updated" ]]; then
                  updated_epoch=$(date -d "$updated" +%s 2>/dev/null || echo "")
                  if [[ -n "$updated_epoch" ]]; then
                      idle_time=$((now - updated_epoch))
                  fi
              fi

              delete=false

              # Condition 1: any stalled state
              if [[ "$status" == *"stalled"* ]]; then
                  delete=true
              fi

              # Condition 2: metadata/queued/loading too long
              if [[ "$status" == *"metadata"* || "$status" == *"queued"* || "$status" == *"loading"* ]]; then
                  if [[ "$idle_time" != "unknown" && "$idle_time" -gt "$MAX_IDLE_SECONDS" ]]; then
                      delete=true
                  fi
              fi

              if [[ "$delete" == true ]]; then
                  curl -s -X POST \
                    -H "Authorization: Bearer $API_KEY" \
                    -H "Content-Type: application/json" \
                    -d "{\"operation\":\"delete\",\"torrent_id\":$id}" \
                    "$BASE_URL/torrents/controltorrent" \
                    > /dev/null
              fi
          done
