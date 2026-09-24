# Native macOS workspace instructions

Parent instructions: `../../AGENTS.md`

成员清单
FirstLine/: writeitdown 原生 macOS 应用（沿用历史源码路径），纯 AppKit，以 Swift Package 构建和测试；改造批次见 `FirstLine/docs/WRITEITDOWN_PLAN.md`。

对外暴露
原生 macOS 子模块目录。

法则: writeitdown 网站与原生 macOS 版分开演进，不混用浏览器运行时实现。

[PROTOCOL]: When this directory's structure or invariants change, update this file and verify `../../AGENTS.md` remains accurate.
