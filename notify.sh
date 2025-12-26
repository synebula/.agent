#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# 通知脚本 - 用于 Claude Code 和 Codex CLI 任务完成通知
# ============================================================================

has_jq=0
if command -v jq >/dev/null 2>&1; then
  has_jq=1
fi

# ============================================================================
# 工具函数
# ============================================================================

# 检测是否在 Hyprland 环境
is_hyprland() {
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1
}

# 从 JSON 行中提取用户文本
extract_user_text_from_line() {
  [ "$has_jq" -eq 1 ] || return 1
  jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")' 2>/dev/null
}

# 截断过长文本
truncate_text() {
  local text="$1" max_len="${2:-40}"
  if [ ${#text} -gt "$max_len" ]; then
    echo "${text:0:$((max_len - 5))}..."
  else
    echo "$text"
  fi
}

# ============================================================================
# Hyprland 窗口跳转支持
# ============================================================================

# 通过进程树找到父窗口信息
# 返回: 设置全局变量 window_addr 和 workspace_id
find_terminal_window() {
  window_addr=""
  workspace_id=""

  [ "$has_jq" -eq 1 ] || return 1

  # 获取所有 Hyprland 窗口的 PID 列表
  local clients_json
  clients_json="$(hyprctl clients -j 2>/dev/null || true)"
  [ -n "$clients_json" ] || return 1

  # 遍历父进程链，找到第一个有窗口的进程
  local pid=$$ ppid window_info
  for _ in {1..20}; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] || [ "$ppid" = "0" ] || [ "$ppid" = "1" ] && break

    # 检查该进程是否有 Hyprland 窗口
    window_info="$(printf '%s' "$clients_json" | jq --arg pid "$ppid" '.[] | select(.pid == ($pid | tonumber))' 2>/dev/null || true)"
    if [ -n "$window_info" ]; then
      window_addr="$(printf '%s' "$window_info" | jq -r '.address // empty' || true)"
      workspace_id="$(printf '%s' "$window_info" | jq -r '.workspace.id // empty' || true)"
      [ -n "$window_addr" ] && return 0
    fi

    pid="$ppid"
  done

  return 1
}

# 发送通知
# 参数: $1=icon, $2=agent, $3=title, $4=body, $5=window_addr(可选), $6=workspace_id(可选)
send_notification() {
  local icon="$1" agent="$2" title="$3" body="$4"
  local win_addr="${5:-}" ws_id="${6:-}"

  command -v notify-send >/dev/null 2>&1 || return 1

  if is_hyprland && [ -n "$win_addr" ]; then
    # Hyprland 环境：使用 setsid 创建独立会话，完全脱离调用方
    setsid bash -c '
      action=$(notify-send -i "'"$icon"'" -a "'"$agent"'" --action="default=打开终端" "'"$title"'" "'"$body"'" 2>/dev/null || true)
      if [ "$action" = "default" ]; then
        [ -n "'"$ws_id"'" ] && hyprctl dispatch workspace "'"$ws_id"'" >/dev/null 2>&1
        hyprctl dispatch focuswindow "address:'"$win_addr"'" >/dev/null 2>&1
      fi
    ' </dev/null >/dev/null 2>&1 &
  else
    # 非 Hyprland 环境：普通通知
    notify-send -i "$icon" -a "$agent" "$title" "$body"
  fi
}

# 播放提示音
play_sound() {
  if command -v paplay >/dev/null 2>&1; then
    paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 || true
  fi
}

# ============================================================================
# Claude Code 信息提取
# ============================================================================

# 从 Claude Code hook 输入中提取通知信息
# 参数: $1=hook_input (JSON)
# 返回: 设置全局变量 agent, icon, body
parse_claude_code_info() {
  local hook_input="$1"

  agent="Claude Code"
  icon="/home/alex/.agent/claude/claude.png"
  body=""

  [ "$has_jq" -eq 1 ] || return 1

  local transcript_path session_id
  transcript_path="$(printf '%s\n' "$hook_input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  session_id="$(printf '%s\n' "$hook_input" | jq -r '.session_id // empty' 2>/dev/null || true)"

  # 1) 优先从 transcript 中取最后一条 user 文本
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    local last_user_line
    last_user_line="$(grep '\"role\":\"user\"' "$transcript_path" | tail -n 1 || true)"
    if [ -n "$last_user_line" ]; then
      body="$(printf '%s\n' "$last_user_line" | extract_user_text_from_line || true)"
    fi
  fi

  # 2) transcript 不可用时，回退到 hook 输入中的显式标题
  if [ -z "$body" ]; then
    body="$(printf '%s\n' "$hook_input" | jq -r '.task_title // .title // empty' 2>/dev/null || true)"
  fi

  # 3) 仍然没有标题时，从 history.jsonl 回退
  if [ -z "$body" ] && [ -f "$HOME/.claude/history.jsonl" ]; then
    if [ -n "$session_id" ]; then
      body="$(jq -r --arg sid "$session_id" 'select(.sessionId == $sid) | .display // empty' "$HOME/.claude/history.jsonl" 2>/dev/null | tail -n 1 || true)"
    else
      body="$(jq -r '.display // empty' "$HOME/.claude/history.jsonl" 2>/dev/null | tail -n 1 || true)"
    fi
  fi
}

# ============================================================================
# Codex 信息提取
# ============================================================================

# 从 Codex CLI 参数中提取通知信息
# 参数: $@ = 命令行参数
# 返回: 设置全局变量 agent, icon, body
parse_codex_info() {
  agent="Codex"
  icon="/home/alex/.agent/codex/openai.png"
  body=""

  [ "$has_jq" -eq 1 ] && [ $# -ge 1 ] || return 0

  # 最后一个参数可能是带 input-messages 的 JSON
  local last_arg="${*: -1}"
  if [[ "$last_arg" == \{* ]]; then
    body="$(printf '%s\n' "$last_arg" | jq -r '.["input-messages"] | .[-1] // empty' 2>/dev/null || true)"
  fi
}

# ============================================================================
# 主逻辑
# ============================================================================

main() {
  local title="任务已完成"
  local agent="" icon="" body=""
  local window_addr="" workspace_id=""

  # Hyprland 环境下获取终端窗口信息
  if is_hyprland; then
    find_terminal_window || true
  fi

  # 读取 stdin（如果有）
  local hook_input=""
  if [ ! -t 0 ]; then
    hook_input="$(cat || true)"
  fi

  # 根据输入来源解析信息
  if [ "$has_jq" -eq 1 ] && [ -n "$hook_input" ]; then
    parse_claude_code_info "$hook_input"
  else
    parse_codex_info "$@"
  fi

  # 截断过长的 body
  body="$(truncate_text "$body" 40)"

  # 发送通知
  send_notification "$icon" "$agent" "$title" "$body" "$window_addr" "$workspace_id"

  # 播放提示音
  play_sound
}

main "$@"
