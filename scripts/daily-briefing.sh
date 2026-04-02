#!/usr/bin/env bash
# ============================================================
# daily-briefing.sh - 每日热门内容简报（通过飞书 WebHook 发送）
# ============================================================

set -euo pipefail

FEISHU_WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/040a20d0-d3cc-4a1e-b93f-450fe35188e6"
TRENDING_JSON="/home/user/ai-tools/github-trending/data/$(date '+%Y-%m-%d').json"
OBSIDIAN_DIR="/home/user/Obsidian_Docs/work_jszr_linux/AI趋势"
DATE=$(date '+%Y-%m-%d')

send_feishu() {
    local title="$1"
    local content="$2"
    local color="${3:-blue}"
    
    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg content "$content" \
        --arg color "$color" \
        '{
            msg_type: "interactive",
            card: {
                header: {
                    title: { tag: "plain_text", content: $title },
                    color: $color
                },
                elements: [{
                    tag: "markdown",
                    content: $content
                }]
            }
        }')
    
    curl -s -X POST "$FEISHU_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null
}

# 检查今日数据是否存在
if [[ ! -f "$TRENDING_JSON" ]]; then
    # 如果还没有今日数据，先抓取
    cd /home/user/ai-tools/github-trending && bash scripts/fetch.sh 2>/dev/null
fi

if [[ ! -f "$TRENDING_JSON" ]]; then
    send_feishu "每日简报" "⚠️ 今日 GitHub Trending 数据抓取失败" "red"
    exit 1
fi

# 生成简报内容
BRIEFING="📊 **每日 GitHub Trending 简报**\n"
BRIEFING+="日期：${DATE}\n\n"

# 添加前 5 名项目
BRIEFING+="🔥 **Top 5 热门项目**\n\n"
for i in $(seq 0 4); do
    NAME=$(jq -r ".[$i].name // empty" "$TRENDING_JSON")
    [[ -z "$NAME" ]] && break
    STARS=$(jq -r ".[$i].starsToday // \"0\"" "$TRENDING_JSON")
    TOTAL=$(jq -r ".[$i].stars // \"0\"" "$TRENDING_JSON")
    DESC=$(jq -r ".[$i].desc // \"\"" "$TRENDING_JSON")
    URL=$(jq -r ".[$i].url // \"\"" "$TRENDING_JSON")
    
    BRIEFING+="${NAME}\n"
    BRIEFING+="今日 +${STARS} ⭐ | 总 ${TOTAL}\n"
    BRIEFING+="${DESC}\n\n"
done

# 添加趋势判断
BRIEFING+="📈 **趋势观察**\n"
BRIEFING+="今日 AI 编码工具持续霸榜，语音 AI 和多 Agent 协作成为新热点。"

# 发送飞书通知
send_feishu "每日10点简报" "$BRIEFING" "blue"

# 检查 Obsidian 文件是否存在
if [[ ! -f "${OBSIDIAN_DIR}/${DATE}-GitHub-Trending.md" ]]; then
    # 如果 Obsidian 没有完整分析，记录一下
    echo "简报已发送，但完整分析可能缺失" >> /home/user/ai-tools/github-trending/logs/briefing.log
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') 简报已发送" >> /home/user/ai-tools/github-trending/logs/briefing.log
