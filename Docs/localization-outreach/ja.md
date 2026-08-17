<!--
Ready to post as an issue once the repository exists. Title and body are in
Japanese on purpose: someone who reads Japanese should not have to read an
English request first. Label it "help wanted" and pin it.
-->

**タイトル:** 日本語訳の見直しにご協力ください

---

`ccwidget` は macOS のデスクトップに置く小さなウィジェットです。Claude の
サブスクリプションをどれだけ使ったか、コンテキストウィンドウがどれだけ埋まって
いるか、週の上限がいつ尽きそうかを表示します。

画面表示は6言語あります。英語とロシア語は母語話者によるものですが、**日本語は
違います** — 開発者が辞書を片手に訳したものです。そのため、日本語を母語とする
方に一度目を通していただけると本当に助かります。

訳し直しをお願いしたいのではありません。辞書では気づけない次の2点だけです。
ひとつは「意味は合っているが、そうは言わない」表現。もうひとつは語調のずれです。
実際にあった例として、行の見出しは当初 `週 使用` でしたが、割合を示す場面では
`週の使用率` のほうが自然だと考えて直しました。同じような箇所はまだあるはずです。

112 個すべての文字列は
[`Docs/localization-review.md`](https://github.com/davidkremlev/ccwidget/blob/main/Docs/localization-review.md) にあります。
表現に影響する前提も併記しています。たとえば3本のバーはいずれも「増えるほど
悪い」方向にそろえていること、幅 338 ポイントのタイルでは 22 文字あたりから
省略が始まることなどです。

**この Issue に一行いただければ十分です:**

```
"Week used" (ja) → 「週の使用率」より「…」のほうが自然です
```

プルリクエストも Swift の知識も不要です。直接編集されたい場合は、文字列は
`App/Resources/Localizable.xcstrings` と
`Widget/Resources/Localizable.xcstrings` に JSON で入っています。

一箇所だけのご指摘でもありがたいです。すべて訳されているが不自然な文章より、
自然な一行のほうが価値があります。
