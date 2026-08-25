# VISION 落地记录

记录 zd-vision-docs-v1 这次改动确定下来的决策。只写实际发生的决定，不发明政策。

## 已定

- 仓库此前没有 VISION.md；本次加入的是第一份，作为验收政策，管一个改动能否合入。
- 产品对外名称是 Zero Draft；First Line 不再作为对外名称使用。内部命名保持不变（目录 `apps/macos/FirstLine`、Swift 类型与模块名、bundle 标识、`window.FirstLineLandingDemo` 等）。
- VISION.md 的位阶：视觉事项低于 `design/DESIGN.md`（视觉宪法），流程事项低于 AGENTS.md。
- 根 AGENTS.md 中支持页停在退休 Kami 视觉（羊皮纸、衬线、墨蓝）的过期说法已改正：七张支持页自 commit `662cab4` 起使用 Flood（`#f1f0eb` 底、Newsreader + IBM Plex Mono）；"无框架纯静态页"的结构规则保留。
- 围城运动（siege）的合同应放在仓库里，不放在私人 `.pi` 目录里。

## Open（本任务未决定，不得当作已定）

- 仓库里目前没有 `siege-motion-model.md`；`VISION.md`、`design/DESIGN.md` 与 `index.html` 注释里的引用暂时悬空，等专门任务补上。
- 空格是否计入字数：未决定。
- 落地页 trial 政策：未决定。
- CI：未决定。
- 归档的 game-mode 演示如何处置：未决定。
- early-bird 定价：未决定（本次只替换对外名称，未改价格或授权条款实质）。
