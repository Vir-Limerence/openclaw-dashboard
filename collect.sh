#!/bin/bash
# OpenClaw Dashboard Data Collector

WORKSPACE="$HOME/.openclaw/workspace"
REPO="$WORKSPACE/openclaw-dashboard"
DATA_DIR="$REPO/data"
TODAY=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +%s)
NOW=$(date +"%Y-%m-%d %H:%M:%S")

echo "🪼 Collecting OpenClaw data..."

mkdir -p "$DATA_DIR"

# === 抓取状态 ===
openclaw status --all > /tmp/openclaw_status.txt 2>/dev/null || true

# === 提取指标 ===
SESSIONS=$(grep '│ Agents' /tmp/openclaw_status.txt | grep -oE '[0-9]+ sessions' | grep -oE '[0-9]+' | head -1)
AGENTS=$(grep '│ Agents' /tmp/openclaw_status.txt | grep -oE '[0-9]+' | head -1)
GW=$(grep -E 'local|remote|off' /tmp/openclaw_status.txt | grep -oE 'local|remote|off' | head -1)
UPD=$(grep -c 'available' /tmp/openclaw_status.txt 2>/dev/null || echo 0)

# 防止空值
SESSIONS=${SESSIONS:-0}; AGENTS=${AGENTS:-0}
GW=${GW:-unknown}; UPD=${UPD:-0}

# === 渠道/机器人 ===
CHANNELS=""
CH_COUNT=0
while IFS= read -r line; do
    CH=$(echo "$line" | awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); gsub(/^[ \t]+|[ \t]+$/,"",$3); gsub(/^[ \t]+|[ \t]+$/,"",$4); print $2"|"$3"|"$4}' | grep -v "^│" | grep -v "^$" | grep "ON")
    if [ -n "$CH" ]; then
        CH_NAME=$(echo "$CH" | cut -d'|' -f1)
        CH_STATE=$(echo "$CH" | cut -d'|' -f2)
        CH_DETAIL=$(echo "$CH" | cut -d'|' -f3 | cut -c1-60)
        CHANNELS="${CHANNELS}{\"name\":\"$CH_NAME\",\"state\":\"$CH_STATE\",\"detail\":\"$CH_DETAIL\"},"
        CH_COUNT=$((CH_COUNT + 1))
    fi
done < /tmp/openclaw_status.txt
CHANNELS=$(echo "$CHANNELS" | sed 's/,$//')

# === Skills ===
SKILLS_CNT=$(ls "$WORKSPACE/skills/" 2>/dev/null | wc -l | tr -d ' ')

# === 短期记忆 ===
SHORT_LIST=""
SHORT_CNT=0
for f in $(ls -t "$WORKSPACE/memory/"*.md 2>/dev/null | head -20); do
    BN=$(basename "$f")
    if echo "$BN" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
        SHORT_LIST="${SHORT_LIST}${BN},"
        SHORT_CNT=$((SHORT_CNT + 1))
    fi
done
SHORT_LIST=$(echo "$SHORT_LIST" | sed 's/,$//')

# === 永久记忆 ===
PERM_LIST=""
[ -f "$WORKSPACE/MEMORY.md" ] && PERM_LIST="MEMORY.md"
for f in "$WORKSPACE/memory/"*.md; do
    [ -f "$f" ] || continue
    BN=$(basename "$f")
    if ! echo "$BN" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
        [ -n "$BN" ] && PERM_LIST="${PERM_LIST},${BN}"
    fi
done
if [ -d "$WORKSPACE/.learnings" ]; then
    for f in "$WORKSPACE/.learnings/"*.md; do
        [ -f "$f" ] && PERM_LIST="${PERM_LIST},$(basename "$f")"
    done
fi
PERM_CNT=$(echo "$PERM_LIST" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)

# === 今日记忆 ===
TODAY_MEM=""
if [ -f "$WORKSPACE/memory/$TODAY.md" ]; then
    TODAY_MEM=$(head -20 "$WORKSPACE/memory/$TODAY.md" 2>/dev/null | tr '\n' ' ' | cut -c1-500)
fi

echo "✅ sessions=$SESSIONS skills=$SKILLS_CNT short=$SHORT_CNT perm=$PERM_CNT"

