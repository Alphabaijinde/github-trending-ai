# GitHub Trending 自动抓取工具

## 概述

使用 Playwright + Chrome CDP 实时抓取 GitHub Trending 页面数据。

## 架构

```
Chrome CDP (端口 9222)
       ↓
Playwright (headless)
       ↓
GitHub Trending 页面
       ↓
实时渲染 + JS 执行
       ↓
提取 Trending 列表
       ↓
保存 JSON 文件
```

## 目录结构

```
github-trending/
├── scripts/
│   ├── scrape.js    # 主抓取脚本
│   └── fetch.sh     # Shell 包装
├── data/
│   └── YYYY-MM-DD.json  # 每日数据
├── logs/
│   ├── fetch.log    # 抓取日志
│   └── error.log    # 错误日志
└── node_modules/    # 依赖
```

## 使用方法

### 手动抓取
```bash
~/ai-tools/github-trending/scripts/fetch.sh
```

### 仅输出 JSON
```bash
~/ai-tools/github-trending/scripts/fetch.sh --json
```

### 查看历史数据
```bash
ls ~/ai-tools/github-trending/data/
cat ~/ai-tools/github-trending/data/2026-03-20.json
```

## 定时任务

| 时间 | 任务 | 命令 |
|------|------|------|
| 09:00 | 抓取 GitHub Trending | `fetch.sh` |

## 数据格式

```json
{
  "name": "owner/repo",
  "url": "https://github.com/owner/repo",
  "desc": "项目描述",
  "stars": "今日星数",
  "fetchedAt": "ISO 时间戳"
}
```

## 依赖

- Playwright
- Chrome (已有，端口 9222)

## 故障排除

### 抓取失败
```bash
# 检查 Chrome CDP 是否可用
curl http://127.0.0.1:9222/json/version

# 查看错误日志
cat ~/ai-tools/github-trending/logs/error.log
```
