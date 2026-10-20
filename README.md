# git-gh 便携式 Git / GitHub CLI 技能

一个自包含的 DSH skill：内置 Windows x64 便携版 **Git for Windows** 与 **GitHub CLI**，通过 `start.bat` 把 `HOME`、`GH_CONFIG_DIR`、Git 全局配置和 SSH 材料全部隔离在 skill 目录内。配套规则覆盖 Conventional Commits、SemVer、提交前密钥扫描、授权分级和 release notes 生成。

## 目录结构

```text
git-gh/
├─ SKILL.md                 # 技能指令（DSH 加载）
├─ start.bat                # 唯一入口：设置隔离环境并执行命令
├─ setup-auth.bat           # 首次生成/检查 SSH 密钥的便捷入口
├─ install.ps1              # 安装/更新到 <DSH_HOME>\skills\git-gh
├─ README.md
├─ THIRD_PARTY_NOTICES.md
├─ .github/
│  └─ workflows/
│     └─ validate.yml       # push/PR 校验：环境、脚本语法、必需文件、密钥扫描
├─ home/                    # 运行时使用：凭据、SSH、Git 配置（凭据不随技能分发）
│  ├─ .gitconfig
│  ├─ gh/                   # GH_CONFIG_DIR
│  └─ .ssh/                 # 内部密钥、known_hosts、config
├─ scripts/
│  ├─ check-env.ps1         # 校验隔离环境
│  ├─ diagnose.ps1          # 只读诊断
│  ├─ scan-secrets.ps1      # 密钥/Token 扫描
│  ├─ setup-auth.ps1        # 首次生成/检查 SSH 密钥
│  ├─ validate-commit-msg.ps1
│  ├─ release-notes.ps1     # 生成详细 release notes
│  └─ trust-host.ps1        # 校验 GitHub 主机指纹
└─ tools/
   ├─ git/                  # PortableGit
   ├─ gh/                   # gh.exe
   └─ VERSIONS.txt          # 版本、来源 URL、SHA256
```

## 安装

### Agent 一句话安装

对 agent 说：**“把 `https://github.com/Angel-GP/git-gh.skill.git` 克隆到 `$env:DSH_HOME\skills\git-gh`（未设置时 `$HOME\.dsh\skills\git-gh`），然后运行 `start.bat --bootstrap`。”**

等价的 PowerShell 命令：

```powershell
$dst = if ($env:DSH_HOME) { Join-Path $env:DSH_HOME 'skills\git-gh' } else { Join-Path $HOME '.dsh\skills\git-gh' }
git clone https://github.com/Angel-GP/git-gh.skill.git $dst
& "$dst\start.bat" --bootstrap
```

默认用 HTTPS，是因为它不需要预先配置 SSH 密钥，别人拿到就能装。只有在已经配置好 GitHub SSH key、或仓库是私有且你使用 SSH 认证时，才把地址换成 `git@github.com:Angel-GP/git-gh.skill.git`。

### 方式 A：用户级安装（推荐）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

默认目标：`$env:DSH_HOME\skills\git-gh`（未设置 `DSH_HOME` 时为 `%USERPROFILE%\.dsh\skills\git-gh`）。安装后 DSH 会自动发现，直接 `/git-gh` 或让 agent 使用即可。

覆盖更新：

```powershell
.\install.ps1 -Force
```

`home\` 不会被复制、覆盖或删除，已有凭据和 SSH 密钥保留在目标目录。

### 方式 B：项目级

把整个 `git-gh` 目录放到项目的 `.dsh\skills\git-gh`（或 `.agents\skills\git-gh`）。项目根目录是最近的 `.git` 祖先；没有 `.git` 时是当前工作目录。

## 使用

```powershell
# 首次加载 / 新会话：第一条命令必须是 bootstrap
# 创建 home 目录树 -> 校验隔离环境 -> 无密钥时生成并输出公钥
& ".\start.bat" --bootstrap

# 之后自检
& ".\start.bat" --check
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-env.ps1"

# 只读
& ".\start.bat" git status --short --branch
& ".\start.bat" gh auth status

# 扫描
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\scan-secrets.ps1" -Worktree
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\scan-secrets.ps1" -Staged
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\scan-secrets.ps1" -Tracked

