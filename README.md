# git-gh 便携式 Git / GitHub CLI 技能

一个自包含的 DSH skill：内置 Windows x64 便携版 **Git for Windows** 与 **GitHub CLI**，所有 git/gh 命令通过 `start.bat` 在隔离环境中运行，不污染系统的 Git 配置和 SSH 目录。

## 安装（仅全局）

唯一安装目标：

```text
$env:DSH_HOME\skills\git-gh
```

未设置 `DSH_HOME` 时为 `$HOME\.dsh\skills\git-gh`。不支持项目级安装。

### Agent 一句话安装

对 agent 说：**“把 `https://github.com/Angel-GP/git-gh.skill.git` 克隆到 `$env:DSH_HOME\skills\git-gh`（未设置时 `$HOME\.dsh\skills\git-gh`）。”**

等价的 PowerShell 命令：

```powershell
$dst = if ($env:DSH_HOME) { Join-Path $env:DSH_HOME 'skills\git-gh' } else { Join-Path $HOME '.dsh\skills\git-gh' }
git clone https://github.com/Angel-GP/git-gh.skill.git $dst
```

不需要手动初始化。首次加载 skill 时，Agent 会自动执行 `start.bat --bootstrap`：

```text
创建 home\ 目录树 → 校验隔离环境 → 无密钥时生成密钥并输出公钥
```

默认使用 HTTPS，不需要预先配置 SSH 密钥。只有在已经配置 GitHub SSH key，或私有仓库使用 SSH 认证时，才把地址换成 `git@github.com:Angel-GP/git-gh.skill.git`。

### 手动安装 / 更新

```powershell
# 首次安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# 覆盖更新
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

`install.ps1` 同样只安装到全局 skill 目录，`home\` 不会被复制、覆盖或删除。

## 使用

```powershell
# 进入隔离 shell
.\start.bat

# 自检
.\start.bat --check

# 只读
.\start.bat git status --short --branch
.\start.bat gh auth status
```

所有 git/gh 命令都必须经过 `start.bat`。直接运行系统 `git` / `gh` 会绕过隔离环境。

## 打包与发布

推送 `vX.Y.Z` tag 会触发 `.github/workflows/package.yml`：

- 打包 `git-gh-vX.Y.Z.zip`，自动排除 `.git` 和 `home`
- 生成 `.sha256` 校验文件
- 上传为 GitHub Actions artifact
- 自动创建 GitHub Release，并把 zip 和 `.sha256` 作为附件

不需要本地打包，也不需要本地 gh 登录。`git push` tag 负责触发 Actions；Release 由 Actions 使用 `GITHUB_TOKEN` 创建。

## 首次认证

首次加载 skill 时，Agent 会自动执行 `start.bat --bootstrap`：

- 检查 `home\.ssh` 是否已有密钥；
- 没有则自动生成专用 ed25519 密钥；
- 把**公钥**和指纹输出到对话，供你复制并上传到 GitHub；
- 私钥只保存在 `home\.ssh\id_ed25519`，不会打印、不会上传。

你只需要把公钥添加到 <https://github.com/settings/ssh/new>。

### SSH（推荐）

如果自动流程没有完成，或你想手动重新生成：

```powershell
# 生成专用密钥，会提示设置口令；直接回车表示不设口令
.\setup-auth.bat

# 或明确不设口令
.\setup-auth.bat -Mode Generate -NoPassphrase

# 生成后把公钥添加到 https://github.com/settings/ssh/new
# 然后验证
.\setup-auth.bat -Mode Check
```

脚本只打印**公钥**和指纹，不读取、不打印私钥。密钥保存在 `home\.ssh\id_ed25519`。

> 本 skill 的 git 使用 `BatchMode=yes` 非交互运行。如果密钥设置了口令，必须先加载到 ssh-agent，否则会报 `Permission denied`。最省事的方式是用 `-NoPassphrase` 生成专用密钥。

### HTTPS + gh 登录

```powershell
.\setup-auth.bat -Mode Login
.\start.bat gh auth login
.\start.bat gh auth status
```

### 已有密钥

由用户自己把密钥放到 `home\.ssh\id_ed25519`（或 `id_rsa`），然后运行：

```powershell
.\setup-auth.bat -Mode Check
```

不要扫描 `C:\Users\<用户>\.ssh` 或复制未知密钥。

## 拉取别人的仓库

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
.\start.bat git clone https://github.com/owner/repo.git
```

如果 SSH 拉取非自己仓库失败，先检查：

```powershell
.\start.bat ssh -T git@github.com
.\start.bat powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-auth.ps1 -Mode Check
```

确认公钥已添加到**你自己的 GitHub 账号**，而不是某个仓库的 deploy key。

## 安全

- 私钥和 `home\` 不提交、不打包、不分享。
- 提交前扫描工作区、暂存区、commit message 和分支名；命中密钥/Token 直接拦截，只报位置不报原文。
- `.gitignore` 与 `git rm --cached` 都需要用户确认。
- 强制推送默认禁止，必须展示覆盖范围并二次确认。
- 所有输出脱敏；不要运行 `gh auth token` 或读取 `home\gh\hosts.yml`。

## 故障排查

```powershell
.\start.bat --check
.\start.bat powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-env.ps1
.\start.bat powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\diagnose.ps1
```

| 现象 | 处理 |
|---|---|
| `git` 解析到系统路径 | 必须用 `start.bat`；检查 PATH 是否被外部改写 |
| `gh auth status` 未登录 | `.\start.bat gh auth login` |
| SSH `Permission denied (publickey)` | 检查 `home\.ssh` 是否有密钥、公钥是否加到 GitHub 账号 |
| HTTPS 私有仓库 401 | 登录 gh 后运行 `gh auth setup-git`，或改用 SSH |
| HTTPS 报 `schannel: SEC_E_NO_CREDENTIALS` | 确认内部 `.gitconfig` 有 `http.sslBackend=openssl`；`start.bat` 会自动补齐 |
| SSH 报 `couldn't create signal pipe` | 受限沙箱/终端禁止命名管道；改用 HTTPS，或在本机普通终端使用 SSH |
| 首次 SSH 主机密钥提示 | 默认 `accept-new`；需要严格校验时运行 `scripts\trust-host.ps1` |
| 命令卡住等待输入 | `GIT_TERMINAL_PROMPT=0` 已启用；不要在有交互提示时继续 |

## 卸载

```powershell
Remove-Item -Recurse -Force "$env:DSH_HOME\skills\git-gh"
```

如果目录内有 `home\` 凭据，删除前确认不再需要。

## License

Original git-gh code and documentation are licensed under the **MIT License**. See `LICENSE`.

Bundled third-party tools keep their own licenses:

- Git for Windows: **GPL-2.0**
- GitHub CLI: **MIT**

See `THIRD_PARTY_NOTICES.md` for details and source links.

内置工具版本与许可证见 `tools\VERSIONS.txt` 和 `THIRD_PARTY_NOTICES.md`。
