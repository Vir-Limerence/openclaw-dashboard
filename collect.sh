#!/bin/bash
# OpenClaw Dashboard Data Collector
# Run hourly via cron: 0 * * * * /Users/maqi/.openclaw/workspace/openclaw-dashboard/collect.sh

WORKSPACE="$HOME/.openclaw/workspace"
REPO="$WORKSPACE/openclaw-dashboard"
DATA_DIR="$REPO/data"
NOW=$(date +"%Y-%m-%d %H:%M:%S")
TODAY=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +%s)

echo "🪼 Collecting OpenClaw data at $NOW"

mkdir -p "$DATA_DIR"

# === 1. OpenClaw Status ===
openclaw status --all > /tmp/openclaw_status.txt 2>/dev/null || true
STATUS_RAW=$(cat /tmp/openclaw_status.txt)

# Extract key metrics - use safe defaults if grep fails
_agents_line=$(echo "$STATUS_RAW" | grep 'Agents' | head -1)
SESSION_COUNT=$(echo "$_agents_line" | grep -oE '[0-9]+ sessions' | grep -oE '[0-9]+' | head -1 || echo "0")
AGENT_COUNT=$(echo "$_agents_line" | grep -oE '[0-9]+' | head -1 || echo "0")
MEMORY_FILES=$(ls "$WORKSPACE/memory/"*.md 2>/dev/null | wc -l | tr -d ' ')
SKILLS_COUNT=$(ls "$WORKSPACE/skills/" 2>/dev/null | wc -l | tr -d ' ')
GATEWAY_STATE=$(echo "$STATUS_RAW" | grep -E '(local|remote|off)' | grep -oE '(local|remote|off)' | head -1 || echo "unknown")
UPDATE_AVAILABLE=$(echo "$STATUS_RAW" | grep -c "available" || echo "0")

# === 2. Memory files summary ===
MEMORY_LIST=$(ls -t "$WORKSPACE/memory/"*.md 2>/dev/null | head -10 | xargs -I{} basename {} | tr '\n' ',' | sed 's/,$//')

# === 3. Skills list ===
SKILLS_LIST=$(ls "$WORKSPACE/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# === 4. Daily memory content summary (today's file) ===
TODAY_MEM=""
if [ -f "$WORKSPACE/memory/$TODAY.md" ]; then
    TODAY_MEM=$(head -30 "$WORKSPACE/memory/$TODAY.md" | sed 's/"/\\"/g' | tr '\n' ' ' | cut -c1-500)
fi

# === 5. Build JSON snapshot ===
cat > "$DATA_DIR/status.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "datetime": "$NOW",
  "sessions": $SESSION_COUNT,
  "agents": $AGENT_COUNT,
  "memoryFiles": $MEMORY_FILES,
  "memoryList": "$MEMORY_LIST",
  "skillsCount": $SKILLS_COUNT,
  "skillsList": "$SKILLS_LIST",
  "gatewayState": "$GATEWAY_STATE",
  "updateAvailable": $UPDATE_AVAILABLE,
  "todayMemory": "$(echo "$TODAY_MEM" | sed 's/"/\\"/g')",
  "rawStatus": $(echo "$STATUS_RAW" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()[:2000]))" 2>/dev/null || echo '""')
}
EOF

# === 6. Append to history (JSONL) ===
echo "$(cat "$DATA_DIR/status.json")" >> "$DATA_DIR/history.jsonl"

# === 7. Recent history (last 48 hours from JSONL) ===
if [ -f "$DATA_DIR/history.jsonl" ]; then
    tail -48 "$DATA_DIR/history.jsonl" > "$DATA_DIR/history_recent.jsonl"
fi

# === 8. Skills detail ===
cat > "$DATA_DIR/skills.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "skills": [$(ls "$WORKSPACE/skills/" 2>/dev/null | while read s; do echo "\"$s\","; done | tr -d '\n' | sed 's/,$//')]
}
EOF

echo "✅ Data collected: sessions=$SESSION_COUNT, skills=$SKILLS_COUNT, memoryFiles=$MEMORY_FILES"
echo "📤 Pushing to GitHub..."

cd "$REPO"
git add data/
git commit -m "Update data $NOW" > /dev/null 2>&1 && git push origin main 2>&1 && echo "🚀 Pushed!" || echo "⚠️ Nothing to push or push failed"

# === Cleanup old history (keep 30 days) ===
find "$DATA_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true
