#!/usr/bin/env python3
"""WeChat Reminder — 微信模板消息发送器

通过微信测试公众号 API 发送模板消息。
支持本地 (.env) 和 GitHub Actions (环境变量) 两种凭证来源。

用法:
    python3 scripts/send.py --type daily       # 发送每日消息
    python3 scripts/send.py --type weekly      # 发送每周消息
    python3 scripts/send.py --message "hello"  # 发送自定义消息
    python3 scripts/send.py --test             # 发送测试消息
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ── 常量 ────────────────────────────────────────────────
WX_TOKEN_URL = "https://api.weixin.qq.com/cgi-bin/token"
WX_SEND_URL = "https://api.weixin.qq.com/cgi-bin/message/template/send"
TOKEN_CACHE_FILE = "/tmp/wx_reminder_token.json"
TOKEN_BUFFER_SECONDS = 300  # 提前 5 分钟刷新 token
MAX_RETRIES = 3
RETRY_BACKOFF = [2, 4, 8]

# 项目根目录（send.py 在 scripts/ 下）
PROJECT_ROOT = Path(__file__).resolve().parent.parent


# ── 日志 ────────────────────────────────────────────────
def log(level: str, msg: str):
    """写入结构化日志到文件和控制台。"""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} [{level}] {msg}"
    print(line, file=sys.stderr)
    try:
        log_dir = PROJECT_ROOT / "logs"
        log_dir.mkdir(exist_ok=True)
        log_file = log_dir / "wechat-reminder.log"
        # 日志轮转：超过 1MB 则重命名
        if log_file.exists() and log_file.stat().st_size > 1_000_000:
            backup = log_dir / "wechat-reminder.log.1"
            backup.unlink(missing_ok=True)
            log_file.rename(backup)
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass  # 写日志失败不阻塞发送


# ── 凭证加载 ────────────────────────────────────────────
def load_credentials() -> dict:
    """加载微信凭证。优先环境变量 (GitHub Actions)，其次 .env 文件 (本地)。"""
    creds = {}
    keys = ["WX_APPID", "WX_SECRET", "WX_OPENID", "WX_TEMPLATE_ID"]

    for key in keys:
        val = os.environ.get(key, "").strip()
        if val:
            creds[key] = val
            continue
        # 从 .env 文件读取
        val = _read_env_file(key)
        if val:
            creds[key] = val

    missing = [k for k in keys if not creds.get(k)]
    if missing:
        log("ERROR", f"缺少凭证: {', '.join(missing)}。请运行 ./manage.sh setup")
        sys.exit(1)

    return creds


def _read_env_file(key: str) -> str:
    """从项目根目录的 .env 文件读取指定 key。"""
    env_file = PROJECT_ROOT / ".env"
    if not env_file.exists():
        return ""
    try:
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    if k.strip() == key:
                        return v.strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


# ── Token 管理 ──────────────────────────────────────────
def get_access_token(appid: str, secret: str) -> str:
    """获取 access_token，优先使用缓存。"""
    # 尝试读取缓存
    try:
        with open(TOKEN_CACHE_FILE, "r") as f:
            cache = json.load(f)
            if cache.get("appid") == appid:
                expires_at = cache.get("expires_at", 0)
                if time.time() + TOKEN_BUFFER_SECONDS < expires_at:
                    return cache["token"]
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        pass

    # 请求新 token
    url = f"{WX_TOKEN_URL}?grant_type=client_credential&appid={appid}&secret={secret}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.URLError as e:
        log("ERROR", f"获取 access_token 网络错误: {e}")
        raise

    if "access_token" not in data:
        log("ERROR", f"获取 access_token 失败: errcode={data.get('errcode')} {data.get('errmsg')}")
        raise RuntimeError(f"WeChat token error: {data}")

    token = data["access_token"]
    expires_in = data.get("expires_in", 7200)

    # 写入缓存
    cache = {
        "appid": appid,
        "token": token,
        "expires_at": time.time() + expires_in,
    }
    try:
        with open(TOKEN_CACHE_FILE, "w") as f:
            json.dump(cache, f)
    except OSError:
        pass

    return token


def clear_token_cache():
    """清除 token 缓存（token 失效时调用）。"""
    try:
        os.remove(TOKEN_CACHE_FILE)
    except FileNotFoundError:
        pass


# ── 配置加载 ────────────────────────────────────────────
def load_config() -> dict:
    """加载 config.json。"""
    config_file = PROJECT_ROOT / "config.json"
    if not config_file.exists():
        log("ERROR", "config.json 不存在，请运行 ./manage.sh setup")
        sys.exit(1)
    with open(config_file, "r", encoding="utf-8") as f:
        return json.load(f)


# ── 消息发送 ────────────────────────────────────────────
def send_template_message(creds: dict, content: str) -> dict:
    """发送模板消息到微信。返回 API 响应 JSON。"""
    beijing_now = datetime.now(timezone(timedelta(hours=8)))

    body = {
        "touser": creds["WX_OPENID"],
        "template_id": creds["WX_TEMPLATE_ID"],
        "data": {
            "first": {"value": "⏰ 定时提醒"},
            "keyword1": {"value": content},
            "keyword2": {"value": beijing_now.strftime("%Y-%m-%d %H:%M:%S")},
            "remark": {"value": "来自 WeChat Reminder"},
        },
    }

    data_bytes = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        WX_SEND_URL,
        data=data_bytes,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )

    for attempt in range(MAX_RETRIES + 1):
        try:
            token = get_access_token(creds["WX_APPID"], creds["WX_SECRET"])
            url = f"{WX_SEND_URL}?access_token={token}"
            req.full_url = url  # 更新 URL 中的 token

            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode())

            errcode = result.get("errcode", -1)

            # 成功
            if errcode == 0:
                return result

            # Token 失效 —— 清除缓存重试
            if errcode in (40001, 40014, 42001):
                log("WARN", f"access_token 失效 (errcode={errcode})，刷新后重试")
                clear_token_cache()
                if attempt < MAX_RETRIES:
                    time.sleep(RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)])
                    continue
                return result

            # 频率限制 —— 等待后重试
            if errcode in (45009, 45011):
                if attempt < MAX_RETRIES:
                    wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
                    log("WARN", f"频率限制 (errcode={errcode})，{wait}s 后重试")
                    time.sleep(wait)
                    continue
                return result

            # 其他 API 错误
            return result

        except urllib.error.URLError as e:
            if attempt < MAX_RETRIES:
                wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
                log("WARN", f"网络错误: {e}，{wait}s 后重试 (第 {attempt + 1}/{MAX_RETRIES} 次)")
                time.sleep(wait)
            else:
                log("ERROR", f"网络错误，已重试 {MAX_RETRIES} 次: {e}")
                raise

    return {"errcode": -1, "errmsg": "max retries exhausted"}


# ── 辅助 ────────────────────────────────────────────────
def is_weekly_day(day_of_week: int) -> bool:
    """检查今天是否是配置的每周发送日（北京时间）。"""
    beijing_now = datetime.now(timezone(timedelta(hours=8)))
    # Python: Monday=0, Sunday=6. config 中: Sunday=0, Monday=1, ...
    python_weekday = beijing_now.weekday()  # Monday=0
    config_to_python = {0: 6, 1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}
    return python_weekday == config_to_python.get(day_of_week, -1)


def send_one(creds: dict, label: str, msg: str) -> bool:
    """发送一条消息，返回是否成功。"""
    log("INFO", f"[{label}] 发送中...")
    try:
        result = send_template_message(creds, msg)
    except Exception as e:
        log("ERROR", f"[{label}] 发送失败: {e}")
        return False

    errcode = result.get("errcode", -1)
    if errcode == 0:
        msgid = result.get("msgid", "N/A")
        log("INFO", f"[{label}] 发送成功! msgid={msgid}")
        return True
    else:
        log("ERROR", f"[{label}] API 错误: errcode={errcode} errmsg={result.get('errmsg', 'unknown')}")
        return False


# ── 主逻辑 ──────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="WeChat Reminder 消息发送器")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--type", choices=["daily", "weekly"], help="发送指定类型的提醒")
    group.add_argument("--message", type=str, help="发送自定义消息")
    group.add_argument("--test", action="store_true", help="发送测试消息")
    group.add_argument("--all", action="store_true", help="发送所有启用的提醒（用于 GitHub Actions 定时触发）")
    args = parser.parse_args()

    creds = load_credentials()

    # ── 测试消息 ──
    if args.test:
        msg = "【测试消息】WeChat Reminder 系统配置成功！🎉"
        ok = send_one(creds, "test", msg)
        sys.exit(0 if ok else 1)

    # ── 自定义消息 ──
    if args.message:
        ok = send_one(creds, "custom", args.message)
        sys.exit(0 if ok else 1)

    # ── 单类型消息 ──
    if args.type:
        config = load_config()
        section = config.get(args.type, {})
        if not section.get("enabled", True):
            log("INFO", f"[{args.type}] 已禁用，跳过发送")
            sys.exit(0)
        msg = section.get("message", "").strip()
        if not msg:
            log("ERROR", f"[{args.type}] 消息内容为空，请检查 config.json")
            sys.exit(1)
        ok = send_one(creds, args.type, msg)
        sys.exit(0 if ok else 1)

    # ── 全部消息（GitHub Actions 定时触发）──
    if args.all:
        config = load_config()
        success_all = True

        # 每日消息
        daily = config.get("daily", {})
        if daily.get("enabled", True):
            msg = daily.get("message", "").strip()
            if msg:
                if not send_one(creds, "daily", msg):
                    success_all = False
            else:
                log("WARN", "[daily] 消息内容为空，跳过")
        else:
            log("INFO", "[daily] 已禁用，跳过")

        # 每周消息（仅在配置的星期几发送）
        weekly = config.get("weekly", {})
        if weekly.get("enabled", True):
            day_of_week = weekly.get("day_of_week", 0)
            if is_weekly_day(day_of_week):
                msg = weekly.get("message", "").strip()
                if msg:
                    if not send_one(creds, "weekly", msg):
                        success_all = False
                else:
                    log("WARN", "[weekly] 消息内容为空，跳过")
            else:
                today_name = ["周一","周二","周三","周四","周五","周六","周日"]
                cfg_name = ["周日","周一","周二","周三","周四","周五","周六"]
                log("INFO", f"[weekly] 今天是{today_name[datetime.now(timezone(timedelta(hours=8))).weekday()]}，配置为{cfg_name[day_of_week]}，跳过")
        else:
            log("INFO", "[weekly] 已禁用，跳过")

        if not success_all:
            log("ERROR", "部分消息发送失败")
            sys.exit(1)
        sys.exit(0)


if __name__ == "__main__":
    main()
