#!/usr/bin/env bash
# WeChat Reminder — 交互式配置向导
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    WeChat Reminder — 初始配置向导       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo
echo -e "本向导将帮助你配置微信定时提醒系统。"
echo -e "${YELLOW}请提前准备好:${NC}"
echo -e "  1. 微信测试公众号的凭证（访问下方链接获取）"
echo -e "  2. 一条每日提醒的消息文案"
echo -e "  3. 一条每周提醒的消息文案"
echo

# ── Step 1: 微信测试号 ─────────────────────────────────
echo -e "${BOLD}━━━ 第 1 步: 申请微信测试公众号 ━━━${NC}"
echo
echo -e "请用 ${YELLOW}微信扫码${NC} 打开以下链接:"
echo -e "  ${CYAN}https://mp.weixin.qq.com/debug/cgi-bin/sandbox?t=sandbox/login${NC}"
echo
echo -e "扫码登录后，你会看到以下信息，请依次填入:"
echo

read -p "appID (示例: wx0000000000000000): " appid
read -p "appsecret (示例: 00000000...): " secret

echo
echo -e "${YELLOW}请在同页面找到「测试号二维码」，用微信扫码关注你的测试号。${NC}"
echo -e "然后在「用户列表」中复制你的微信号（openid）。"
read -p "openid (示例: o000000...): " openid

echo
echo -e "${YELLOW}请在同页面「模板消息接口」区域，点击「新增测试模板」。${NC}"
echo -e "模板内容请填写以下文本（一字不差）:"
echo
echo -e "  ${CYAN}{{first.DATA}}${NC}"
echo -e "  ${CYAN}提醒内容：{{keyword1.DATA}}${NC}"
echo -e "  ${CYAN}时间：{{keyword2.DATA}}${NC}"
echo -e "  ${CYAN}{{remark.DATA}}${NC}"
echo
echo -e "提交后可看到 template_id。"
read -p "template_id (示例: 000000...): " template_id

# ── 写入 .env ────────────────────────────────────────────
echo
echo -e "${YELLOW}正在写入 .env 文件...${NC}"
cat > .env <<EOF
# WeChat Reminder 凭证
# 生成日期: $(date '+%Y-%m-%d %H:%M:%S')
WX_APPID=$appid
WX_SECRET=$secret
WX_OPENID=$openid
WX_TEMPLATE_ID=$template_id
EOF
chmod 600 .env
echo -e "${GREEN}.env 文件已创建 (权限 600)${NC}"

# ── Step 2: 消息内容 ────────────────────────────────────
echo
echo -e "${BOLD}━━━ 第 2 步: 设置消息内容 ━━━${NC}"
echo

read -p "每日提醒消息 [默认: 早上好！记得查看今日待办事项]: " daily_msg
daily_msg=${daily_msg:-"早上好！记得查看今日待办事项"}
read -p "每日提醒时间 (小时, 0-23) [默认: 9]: " daily_hour
daily_hour=${daily_hour:-9}
read -p "每日提醒时间 (分钟, 0-59) [默认: 0]: " daily_min
daily_min=${daily_min:-0}

echo
read -p "每周提醒消息 [默认: 该给老妈买矿泉水了]: " weekly_msg
weekly_msg=${weekly_msg:-"该给老妈买矿泉水了"}
echo -e "每周发送日:"
echo "  0 = 周日, 1 = 周一, 2 = 周二, 3 = 周三, 4 = 周四, 5 = 周五, 6 = 周六"
read -p "选择星期几 [默认: 0 (周日)]: " weekly_day
weekly_day=${weekly_day:-0}
read -p "每周提醒时间 (小时, 0-23) [默认: 10]: " weekly_hour
weekly_hour=${weekly_hour:-10}
read -p "每周提醒时间 (分钟, 0-59) [默认: 0]: " weekly_min
weekly_min=${weekly_min:-0}

# ── 写入 config.json ─────────────────────────────────────
echo
echo -e "${YELLOW}正在写入 config.json...${NC}"
cat > config.json <<EOF
{
  "daily": {
    "enabled": true,
    "message": "$daily_msg",
    "hour": $daily_hour,
    "minute": $daily_min
  },
  "weekly": {
    "enabled": true,
    "message": "$weekly_msg",
    "day_of_week": $weekly_day,
    "hour": $weekly_hour,
    "minute": $weekly_min
  }
}
EOF
echo -e "${GREEN}config.json 已创建${NC}"

# ── Step 3: 创建 .env.example ────────────────────────────
cat > .env.example <<'TEMPLATE'
# WeChat Reminder 凭证模板
# 复制此文件为 .env 并填入实际值
WX_APPID=wx0000000000000000
WX_SECRET=your_secret_here
WX_OPENID=your_openid_here
WX_TEMPLATE_ID=your_template_id_here
TEMPLATE

# ── 完成 ─────────────────────────────────────────────────
echo
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         配置完成！接下来:                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo
echo -e "  ${BOLD}1.${NC} 测试发送: ${CYAN}./manage.sh test${NC}"
echo -e "  ${BOLD}2.${NC} 推送到 GitHub 并上传凭证后即可自动运行"
echo

# 询问是否立即测试
read -p "是否立即发送测试消息? (y/n) [默认: y]: " do_test
if [ "${do_test:-y}" = "y" ]; then
    echo
    echo -e "${YELLOW}正在发送测试消息...${NC}"
    python3 scripts/send.py --test
fi