# 交互式 shell（需要手动 gh auth login 时）
.\start.bat
```

所有命令都必须经过 `start.bat`。直接运行系统 `git` / `gh` 会绕过隔离环境，技能规则禁止这样做。

### 拉取别人的仓库

SSH 不是匿名协议：`git@github.com:...` 会先以你的 GitHub 账号认证，再由账号权限决定能否读取。

| 场景 | 建议 |
|---|---|
| 自己的仓库 | 优先 SSH |
| 他人的公开仓库，只读 | HTTPS，无需密钥 |
| 他人的公开仓库，坚持 SSH | 密钥必须已加入你的 GitHub 账号，且不能是只绑定单个仓库的 deploy key |
| 他人的私有仓库 | 必须先是 collaborator；SSH 不能绕过权限 |
| 权限未知 | 先询问，不猜 |

公开仓库示例：

```powershell
& ".\start.bat" git clone https://github.com/owner/repo.git
```

如果 SSH 拉取非自己仓库失败，先检查：

```powershell
& ".\start.bat" ssh -T git@github.com
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\setup-auth.ps1" -Mode Check
```

确认公钥已添加到**你自己的 GitHub 账号**，而不是只作为某个仓库的 deploy key。没有权限的私有仓库，SSH 和 HTTPS 都无法拉取，需要仓库管理员授权。

### 推送与 CI

标准流程：

```text
修改 → 密钥扫描 → 展示 diff → 确认 → commit → 确认 → push → CI 通过 → release
```

本仓库自带 `.github/workflows/validate.yml`，在 push/PR 时执行：

- `start.bat --check`
- `scripts/check-env.ps1`
- 所有 PowerShell 脚本语法解析
- 必需文件检查
- `scripts/scan-secrets.ps1 -Tracked`（扫描已跟踪文件，自动跳过 tools/home）

推送后检查：

```powershell
& ".\start.bat" gh run list --commit <sha> --limit 5
& ".\start.bat" gh run view <run-id>
& ".\start.bat" gh run view <run-id> --log-failed
```

CI 失败时停止后续发布，不要自动改代码或重推；先看失败 job 再决定。仓库没有 workflow 时，推送完成不等于 CI 通过，应明确说明并建议添加 workflow。

## 分享给他人 / 首次添加密钥

**分享前**：不要打包 `home\`。里面有私钥和 gh token。`install.ps1` 不会复制 `home\`；手动压缩时请排除它，或先删除 `home\`（对方首次运行会重建骨架）。

对方拿到 skill 后，首次加载时 Agent 会执行：

```powershell
& ".\start.bat" --bootstrap
```

`--bootstrap` 会先创建 `home\` 目录树、校验隔离环境，再执行 `setup-auth.ps1 -Mode Ensure`：无密钥时自动生成无口令专用密钥，并把公钥输出到对话；已有密钥时只输出公钥。下面是手动操作方式，按需要二选一：

### 方案 A：SSH（推荐，专用密钥）

```powershell
# 默认生成 ed25519 密钥，会提示设置口令（直接回车表示无口令）
.\setup-auth.bat

# 或明确不设口令（方便但安全性较低）
.\setup-auth.bat -Mode Generate -NoPassphrase

