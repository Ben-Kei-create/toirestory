# PaperStory — iPhone / Mac

巻紙を下へドラッグして『走れメロス』を読むアプリです。
**iPhone（iOS 18以降）とMac（macOS 15以降）の両方に対応します。**

## 起動

`paperstory.xcodeproj` をXcodeで開き、`paperstory` スキームを選びます。

- iPhone版：実行先をiPhone実機、またはiPhoneシミュレータにする。
- Mac版：実行先を「My Mac」にする。

Mac版はネイティブウィンドウで動作し、標準900×820pt、最小640×700ptです。
物理演算の応答を保つため、DebugでもSwiftの最適化を有効にしています。

```sh
xcodebuild -project paperstory.xcodeproj -scheme paperstory -sdk iphonesimulator -configuration Debug build
xcodebuild -project paperstory.xcodeproj -scheme paperstory -destination 'platform=macOS' -configuration Debug build
```

## 操作

- 紙を下へドラッグすると本文が繰り出されます。Macではスクロールと下矢印キーにも対応します。
- 「ここで切る」でミシン目を切れます（Macは⌘K）。
- 紙の外をドラッグすると視点が回り、「視点」で戻せます（⌘0）。
- 右下の「本文」「ロール」で表示を切り替えます（⌘1）。
- 左上の戻るボタンで作品選択へ戻ります（⌘←）。
- 紙をタップ／クリックすると濡れた跡がつき、同じ箇所を繰り返すと破れます。
- 引き出した位置は各端末内に保存します。右上のメニューから最初に戻せます。端末間同期はありません。

## 広告

- **iPhone版**：下部にGoogle AdMobバナーを表示します。UMPの同意確認を使用します。Debugは公式テスト広告、Releaseは本番広告IDです。
- **Mac版**：広告は表示しません。Google Mobile Ads SDKはiOS向けのみリンクし、Mac向けビルドでは使用しません。
- DebugのiPhone版は起動引数 `-hideAds` で、撮影用に広告読み込みを止められます。
- IDはBuild Settingsの `ADMOB_APP_ID` / `ADMOB_BANNER_AD_UNIT_ID`、iOS用Info.plistは `paperstory/Info-iOS.plist` です。

## 提出

App Store Connectの同じPaperStoryアプリに、iOS版とmacOS版をそれぞれのプラットフォームとして提出します。
Mac対応の追加に伴いiPhone版を取り下げる必要はありません。
審査資料は `docs/app-review/` を参照してください。
