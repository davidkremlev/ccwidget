<!--
Ready to post as an issue once the repository exists. Title and body are in
Simplified Chinese on purpose: someone who reads Chinese should not have to
read an English request first. Label it "help wanted" and pin it.
-->

**标题:** 简体中文翻译：希望有母语者帮忙校对

---

`ccwidget` 是一个放在 macOS 桌面上的小组件，显示你的 Claude 订阅额度用了多少、
上下文窗口填了多少，以及本周的额度大概什么时候会用完。

界面共有六种语言。英语和俄语出自母语者之手，**简体中文不是** —— 是开发者自己
对着词典译的。因此非常希望有以中文为母语的朋友帮忙看一遍。

不需要重译。只想请你留意词典发现不了的两件事：一是意思没错、但中文里没人这么
说的句子；二是语气不合适的地方。已经改过一处类似的问题：几行标题原本是德语的
`Woche genutzt`、西班牙语的 `Semana usada`，字面对但读起来像「被使用过的一周」。
中文目前用的是 `本周已用`，我认为是地道的，但也可能有别的地方不是。

全部 112 条字符串都在
[`Docs/localization-review.md`](https://github.com/davidkremlev/ccwidget/blob/main/Docs/localization-review.md) 里，同时列出了
会影响措辞的背景：例如三条进度条都是「越多越糟」的方向，以及在 338 点宽的卡片
上，标题超过 22 个字符左右就会被截断。

**在这个 issue 里留一行就够了：**

```
"Week used" (zh-Hans) → 「本周已用」不如说成「…」
```

不需要提交 pull request，也不需要懂 Swift。如果你更愿意直接改，字符串是 JSON，
位于 `App/Resources/Localizable.xcstrings` 和
`Widget/Resources/Localizable.xcstrings`。

哪怕只指出一处也非常感谢。一句自然的中文，胜过一份完整但生硬的译文。
