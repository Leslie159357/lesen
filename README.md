# Lesen · 德语精读（v0.3.0）

从 OneBook 拆解里挑出的主干，做到能真实用起来的最小闭环：**EPUB 排版 + 音频播放 + 点词查义 + 生词复习 + 进度记忆**。

## 这一版能做什么

| 能力 | 状态 | 实现 |
| :--- | :--- | :--- |
| 导入 EPUB（含图片） | ✅ | ZIPFoundation 解包 → container.xml → OPF → 章节 HTML |
| 排版阅读 | ✅ | WKWebView + 自研 reader.js（段落/标题/图片/字号/深浅色） |
| 滚动 / 分页两种模式 | ✅ | 分页用 CSS 多栏 + 横向滚动，手势与按钮翻页 |
| 点击取词 | ✅ | 文本按句切分 → 词级 span → 点击回传 Swift |
| 本地词典 | ✅ | SQLite + FTS5（unicode61），129 条种子词入库后走 SQL |
| 词形回退 | ✅ | 62 条变形索引（Häuser→Haus、spricht→sprechen、geholfen→helfen）＋后缀回退＋FTS 前缀 |
| 生词本 + 复习 | ✅ | 点击即存，Leitner 6 档（0/1/2/4/8/16 天），到期列表 |
| 阅读进度 | ✅ | 按书记录章节 + 章内百分比，重开自动回到原位 |
| 设置持久化 | ✅ | 字号与阅读模式走 AppStorage |
| 德语发音 | ✅ | AVSpeechSynthesizer de-DE（系统音色，离线），单词与整句都能读 |
| 音频播放 | ✅ | AVAudioPlayer + 0.75/1.0/1.25/1.5 倍速 |
| EPUB3 Media Overlays 逐句高亮 | ✅ | 解析 SMIL `clipBegin/clipEnd` → 时间轴驱动高亮 |
| TTS 云音色 / 全文翻译 | ⏳ P2 | — |
| FFmpeg（mkv/flac/ogg） | ⏳ P2 | 当前只有 AVFoundation，m4a/mp3/aac 可用 |

## 目录

```
Sources/
  App.swift           入口
  Models.swift        数据模型
  EPUBBook.swift      解包 + OPF/SMIL 解析（正则，无 XML 依赖）
  LibraryStore.swift  书库（Documents/Books/<uuid>）
  LexiconStore.swift  SQLite：词典 / FTS5 / 变形别名 / 生词本 / 进度
  WebReader.swift     WKWebView + JS 桥
  ReaderView.swift    阅读页（词典卡、播放控制、逐句跳转、模式切换）
  VocabularyView.swift 生词本与复习
  LibraryView.swift   书库页（导入/打开/删除，生词本入口）
  Speech.swift        de-DE 发音
  AudioEngine.swift   播放器 + 0.25s tick
Web/
  reader.html/css/js 渲染层（无网络请求，全部由 Swift 注入）
  de-zh-demo.json    词典种子（129 条）
fixtures/
  demo-de.epub       带真音频与 SMIL 的测试书
  grimm-froschkoenig.epub 纯文本冒烟样本
```

## 设计取舍（相对 OneBook）

- **不引入 Foliate**：自研 JS 完成排版与切句；Foliate 的 CFI 体系是后续要复用的东西，但不是第一天该背的债。
- **不引入 FFmpeg**：AVFoundation 覆盖 m4a/mp3/aac，够读有声书；mkv/flac 等场景留到 P2。
- **不走 file:// 读盘**：EPUB 内容由 Swift 读成字符串注入 WebView，图片转 data URI，彻底避开 CORS 与沙盒路径问题。
- **词典与生词本同库**：`lexicon.sqlite` 一个文件装 entry / entry_fts / alias / vocab / progress，备份只需拷一个文件。

## 数据表

| 表 | 用途 |
| :--- | :--- |
| `entry` | 词条（word / pos / zh / note） |
| `entry_fts` | FTS5 外部内容表，前缀匹配用 |
| `alias` | 变形 → 原形 |
| `vocab` | 生词（sentence 上下文、box、due、reps） |
| `progress` | 每本书的章节 + 百分比 |

## 构建

CI（GitHub Actions，`macos-26`）产出未签名 IPA：

```
Actions → ios-unsigned-ipa → Lesen-ipa
```

本机无需 Xcode。打包后 CI 会断言 `Web/reader.html` 与 `Web/de-zh-demo.json` 确实进了 IPA。

## 待办

- [ ] FFmpeg 解码（mkv/flac/ogg，需要 ffmpeg-kit 替代方案或自建）
- [ ] 云 TTS（多供应商可插拔，OneBook 的 20 家设计）
- [ ] 全文翻译（Apple Translation 框架）
- [ ] 生词导出（CSV / Anki）
- [ ] 全文检索（FTS5 已就绪，缺 UI）
- [ ] 词典换库（Duden / Wiktionary dump 导入器）
