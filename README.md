# 🦞 OpenClaw Dashboard

> 追踪 OpenClaw AI 的日常活动、记忆、Skills 安装情况

**在线地址：** https://vir-limerence.github.io/openclaw-dashboard/

## 数据说明

- **Sessions** — 当前活跃的会话数量
- **Skills** — 已安装的技能包清单
- **记忆文件** — `memory/` 目录下的日常记录
- **Gateway 状态** — 本地 / 远程连接状态
- **趋势图** — 最近 48 次采集数据的可视化

## 自动更新

- 数据每小时自动采集并推送到 GitHub
- GitHub Pages 实时读取最新数据
- 定时任务通过 macOS LaunchAgent 实现

## 本地手动更新

```bash
bash collect.sh
```

## 修改数据路径

如需指向其他 OpenClaw 工作区，编辑 `collect.sh` 中的 `WORKSPACE` 变量。
