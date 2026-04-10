#!/bin/bash
# GitHub Trending 抓取脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/logs/fetch.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Load bridge environment for Feishu webhook (if available)
if [[ -f "$HOME/ai-tasks/bridge/bridge.env" ]]; then
    source "$HOME/ai-tasks/bridge/bridge.env"
    # Restore LOG_FILE to fetch script's log file (override bridge.env setting)
    LOG_FILE="$PROJECT_DIR/logs/fetch.log"
fi

show_help() {
    echo "GitHub Trending 抓取工具"
    echo ""
    echo "用法: $(basename $0) [选项]"
    echo ""
    echo "选项:"
    echo "  --help     显示帮助"
    echo "  --json     仅输出 JSON"
    echo "  --analyze  抓取后自动分析"
    echo ""
    echo "示例:"
    echo "  $(basename $0)              # 抓取今天"
    echo "  $(basename $0) --json       # 仅输出 JSON"
    echo "  $(basename $0) --analyze   # 抓取 + 分析"
}

run_scrape() {
    cd "$PROJECT_DIR"
    
    # Ensure node is available via nvm if not in PATH (for cron compatibility)
    if ! command -v node &> /dev/null; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    fi
    
    if [ ! -d "$PROJECT_DIR/node_modules" ]; then
        log "安装依赖..."
        npm init -y > /dev/null 2>&1
        npm install playwright --silent
    fi
    
    log "开始抓取 GitHub Trending..."
    node "$SCRIPT_DIR/scrape.js"
    
    # After successful scrape, send Feishu notification if webhook is configured
    if [[ -n "$FEISHU_WEBHOOK_URL" ]]; then
        # Count number of projects in the latest JSON file
        LATEST_JSON=$(ls -t "$PROJECT_DIR/data/"*.json 2>/dev/null | head -1)
        if [[ -n "$LATEST_JSON" && -f "$LATEST_JSON" ]]; then
            PROJECT_COUNT=$(jq 'length' "$LATEST_JSON" 2>/dev/null || echo "未知")
            MESSAGE="GitHub Trending 自动抓取完成：共抓取到 $PROJECT_COUNT 个项目。"
        else
            MESSAGE="GitHub Trending 自动抓取完成，但未能读取项目数量。"
        fi
        
        # Prepare payload for Feishu (text message)
        PAYLOAD=$(printf '{"msg_type":"text","content":{"text":"%s"}}' "$MESSAGE")
        
        # Prepare curl arguments
        CURL_ARGS=(-sS -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$FEISHU_WEBHOOK_URL")
        
        # Add signature if secret is provided
        if [[ -n "$FEISHU_BOT_SECRET" ]]; then
            TIMESTAMP=$(date +%s)
            STRING_TO_SIGN="${TIMESTAMP}\n${FEISHU_BOT_SECRET}"
            SIGNATURE=$(echo -n "$STRING_TO_SIGN" | openssl dgst -sha256 -hmac "$FEISHU_BOT_SECRET" -binary | openssl base64)
            CURL_ARGS=(-sS -X POST -H "Content-Type: application/json" -H "Timestamp: $TIMESTAMP" -H "Sign: $SIGNATURE" -d "$PAYLOAD" "$FEISHU_WEBHOOK_URL")
        fi
        
        # Send notification
        curl "${CURL_ARGS[@]}" >/dev/null
        if [[ $? -eq 0 ]]; then
            log "Feishu 通知发送成功"
        else
            log "Feishu 通知发送失败"
        fi
        
        # Save to Obsidian vault and push to git
        if [[ -n "$LATEST_JSON" && -f "$LATEST_JSON" ]]; then
            OBSIDIAN_DIR="$HOME/Obsidian_Docs/work_jszr_linux/AI趋势"
            DATE=$(date '+%Y-%m-%d')
            FILENAME="${OBSIDIAN_DIR}/${DATE}-GitHub-Trending.md"
            
            # Skip if today's file already has analysis (prevent overwriting good data)
            if [[ -f "$FILENAME" ]] && grep -q "^### 深度分析" "$FILENAME" && grep -q "^### 1\." "$FILENAME"; then
                log "今日分析已存在且完整，跳过重新生成"
                return 0
            fi
            
            # Ensure Obsidian directory exists
            mkdir -p "$OBSIDIAN_DIR"
            
            # Generate markdown file from JSON data
            {
                echo "---"
                echo "date: ${DATE}"
                echo "tags: [GitHub, AI, 趋势, ${DATE}, 自动抓取]"
                echo "---"
                echo ""
                echo "# GitHub 今日热门分析 (${DATE})"
                echo ""
                echo "## 项目列表"
                echo ""
                echo "| 排名 | 项目 | 今日新增 | 总Stars | 描述 |"
                echo "|------|------|----------|---------|------|"
                # Process up to 30 projects - use temp file to avoid shell escaping issues
                JQ_FILTER=$(mktemp)
                echo 'to_entries | .[:30][] | "| \(.key+1) | [\(.value.name)](\(.value.url)) | \(.value.starsToday // "0") | \(.value.stars) | \(.value.desc // "") |"' > "$JQ_FILTER"
                jq -r -f "$JQ_FILTER" "$LATEST_JSON" 2>/dev/null || echo "| Error | | | |"
                rm -f "$JQ_FILTER"
            } > "$FILENAME"
            
            # Dynamic batch analysis: process all projects in batches of 6
            TOTAL_PROJECTS=$(jq 'length' "$LATEST_JSON")
            BATCH_SIZE=6
            BATCH_COUNT=$(( (TOTAL_PROJECTS + BATCH_SIZE - 1) / BATCH_SIZE ))
            
            ALL_ANALYSIS_FILE=$(mktemp)
            
            for batch in $(seq 0 $((BATCH_COUNT - 1))); do
                START=$((batch * BATCH_SIZE))
                END=$((START + BATCH_SIZE))
                if [[ $END -gt $TOTAL_PROJECTS ]]; then
                    END=$TOTAL_PROJECTS
                fi
                
                log "正在使用 OpenCode AI 生成详细分析（第 $((batch+1)) 批：项目 $((START+1))-$END）..."
                
                # Fetch README for this batch
                README_CONTEXT=""
                for i in $(seq $START $((END - 1))); do
                    PROJ_NAME=$(jq -r ".[$i].name" "$LATEST_JSON")
                    PROJ_URL=$(jq -r ".[$i].url" "$LATEST_JSON")
                    README_URL="${PROJ_URL}/raw/main/README.md"
                    README_CONTENT=$(curl -sL --max-time 5 "$README_URL" 2>/dev/null | head -100)
                    if [[ -n "$README_CONTENT" ]]; then
                        README_CONTEXT="${README_CONTEXT}项目 $((i+1)): ${PROJ_NAME}\nREADME 摘要: $(echo "$README_CONTENT" | head -10)\n\n"
                    fi
                done
                
                # Build data for this batch with correct numbering
                DATA_BATCH=""
                for i in $(seq $START $((END - 1))); do
                    NUM=$((i + 1))
                    NAME=$(jq -r ".[$i].name" "$LATEST_JSON")
                    URL=$(jq -r ".[$i].url" "$LATEST_JSON")
                    TODAY=$(jq -r ".[$i].starsToday" "$LATEST_JSON")
                    TOTAL=$(jq -r ".[$i].stars" "$LATEST_JSON")
                    DESC=$(jq -r ".[$i].desc" "$LATEST_JSON")
                    DATA_BATCH="${DATA_BATCH}${NUM}. [${NAME}](${URL}) | 今日+${TODAY} | 总${TOTAL} | ${DESC}
"
                done
                
                PROMPT_FILE=$(mktemp)
                cat > "$PROMPT_FILE" << 'PROMPT_EOF'
你是一位资深技术分析师，正在为技术团队撰写 GitHub Trending 日报。

【严格禁止】
- 不要输出任何 Agent 工作日志（如 Waiting、Analyze、Research、Librarian）
- 不要输出思考过程
- 不要输出开场白
- 不要使用任何工具

【输出格式 - 直接输出每个项目的分析表格】
### N. 项目名

| 维度 | 内容 |
|------|------|
| 简介 | 一句话说明 |
| 核心功能 | • 功能1<br>• 功能2 |
| 技术栈 | 主要技术 |
| 为什么火 | 具体原因 |
| 适用场景 | 谁用 |

【项目数据】
PROMPT_EOF
                
                # Write full prompt to temp file
                {
                    cat "$PROMPT_FILE"
                    echo -e "\n${README_CONTEXT}"
                    echo -e "\n【项目数据】\n\n${DATA_BATCH}"
                } > "${PROMPT_FILE}.full"
                
                ANALYSIS_FILE=$(mktemp)
                
                MODELS=("opencode/big-pickle" "opencode/minimax-m2.5-free" "openai/gpt-5-nano")
                MODEL_SUCCESS=false
                
                for MODEL in "${MODELS[@]}"; do
                    local retry=0
                    local max_retries=2
                    log "尝试使用模型: $MODEL"
                    
                    while [[ $retry -le $max_retries ]]; do
                        timeout 90 opencode run -m "$MODEL" < "${PROMPT_FILE}.full" > "$ANALYSIS_FILE" 2>/dev/null
                        
                        if [[ -s "$ANALYSIS_FILE" ]]; then
                            MODEL_SUCCESS=true
                            break
                        fi
                        
                        retry=$((retry + 1))
                        if [[ $retry -le $max_retries ]]; then
                            log "模型 $MODEL 第 $((retry)) 次超时，重试..."
                            sleep 2
                        fi
                    done
                    
                    [[ "$MODEL_SUCCESS" == "true" ]] && break
                done
                
                if [[ "$MODEL_SUCCESS" != "true" ]]; then
                    log "所有模型均失败，跳过 AI 分析"
                fi
                
                # Clean up AI output
                sed -i '/^<think>$/,/^<\/think>$/d' "$ANALYSIS_FILE"
                sed -i '/^▄$/,/^$/d' "$ANALYSIS_FILE"
                sed -i '/^---$/d' "$ANALYSIS_FILE"
                sed -i '/^我检测到/,/^---$/d' "$ANALYSIS_FILE"
                sed -i '/^我将为/d' "$ANALYSIS_FILE"
                sed -i '/^我正在分析/d' "$ANALYSIS_FILE"
                sed -i '/^先收集/d' "$ANALYSIS_FILE"
                sed -i '/^好的/d' "$ANALYSIS_FILE"
                sed -i '/^嗯/d' "$ANALYSIS_FILE"
                sed -i '/^今天用户/d' "$ANALYSIS_FILE"
                sed -i '/^首先/d' "$ANALYSIS_FILE"
                sed -i '/^接下来/d' "$ANALYSIS_FILE"
                sed -i '/^最后/d' "$ANALYSIS_FILE"
                sed -i '/^总的来说/d' "$ANALYSIS_FILE"
                sed -i '/^思考过程/d' "$ANALYSIS_FILE"
                sed -i "/^I'll gather/d" "$ANALYSIS_FILE"
                sed -i '/^I will/d' "$ANALYSIS_FILE"
                sed -i '/^Let me/d' "$ANALYSIS_FILE"
                sed -i '/^I need to/d' "$ANALYSIS_FILE"
                sed -i '/^\[0m$/d' "$ANALYSIS_FILE"
                sed -i '/^> Sisyphus.*$/d' "$ANALYSIS_FILE"
                sed -i '/^• Research.*Librarian Agent$/d' "$ANALYSIS_FILE"
                sed -i '/^✓ Research.*Librarian Agent$/d' "$ANALYSIS_FILE"
                sed -i '/^等待.*$/d' "$ANALYSIS_FILE"
                sed -i '/^\[90m.*$/d' "$ANALYSIS_FILE"
                sed -i 's/\[90m//g' "$ANALYSIS_FILE"
                sed -i 's/\[0m//g' "$ANALYSIS_FILE"
                sed -i '/^⚙ background_output/d' "$ANALYSIS_FILE"
                sed -i '/^报告已完成/d' "$ANALYSIS_FILE"
                sed -i '/^.*背景任务.*$/d' "$ANALYSIS_FILE"
                sed -i '/^• Analyze.*$/d' "$ANALYSIS_FILE"
                sed -i '/^✓ Analyze.*$/d' "$ANALYSIS_FILE"
                sed -i '/Unknown Agent/d' "$ANALYSIS_FILE"
                sed -i '/^Webfetch/d' "$ANALYSIS_FILE"
                sed -i '/^> Sisyphus/d' "$ANALYSIS_FILE"
                sed -i '/^I'll/d' "$ANALYSIS_FILE"
                sed -i '/^Let me/d' "$ANALYSIS_FILE"
                sed -i '/^等待其余/d' "$ANALYSIS_FILE"
                sed -i '/^Waiting for/d' "$ANALYSIS_FILE"
                
                if [[ -s "$ANALYSIS_FILE" ]]; then
                    cat "$ANALYSIS_FILE" >> "$ALL_ANALYSIS_FILE"
                    echo "" >> "$ALL_ANALYSIS_FILE"
                fi
                
                rm -f "$PROMPT_FILE" "${PROMPT_FILE}.full" "$ANALYSIS_FILE"
            done
            
            # Append all analyses to markdown file
            if [[ -s "$ALL_ANALYSIS_FILE" ]]; then
                echo "" >> "$FILENAME"
                echo "### 深度分析" >> "$FILENAME"
                echo "" >> "$FILENAME"
                cat "$ALL_ANALYSIS_FILE" >> "$FILENAME"
                log "已生成 AI 详细分析（全部${TOTAL_PROJECTS}个项目）"
            else
                log "AI 分析生成失败，跳过"
            fi
            
            rm -f "$ALL_ANALYSIS_FILE"
            
            log "已保存 GitHub Trending 数据到 Obsidian: $FILENAME"
            
            # Commit and push to Obsidian vault git repo using specified SSH key
            cd "$HOME/Obsidian_Docs/work_jszr_linux" && \
            git add "AI趋势/${DATE}-GitHub-Trending.md" && \
            git -c user.name="homebot" -c user.email="homebot@local" commit -m "Add GitHub Trending for ${DATE}" >/dev/null 2>&1
            
            # Attempt push with specific SSH key (works in cron where ssh-agent may not be running)
            if GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_rsa -o BatchMode=yes -o ConnectTimeout=5" git push origin main >/dev/null 2>&1; then
                log "已成功推送到 Obsidian 仓库"
            else
                log "推送到 Obsidian 仓库失败（文件已保存到 Obsidian）"
            fi
        fi
    fi
}

case "${1:-}" in
    --help|-h)
        show_help
        ;;
    *)
        run_scrape
        ;;
esac