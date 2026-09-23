# ============================================================
# 嵌入式学习同步 · 配置
# 改这里就行，不用动 sync.sh
# ============================================================

# 公开博客仓库：学习路线 + 每日发布内容（posts/）
PUBLIC_REPO="oh-wang/embedded-learning"

# 私有全量备份仓库：学习目录中的所有文件（包括 memory/）
BACKUP_REPO="oh-wang/embedded-learning-memory"

# 公开仓库里那个「进度流水」Issue 的标题
ISSUE_TITLE="嵌入式学习进度"

# 分支名
PUBLIC_BRANCH="main"
MEMORY_BRANCH="main"

# 是否在同步时往 Issue 里追加一条评论（true / false）
USE_ISSUE="true"

# 提交时使用的 git 身份（留空则用全局配置）
GIT_NAME=""
GIT_EMAIL=""
