#!/usr/bin/env python3
import json, os

data_dir = os.environ.get('COL_DATA_DIR', '/tmp')
repo_dir = os.environ.get('COL_REPO_DIR', '/tmp')
workspace = os.environ.get('COL_WORKSPACE', '/tmp')

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

try:
    raw = open('/tmp/openclaw_status.txt').read()[:2000]
except:
    raw = ""

status_data = {
    "timestamp": ts,
    "datetime": dt,
    "sessions": sessions,
    "agents": agents,
    "memoryFiles": short_count,
    "memoryList": short_list,
    "shortTermCount": short_count,
    "shortTermList": short_list,
    "permanentCount": perm_count,
    "permanentList": perm_list,
    "skillsCount": skills_count,
    "skillsList": "",
    "gatewayState": gw,
    "updateAvailable": upd,
    "todayMemory": today_mem,
    "rawStatus": raw
}

os.makedirs(data_dir, exist_ok=True)
with open(data_dir + '/status.json', 'w') as f:
    json.dump(status_data, f, ensure_ascii=False, indent=2)

# Skills with descriptions
skills_dir = workspace + '/skills/'
skills = sorted([s for s in os.listdir(skills_dir) if os.path.isdir(skills_dir + s)])
desc_path = repo_dir + '/skill_descriptions.json'
try:
    desc_map = json.load(open(desc_path))
except:
    desc_map = {}

skills_with_desc = [{"name": s, "desc": desc_map.get(s, "")} for s in skills]

with open(data_dir + '/skills.json', 'w') as f:
    json.dump({"timestamp": ts, "skills": skills_with_desc, "count": len(skills)}, f, ensure_ascii=False)

print("JSON generated OK")
