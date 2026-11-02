# PaperStory：Mac専用で提出する手順

1. Xcodeで `paperstory` → My Mac → Releaseを選び、Mac実機で起動・作品選択・ドラッグ・切断・本文／ロール切り替え・戻る・保存と再開を確認する。
2. サポート／プライバシーポリシーのWebページをMac版・広告なしの内容に更新する。現在のiOS／AdMob向け説明をそのまま使わない。
3. App Store Connect → PaperStory → 「プラットフォームを追加」でmacOSを追加する。iOSビルドをそのままMac用として提出することはできない。
4. Xcode → Product → Archive → Distribute Appから、署名したMac用ビルドをApp Store Connectへアップロードする。
5. macOSバージョンのスクリーンショット・概要・サポートURL・価格・配信地域・年齢制限指定・Appのプライバシーを、Mac版の実装に合わせて設定する。アカウントは不要のため「サインインが必要です」はオフ。
6. Macの実機録画を添付し、`review-notes-en.txt` を「App Reviewに関する情報」のメモへ貼り付ける。録画添付後に、最初の項目を「A screen recording captured on a physical Mac running the latest macOS version is attached.」から始める文章に更新する。
7. Mac用ビルドを選択し、macOSバージョンを審査へ提出する。iOS版の再提出は進めない。

録画の操作は `recording-checklist-ja.txt` を参照。
署名・アップロード・App Store Connectのプラットフォーム追加・Webページの変更・審査提出は、コード変更だけでは完了しない。
