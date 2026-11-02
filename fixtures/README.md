# 测试书

- `demo-de.epub`（103 KB）：德语 TTS 真音频 + EPUB3 SMIL 时间轴，用来验证「播放时逐句高亮」。两句正文共用一条 `audio/demo.mp3`，`clipBegin/clipEnd` 与音频实际时长对齐（0–6.10s / 6.50–12.71s）。
- `grimm-froschkoenig.epub`（5 KB）：纯文本冒烟样本，不含真实音频，用来验证解包/OPF/章节渲染。

两份都是公版文本（格林童话），音频由 Edge TTS（de-DE）生成。
