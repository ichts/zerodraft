# Native macOS workspace instructions

Parent instructions: `../../AGENTS.md`

成员清单
FirstLine/: 原生 macOS First Line 应用，纯 AppKit（NSApplication 入口，无 SwiftUI；已从 SwiftUI 壳重写），以 Swift Package 构建和测试。

对外暴露
原生 macOS 子模块目录。

法则: Web 版 zerodraft 与原生 First Line 分开演进，不混用 Datastar 运行时实现。

[PROTOCOL]: When this directory's structure or invariants change, update this file and verify `../../AGENTS.md` remains accurate.
