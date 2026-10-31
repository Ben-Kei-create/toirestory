# paperstory

紙を引き出して物語を読むiOSアプリ。

読書画面の右下で「本文」「ロール」を切り替えられます。
本文表示ではロールとホルダーを隠して紙を拡大します。
切り替えても、引き出した紙・切断・染みの状態は保持されます。

## 開発

`paperstory.xcodeproj` をXcodeで開き、`paperstory` スキームを実行します。
Google Mobile Ads SDKはSwift Package Managerで取得します。

## 広告

ライブラリと読書画面の下部に320×50ptのAdMobバナーを表示します。
操作欄とは別のセーフエリアに配置し、起動演出中は表示しません。

- DebugはGoogle公式のテスト広告ユニットIDを使用します。
- Releaseは登録済みの本番アプリID・広告ユニットIDを使用します。
- IDの設定場所はターゲットのBuild Settings内の `ADMOB_APP_ID` と `ADMOB_BANNER_AD_UNIT_ID` です。
- UMPで広告の同意状態を更新し、必要なフォームを表示してから広告を読み込みます。
  必要な地域向けのメッセージはAdMob管理画面の「プライバシーとメッセージ」で設定してください。
- 同意状態や通信エラーで広告を取得できない場合は、広告枠だけを残します。

参考: [公式セットアップ](https://developers.google.com/admob/ios/quick-start)、
[バナー広告](https://developers.google.com/admob/ios/banner)、
[UMP](https://developers.google.com/admob/ios/privacy)。