# === 写变量文件（避免heredoc引号问题）===
VARS_FILE="/tmp/openclaw_vars_$$.txt"
echo "ts=$TIMESTAMP" > "$VARS_FILE"
echo "dt=$NOW" >> "$VARS_FILE"
echo "sessions=$SESSIONS" >> "$VARS_FILE"
echo "agents=$AGENTS" >> "$VARS_FILE"
echo "short_cnt=$SHORT_CNT" >> "$VARS_FILE"
echo "short_list=$SHORT_LIST" >> "$VARS_FILE"
echo "perm_cnt=$PERM_CNT" >> "$VARS_FILE"
echo "perm_list=$PERM_LIST" >> "$VARS_FILE"
echo "skills_cnt=$SKILLS_CNT" >> "$VARS_FILE"
echo "gw=$GW" >> "$VARS_FILE"
echo "upd=$UPD" >> "$VARS_FILE"
echo "today_mem=$TODAY_MEM" >> "$VARS_FILE"
echo "data_dir=$DATA_DIR" >> "$VARS_FILE"
echo "repo_dir=$REPO" >> "$VARS_FILE"
echo "workspace=$WORKSPACE" >> "$VARS_FILE"
echo "CHANNELS=$CHANNELS" >> "$VARS_FILE"

# === Python 生成 JSON ===
python3 - "$VARS_FILE" << 'PYEOF'
import sys, json, os

vars_file = sys.argv[1]
vars = {}
with open(vars_file) as f:
    for line in f:
        line = line.strip()
        if '=' in line:
            k, v = line.split('=', 1)
            vars[k] = v

os.remove(vars_file)

# Parse channels from shell variable
import ast
channels_raw = vars.get('CHANNELS', '')
if channels_raw:
    try:
        channels = json.loads('[' + channels_raw + ']')
    except:
        channels = []
else:
    channels = []

ts = int(vars.get('ts', 0))
dt = vars.get('dt', '')
data_dir = vars.get('data_dir', '')
repo_dir = vars.get('repo_dir', '')
workspace = vars.get('workspace', '')

# Status JSON
raw = open('/tmp/openclaw_status.txt').read()[:2000]
status = {
    "timestamp": ts,
    "datetime": dt,
    "sessions": int(vars.get('sessions', 0)),
    "agents": int(vars.get('agents', 0)),
    "memoryFiles": int(vars.get('short_cnt', 0)),
    "memoryList": vars.get('short_list', ''),
    "shortTermCount": int(vars.get('short_cnt', 0)),
    "shortTermList": vars.get('short_list', ''),
    "permanentCount": int(vars.get('perm_cnt', 0)),
    "permanentList": vars.get('perm_list', ''),
    "skillsCount": int(vars.get('skills_cnt', 0)),
    "skillsList": "",
    "gatewayState": vars.get('gw', 'unknown'),
    "updateAvailable": int(vars.get('upd', 0)),
    "todayMemory": vars.get('today_mem', '')[:500],
    "rawStatus": raw,
    "channels": channels,
    "channelCount": len(channels)
}

with open(data_dir + '/status.json', 'w') as f:
    json.dump(status, f, ensure_ascii=False, indent=None)

# Skills JSON with descriptions
skills_dir = workspace + '/skills/'
skills = sorted([s for s in os.listdir(skills_dir) if os.path.isdir(skills_dir + s)])
desc_path = repo_dir + '/skill_descriptions.json'
try:
    desc_map = json.load(open(desc_path))
except:
    desc_map = {}

skills_data = [{"name": s, "desc": desc_map.get(s, "")} for s in skills]
with open(data_dir + '/skills.json', 'w') as f:
    json.dump({"timestamp": ts, "skills": skills_data, "count": len(skills)}, f, ensure_ascii=False)
PYEOF

# === 历史记录 ===
cat "$DATA_DIR/status.json" >> "$DATA_DIR/history.jsonl"
tail -48 "$DATA_DIR/history.jsonl" > "$DATA_DIR/history_recent.jsonl"

# === 推送 ===
echo "📤 Pushing..."
cd "$REPO"
git add data/
git commit -m "Update $NOW" > /dev/null 2>&1 && git push origin main 2>&1 && echo "🚀 Pushed!" || echo "⚠️ 无更新或推送失败"

# === 清理 ===
find "$DATA_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true
