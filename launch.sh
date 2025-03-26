#!/bin/bash

BASE=/app

# 需要管理的目标文件和文件夹列表
TARGETS="appsettings.json data device.json keystore.json lagrange-0-db qr-0.png astrbot"

env() {
  if [ ! -z "${fetch}" ]; then
    echo '远程获取参数...'
    curl -s "$fetch" -o data.json
    export github_secret=$(jq -r .github_secret data.json)
    export github_project=$(jq -r .github_project data.json)
  fi

  echo
  echo "fetch = ${fetch}"
  echo "github_secret = ${github_secret}"
  echo "github_project = ${github_project}"
  echo

  sed -i "s/\[github_secret\]/${github_secret}/g" launch.sh
  sed -i "s#\[github_project\]#${github_project}#g" launch.sh
}

process_target() {
  target="$1"
  if [ -e ${BASE}/$target ] && [ ! -L ${BASE}/$target ]; then
    echo "Processing new file/folder: $target"
    mv ${BASE}/$target ${BASE}/history/$target
    ln -sf ${BASE}/history/$target ${BASE}/$target
    # 添加到 git 并提交更新
    cd ${BASE}/history
    git add $target
    git commit -m "Add new $target $(date '+%Y-%m-%d %H:%M:%S')"
    cd ${BASE}
  fi
}

do_init() {
  # 创建 history 目录
  mkdir -p ${BASE}/history

  # 进入 history 目录并初始化 Git 仓库
  cd ${BASE}/history
  
  # 检查是否已经是git仓库
  if [ -d ".git" ]; then
    echo "Git仓库已存在，使用现有仓库"
  else
    echo "初始化新的Git仓库"
    # 使用本地配置，避免使用全局配置
    git init
    mkdir -p .git/info
    echo "[user]
      email = huggingface@hf.com
      name = complete-Mmx" > .git/config
  fi

  # 检查 github_project 格式并修正
  if [ -z "$(echo $github_project | grep '/')" ]; then
    echo "注意：github_project 格式不正确，应为 '用户名/仓库名'"
    echo "当前值: $github_project"
    github_project="complete-Mmx/$github_project"
    echo "已修正为: $github_project"
  fi

  # 检查是否已配置远程仓库
  if ! git remote | grep -q "origin"; then
    echo "添加远程仓库"
    git remote add origin https://${github_secret}@github.com/${github_project}.git
  else
    echo "更新远程仓库URL"
    git remote set-url origin https://${github_secret}@github.com/${github_project}.git
  fi

  # 设置 pull 策略为 merge
  git config pull.rebase false

  # 检查并确保我们在main分支上
  current_branch=$(git branch --show-current 2>/dev/null || echo "")
  if [ -z "$current_branch" ]; then
    echo "无当前分支，创建main分支"
    # 检查是否有任何提交
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
      echo "无提交历史，创建初始提交"
      echo "# 仓库初始化于 $(date)" > README.md
      git add README.md
      git commit -m "Initial commit $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    git branch -M main
  elif [ "$current_branch" != "main" ]; then
    echo "当前在 $current_branch 分支，切换到main分支"
    git checkout main 2>/dev/null || git checkout -b main
  else
    echo "已在main分支上"
  fi

  # 首先尝试从远程仓库拉取数据
  echo "尝试从远程仓库拉取数据..."
  if git fetch origin main && git merge origin/main --ff-only; then
    echo "成功从远程仓库拉取数据"
    pull_success=true
  else
    echo "无法从远程仓库拉取数据，可能是新仓库或仓库为空"
    pull_success=false
    
    # 尝试推送当前分支
    echo "尝试推送到远程仓库..."
    if ! git push -u origin main; then
      echo "无法推送到远程仓库，请确认仓库存在且有访问权限"
    else
      echo "成功推送到远程仓库"
    fi
  fi
  
  cd ${BASE}

  # 根据拉取结果决定如何处理目标文件/文件夹
  if [ "$pull_success" = true ]; then
    # 如果成功拉取，将从仓库拉取的文件链接到 BASE 目录
    for target in $TARGETS; do
      if [ -e ${BASE}/history/$target ]; then
        echo "从仓库获取文件: $target"
        # 如果目标文件已存在，先备份
        if [ -e ${BASE}/$target ] && [ ! -L ${BASE}/$target ]; then
          echo "备份现有文件: $target"
          mv ${BASE}/$target ${BASE}/${target}.bak
        fi
        # 移除可能存在的链接
        rm -f ${BASE}/$target
        # 创建新链接
        ln -sf ${BASE}/history/$target ${BASE}/$target
      fi
    done
  else
    # 如果拉取失败，按原流程移动目标文件到 history 并建立符号链接
    for target in $TARGETS; do
      if [ -e ${BASE}/$target ]; then
        echo "初始化目标文件: $target"
        mv ${BASE}/$target ${BASE}/history/$target
        ln -sf ${BASE}/history/$target ${BASE}/$target
      fi
    done
    
    # 添加并提交这些文件
    cd ${BASE}/history
    git add .
    git commit -m "Add initial targets $(date '+%Y-%m-%d %H:%M:%S')"
    git push origin main || echo "无法推送初始目标文件到远程仓库"
    cd ${BASE}
  fi

  # 如果 history 除了 .git 之外还有内容则输出提示
  DIR="${BASE}/history"
  if [ "$(ls -A $DIR | grep -v .git)" ]; then
    echo "History 目录已有内容..."
  else
    echo "History 目录为空..."
  fi

  echo "初始化 history 完成."
  chmod -R 777 ${BASE}/history

  # 后台启动 git-batch 进行自动提交与推送
  nohup ./git-batch --commit 10s --name git-batch --email git-batch@github.com --push 1m -p history > access.log 2>&1 &
  
  # 创建一个标志文件表示已初始化和同步完成
  touch ${BASE}/.initialized
  touch ${BASE}/.git_sync_done
}

