# WeChat Reminder — 微信定时提醒系统

> 电脑关机也不怕！基于 GitHub Actions 的云端微信定时提醒。

## 功能

- 📅 **每日提醒**：每天 9:00 发送自定义消息到你的微信
- 📆 **每周提醒**：每周指定日发送消息（默认：该给老妈买矿泉水了）
- ☁️ **云端运行**：GitHub Actions 免费托管，电脑关机照常发送
- 🔒 **安全可靠**：凭证存储在 GitHub Secrets 中，代码公开密钥安全

## 快速开始

### 前提条件

- GitHub 账号（[免费注册](https://github.com)）
- 微信（用于接收消息）
- Python 3.6+

### 第 1 步：申请微信测试公众号

打开 [微信测试号页面](https://mp.weixin.qq.com/debug/cgi-bin/sandbox?t=sandbox/login)，用微信扫码登录。

获取以下 4 个信息：

| 信息 | 位置 |
|------|------|
| `appID` | 页面顶部 |
| `appsecret` | 页面顶部 |
| `openid` | 扫码关注测试号后，在「用户列表」中 |
| `template_id` | 在「模板消息接口」新增模板后获得 |

新增模板时，模板内容请填写：

```
{{first.DATA}}
提醒内容：{{keyword1.DATA}}
时间：{{keyword2.DATA}}
{{remark.DATA}}
```

### 第 2 步：运行配置向导

```bash
./manage.sh setup
```

按提示填入凭证和消息内容。

### 第 3 步：本地测试

```bash
./manage.sh test
```

手机微信应收到一条测试消息。

### 第 4 步：部署到 GitHub

```bash
# 初始化 Git 仓库（如果还没做）
git init
git add .
git commit -m "init: WeChat Reminder"

# 登录 GitHub CLI（首次使用需要）
gh auth login

# 创建 GitHub 仓库并推送
gh repo create wechat-reminder --public --source=. --push

# 上传凭证到 GitHub Secrets
./manage.sh push-secrets
```

### 第 5 步：验证云端运行

1. 打开你的 GitHub 仓库
2. 进入 **Actions** 标签页
3. 点击 **WeChat Reminder** → **Run workflow** 手动触发
4. 检查手机微信是否收到消息

## 修改消息内容

编辑 `config.json`，然后推送：

```bash
# 方式一：用命令编辑
./manage.sh edit-config

# 方式二：手动编辑
nano config.json

# 推送到 GitHub（修改即时生效）
git commit -am "更新提醒内容"
git push
```

## 修改发送时间

编辑 `config.json` 中对应的时间字段，然后编辑 `.github/workflows/reminder.yml` 中的 cron 表达式：

> ⚠️ GitHub Actions cron 使用 **UTC 时间**，北京时间 = UTC + 8 小时

| 北京时间 | UTC cron |
|----------|----------|
| 08:00 | `0 0 * * *` |
| 09:00 | `0 1 * * *` |
| 12:00 | `0 4 * * *` |
| 20:00 | `0 12 * * *` |

修改后 `git push` 生效。

## 禁用/启用提醒

编辑 `config.json`，将对应类型的 `"enabled"` 设为 `false`：

```json
{
  "daily": {
    "enabled": false,
    "message": "..."
  }
}
```

推送后生效。

## 命令参考

| 命令 | 功能 |
|------|------|
| `./manage.sh setup` | 交互式配置向导 |
| `./manage.sh test` | 发送测试消息 |
| `./manage.sh send daily` | 手动发送每日消息 |
| `./manage.sh send weekly` | 手动发送每周消息 |
| `./manage.sh config` | 查看当前配置 |
| `./manage.sh edit-config` | 编辑配置 |
| `./manage.sh secrets` | 查看凭证状态 |
| `./manage.sh push-secrets` | 上传凭证到 GitHub Secrets |
| `./manage.sh status` | 查看系统状态 |

## 工作原理

```
GitHub Actions (每天 9:00 北京时间)
  → 运行 scripts/send.py
    → 调用微信测试公众号 API
      → 模板消息发送到你的微信
```

## 常见问题

### 消息在微信哪里看到？

消息出现在微信的「**订阅号**」文件夹中，作为一个叫"xxxx测试号"的公众号消息。

### 会不会消耗手机流量？

极少。每条消息只有几 KB。

### GitHub Actions 会过期吗？

公开仓库的 GitHub Actions 完全免费且无限制。只要仓库有活动（每天定时运行就算），就不会被暂停。

### 如果微信测试号 API 关闭了怎么办？

可以迁移到企业微信机器人 Webhook，修改 `scripts/send.py` 中的发送逻辑即可。