# 生成后按提示复制公钥到 https://github.com/settings/ssh/new
# 然后验证
.\setup-auth.bat -Mode Check
```

脚本只打印**公钥**和指纹，不读取、不打印私钥。密钥保存在 `home\.ssh\id_ed25519`。

> 本 skill 的 git 使用 `BatchMode=yes` 非交互运行。如果你给密钥设置了口令，必须先把它加载进 ssh-agent，否则 git 会直接报 `Permission denied` 而不是提示输入口令。最省事的方式是用 `-NoPassphrase` 生成专用密钥（文件 ACL 会限制为当前用户）。

### 方案 B：HTTPS + gh 登录（不用密钥）

```powershell
.\setup-auth.bat -Mode Login
# 按提示运行：
.\start.bat gh auth login
.\start.bat gh auth status
```

### 已有密钥怎么办

只由用户**手动**把密钥放到 `home\.ssh\id_ed25519`（或 `id_rsa`），然后运行 `setup-auth.bat -Mode Check`。不要让 agent 扫描 `C:\Users\<用户>\.ssh` 或复制未知密钥。

> ⚠️ 一旦 `home\` 里生成或导入了私钥、登录了 gh，这个文件夹就包含凭据。**不要再把整个文件夹分享给第三人**；重新分享前删除 `home\`，或只分享 `SKILL.md`、`start.bat`、`setup-auth.bat`、`scripts\`、`tools\` 和说明文件。

## 环境隔离

`start.bat` 设置：

| 变量 | 值 |
|---|---|
| `HOME` | `<skill>\home` |
| `GH_CONFIG_DIR` | `<skill>\home\gh` |
| `GIT_CONFIG_GLOBAL` | `<skill>\home\.gitconfig` |
| `GIT_CONFIG_NOSYSTEM` | `1` |
| `GIT_TERMINAL_PROMPT` | `0`（需要交互时设 `GITSKILL_ALLOW_PROMPT=1`） |
| `GIT_SSL_CAINFO` | `tools\git\ucrt64\etc\ssl\certs\ca-bundle.crt` |
| `PATH` | 前置 `tools\gh\bin`、`tools\git\cmd`、`tools\git\ucrt64\bin`、`tools\git\mingw64\bin`、`tools\git\usr\bin` |

首次运行会生成内部 `.gitconfig`、`.ssh\config` 和空的 `known_hosts`。`.gitconfig` 默认使用 OpenSSL HTTPS 后端（`http.sslBackend=openssl`）并禁用凭据 helper；如果 HTTPS 因 schannel 报 `SEC_E_NO_CREDENTIALS`，该设置可避免问题。

Git 的全局身份默认不设置；提交前按仓库配置：

```powershell
& ".\start.bat" git config user.name "Your Name"
& ".\start.bat" git config user.email "you@example.com"
```

## 安全模型

- 不读取、不打印、不提交私钥；只使用 `home\.ssh` 或 ssh-agent，不搜索全局用户目录。
- 提交前扫描工作区、暂存区、commit message 和分支名；命中私钥头/Token 特征直接拦截，只报位置不报原文。
- `.gitignore` 与 `git rm --cached` 都需要用户确认。
- 强制推送默认禁止，必须展示覆盖范围并二次确认。
- 所有输出脱敏；`home\` 内含凭据，不要提交、打包或分享。

## 工具版本与更新

见 `tools\VERSIONS.txt`。升级时替换 `tools\git` / `tools\gh`，并同步更新版本文件；建议先校验 SHA256。不要在执行任务过程中自动升级工具。

- Git for Windows：GPL-2.0，<https://gitforwindows.org/>
- GitHub CLI：MIT，<https://cli.github.com/>

## 故障排查

```powershell
& ".\start.bat" --check
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\check-env.ps1"
& ".\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\diagnose.ps1"
```

常见问题：

| 现象 | 处理 |
|---|---|
| `git` 解析到系统路径 | 必须用 `start.bat`；检查 PATH 是否被外部改写 |
| `gh auth status` 未登录 | `.\start.bat gh auth login`（用户手动完成浏览器流程） |
| SSH `Permission denied (publickey)` | 检查 `home\.ssh` 是否有密钥、`ssh-add -l` 是否有身份；不要自动切 HTTPS |
| HTTPS 私有仓库 401 | 登录 gh 后运行 `gh auth setup-git`，或改用 SSH |
| HTTPS 报 `schannel: SEC_E_NO_CREDENTIALS` | 确认内部 `.gitconfig` 有 `http.sslBackend=openssl`；`start.bat` 会自动补齐 |
| SSH 报 `couldn't create signal pipe` | 受限沙箱/终端禁止命名管道；改用 HTTPS，或在本机普通终端使用 SSH |
| 首次 SSH 主机密钥提示 | 默认 `accept-new`；需要严格校验时运行 `trust-host.ps1` |
| 命令卡住等待输入 | `GIT_TERMINAL_PROMPT=0` 已启用；不要在有交互提示时继续 |

## 卸载

删除安装目录即可：

```powershell
Remove-Item -Recurse -Force "$env:DSH_HOME\skills\git-gh"
```

如果目录内有 `home\` 凭据，删除前确认不再需要。
