---
name: git-gh
description: 便携式 Git/GitHub CLI 操作技能。通过自带 start.bat 隔离运行 PortableGit 与 gh（HOME、GH_CONFIG_DIR 均指向 skill 内部目录），按授权分级执行只读/写命令，遵循 Conventional Commits、SemVer 与发布流程，提交前扫描并拦截密钥/Token。适用于克隆、提交、推送、打标签、创建 GitHub Release、PR/Issue 等任务。
whenToUse: 用户要求执行 git 或 gh 操作（clone/status/commit/push/tag/release/PR/issue），或要求按规范管理版本与发布时。
---

# git-gh：便携式 Git / GitHub CLI 技能

本技能自带 Windows x64 便携版 Git 与 GitHub CLI。**所有 git/gh 命令必须通过本目录下的 `start.bat` 启动**，以保证 `HOME`、`GH_CONFIG_DIR`、Git 全局配置和 SSH 材料都落在 skill 内部，不污染用户全局环境。

下文用 `<skill>` 表示本 `SKILL.md` 所在目录的绝对路径。首次使用先解析：

```powershell
$Skill = (Resolve-Path "<本文件所在目录>").Path
```

如果忘记路径，只读定位：

```powershell
Get-ChildItem -Path "$env:DSH_HOME\skills", ".dsh\skills" -Filter start.bat -Recurse -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty FullName
```

## 0. 不可违反的硬规则

