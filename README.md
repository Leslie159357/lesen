# Lesen · 德语精读（P0）

从 OneBook 拆解里挑出 P0 主干做的最小可用版本：**EPUB 排版 + 音频播放 + 点词查义 + 德语发音**。

## 这一版能做什么

| 能力 | 状态 | 实现 |
| :--- | :--- | :--- |
| 导入 EPUB（含图片） | ✅ | ZIPFoundation 解包 → container.xml → OPF → 章节 HTML |
| 排版阅读 | ✅ | WKWebView + 自研 reader.js（段落/标题/图片/字号/深浅色） |
| 点击取词 | ✅ | 文本按句切分 → 词级 span → 点击回传 Swift |
| 本地词典 | ✅ | 129 条德语演示词（含词性、复数、强变化），可整体替换 |
| 德语发音 | ✅ | AVSpeechSynthesizer de-DE（系统音色，离线） |
| 音频播放 | ✅ | AVAudioPlayer + 0.75/1.0/1.25/1.5 倍速 |
| EPUB3 Media Overlays 逐句高亮 | ✅ | 解析 SMIL `clipBegin/clipEnd` → 时间轴驱动高亮 |
| 词典查词增强（词形还原） | 部分 | 简易后缀回退，非完整词形表 |
| TTS 云音色 / 全文翻译 / 生词本 | ⏳ P1 | — |

## 目录

```
Sources/
  App.swift          入口
  Models.swift       数据模型
  EPUBBook.swift     解包 + OPF/SMIL 解析（正则，无 XML 依赖）
  LibraryStore.swift 书库（Documents/Books/<uuid>）
  WebReader.swift    WKWebView + JS 桥
  ReaderView.swift   阅读页（词典卡、播放控制、逐句跳转）
  LibraryView.swift  书库页（导入/打开/删除）
  Dictionary.swift   本地词库 + 简易词形回退
  Speech.swift       de-DE 发音
  AudioEngine.swift  播放器 + 0.25s tick
Web/
  reader.html/css/js 渲染层（无网络请求，全部由 Swift 注入）
  de-zh-demo.json    演示词库
```

## 设计取舍（相对 OneBook）

- **不引入 Foliate**：P0 用自研 200 行 JS 完成排版与切句；Foliate 的 CFI 体系是 P1 再上的事。
- **不引入 FFmpeg**：先用 AVFoundation，m4a/mp3 够用；mkv/flac 等 FFmpeg 场景留到 P1。
- **不走 file:// 读盘**：EPUB 内容由 Swift 读成字符串注入 WebView，图片转 data URI，彻底避开 CORS 与沙盒路径问题。
- **词典数据自带 129 条**：授权问题不碰，接口留好，换库只要替换 JSON。

## 构建

CI（GitHub Actions，`macos-26`）产出未签名 IPA：

```
Actions → ios-unsigned-ipa → Lesen-ipa
```

本机无需 Xcode。打包后 CI 会断言 `Web/reader.html` 与 `Web/de-zh-demo.json` 确实进了 IPA。

## 待办（按 OneBook 报告里的 P0/P1）

- [ ] 字号/行距/边距设置持久化
- [ ] 阅读进度记忆（章节 + 段落 id）
- [ ] 生词本（点击记录 + 复习队列）
- [ ] 完整词典接入（SQLite + FTS5，替代演示 JSON）
- [ ] 分页模式（现在是连续滚动）
- [ ] FFmpeg 解码（mkv/flac/ogg）
