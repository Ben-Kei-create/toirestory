# PaperStory for Mac

巻紙を下へドラッグして『走れメロス』を読む、macOS専用アプリです。
macOS 15以降に対応します。

## 開発

`paperstory.xcodeproj` をXcodeで開き、`paperstory` スキームの実行先に「My Mac」を選びます。
標準ウィンドウは900×820pt、最小サイズは640×700ptです。
物理演算の応答を保つため、DebugでもSwiftの最適化を有効にしています。

```sh
xcodebuild -project paperstory.xcodeproj -scheme paperstory -destination 'platform=macOS' -configuration Debug build
```

## 操作

- 紙を下へドラッグ、スクロール、または下矢印キーで本文を繰り出します。
- 「ここで切る」でミシン目を切れます（⌘K）。
- 紙の外をドラッグすると視点が回り、「視点」で戻せます（⌘0）。
- 右下の「本文」「ロール」で表示を切り替えます（⌘1）。
- 左上の戻るボタンで作品選択へ戻ります（⌘←）。
- 紙をクリックすると濡れた跡がつき、同じ箇所を繰り返しクリックすると破れます。
- 引き出した位置は端末内に保存します。右上のメニューから最初に戻せます。

## 配布と広告

Macネイティブ版はGoogle Mobile Ads / UMPを使用せず、広告枠も表示しません。
外部SDK依存や、アプリから外部へ通信する処理はありません。
iOS向けのAdMob設定・SDK依存は取り除いています。

App Store ConnectではPaperStoryにmacOSプラットフォームを追加し、Mac用ビルドを提出します。
審査資料は `docs/app-review/` を参照してください。
サポートページとプライバシーポリシーのWeb上の説明も、Mac版の内容へ更新が必要です。
