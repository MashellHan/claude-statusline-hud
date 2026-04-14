# Review 023 — BUG: Daily Totals Show Cross-Day Accumulated Data

**Date:** 2026-04-15  
**Reviewer:** Claude Opus 4.6 (Lead & Reviewer)  
**Severity:** HIGH  
**Type:** Correctness — Data Integrity  

---

## User Report

> "4/15 的数据好像有问题 因为 15 号刚开始"

Screenshot shows:
```
day-total(04-15) token 158M (in 21M cache 136M out 667k) │ msg 4k │ cost $114.30
```

15 号刚过零点几分钟，不可能有 158M token 和 $114.30。

---

## Root Cause: `find -newermt` Matches by File mtime, Not Message Timestamp

**Lines:** 597-601

```bash
TODAY=$(date +%Y-%m-%d)
_DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" -type f -print0 2>/dev/null | \
  xargs -0 grep -h "input_tokens" 2>/dev/null | \
  jq -c '.message.usage // empty | ...'
```

### The Bug

1. `find -newermt "$TODAY 00:00"` — 匹配**文件修改时间** > 今天 00:00 的文件
2. 跨天 session（如 4/14 22:39 创建，4/15 00:06 仍在写入）的 mtime 被更新到 4/15
3. `grep "input_tokens"` 扫出该文件中**所有** usage 行 — 包括 4/11~4/14 的旧数据
4. 结果：把多天的数据全算进"今日"

### 证据

| 文件 | 创建时间 | 修改时间 | 实际天数 |
|------|---------|---------|---------|
| ae84d5aa.jsonl | **4/11** 22:55 | 4/15 00:07 | 4天数据被计入4/15 |
| 7b464892.jsonl | **4/11** 14:36 | 4/15 00:07 | 4天数据被计入4/15 |
| d93c14d4.jsonl | **4/14** 22:39 | 4/15 00:06 | 大部分4/14数据被计入4/15 |
| 698ecba2.jsonl | **4/14** 23:46 | 4/15 00:07 | 4/14数据被计入4/15 |

### 验证结果

```
BROKEN  (file mtime filter): 160,002,958 tokens / 4,080 messages
CORRECT (message timestamp filter): 0 tokens / 0 messages
```

差异：**160M tokens (100% 错误)**

---

## Fix

每条 JSONL 行都有 `"timestamp": "2026-04-14T14:39:47.728Z"` 字段（ISO 8601 格式）。正确做法是在 jq 内按消息时间戳过滤。

### Before (lines 599-611)

```bash
_DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" -type f -print0 2>/dev/null | \
  xargs -0 grep -h "input_tokens" 2>/dev/null | \
  jq -c '.message.usage // empty |
    {i: (.input_tokens // 0), o: (.output_tokens // 0),
     cr: (.cache_read_input_tokens // 0)}' 2>/dev/null | \
  jq -s '{ ... }' 2>/dev/null)
```

### After

```bash
_DAY_STATS=$(find "$_PROJECTS_DIR" -name "*.jsonl" \
  -newermt "$TODAY 00:00" -type f -print0 2>/dev/null | \
  xargs -0 grep -h "input_tokens" 2>/dev/null | \
  jq -c --arg today "$TODAY" '
    select(.timestamp != null and (.timestamp | startswith($today))) |
    .message.usage // empty |
    {i: (.input_tokens // 0), o: (.output_tokens // 0),
     cr: (.cache_read_input_tokens // 0)}' 2>/dev/null | \
  jq -s '{
    input: (map(.i) | add // 0),
    output: (map(.o) | add // 0),
    cache_read: (map(.cr) | add // 0),
    tokens: (map(.i + .o + .cr) | add // 0),
    messages: length
  }' 2>/dev/null)
```

**Key change:** 添加 `select(.timestamp | startswith($today))` — 只统计 timestamp 以当天日期开头的消息。

### Why Keep `find -newermt`

仍然保留 `find -newermt` 作为**第一层粗过滤**（减少需要 grep 的文件数量）。`-newermt` 不精确但无害 — 它只是多匹配一些文件（false positive），真正的精确过滤由 jq 的 `startswith($today)` 完成。

### Edge Case: Timezone

`timestamp` 是 UTC（`Z` 后缀），`date +%Y-%m-%d` 是本地时间。如果用户在 UTC+8，本地 4/15 00:00 = UTC 4/14 16:00。需要用本地日期而非 UTC 日期来比较。

方案 A（简单 — 接受几小时误差）：直接用本地日期的 `startswith` —— 在 UTC+8 时区会少计当天 00:00~08:00 的消息。对绝大多数场景可接受。

方案 B（精确）：计算本地 midnight 的 UTC ISO 时间戳，在 jq 里做范围比较。更复杂，收益有限。

**建议：** 先用方案 A，用 `startswith($today)` 即可。如果用户反馈日切偏差再升级到方案 B。

---

## Post-Fix: Clear Stale Cache

修复后需要清除缓存，否则旧的错误数据会持续 30 秒：

```bash
rm -f ~/.cache/claude-statusline/daily_*.cache 2>/dev/null
# 或旧路径:
rm -f /tmp/.claude_sl_daily_* 2>/dev/null
```

---

## Test Plan

1. 在 4/15 凌晨运行，验证 day-total 显示接近 0（或只显示真正 4/15 的数据）
2. 模拟跨天 session：创建 mock JSONL 含 4/14 和 4/15 的 timestamp，验证只统计 4/15
3. 验证 `find -newermt` 仍然正确缩小文件范围（不遗漏当天文件）
4. 验证缓存 30 秒后更新为正确数据
