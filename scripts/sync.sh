#!/usr/bin/env bash
# ============================================================
# 嵌入式学习 · 一键同步
#   用法：
#     sync.sh                 同步今天的进度（需先写好当天文件）
#     sync.sh --init          首次初始化：建仓库 + 首次推送
#     sync.sh --dry-run       只检查、不提交不推送
#     sync.sh --no-push       提交到本地，不推送
#     sync.sh --status        查看当前状态
#     sync.sh --date 2026-09-19   指定日期
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/config.sh"

DRY_RUN=false; NO_PUSH=false; MODE="sync"; TARGET_DATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --init)    MODE="init" ;;
    --dry-run) DRY_RUN=true ;;
    --no-push) NO_PUSH=true ;;
    --status)  MODE="status" ;;
    --date)    TARGET_DATE="${2:-}"; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
  shift
done

DATE="${TARGET_DATE:-$(date +%Y-%m-%d)}"
MEM_DIR="$ROOT/memory"
PUB_DIR="$ROOT"
MIRROR="$ROOT/.memory-repo"

# ---------- 输出工具 ----------
c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
c_dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
hr()     { printf '%s\n' "────────────────────────────────────────"; }
die()    { c_red "✗ $*"; exit 1; }
ok()     { c_grn "✓ $*"; }
step()   { printf '\n'; hr; printf '\033[1m%s\033[0m\n' "$*"; hr; }

# ---------- 找一个能用的 git ----------
find_git() {
  for g in "$(command -v git 2>/dev/null || true)" \
           /Users/level/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/fallback/git \
           /opt/homebrew/bin/git /usr/local/bin/git; do
    [ -n "$g" ] && [ -x "$g" ] || continue
    if "$g" --version >/dev/null 2>&1; then printf '%s' "$g"; return 0; fi
  done
  return 1
}
GIT="$(find_git)" || die "找不到可用的 git。请先在终端执行： sudo xcodebuild -license"

# 统一的 git 调用（自动带上提交身份）
gitc() {
  if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
    "$GIT" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" "$@"
  else
    "$GIT" "$@"
  fi
}
have_gh() { command -v gh >/dev/null 2>&1; }

# ---------- 状态 / 检查 ----------
LOG_FILE="$MEM_DIR/log/$DATE.md"
POST_FILE="$ROOT/posts/$DATE.md"

count_days() {
  local n=0 f
  for f in "$MEM_DIR"/log/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in .gitkeep) continue ;; esac
    n=$((n+1))
  done
  printf '%s' "$n"
}

preflight() {
  local bad=0
  [ -f "$LOG_FILE" ]  || { c_ylw "缺少当日记忆：${LOG_FILE#$ROOT/}"; bad=1; }
  [ -f "$POST_FILE" ] || { c_ylw "缺少当日发布稿：${POST_FILE#$ROOT/}"; bad=1; }
  if [ "$bad" = 1 ]; then
    hr
    c_dim "请先让 AI 写好这两个文件，再执行本脚本。"
    c_dim "记忆文件字段：今天主题 / 学了什么"
    return 1
  fi
  return 0
}

show_status() {
  step "当前状态"
  printf '%-16s %s\n' "日期"        "$DATE"
  printf '%-16s %s\n' "已学习天数"  "$(count_days)"
  printf '%-16s %s\n' "今日记忆"    "$( [ -f "$LOG_FILE" ]  && echo "已写" || echo "未写" )"
  printf '%-16s %s\n' "今日发布稿"  "$( [ -f "$POST_FILE" ] && echo "已写" || echo "未写" )"
  printf '%-16s %s\n' "公开仓库"    "$PUBLIC_REPO"
  printf '%-16s %s\n' "记忆仓库"    "$MEMORY_REPO"
  printf '%-16s %s\n' "git"         "$GIT"
  printf '%-16s %s\n' "gh"          "$(have_gh && echo 已安装 || echo 未安装)"
  hr
  if [ -f "$MEM_DIR/progress.md" ]; then
    printf '\033[1mprogress.md 摘要\033[0m\n'
    sed -n '1,12p' "$MEM_DIR/progress.md" | sed 's/^/  /'
  fi
}

