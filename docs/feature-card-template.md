# Feature card template

Status: the template for step 6 of `docs/feature-flow.md`. One page at most; if it does not fit, split
it into two cards. The agent fills it, the captain reads and corrects it.

The headings stay in Chinese so every card has the same shape. The italic line under each heading
glosses it in English and says what the agent must write there.

---

# 功能卡：<名字>　状态：草稿 / 已确认 / 已上线

*Feature card: <name>. Status: draft / confirmed / shipped.*

## 一句话

*One sentence: who uses it, at what moment, and what they get.*

<谁>在<什么时刻>用它，得到<什么>。

## 手感

*Feel: which prototype was picked, what it should resemble and what it must not resemble, and the
motion or feedback contract with numbers. The captain owns this section and may rewrite it.*

- 选定原型：<分支/路由 ?v=b>（截图链接）
  *The chosen prototype: its route or build flag, with the capture.*
- 像：<喜欢的参照>　不要像：<讨厌的参照>
  *Resembles: <a reference the captain likes>. Must not resemble: <a reference the captain dislikes>.*
- 动效/反馈：<例如 按下 100ms 内有反馈；成功不弹窗，只换状态>
  *Motion and feedback with a number and a duration, for example "press responds within 100 ms".
  State a substitution when it should not interrupt, for example "success swaps the state, no dialog".*

## 打回标准（看到这些我会打回）

*The rejection bar: what the captain would reject this for. Copy step 1's answer here word for word;
the captain may rewrite it.*

- …
- …

## 必须有（≤5）

*Must have, at most five items. Anything past five is scope creep.*

1. …

## 不做（≤5，防止 agent 发挥）

*Out of scope, at most five items. This list exists to stop the agent from improvising.*

- …

## 情况清单（第 4 步勾选结果）

*The case list with the captain's marking from step 5: want, later or ignore, plus the default
handling for each row. The full list including the folded cut cases stays with the sweep artifact.*

| 情况 | 处理 |
| 空状态 | … *Empty: what the screen shows with no content, and whether the primary action is shown.* |
| 加载/慢网（>1s） | … *Loading or a slow connection over one second: what appears, and what stays clickable.* |
| 出错（服务端/校验） | …（字段旁提示，保留输入）*Error: message next to the field, the input is kept.* |
| 超长/特殊字符 | … *Overlong input and special characters: what is truncated, what is rejected, what is kept.* |
| 重复提交/连点 | … *Double submit and rapid clicks: what is guarded, and what the second attempt sees.* |
| ⏭ 以后再说 | … *Later: the case the captain marked later, and what happens until then.* |

## 已定决定（问答结果，一行一个）

*Decided, one line per settled decision from step 4. A decision here is not a guess; it is an answer
the captain gave.*

- D1：…
- D2：…

## 仍是假设（agent 猜的，我没确认）

*Still assumptions: what the agent assumed and the captain did not confirm. Read this section before
starting work; an empty list means everything above is settled.*

- A1：…

## 验收（3-7 条，EARS）

*Acceptance, three to seven EARS lines: WHEN <event>, THE SYSTEM SHALL <behaviour>. IF <exception>,
THEN THE SYSTEM SHALL <handling>.*

- WHEN <事件>, THE SYSTEM SHALL <行为>.
- IF <异常>, THEN THE SYSTEM SHALL <处理>.

## 技术约束（只写这次相关的）

*Technical constraints, only the ones this change actually touches. Name the component, the signals
and the endpoint, or name what must not change.*

- templ 组件：… / Datastar：signals …，SSE 端点 … / 不改：…

## 实现后补（agent 填）

*Filled after implementation, by the agent: the decisions the card did not contain, and the review
result per acceptance line.*

- implementation-notes：<spec 里没有、实现时自己做的决定>
  *Implementation notes: what the code decided that the card did not.*
- 审查结果：通过 / 不通过（逐条）
  *Review result: pass or fail, one line per acceptance item.*
