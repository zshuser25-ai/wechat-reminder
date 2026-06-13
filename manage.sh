#!/usr/bin/env bash
# WeChat Reminder — CLI 管理入口
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  WeChat Reminder — 微信定时提醒系统${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo
}

print_help() {
    echo "用法: ./manage.sh <命令>"
    echo
    echo "命令:"
    echo "  setup          交互式配置向导（首次使用）"
    echo "  test           发送测试消息到微信"
    echo "  send <类型>    手动发送消息（daily/weekly）"
    echo "  config         查看当前配置"
    echo "  edit-config    编辑 config.json"
    echo "  secrets        查看凭证状态"
    echo "  push-secrets   将凭证推送到 GitHub Secrets"
    echo "  status         查看系统状态"
}

ensure_python() {
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}错误: 未找到 python3，请先安装 Python 3.6+${NC}"
        exit 1
    fi
}

cmd_setup() {
    ensure_python
    if [ -f scripts/setup.sh ]; then
        bash scripts/setup.sh
    else
        echo -e "${RED}错误: scripts/setup.sh 不存在${NC}"
        exit 1
    fi
}

cmd_test() {
    ensure_python
    echo -e "${YELLOW}正在发送测试消息...${NC}"
    python3 scripts/send.py --test
}

cmd_send() {
    ensure_python
    local type="${1:-}"
    if [ "$type" != "daily" ] && [ "$type" != "weekly" ]; then
        echo -e "${RED}用法: ./manage.sh send <daily|weekly>${NC}"
        exit 1
    fi
    python3 scripts/send.py --type "$type"
}

cmd_config() {
    if [ -f config.json ]; then
        echo -e "${CYAN}当前 config.json:${NC}"
        cat config.json
    else
        echo -e "${RED}config.json 不存在，请运行 ./manage.sh setup${NC}"
    fi
}

cmd_edit_config() {
    if [ -f config.json ]; then
        ${EDITOR:-nano} config.json
        echo -e "${GREEN}配置已更新。如果修改了时间，需要推送到 GitHub 后生效。${NC}"
    else
        echo -e "${RED}config.json 不存在，请运行 ./manage.sh setup${NC}"
    fi
}

cmd_secrets() {
    echo -e "${CYAN}凭证状态:${NC}"
    if [ -f .env ]; then
        echo -e "  .env 文件: ${GREEN}存在${NC} (权限: $(stat -c '%a' .env 2>/dev/null || echo '?'))"
        for key in WX_APPID WX_SECRET WX_OPENID WX_TEMPLATE_ID; do
            if grep -q "^${key}=" .env 2>/dev/null && [ -n "$(grep "^${key}=" .env | cut -d= -f2- | tr -d ' ')" ]; then
                echo -e "  $key: ${GREEN}已配置${NC}"
            else
                echo -e "  $key: ${RED}未配置${NC}"
            fi
        done
    else
        echo -e "  .env 文件: ${RED}不存在${NC}"
    fi

    echo
    echo -e "${CYAN}GitHub Secrets:${NC}"
    if command -v gh &>/dev/null; then
        if gh secret list 2>/dev/null | grep -q "WX_APPID"; then
            echo -e "  ${GREEN}已配置${NC} (GitHub)"
        else
            echo -e "  ${YELLOW}未配置，运行 ./manage.sh push-secrets 上传${NC}"
        fi
    else
        echo -e "  ${YELLOW}gh CLI 未安装，无法检查 GitHub Secrets${NC}"
    fi
}

cmd_push_secrets() {
    if ! command -v gh &>/dev/null; then
        echo -e "${RED}未安装 GitHub CLI (gh)。请先安装:${NC}"
        echo "  sudo apt-get install gh    # Ubuntu/Debian"
        echo "  brew install gh            # macOS"
        exit 1
    fi

    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}请先登录 GitHub:${NC}"
        gh auth login
    fi

    if [ ! -f .env ]; then
        echo -e "${RED}.env 文件不存在，请先运行 ./manage.sh setup${NC}"
        exit 1
    fi

    echo -e "${YELLOW}正在将凭证上传到 GitHub Secrets...${NC}"
    for key in WX_APPID WX_SECRET WX_OPENID WX_TEMPLATE_ID; do
        value=$(grep "^${key}=" .env | cut -d= -f2- | tr -d ' ' | tr -d '"' | tr -d "'")
        if [ -n "$value" ]; then
            echo "  uploading $key..."
            gh secret set "$key" --body "$value"
        else
            echo -e "  ${RED}$key 为空，跳过${NC}"
        fi
    done
    echo -e "${GREEN}GitHub Secrets 上传完成！${NC}"
}

cmd_status() {
    print_header

    # 配置状态
    if [ -f config.json ]; then
        echo -e "${CYAN}📋 当前配置:${NC}"
        python3 -c "
import json
with open('config.json') as f:
    c = json.load(f)
d = c.get('daily', {})
w = c.get('weekly', {})
print(f\"  每日: {'✅ 启用' if d.get('enabled',True) else '❌ 禁用'} | {d.get('hour',9):02d}:{d.get('minute',0):02d} | {d.get('message','')[:30]}\")
print(f\"  每周: {'✅ 启用' if w.get('enabled',True) else '❌ 禁用'} | {['日','一','二','三','四','五','六'][w.get('day_of_week',0)]} {w.get('hour',10):02d}:{w.get('minute',0):02d} | {w.get('message','')[:30]}\")
" 2>/dev/null || echo "  解析失败"
    else
        echo -e "${RED} config.json 不存在${NC}"
    fi

    echo

    # GitHub Actions 状态
    echo -e "${CYAN}🔧 GitHub Actions:${NC}"
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        repo=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com/||;s|\.git$||')
        if [ -n "$repo" ]; then
            echo "  仓库: $repo"
            echo "  最近运行: $(gh run list --limit 1 --json status,name --jq '.[0].name + " - " + .[0].status' 2>/dev/null || echo '无法获取')"
        fi
    else
        echo "  请先安装 gh CLI 并登录以查看状态"
    fi

    echo

    # 最近日志
    if [ -f logs/wechat-reminder.log ]; then
        echo -e "${CYAN}📝 最近 5 条日志:${NC}"
        tail -5 logs/wechat-reminder.log
    else
        echo -e "${YELLOW}  暂无日志${NC}"
    fi
}

# ── 入口 ──────────────────────────────────────────────────
case "${1:-help}" in
    setup)       cmd_setup ;;
    test)        cmd_test ;;
    send)        cmd_send "${2:-}" ;;
    config)      cmd_config ;;
    edit-config) cmd_edit_config ;;
    secrets)     cmd_secrets ;;
    push-secrets) cmd_push_secrets ;;
    status)      cmd_status ;;
    help|--help|-h) print_help ;;
    *)           echo -e "${RED}未知命令: ${1:-}${NC}"; print_help; exit 1 ;;
esac