# ---------- 1. 更新记忆索引 ----------
update_progress() {
  step "1/5  更新进度快照"
  local days; days="$(count_days)"
  local f="$MEM_DIR/progress.md"
  [ -f "$f" ] || { c_ylw "没有 progress.md，跳过"; return 0; }

  if [ "$DRY_RUN" = true ]; then
    c_dim "（dry-run）会把 最后同步 改为 ${DATE}，已学习天数改为 ${days}"
    return 0
  fi

  local tmp; tmp="$(mktemp)"
  awk -v d="$DATE" -v n="$days" '
    /^> 最后同步：/ { print "> 最后同步：" d; next }
    /^> 已学习天数：/ { print "> 已学习天数：" n; next }
    { print }
  ' "$f" > "$tmp"
  mv "$tmp" "$f"
  ok "最后同步 → ${DATE}，已学习 ${days} 天"
}

# ---------- 2. 公开仓库 ----------
push_public() {
  step "2/5  提交公开仓库"
  if [ ! -d "$ROOT/.git" ]; then
    gitc init -q -b "$PUBLIC_BRANCH" 2>/dev/null || gitc init -q
  fi
  if [ "$DRY_RUN" = true ]; then
    c_dim "（dry-run）会提交 posts/ 下的改动，此处不执行"
    return 0
  fi

  gitc add -A
  # 安全断言：记忆目录绝不允许进入公开仓库
  if gitc diff --cached --name-only | grep -q '^memory/'; then
    die "安全中止：memory/ 被暂存，可能泄露隐私。不要用 -f 强制添加。"
  fi
  if gitc diff --cached --quiet 2>/dev/null; then
    c_dim "没有变化，跳过提交"
  else
    gitc commit -q -m "学习进度 ${DATE}"
    ok "已提交：学习进度 ${DATE}"
  fi
  if [ "$NO_PUSH" = true ]; then
    c_dim "（no-push 跳过推送）"; return 0
  fi
  if gitc remote get-url origin >/dev/null 2>&1; then
    c_dim "推送到 $PUBLIC_REPO ..."
    gitc push -q origin "$PUBLIC_BRANCH" && ok "公开仓库已更新"
  else
    c_ylw "还没配置 origin，跳过推送（执行 --init 可自动创建）"
  fi
}

# ---------- 3. 记忆仓库镜像 ----------
mirror_memory() {
  step "3/5  同步记忆到备份仓库"
  if [ ! -d "$MIRROR/.git" ]; then
    if [ "$DRY_RUN" = true ]; then
      c_dim "（dry-run）会克隆 $MEMORY_REPO 到 .memory-repo/"; return 0
    fi
    c_dim "克隆 $MEMORY_REPO ..."
    gitc clone -q "https://github.com/${MEMORY_REPO}.git" "$MIRROR" \
      || die "克隆失败。先执行： bash scripts/sync.sh --init"
  fi
  # 镜像：清掉旧内容（保留 .git 与 README），再拷入最新 memory/
  find "$MIRROR" -mindepth 1 -maxdepth 1 \
    ! -name '.git' ! -name 'README.md' -exec rm -rf {} +
  cp -R "$MEM_DIR/." "$MIRROR/"
  ok "记忆文件已镜像到 .memory-repo/"
}

push_memory() {
  step "4/5  提交备份仓库"
  [ "$DRY_RUN" = true ] && { c_dim "（dry-run 跳过）"; return 0; }
  [ -d "$MIRROR/.git" ] || die "备份仓库不存在，先执行 --init"
  cd "$MIRROR"
  gitc add -A
  if gitc diff --cached --quiet 2>/dev/null; then
    c_dim "没有变化，跳过提交"
  else
    gitc commit -q -m "记忆备份 ${DATE}"
    ok "已提交：记忆备份 ${DATE}"
  fi
  if [ "$NO_PUSH" = true ]; then c_dim "（no-push 跳过推送）"; cd "$ROOT"; return 0; fi
  gitc push -q origin "$MEMORY_BRANCH" && ok "备份仓库已更新"
  cd "$ROOT"
}

