#!/bin/bash
# OpenClaw Dashboard Data Collector
# 每小时自动采集 OpenClaw 状态数据，推送到 GitHub

WORKSPACE="$HOME/.openclaw/workspace"
REPO="$WORKSPACE/openclaw-dashboard"
DATA_DIR="$REPO/data"
TODAY=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +%s)
NOW=$(date +"%Y-%m-%d %H:%M:%S")

echo "🪼 Collecting OpenClaw data..."

mkdir -p "$DATA_DIR"

# === 抓取 OpenClaw 状态 ===
openclaw status --all 2>&1 | grep -v '^\[' > /tmp/openclaw_status.txt || true

# === 提取关键指标 ===
SESSION_COUNT=$(grep '│ Agents' /tmp/openclaw_status.txt | grep -oE '[0-9]+ sessions' | grep -oE '[0-9]+' | tr -d ' \n' || echo 0)
AGENT_COUNT=$(grep '│ Agents' /tmp/openclaw_status.txt | grep -oE '[0-9]+' | head -1 | tr -d ' \n' || echo 0)
GATEWAY_STATE=$(grep -E '(local|remote|off)' /tmp/openclaw_status.txt | grep -oE '(local|remote|off)' | head -1 || echo unknown)
UPDATE_AVAILABLE=$(grep -c 'available' /tmp/openclaw_status.txt 2>/dev/null || echo 0)

# === Skills ===
SKILLS_LIST=$(ls "$WORKSPACE/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
SKILLS_COUNT=$(ls "$WORKSPACE/skills/" 2>/dev/null | wc -l | tr -d ' ')

# === 短期记忆（YYYY-MM-DD.md 格式的每日日志）===
SHORT_TERM=""
COUNT=0
for f in $(ls -t "$WORKSPACE/memory/"*.md 2>/dev/null | head -20); do
    BN=$(basename "$f")
    # 只包含日期格式的文件 (YYYY-MM-DD.md)
    if echo "$BN" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
        SHORT_TERM="${SHORT_TERM}${BN},"
        COUNT=$((COUNT + 1))
    fi
done
SHORT_TERM=$(echo "$SHORT_TERM" | sed 's/,$//')
SHORT_TERM_COUNT=${COUNT:-0}

# === 永久记忆（MEMORY.md + .learnings/ + 其他非日记memory文件）===
PERM_FILES=""
[ -f "$WORKSPACE/MEMORY.md" ] && PERM_FILES="MEMORY.md"
# 添加非日记的memory文件
for f in "$WORKSPACE/memory/"*.md; do
    [ -f "$f" ] || continue
    BN=$(basename "$f")
    # 排除日期格式的日志文件
    if ! echo "$BN" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
        [ -n "$BN" ] && PERM_FILES="${PERM_FILES},${BN}"
    fi
done
# 添加 .learnings/ 目录
if [ -d "$WORKSPACE/.learnings" ]; then
    for f in "$WORKSPACE/.learnings/"*.md; do
        [ -f "$f" ] && PERM_FILES="${PERM_FILES},$(basename "$f")"
    done
fi
PERM_COUNT=$(echo "$PERM_FILES" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)

# === 今日记忆摘要 ===
TODAY_MEM=""
if [ -f "$WORKSPACE/memory/$TODAY.md" ]; then
    TODAY_MEM=$(head -20 "$WORKSPACE/memory/$TODAY.md" 2>/dev/null | tr '\n' ' ' | cut -c1-500)
fi

# === 导出环境变量给 Python ===
export COL_TS="$TIMESTAMP" COL_DT="$NOW" COL_SESSIONS="$SESSION_COUNT" COL_AGENTS="$AGENT_COUNT"
export COL_SHORT="$SHORT_TERM_COUNT" COL_SHORT_LIST="$SHORT_TERM" COL_PERM="$PERM_COUNT" COL_PERM_LIST="$PERM_FILES"
export COL_SKILLS_CNT="$SKILLS_COUNT" COL_GW="$GATEWAY_STATE" COL_UPD="$UPDATE_AVAILABLE"
export COL_TODAY="$TODAY_MEM" COL_DATA_DIR="$DATA_DIR" COL_REPO_DIR="$REPO" COL_WORKSPACE="$WORKSPACE"

# === 生成 JSON ===
python3 << 'PYEOF'
import json, os

# Read shell vars from env (safe from injection)
ts = int(os.environ.get('COL_TS', '0'))
dt = os.environ.get('COL_DT', '')
sessions = int(os.environ.get('COL_SESSIONS', '0'))
agents = int(os.environ.get('COL_AGENTS', '0'))
short_count = int(os.environ.get('COL_SHORT', '0'))
short_list = os.environ.get('COL_SHORT_LIST', '')
perm_count = int(os.environ.get('COL_PERM', '0'))
perm_list = os.environ.get('COL_PERM_LIST', '')
skills_count = int(os.environ.get('COL_SKILLS_CNT', '0'))
gw = os.environ.get('COL_GW', 'unknown')
upd = int(os.environ.get('COL_UPD', '0'))
today_mem = os.environ.get('COL_TODAY', '')[:500]
raw = open('/tmp/openclaw_status.txt').read()[:2000]

data_dir = os.environ.get('COL_DATA_DIR')
repo_dir = os.environ.get('COL_REPO_DIR')

status_data = {
    "timestamp": ts, "datetime": dt,
    "sessions": sessions, "agents": agents,
    "memoryFiles": short_count, "memoryList": short_list,
    "shortTermCount": short_count, "shortTermList": short_list,
    "permanentCount": perm_count, "permanentList": perm_list,
    "skillsCount": skills_count, "skillsList": "",
    "gatewayState": gw, "updateAvailable": upd,
    "todayMemory": today_mem, "rawStatus": raw
}

with open(data_dir + '/status.json', 'w') as f:
    json.dump(status_data, f, ensure_ascii=False, indent=2)

# Skills with descriptions
skills_dir = os.environ.get('COL_WORKSPACE') + '/skills/'
skills = sorted([s for s in os.listdir(skills_dir) if os.path.isdir(skills_dir + s)])
desc_path = repo_dir + '/skill_descriptions.json'
try:
    desc_map = json.load(open(desc_path))
except:
    desc_map = {}

skills_with_desc = [{"name": s, "desc": desc_map.get(s, "")} for s in skills]

with open(data_dir + '/skills.json', 'w') as f:
    json.dump({"timestamp": ts, "skills": skills_with_desc, "count": len(skills)}, f, ensure_ascii=False)
PYEOF

echo "✅ sessions=$SESSION_COUNT skills=$SKILLS_COUNT short=$SHORT_TERM_COUNT perm=$PERM_COUNT"

# === 历史记录（JSONL）===
cat "$DATA_DIR/status.json" >> "$DATA_DIR/history.jsonl"
echo "" >> "$DATA_DIR/history.jsonl"
tail -48 "$DATA_DIR/history.jsonl" > "$DATA_DIR/history_recent.jsonl"

# === 推送 GitHub ===
echo "📤 Pushing..."
cd "$REPO"
git add data/
git commit -m "Update $NOW" > /dev/null 2>&1 && git push origin main 2>&1 && echo "🚀 Pushed!" || echo "⚠️ 无更新或推送失败"

# === 清理30天前历史 ===
find "$DATA_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true
