# Lesen · 德语精读（v0.5.0）

把 OneBook 拆解里值得抄的部分，做成一个能真读、真听、真背的工具：**EPUB 排版 + 音频对齐 + 点词查义 + 生词复习 + AI 翻译讲解 + 全书搜索**。

## 功能清单

| 能力 | 状态 | 实现 |
| :--- | :--- | :--- |
| 导入 EPUB（含图片） | ✅ | ZIPFoundation 解包 → container.xml → OPF → 章节 HTML |
| 排版阅读 | ✅ | WKWebView + 自研 reader.js（段落/标题/图片/字号/深浅色） |
| 滚动 / 分页 | ✅ | 分页用 CSS 多栏 + 横向滚动，按钮翻页 |
| 点击取词 | ✅ | 句子切分 + 词级 span，点击回传 Swift |
| 本地词典 | ✅ | SQLite + FTS5（unicode61），129 条种子入库后全走 SQL |
| 词形回退 | ✅ | 62 条变形索引（Häuser→Haus、spricht→sprechen、geholfen→helfen）＋后缀＋FTS 前缀 |
| 生词本 + 复习 | ✅ | 点击即存，Leitner 6 档（0/1/2/4/8/16 天），到期队列 |
| 生词导出 | ✅ | 生成 CSV，走系统分享面板 |
| 阅读进度 | ✅ | 按书记录章节 + 章内百分比，重开回到原位 |
| 全书搜索 | ✅ | 章节正文（忽略变音符号）+ 词典 FTS 双通道，点结果直接跳章 |
| 德语发音 | ✅ | AVSpeechSynthesizer de-DE，离线 |
| 云 TTS | ✅ | 任意 OpenAI 兼容 `/audio/speech`，可切音色；未配置时回落系统音色 |
| AI 翻译 / 讲解 | ✅ | 同一 OpenAI 兼容接口，译成中文或分三行讲语法 |
| 音频播放 | ✅ | m4a/mp3/aac/flac 走 AVFoundation；mkv/ogg/opus/webm 走 libmpv（MPVKit） |
| 逐句高亮 | ✅ | 解析 SMIL `clipBegin/clipEnd`，两套引擎都向同一时间轴同步 |
| 词典导入 | ✅ | CSV/TSV（word,pos,zh,note），导入后自动重建 FTS 与变形索引 |

## 目录

```
Sources/
  App.swift           入口
  Models.swift        数据模型
  EPUBBook.swift      解包 + OPF/SMIL 解析（正则，无 XML 依赖）
  LibraryStore.swift  书库（Documents/Books/<uuid>）
  LexiconStore.swift  SQLite：词典/FTS5/变形/生词/进度/搜索/导入/导出
  WebReader.swift     WKWebView + JS 桥
  ReaderView.swift    阅读页（词典卡、AI、播放控制、模式切换、搜索入口）
  VocabularyView.swift 生词本与复习
  SearchView.swift    全书搜索
  SettingsView.swift  AI 接口、云 TTS、词典导入
  AISettings.swift    OpenAI 兼容客户端（chat + audio/speech）
  CloudSpeaker.swift  云 TTS 播放
  Speech.swift        de-DE 系统发音
  AudioEngine.swift   AVFoundation 播放 + 0.25s tick
  MPVEngine.swift     libmpv 控制面（无渲染面，音频专用）
  ActivityView.swift  系统分享面板包装
Web/
  reader.html/css/js 渲染层（无网络请求，全部由 Swift 注入）
  de-zh-demo.json    词典种子（129 条）
fixtures/
  demo-de.epub       带真音频与 SMIL 的测试书
  grimm-froschkoenig.epub 纯文本冒烟样本
```

## 设计取舍（相对 OneBook）

- **不引入 Foliate**：自研 JS 完成排版与切句；Foliate 的 CFI 体系值得复用，但不是第一版该背的债。
- **双播放引擎而非 FFmpeg**：AVFoundation 覆盖 m4a/mp3/aac/flac；容器不支持的走 libmpv。比塞 ffmpeg-kit（已停维护）稳。
- **不走 file:// 读盘**：EPUB 内容由 Swift 读成字符串注入 WebView，图片转 data URI，绕开 CORS 与沙盒路径。
- **一个 SQLite 装全部**：entry / entry_fts / alias / vocab / progress 同库，备份只拷一个文件。
- **AI 不预设厂商**：只要求 OpenAI 兼容协议，key 与 base URL 由用户填，端上不内置任何服务。

## 数据表

| 表 | 用途 |
| :--- | :--- |
| `entry` | 词条（word / pos / zh / note） |
| `entry_fts` | FTS5 外部内容表 |
| `alias` | 变形 → 原形 |
| `vocab` | 生词（上下文句、box、due、reps） |
| `progress` | 每本书的章节 + 百分比 |

## 构建

CI（GitHub Actions，`macos-26`）产出未签名 IPA：

```
Actions → ios-unsigned-ipa → Lesen-ipa
```

本机无需 Xcode。打包后 CI 会断言 `Web/reader.html` 与 `Web/de-zh-demo.json` 确实进了 IPA。

## 已知限制

- 分页模式的页码按 CSS 栏位估算，不是精确的印刷页。
- 图片是 base64 内联，超大画册会吃内存（一般小说无影响）。
- 云 TTS/翻译需要自备 key，端上不代理、不代付。
- 词形回退基于种子词表的备注列，词表越小命中越低；换成完整词典后才有意义。