# ---------- 5. Issue 流水 ----------
update_issue() {
  step "5/5  更新进度 Issue"
  if [ "$USE_ISSUE" != "true" ]; then c_dim "（已关闭）"; return 0; fi
  if ! have_gh; then c_ylw "未安装 gh，跳过"; return 0; fi
  if [ "$DRY_RUN" = true ] || [ "$NO_PUSH" = true ]; then c_dim "（跳过）"; return 0; fi

  local num
  num="$(gh issue list --repo "$PUBLIC_REPO" --state all --limit 100 \
        --json number,title -q ".[] | select(.title==\"$ISSUE_TITLE\") | .number" 2>/dev/null | head -1 || true)"
  if [ -z "$num" ]; then
    c_dim "未找到 Issue「${ISSUE_TITLE}」，正在创建 ..."
    num="$(gh issue create --repo "$PUBLIC_REPO" --title "$ISSUE_TITLE" \
          --body "嵌入式学习进度流水。每完成一次学习，本 Issue 追加一条评论。" \
          2>/dev/null | grep -oE '[0-9]+$' || true)"
  fi
  [ -n "$num" ] || { c_ylw "Issue 处理失败，跳过"; return 0; }

  local topic; topic="$(sed -n 's/^- 今天主题：//p' "$LOG_FILE" | head -1)"
  local body; body="$(printf '**%s**（累计第 %s 天）\n\n%s\n\n<sub>%s</sub>' \
    "$DATE" "$(count_days)" "${topic:-今日已完成学习}" "$PUBLIC_REPO")"
  gh issue comment "$num" --repo "$PUBLIC_REPO" --body "$body" >/dev/null \
    && ok "Issue #$num 已追加：$DATE"
}

# ---------- init ----------
do_init() {
  step "初始化：创建仓库并首次推送"
  have_gh || die "需要 gh 且已登录： gh auth login"

  for spec in "$PUBLIC_REPO:public" "$MEMORY_REPO:private"; do
    local repo="${spec%:*}" vis="${spec#*:}"
    if gh repo view "$repo" >/dev/null 2>&1; then
      c_dim "已存在：$repo"
    else
      c_dim "创建 $vis 仓库：$repo"
      gh repo create "$repo" "--$vis" \
        --description "$( [ "$vis" = public ] && echo "嵌入式学习｜路线与每日进度" || echo "嵌入式学习记忆备份（私有）" )" >/dev/null
      ok "已创建 $repo"
    fi
  done

  if [ ! -d "$MIRROR/.git" ]; then
    gitc clone -q "https://github.com/${MEMORY_REPO}.git" "$MIRROR" 2>/dev/null || true
  fi

  if [ ! -d "$ROOT/.git" ]; then gitc init -q -b "$PUBLIC_BRANCH" 2>/dev/null || gitc init -q; fi
  if ! gitc remote get-url origin >/dev/null 2>&1; then
    gitc remote add origin "https://github.com/${PUBLIC_REPO}.git"
  fi
  gitc add -A
  # 安全断言：记忆目录绝不允许进入公开仓库
  if gitc diff --cached --name-only | grep -q '^memory/'; then
    die "安全中止：memory/ 被暂存，可能泄露隐私。不要用 -f 强制添加。"
  fi
  gitc diff --cached --quiet 2>/dev/null || gitc commit -q -m "chore: 初始化学习仓库"
  gitc push -q -u origin "$PUBLIC_BRANCH" && ok "公开仓库首次推送完成"

  mirror_memory
  cd "$MIRROR"
  gitc add -A
  gitc diff --cached --quiet 2>/dev/null || gitc commit -q -m "chore: 初始化记忆备份"
  gitc push -q -u origin "$MEMORY_BRANCH" && ok "备份仓库首次推送完成"
  cd "$ROOT"
  hr
  ok "初始化完成："
  c_dim "  公开： https://github.com/$PUBLIC_REPO"
  c_dim "  备份： https://github.com/$MEMORY_REPO"
}

# ---------- 主线 ----------
case "$MODE" in
  status) show_status ;;
  init)   do_init ;;
  sync)
    step "同步 $DATE"
    preflight || exit 1
    update_progress
    push_public
    mirror_memory
    push_memory
    update_issue
    hr
    ok "同步完成：${DATE}（累计 $(count_days) 天）"
    c_dim "  发布： https://github.com/${PUBLIC_REPO}/blob/${PUBLIC_BRANCH}/posts/${DATE}.md"
    ;;
esac