# 监控函数作为后台任务运行
start_monitor() {
  echo "启动监控，定时检测新增文件..."
  
  # 定期提交计数器初始化
  counter=0
  
  while true; do
    # 检测并处理目标文件
    for target in $TARGETS; do
      process_target "$target"
    done
    
    # 增加计数器
    counter=$((counter + 1))
    
    # 每60次循环(约10分钟)执行一次提交
    if [ $counter -ge 6 ]; then
      echo "执行定期提交 $(date '+%Y-%m-%d %H:%M:%S')"
      cd ${BASE}/history
      # 检查是否有需要提交的更改
      if git status --porcelain | grep -q .; then
        git add .
        git commit -m "定期提交 $(date '+%Y-%m-%d %H:%M:%S')"
        git push origin main
        echo "定期提交完成"
      else
        echo "没有新的更改需要提交"
      fi
      cd ${BASE}
      
      # 重置计数器
      counter=0
    fi
    
    sleep 10  # 每 10 秒检测一次
  done
}

init() {
  # 先执行初始化
  do_init
  
  # 在前台启动监控
  start_monitor
}

release() {
  rm -rf ${BASE}/history
}

update() {
  cd ${BASE}/history
  git pull origin main
  git add .
  git commit -m "update history $(date '+%Y-%m-%d %H:%M:%S')"
  git push origin main
}

# 创建标志文件指示git同步完成
mark_git_sync_done() {
  touch ${BASE}/.git_sync_done
  echo "Git同步已完成，创建标志文件"
}

# 检查git同步是否完成
check_git_sync_done() {
  if [ -f ${BASE}/.git_sync_done ]; then
    echo "Git同步已完成"
    return 0
  else
    echo "Git同步尚未完成"
    return 1
  fi
}

case $1 in
  env)
    env
  ;;
  init)
    init
  ;;
  monitor)
    start_monitor
  ;;
  release)
    release
  ;;
  update)
    update
  ;;
  check_sync)
    check_git_sync_done
  ;;
  mark_sync_done)
    mark_git_sync_done
  ;;
  *)
    # 默认行为，无参数时也执行初始化
    echo "未指定参数，默认执行初始化..."
    init
  ;;
esac
