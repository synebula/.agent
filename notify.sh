#!/usr/bin/env bash

set -euo pipefail

title="Codex 任务已完成"
body=""

has_jq=0
if command -v jq >/dev/null 2>&1; then
  has_jq=1
fi

extract_user_text_from_line() {
  if [ "$has_jq" -ne 1 ]; then
    return 1
  fi
  jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")' 2>/dev/null
}

# 如果是 Claude Code Stop hook，会从 stdin 传入 JSON
hook_input=""
if [ ! -t 0 ]; then
  hook_input="$(cat || true)"
fi

if [ "$has_jq" -eq 1 ] && [ -n "$hook_input" ]; then
  # ====================================
  # ===== Claude Code 分支（有 stdin JSON）=====
  # ====================================
  title="CC 任务已完成"
  session_id=""

  transcript_path="$(printf '%s\n' "$hook_input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  session_id="$(printf '%s\n' "$hook_input" | jq -r '.session_id // empty' 2>/dev/null || true)"

  # 1）优先从 transcript 中取最后一条 user 文本
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    last_user_line="$(grep '\"role\":\"user\"' "$transcript_path" | tail -n 1 || true)"
    if [ -n "$last_user_line" ]; then
      body="$(printf '%s\n' "$last_user_line" | extract_user_text_from_line || true)"
    fi
  fi

  # 2）transcript 不可用时，回退到 hook 输入中的显式标题
  if [ -z "$body" ]; then
    body="$(printf '%s\n' "$hook_input" | jq -r '.task_title // .title // empty' 2>/dev/null || true)"
  fi

  # 3）仍然没有标题时，仅在 Claude Code 上下文内再从 history.jsonl 回退
  if [ -z "$body" ] && [ -f "$HOME/.claude/history.jsonl" ]; then
    if [ -n "$session_id" ]; then
      body="$(jq -r --arg sid "$session_id" 'select(.sessionId == $sid) | .display // empty' "$HOME/.claude/history.jsonl" 2>/dev/null | tail -n 1 || true)"
    else
      body="$(jq -r '.display // empty' "$HOME/.claude/history.jsonl" 2>/dev/null | tail -n 1 || true)"
    fi
  fi
else
  # ====================================
  # ===== Codex 分支（无 stdin JSON）=====
  # ====================================
  # 兼容 Codex CLI：最后一个参数是带 input-messages 的 JSON
  if [ "$has_jq" -eq 1 ] && [ $# -ge 2 ]; then
    last_arg="${@: -1}"
    if [[ "$last_arg" == \{* ]]; then
      body="$(printf '%s\n' "$last_arg" | jq -r '.["input-messages"] | .[-1] // empty' 2>/dev/null || echo "$body")"
    fi
  fi
fi

# 截断过长的 body（> 30 字符截断为 20 字符 + ...）
if [ ${#body} -gt 30 ]; then
  body="${body:0:20}..."
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send "$title" "$body"
fi

if command -v paplay >/dev/null 2>&1; then
  paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 || true
fi

exit 0