1. **首次加载或新会话首次使用时，第一条实际命令必须是 `start.bat --bootstrap`**（依次执行 `--check`、`check-env.ps1`、`setup-auth.ps1 -Mode Ensure`），通过后才允许执行其他 git/gh 操作。之后所有 git/gh 命令必须通过 `<skill>\start.bat`；禁止直接调用系统 git/gh，禁止绕过 `start.bat` 设置环境。
   - `--bootstrap` 会自动创建 `home\` 目录树；若 `home\.ssh` 下没有 `id_ed25519` / `id_rsa` / `id_ecdsa`，自动生成无口令专用密钥，并把**公钥行**输出到对话供用户添加到 GitHub；若生成失败则停止，建议在普通终端运行 `setup-auth.bat` 或改用 HTTPS。绝不输出私钥。
2. 用户未提供仓库地址时**主动询问**，不猜测、不从全局配置推断；仓库上下文只记在本次对话中，不写入全局配置。
3. 有内部 SSH 密钥或 ssh-agent 时优先 SSH；没有条件时可用 HTTPS。HTTPS 改 SSH 必须先展示完整命令并取得同意。
4. 只读命令展示完整命令后自动执行；**所有写命令**（add/commit/push/tag/merge/rebase/reset/gh 写操作等）必须展示完整命令、影响范围、风险，并等待用户明确同意。一次同意只对当前展示的那一条命令有效。
5. 提交信息必须使用 Conventional Commits：`<type>(<scope>): <描述>`；type 只能是 `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert`。
6. 每次代码修改后主动询问是否提交；提交前必须展示 `git status`、`git diff --staged` 和拟用 commit message，只提交用户确认的文件。
7. 打 tag / 发布 release 前必须展示完整命令与详细 release notes，取得确认后才执行。
8. 禁止无提示执行 `push --force`、`-f`、`--force-with-lease`；强制推送必须展示被覆盖范围，并单独进行二次风险确认。
9. 遵循 SemVer，tag 固定 `vX.Y.Z`；升级前确认 PATCH/MINOR/MAJOR；MAJOR 或 `0.y.z` 阶段的破坏性变更必须再次取得明确确认。
10. 合并冲突、权限拒绝、非快进推送、SSH 连接失败时**停止自动流程**等待指示；绝不自动执行 `reset --hard` 或 merge/rebase 的 `--continue`/`--abort`。
11. 不读取、不打印、不提交私钥；只用 skill 内部 `home\.ssh` 或 ssh-agent，不去 `C:\Users\<用户>\.ssh` 等全局目录翻找未知密钥。
12. 提交前扫描代码、提交信息、分支名；命中私钥头、Token 特征等敏感内容直接拦截，只报位置不报原文；`.gitignore` 与 `git rm --cached` 都要先征得同意。
13. 所有输出脱敏；操作结束返回已执行命令、退出码、变更摘要；报错附排查提示和只读诊断命令。
14. Release notes 自动按 type 整理变更列表；存在破坏性变更时必须在介绍顶部显著提示。
15. `.github/workflows/*` 等工作流文件按普通代码提交，使用 `ci:` 类型，正常参与 changelog。

## 1. 启动与环境

### 1.0 首次加载：必须先启动 start.bat，再自动准备密钥

DSH 加载 skill 时只会注入本文件的指令，**不会自动执行 `.bat`**。因此本 skill 明确规定：

> 每次新会话第一次使用、或首次安装后，解析 `$Skill` 路径之后，**第一条实际执行的命令必须是 `start.bat --bootstrap`**。它会先创建 `home\` 目录树，再校验隔离环境，最后在无密钥时自动生成密钥并输出公钥。失败则停止并报告，不得直接用系统 git/gh 兜底。

```powershell
& "$Skill\start.bat" --bootstrap
```

`--bootstrap` 等价于按顺序执行：

```powershell
# 1) 启动隔离环境，创建 home\、home\gh、home\.ssh、.gitconfig、ssh config
& "$Skill\start.bat" --check

# 2) 校验 HOME / GH_CONFIG_DIR / GIT_CONFIG_GLOBAL 与工具路径
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\check-env.ps1"

# 3) 无密钥则自动生成无口令专用密钥，并打印公钥
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\setup-auth.ps1" -Mode Ensure
```

第 3 步行为：

- `home\.ssh` 已有 `id_ed25519` / `id_rsa` / `id_ecdsa`：直接打印对应**公钥**和指纹，不重新生成。
- 没有任何密钥：自动生成 `id_ed25519`（无口令，ACL 限制为当前用户），打印**公钥**和指纹。
- 生成失败（例如受限沙箱禁止 `ssh-keygen`）：停止，提示用户在普通终端运行 `setup-auth.bat`，或改用 HTTPS；不得自动改用系统 git/gh。

Agent 必须把输出中的公钥行（`ssh-ed25519 ...`）原样贴到对话里，并请用户添加到 <https://github.com/settings/ssh/new>。**只输出公钥，绝不输出私钥。** 这是用户明确要求的首次初始化例外；生成后仍需报告生成路径和结果。

### 1.1 标准调用方式

```powershell
& "$Skill\start.bat" git status --short --branch
& "$Skill\start.bat" gh auth status
```

需要运行辅助脚本时，同样经由 `start.bat`：

```powershell
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -Worktree
```

### 1.2 自检结果确认

确认：`HOME=<skill>\home`、`GH_CONFIG_DIR=<skill>\home\gh`、`git`/`gh`/`ssh` 都解析到 `<skill>\tools\...`。任何一项不符，停止并修复，不要继续。

### 1.3 环境约束

- `start.bat` 已设置：内部 `HOME`、`GH_CONFIG_DIR`、`GIT_CONFIG_GLOBAL`、`GIT_CONFIG_NOSYSTEM=1`、`GIT_TERMINAL_PROMPT=0`、分页器关闭、编辑器关闭。
- 需要交互式登录/输入密码时，让用户在自己的终端运行 `start.bat gh auth login`；Agent 不代替用户完成浏览器/密码交互。
- 不要设置或导出 `GH_TOKEN`、`GITHUB_TOKEN` 到命令里；不要在聊天中索要 Token。
- 永远不要运行 `gh auth token`、`git config --get credential.helper` 之类的命令去读取凭据；`gh auth status` 足够。

## 2. 会话仓库上下文

用户提供仓库地址后，在对话中维护以下上下文（用表格复述一次，后续复用）：

| 字段 | 含义 |
|---|---|
| `repo_url` | 用户提供的原始地址（展示时脱敏） |
| `owner` | 组织/用户 |
| `repo` | 仓库名 |
| `remote` | 默认 `origin` |
| `default_branch` | 用户确认的默认分支；未知则询问 |
| `protocol` | `ssh` 或 `https` |
| `auth_mode` | `ssh-agent` / `internal-key` / `gh-token` / `anonymous` |
| `workspace` | 本地工作目录绝对路径 |

规则：

- 只在本次对话记忆；**不写入** `~/.gitconfig`、gh 配置、环境变量或仓库文件。
- 用户未给地址时，问一个最短问题：`请提供仓库地址（owner/repo 或完整 URL），以及默认分支。`
- 可以只读检查当前目录的 remote 作为**候选**，但必须让用户确认，不能直接当作已绑定仓库。
- 地址变化（换仓库、换 fork、换协议）时更新上下文并重新确认。

## 3. 协议与认证

### 3.1 选择顺序

1. 检查 skill 内部密钥（只看文件名，不读内容）：`home\.ssh\id_ed25519`、`id_rsa` 等是否存在；检查 `ssh-add -l` 是否有可用身份。
2. 有内部密钥或 ssh-agent，且用户对仓库有写权限：优先 SSH。
3. 无密钥、仅拉取他人的公开仓库、或用户明确要求 HTTPS：使用 HTTPS。
4. 不在全局用户目录搜索密钥；不把全局密钥复制进 skill；不打印密钥内容。
5. 用户明确给出外部密钥路径时，先展示 `GIT_SSH_COMMAND=ssh -i <path>` 的完整命令、影响和风险，征得同意后才使用；不得自行扫描全局 `.ssh`。

SSH 地址格式：`git@github.com:<owner>/<repo>.git`
HTTPS 地址格式：`https://github.com/<owner>/<repo>.git`

### 3.2 HTTPS 切换为 SSH

必须展示完整命令、影响和风险，等待同意后才执行：

```powershell
& "$Skill\start.bat" git remote set-url origin git@github.com:<owner>/<repo>.git
& "$Skill\start.bat" git remote -v
& "$Skill\start.bat" ssh -T git@github.com
```

说明：`ssh -T` 成功时通常返回退出码 1 并提示 `successfully authenticated`，这不是失败；真正失败时按第 9 节处理。切换后如果推送失败，不要自动切回 HTTPS，先询问。

### 3.3 gh 认证

```powershell
& "$Skill\start.bat" gh auth status
```

未登录时，让用户自行运行：

```powershell
& "$Skill\start.bat" gh auth login
```

如需让 git 的 HTTPS 操作复用 gh 凭据，展示并征得同意后运行：

```powershell
& "$Skill\start.bat" gh auth setup-git
```

该命令只写入 skill 内部 `GIT_CONFIG_GLOBAL`，不会改用户全局配置。不要读取 `home\gh\hosts.yml` 的内容。

### 3.4 首次配置与分享给他人

分享 skill 前必须排除 `home\`（私钥、gh token）。对方拿到后，首次加载按 1.0 自动执行：

```powershell
& "$Skill\start.bat" --bootstrap
```

`--bootstrap` 会先创建目录树、校验隔离环境，再执行 `setup-auth.ps1 -Mode Ensure`：无密钥时自动生成专用 ed25519 密钥并打印公钥；已有密钥时只打印公钥。Agent 必须把公钥行贴到对话里，让用户添加到 <https://github.com/settings/ssh/new>。

用户也可以手动操作：

```powershell
# 生成专用 SSH 密钥（交互式设置口令）
& "$Skill\setup-auth.bat"

# 或明确不设口令
& "$Skill\setup-auth.bat" -Mode Generate -NoPassphrase

# 验证
& "$Skill\setup-auth.bat" -Mode Check

# 不想用 SSH：走 HTTPS + gh 登录
& "$Skill\setup-auth.bat" -Mode Login
& "$Skill\start.bat" gh auth login
```

- 只有首次 `-Mode Ensure` 允许自动生成专用密钥并输出公钥；除此之外，Agent 不得代替用户生成/导入密钥，也不得读取或打印私钥。
- 已有密钥只能由用户手动放入 `home\.ssh`；不要扫描 `C:\Users\<用户>\.ssh`。
- 一旦 `home\` 含私钥或 gh 凭据，不要再次分享整个文件夹；重新分享前删除 `home\`。

## 4. 授权分级

### L0 只读：展示完整命令后自动执行

`status`、`log`、`diff`、`show`、`blame`、`shortlog`、`describe`、`rev-parse`、`branch --list`、`tag --list`、`remote -v`、`config --get`、`ls-remote`、`cat-file`、`show-ref`、`gh repo view`、`gh pr view/list`、`gh issue view/list`、`gh release view/list`、`gh api` 的 GET、`gh auth status`、`ssh -T`、`ssh-add -l`。

即使只读，也要先展示命令；输出可能含敏感信息时先脱敏。

### L1 本地写 / 低风险写：展示命令 + 影响 + 风险，等待同意

`clone`、`init`、`fetch`、`pull`、`checkout`、`switch`、`add`、`commit`、`tag`、`merge`、`rebase`、`stash`、`reset`、`clean`、`restore`、`rm --cached`、`config set`、`remote set-url`、`gh auth login/logout/setup-git`。

### L2 远程写 / 高风险：展示命令 + 影响范围 + 风险，等待同意；强制操作二次确认

`push`、`push --tags`、`push --force*`、`gh repo create/edit/delete`、`gh pr create/merge/close`、`gh release create/edit/delete`、`gh api` 的 POST/PATCH/PUT/DELETE、任何删除远端分支/标签/release 的操作。

确认格式固定：

```text
命令：<完整命令>
影响：<会改哪些文件/分支/远端/发布>
风险：<可逆性、覆盖范围、权限要求>
请回复“确认执行”以运行这一条命令；本次确认仅对上面这条命令有效。
```

用户没有明确同意（例如只说“继续”“可以看看”）时，不得执行写命令。命令内容变化（路径、分支、message、remote）必须重新确认。

## 5. 提交工作流（每次代码修改后）

### 5.1 先问是否提交

代码修改完成后，先报告改了什么，再问：

> 是否现在提交？如果要提交，请确认要包含的文件（默认只提交本次修改相关文件，不使用 `git add -A`）。

用户说“不用/稍后”就停止，不要自动提交。

### 5.2 查看与选择文件（L0）

```powershell
& "$Skill\start.bat" git status --short --branch
& "$Skill\start.bat" git diff
& "$Skill\start.bat" git diff --staged
```

只提交用户确认的文件。禁止默认 `git add .`、`git add -A`、`git commit -a`。

### 5.3 提交前安全扫描（L0）

先扫工作区候选文件，再暂存，再扫暂存区：

```powershell
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -Worktree
```

若当前目录不是仓库根目录，追加 `-RepoPath "<仓库路径>"`；git 命令可用 `git -C "<仓库路径>" ...`。

命中时：停止，不暂存、不提交；只报告规则、文件、行号；建议 `.gitignore`（写之前征得同意），已跟踪文件建议 `git rm --cached -- <path>`（同样先征得同意）。

### 5.4 暂存（L1，需同意）

```powershell
& "$Skill\start.bat" git add -- <file1> <file2>
```

展示命令、影响文件列表、风险（会把内容放入 index），等待同意。

### 5.5 展示待提交内容（L0）

```powershell
& "$Skill\start.bat" git status --short
& "$Skill\start.bat" git diff --staged
```

`git diff --staged` 必须完整展示；内容过长时分段展示，不能只说“已查看”。同时展示拟用 commit message 全文。

### 5.6 校验 commit message（L0）

```powershell
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\validate-commit-msg.ps1" -MessageFile "<message-file>"
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -MessageFile "<message-file>"
```

### 5.7 提交（L1，需同意）

```powershell
& "$Skill\start.bat" git commit -m "<type>(<scope>): <描述>"
```

多行 message 用 `-F <file>`，不要打开编辑器。展示命令、影响（哪个分支、哪些文件、message 全文）、风险（生成提交对象；尚未推送），等待明确同意后执行。

提交成功后报告：commit hash、分支、文件数、message；然后**单独**询问是否推送。

## 6. Conventional Commits 规范

格式：

```text
<type>(<scope>): <描述>

<可选正文>

<可选 footer>
```

- `type` 只能是：`feat`、`fix`、`docs`、`style`、`refactor`、`perf`、`test`、`build`、`ci`、`chore`、`revert`。
- `scope` 可选，小写名词，如 `api`、`auth`、`ui`。
- 描述用祈使句、现在时、结尾不加句号，建议 ≤ 72 字符。
- 破坏性变更：`feat(api)!: ...`，并在 footer 写 `BREAKING CHANGE: <迁移说明>`。
- `.github/workflows/*` 等工作流文件按普通代码提交，使用 `ci:` 类型，正常参与 changelog。
- 不把多个无关改动塞进一个提交；不写 `update`、`fix bug`、`修改` 这类无信息量的 message。

示例：

```text
feat(auth): add refresh-token rotation
fix(api): handle empty pagination cursor
docs: document portable environment variables
ci: pin actions/checkout to v4
refactor(core)!: drop Node 16 support

BREAKING CHANGE: minimum runtime is now Node 18.
```

## 7. 推送与强制推送

### 7.1 普通推送（L2，需同意）

```powershell
& "$Skill\start.bat" git push origin <branch>
```

展示：目标 remote、目标分支、领先/落后提交数（`git log --oneline origin/<branch>..HEAD`，只读）、风险（更新远端分支）。等待同意。

非快进（non-fast-forward）时停止：不要自动 `--force`，不要自动 merge/rebase。先展示只读诊断：

```powershell
& "$Skill\start.bat" git fetch origin
& "$Skill\start.bat" git log --oneline HEAD..origin/<branch>
& "$Skill\start.bat" git log --oneline origin/<branch>..HEAD
```

### 7.2 强制推送（默认禁止；二次确认）

只有用户明确要求时才讨论。优先 `--force-with-lease`，禁止使用 `-f` 简写。

必须先展示被覆盖范围：

```powershell
& "$Skill\start.bat" git log --oneline HEAD..origin/<branch>
& "$Skill\start.bat" git diff --stat origin/<branch>...HEAD
```

然后展示完整命令：

```powershell
& "$Skill\start.bat" git push --force-with-lease origin <branch>
```

第一次确认后，再进行**单独的二次风险确认**，要求用户回复固定短语 `FORCE PUSH`；未收到固定短语不得执行。若目标是 `main`/`master`/默认分支，额外提示分支保护与团队影响。绝不自动强制推送。

## 8. 标签与 Release

### 8.1 版本类型确认（SemVer）

先只读查看当前版本：

```powershell
& "$Skill\start.bat" git describe --tags --abbrev=0
& "$Skill\start.bat" git tag --sort=-v:refname | Select-Object -First 10
```

询问并确认升级类型：

| 类型 | 适用 | 版本变化 |
|---|---|---|
| PATCH | 向后兼容的修复 | `v1.2.3 -> v1.2.4` |
| MINOR | 向后兼容的新功能 | `v1.2.3 -> v1.3.0` |
| MAJOR | 破坏性变更 | `v1.2.3 -> v2.0.0` |

`0.y.z` 阶段：破坏性变更通常升 MINOR（`v0.3.1 -> v0.4.0`），但必须明确告知并取得确认；不得擅自把 `0.x` 升成 `1.0.0`。MAJOR 或 `0.y.z` 破坏性变更需要用户再次明确确认。

tag 固定 `vX.Y.Z`；不使用 `v1.2`、`1.2.3`、`release-1.2.3`。

### 8.2 生成 release notes（L0，本地写文件）

```powershell
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\release-notes.ps1" `
  -Version "vX.Y.Z" -FromTag "vOLD" -OutputPath ".git\gitskill-release-notes.md"
```

脚本自动按 type 归类，提取 `!` / `BREAKING CHANGE:`，生成：版本摘要、新增、修复、破坏性变更提示、升级步骤、完整变更链接（GitHub compare）。必须完整展示 notes 并让用户确认/修改；缺 compare 链接时补全。当前目录不是仓库根目录时追加 `-RepoPath "<仓库路径>"`。

发布前扫描 notes（把 notes 当作提交信息扫描）：

```powershell
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -MessageFile ".git\gitskill-release-notes.md"
```

### 8.3 打 tag（L1，需同意）

```powershell
& "$Skill\start.bat" git tag -a vX.Y.Z -m "vX.Y.Z"
& "$Skill\start.bat" git tag -n99 vX.Y.Z
```

展示 tag 名、目标 commit、annotation、影响（本地新增 tag，不推送），等待同意。

### 8.4 推送 tag（L2，需同意）

```powershell
& "$Skill\start.bat" git push origin vX.Y.Z
```

### 8.5 创建 GitHub Release（L2，需同意）

仅 GitHub 仓库可用：

```powershell
& "$Skill\start.bat" gh release create vX.Y.Z --verify-tag --title "vX.Y.Z" --notes-file ".git\gitskill-release-notes.md"
```

展示：tag、标题、notes 全文、目标仓库、是否 draft/prerelease、风险（公开可见、通知订阅者），等待同意。成功后用只读命令获取 URL：

```powershell
& "$Skill\start.bat" gh release view vX.Y.Z --json url,name,tagName,isDraft,isPrerelease
```

非 GitHub 仓库：说明 `gh release` 不可用，停在“已打 tag/已推送 tag”，不要伪造 release。

## 9. 异常处理（一律先停）

| 情况 | 必须做 | 禁止 |
|---|---|---|
| 合并冲突 | `git status --short`；列出冲突文件；询问用户如何处理 | 自动 `merge/rebase --continue/--abort`、`reset --hard`、`checkout --ours/--theirs` |
| 权限拒绝 / publickey | `ssh -T git@github.com`、`ssh-add -l`、列出 `home\.ssh` 文件名；判断是“已配置 SSH”还是“无密钥” | 去全局 `.ssh` 找密钥、打印私钥、自动改 HTTPS |
| 非快进推送 | 停止；展示 `git fetch`（需同意）后的领先/落后；询问 merge/rebase/取消 | 自动 force、自动 rebase |
| SSH 连接失败 | 若本来配置了 SSH：停止并引导排查（DNS/22 端口/known_hosts/agent）；若无密钥：告知并建议 HTTPS，切换需同意 | 自动切换协议、自动重建密钥 |
| SSH 报 `couldn't create signal pipe` | 受限沙箱/终端禁止命名管道；改用 HTTPS，或让用户在本机普通终端执行 SSH | 反复重试、自动改用全局密钥 |
| HTTPS 报 `schannel: SEC_E_NO_CREDENTIALS` | 确认内部 `http.sslBackend=openssl`；`start.bat` 会自动补齐，必要时运行 `git config --global http.sslBackend openssl` | 改用系统 git、关闭证书校验 |
| 401/403 | `gh auth status`；让用户重新登录或检查权限 | 读取/打印 Token、把 Token 拼进 URL |
| 网络超时 | 只读诊断：`git ls-remote <url>`、`gh api rate_limit` | 反复重试写操作 |

SSH 失败时先判断：`home\.ssh` 是否有私钥、`ssh-add -l` 是否有身份。若本来已配置 SSH，停止并引导排查（DNS、22 端口、known_hosts、agent、`ssh -T`）；若没有密钥，明确告知无法用 SSH，建议改用 HTTPS，切换命令必须展示并征得同意。绝不自动把全局密钥复制进来，也不自动切换协议。

SSH 排查常用只读命令：

```powershell
& "$Skill\start.bat" ssh -T git@github.com
& "$Skill\start.bat" ssh-add -l
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\diagnose.ps1"
```

需要严格校验 GitHub 主机密钥时（可选，需用户确认指纹）：

```powershell
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\trust-host.ps1" -HostName github.com
```

## 10. 敏感信息与脱敏

### 10.1 绝不读取/打印

- 私钥文件内容（`id_rsa`、`id_ed25519`、`*.pem`、`*.pfx`、`*.p12` 等）。
- `home\gh\hosts.yml`、`.git-credentials`、`.netrc`、`.npmrc`、`.env` 的内容。
- `gh auth token` 的输出；任何 `Authorization` 头。
- 全局用户目录下的未知密钥。

只允许列出文件名/大小/指纹，不允许 `Get-Content`、`cat`、`type` 私钥。

### 10.2 扫描范围

提交前至少扫描：

1. 工作区修改与未跟踪文件（`scan-secrets.ps1 -Worktree`）。
2. 暂存区（`scan-secrets.ps1 -Staged`）。
3. 拟用 commit message（`-MessageFile`）。
4. 当前分支名（`-Branch <name>`）。

识别到私钥头、GitHub/GitLab/AWS/OpenAI/Slack/Google 等 Token 特征、URL 内嵌凭据、JWT、`Bearer` Token 时：**直接拦截提交**。只报 `规则 + 文件:行号`，不报原文，不把命中内容写进聊天、日志或 commit message。

### 10.3 处置

- 建议把相关路径写入 `.gitignore`；写之前展示 diff 并征得同意。
- 已被跟踪的文件：建议 `git rm --cached -- <path>`；这是写操作，先展示命令并征得同意。
- 如果敏感内容已经推送：告知用户立即轮换/吊销，并建议清理历史（`git filter-repo` 等）；不要擅自改写历史或强制推送。

常用 `.gitignore` 建议（按实际命中项选择，不盲目全加）：

```gitignore
.env
.env.*
!.env.example
*.pem
*.key
*.pfx
*.p12
id_rsa
id_ed25519
.npmrc
.pypirc
.netrc
home/gh/
```

## 11. 结果汇报

### 11.1 成功

```markdown
## 执行结果
- 命令：`git commit -m "feat(api): ..."`（退出码 0）
- 变更：3 个文件，+42/-7
- 提交：`abc1234`（分支 `feat/api`）
- 安全检查：worktree / staged / message 均通过
- 下一步：是否推送？`git push origin feat/api`（需确认）
```

### 11.2 失败

```markdown
## 执行失败
- 命令：`git push origin main`（退出码 1）
- 错误：`! [rejected] main -> main (non-fast-forward)`（已脱敏）
- 排查：远端有新提交；本地未包含远端最新提交
- 建议只读诊断：
  - `git fetch origin`（需确认）
  - `git log --oneline HEAD..origin/main`
  - `git status --short --branch`
- 未执行任何自动合并/强推；请选择处理方式。
```

所有输出（包括错误、路径、URL、日志）都要脱敏：Token → `***`，`https://user:pass@host` → `https://***:***@host`，私钥块 → `***PRIVATE KEY REDACTED***`。

## 12. 辅助脚本

| 脚本 | 用途 | 是否写 |
|---|---|---|
| `start.bat` | 唯一入口；设置隔离环境；`--check`/`--env` | 仅创建内部目录/模板 |
| `setup-auth.bat` | 首次生成/检查密钥的便捷入口（仍调用 start.bat） | 写内部 `.ssh` |
| `scripts/check-env.ps1` | 校验 HOME/GH_CONFIG_DIR/tool 路径 | 否 |
| `scripts/diagnose.ps1` | 版本、配置来源、remote、gh 状态、SSH 文件（只列名） | 否 |
| `scripts/scan-secrets.ps1` | 扫描 worktree/staged/message/branch；退出码 2=拦截，3=需复核 | 否 |
| `scripts/setup-auth.ps1` | `Ensure` 自动生成/输出公钥；`Check`/`Login` | 写内部 `.ssh` |
| `scripts/validate-commit-msg.ps1` | 校验 Conventional Commits 格式与 type | 否 |
| `scripts/release-notes.ps1` | 从 Conventional Commits 生成详细 release notes | 写本地 notes 文件 |
| `scripts/trust-host.ps1` | 校验 GitHub 主机指纹并写入内部 known_hosts | 写 known_hosts |

退出码约定：`0` 成功/干净；`1` 工具或命令错误；`2` 高风险拦截；`3` 需人工复核。

## 13. 快速命令索引

```powershell
# 首次加载 / 新会话第一条命令
& "$Skill\start.bat" --bootstrap

# 之后自检
& "$Skill\start.bat" --check
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\diagnose.ps1"

# 只读
& "$Skill\start.bat" git status --short --branch
& "$Skill\start.bat" git log --oneline --decorate -n 20
& "$Skill\start.bat" git diff
& "$Skill\start.bat" git diff --staged
& "$Skill\start.bat" git remote -v
& "$Skill\start.bat" gh auth status
& "$Skill\start.bat" gh repo view <owner>/<repo>

# 扫描
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -Worktree
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -Staged
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\scan-secrets.ps1" -Branch <branch>

# 发布 notes
& "$Skill\start.bat" powershell -NoProfile -ExecutionPolicy Bypass -File "$Skill\scripts\release-notes.ps1" -Version vX.Y.Z -FromTag vOLD -OutputPath ".git\gitskill-release-notes.md"
```

**记住：先展示命令，再执行；写操作必须等用户明确同意；一次确认只对一条命令有效。**
