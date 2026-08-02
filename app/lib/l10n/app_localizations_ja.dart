// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Caller\'s Compendium';

  @override
  String get navCollection => 'コレクション';

  @override
  String get navPrograms => 'プログラム';

  @override
  String get navSettings => '設定';

  @override
  String get navGuide => 'ガイド';

  @override
  String get navGuideTooltip => 'ユーザーガイド';

  @override
  String get navSearch => '検索';

  @override
  String navSearchTooltip(String hint) {
    return '検索 ($hint)';
  }

  @override
  String get appBootstrapPreparing => 'コレクションを準備しています';

  @override
  String get appBootstrapRebuildingIndex => '検索インデックスを再構築しています';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return '検索インデックスを再構築しています… $percent%';
  }

  @override
  String get appBootstrapError => 'コレクションを準備できませんでした。';

  @override
  String get migrationDowngradeMessage =>
      'このデータは新しいバージョンのCaller’s Compendiumで作成されました。アプリを更新してください。';

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return '保存データをアップグレードする前に自動バックアップを作成できなかったため、Caller’s Compendiumを起動できませんでした。$cause空き容量を確保する（またはバックアップフォルダを修復する）か、アプリを再度開いてください。あるいは、再度開いてバックアップなしで続行することもできます。';
  }

  @override
  String get migrationSnapshotCauseDiskFull => 'デバイスの空き容量が不足しているようです。';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      '自動バックアップフォルダに書き込めませんでした。';

  @override
  String get migrationSnapshotConsentTitle => 'データをバックアップできませんでした';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return '保存データを新しい形式にアップグレードする前に、Caller’s Compendiumは自動バックアップを作成し、アップグレードに失敗しても元に戻せるようにします。今回はそのバックアップを作成できませんでした。$cause\n\nバックアップなしで続行してアップグレードが中断されると、一部のダンスやプログラムが失われる可能性があります。アプリを終了し、空き容量を確保（またはバックアップフォルダを修復）してから、アプリを再度開いてもう一度お試しください。';
  }

  @override
  String get migrationSnapshotConsentQuit => '終了';

  @override
  String get migrationSnapshotConsentProceed => 'バックアップなしで続行';

  @override
  String get confirmDeleteTitle => '削除しますか？';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '「$itemLabel」を削除します。元に戻せます。';
  }

  @override
  String get colorEditHexLabel => 'HEX';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsGeneralTitle => '一般';

  @override
  String get settingsAppearanceTitle => '外観';

  @override
  String get settingsDialectTitle => 'ダイアレクト';

  @override
  String get settingsDefaultsTitle => 'デフォルト';

  @override
  String get settingsUpdatesTitle => 'アップデート';

  @override
  String get settingsDiagnosticsTitle => '診断';

  @override
  String get settingsAboutTitle => '情報';

  @override
  String get commonSystemDefault => 'システムのデフォルト';

  @override
  String get commonComingSoon => '近日公開';

  @override
  String get settingsLanguageRegionTitle => '言語と地域';

  @override
  String get settingsRegionalFormatsHeader => 'フォーマット';

  @override
  String get settingsRegionalLanguageHeader => '言語';

  @override
  String get settingsDateFormatTitle => '日付フォーマット';

  @override
  String settingsDateFormatSubtitle(String example) {
    return 'プログラムのイベント日付の表示形式。例: $example';
  }

  @override
  String get settingsDateFormatYmd => '年-月-日 (2026-07-15)';

  @override
  String get settingsDateFormatDmy => '日/月/年 (15/07/2026)';

  @override
  String get settingsDateFormatMdy => '月/日/年 (07/15/2026)';

  @override
  String get settingsDateFormatCustom => 'カスタム…';

  @override
  String get settingsDateFormatCustomPatternLabel => 'カスタム日付パターン';

  @override
  String get settingsDateFormatCustomPatternHint => 'MM.DD.YY';

  @override
  String get settingsDateFormatCustomLegend =>
      'トークン：yyyy または yy = 年、MM = 月（MMM = 略称、MMMM = 正式名称）、d または dd = 日。区切り文字：- / . , またはスペース。';

  @override
  String get settingsDateFormatCustomInvalid =>
      '認識できないパターンです — 修正されるまでシステムの既定値を使用します。';

  @override
  String get settingsFirstDayOfWeekTitle => '週の始まりの曜日';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'アプリ自身が描画する日付表示(プログラム一覧の「今週」ストリップなど)で、週の始まる曜日を指定します。';

  @override
  String get settingsFirstDayOfWeekSunday => '日曜日';

  @override
  String get settingsFirstDayOfWeekMonday => '月曜日';

  @override
  String get settingsFirstDayOfWeekSaturday => '土曜日';

  @override
  String get settingsAppLanguageTitle => 'アプリの言語';

  @override
  String get settingsAppLanguageSubtitle => 'アプリのインターフェース言語を選択してください。';

  @override
  String get settingsAboutHelpHeader => 'ヘルプ';

  @override
  String get settingsAboutUserGuideTitle => 'ユーザーガイド';

  @override
  String get settingsAboutUserGuideSubtitle =>
      '組み込みガイドを読む — 入門、ダイアレクト、インポートなど。オフラインでも利用可能。';

  @override
  String get settingsAboutLicenseHeader => 'ライセンス';

  @override
  String get settingsAboutLicenseBody =>
      'Caller\'s Compendiumはフリーソフトウェアで、GNU Affero General Public License バージョン3（AGPL-3.0）のもとで使用許諾されています。同ライセンスに従い、自由に使用、研究、共有、改変することができます。AGPLの要件により、このアプリを使用するすべての人に完全な対応ソースコードが提供されます。';

  @override
  String get settingsAboutViewSourceTitle => 'GitHubでソースを見る';

  @override
  String get settingsAboutFontsHeader => 'フォント';

  @override
  String get settingsAboutFontsBody =>
      'このアプリにはSIL Open Font License 1.1のもとで以下のフォントが含まれています。ライセンス全文は「ライセンスを見る」から確認できます。';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — 見出し表示用';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — 本文・UI・パフォーム用';

  @override
  String get settingsAboutFontRobotoSubtitle =>
      'SIL Open Font License 1.1 · © The Roboto Project Authors — フォールバック';

  @override
  String get settingsAboutThemesHeader => 'テーマ';

  @override
  String get settingsAboutThemesBody =>
      '一部のカラーテーマはコードエディタのパレット（One Dark、Dracula、Nord、Tokyo Night、Gruvbox、Catppuccinなど）にインスパイアされ、このアプリ向けに再設計・コントラスト調整を施したものです。テーマ名はインスピレーションのクレジットとしてのみ使用されています。';

  @override
  String get settingsAboutDanceDataHeader => 'ダンスデータ';

  @override
  String get settingsAboutDanceDataBody =>
      'ダンスデータはThe Caller\'s Box（Chris Page & Michael Dyck）を参照しており、同コレクションはCreative Commons Attribution-NonCommercial（CC BY-NC）ライセンスのもとで公開されています。感謝を込めて。';

  @override
  String get settingsAboutLicensesHeader => 'ライセンス一覧';

  @override
  String get settingsAboutViewLicensesTitle => 'ライセンスを見る';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'バンドルされているフォントを含む、オープンソースライセンスの全文。';

  @override
  String get settingsAboutLegalese =>
      '© The Caller\'s Compendium contributors. AGPL-3.0のもとで使用許諾。';

  @override
  String settingsAboutVersion(String version) {
    return 'バージョン $version';
  }

  @override
  String settingsAboutVersionLine(
    String appName,
    String version,
    String license,
  ) {
    return '$appName · バージョン $version · $license';
  }

  @override
  String get settingsUpdatesHeader => 'アップデート';

  @override
  String get settingsUpdatesCheckNowTitle => 'アップデートを確認';

  @override
  String settingsUpdatesStatusIdle(String version) {
    return '現在のバージョンは $version です。';
  }

  @override
  String get settingsUpdatesStatusChecking => '確認中…';

  @override
  String settingsUpdatesStatusNoUpdate(String version) {
    return 'アップデートは見つかりませんでした。現在のバージョンは $version です。';
  }

  @override
  String settingsUpdatesStatusAvailable(String version) {
    return 'バージョン $version が利用可能です。バナーをご確認ください。';
  }

  @override
  String get settingsUpdatesChannelHeader => 'チャンネル';

  @override
  String get settingsUpdatesBetaTitle => 'ベータチャンネル';

  @override
  String get settingsUpdatesBetaSubtitle =>
      'プレリリースのベータアップデートを受け取ります。オフの場合は安定版のみです。';

  @override
  String get settingsUpdatesAutoHeader => '自動確認';

  @override
  String get settingsUpdatesAutoTitle => '自動的に確認する';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'アプリ起動時にバックグラウンドで新バージョンを確認します。デフォルトはオフです。';

  @override
  String get settingsUpdatesPrivacyNote =>
      'アップデート確認はHTTPS経由で小さなバージョンファイルをダウンロードするだけで、その他の情報は一切送信されません。ユーザー情報、デバイス情報、使用状況は送信されません。自動でダウンロードやインストールは行われません。アップデートのダウンロードはご自身で選択し、開く前に検証され、システムのインストーラーがインストールを完了します。';

  @override
  String get settingsUpdatesDownloadingTitle => 'アップデートをダウンロード中';

  @override
  String get settingsUpdatesDownloadingIndeterminate => 'ダウンロード中…';

  @override
  String settingsUpdatesDownloadingPercent(int percent) {
    return 'ダウンロード中… $percent%';
  }

  @override
  String get settingsUpdatesVerifyingTitle => 'ダウンロードを検証中';

  @override
  String get settingsUpdatesVerifyingSubtitle => 'ダウンロードのsha256整合性を確認しています…';

  @override
  String get settingsUpdatesHandoffTitle => 'インストーラーを準備中';

  @override
  String get settingsUpdatesHandoffSubtitle => '検証済みのアップデートをシステムに渡しています…';

  @override
  String get settingsUpdatesCompletedTitle => 'アップデートをダウンロードしました';

  @override
  String get settingsUpdatesCompletedSubtitle =>
      'システムのインストーラーに従ってアップデートを完了してください。';

  @override
  String get settingsUpdatesCompletedSubtitleRevealed =>
      '検証済みのファイルがファイルマネージャーで表示されました — インストーラーを実行してアップデートを完了してください。';

  @override
  String get settingsUpdatesDownloadTitle => 'アップデートをダウンロードしてインストール';

  @override
  String get settingsUpdatesDownloadError => 'アップデートをダウンロードできませんでした。';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'バージョン $version をダウンロードして検証し、インストーラーを起動します。アプリが自動的に上書きされることはありません。';
  }

  @override
  String get settingsDialectHeader => 'ダイアレクト';

  @override
  String get settingsDialectNewButton => '新しいダイアレクト';

  @override
  String get settingsDialectNewDefaultName => 'マイダイアレクト';

  @override
  String get settingsDialectCreateConfirm => '作成';

  @override
  String get settingsDialectDuplicateFrom => '複製元を選択…';

  @override
  String get settingsDialectRenameTitle => 'ダイアレクトの名前を変更';

  @override
  String get settingsDialectRename => '名前を変更';

  @override
  String get settingsDialectEditTerms => '用語を編集';

  @override
  String get settingsDialectDuplicateToCustomize => 'カスタマイズのために複製';

  @override
  String get settingsDialectDeleteTitle => 'ダイアレクトを削除しますか？';

  @override
  String settingsDialectDeleteConfirmBody(String name) {
    return '「$name」は完全に削除されます。';
  }

  @override
  String get settingsDialectActionsTooltip => 'ダイアレクトのアクション';

  @override
  String get settingsDialectPresetBadge => 'プリセット';

  @override
  String get settingsDialectNameLabel => '名前';

  @override
  String get settingsAppearanceThemeHeader => 'テーマ';

  @override
  String get settingsAppearanceCustomThemesHeader => 'カスタムテーマ';

  @override
  String get settingsAppearanceEasterEggsHeader => 'イースターエッグ';

  @override
  String get settingsAppearanceSetListsHeader => 'セットリスト';

  @override
  String get settingsAppearanceFormationColoursHeader => 'フォーメーションの色';

  @override
  String get settingsAppearanceColourDanceTitle => '色名を持つダンスはテーマを着色します';

  @override
  String get settingsAppearanceColourDanceSubtitle =>
      '楽しいサプライズ機能：色名を持つダンス（Baby RoseやBlue Boyなど）を開くと、その色でビューが着色されます。デフォルトはオフで、高コントラストのテーマが有効な場合は自動的に無効になります。';

  @override
  String get settingsAppearanceSetListColorTitle => 'セットリストの行をカラーコード化';

  @override
  String get settingsAppearanceSetListColorSubtitle =>
      '各ダンス行をフォーメーションファミリー（コントラ、ミキサー、スクエアなど）で着色します。フォーメーションは常にテキストでも表示されるため、色なしでも読み取れます。';

  @override
  String get settingsAppearanceFormationColoursTitle => 'フォーメーションラベルの色';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      '個々のフォーメーションを独自の色でハイライト表示（例：Becket（CW）を黄色、Becket（CCW）をピンク）します。ダンスカード、ダンス詳細、パフォームヘッダーに反映されます。';

  @override
  String get settingsAppearanceSelectedBadge => '選択済み';

  @override
  String get settingsAppearancePreviewHeading => 'Aa プレビュー';

  @override
  String get settingsAppearancePreviewBody => '本文テキストのサンプル';

  @override
  String get settingsAppearanceNewThemeButton => '新しいカスタムテーマ';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'マイテーマ';

  @override
  String get settingsAppearanceCustomThemesEmpty =>
      '現在のテーマをコピーして色を調整できます。カスタムテーマはこのデバイスに保存されます。';

  @override
  String get settingsAppearanceDeleteThemeTitle => 'テーマを削除しますか？';

  @override
  String settingsAppearanceDeleteThemeBody(String name) {
    return '「$name」は完全に削除されます。';
  }

  @override
  String settingsAppearanceCustomThemeSemantic(String name) {
    return 'カスタムテーマ $name';
  }

  @override
  String get settingsAppearanceThemeActionsTooltip => 'テーマのアクション';

  @override
  String get settingsDefaultsProgramHeader => 'プログラムのデフォルト設定';

  @override
  String get settingsDefaultsCallerLabel => 'デフォルトコーラー';

  @override
  String get settingsDefaultsPrefilledHelper =>
      '新しいプログラムに事前入力されます。プログラムごとに編集可能です。';

  @override
  String get settingsDefaultsBandLabel => 'デフォルトバンド';

  @override
  String get settingsDefaultsDisplayHeader => '表示のデフォルト設定';

  @override
  String get settingsDefaultsSortTitle => 'コレクションの並び順';

  @override
  String get settingsDefaultsSortSubtitle =>
      'コレクションを開いたときの並び順です。閲覧中でも並び順を変更できます。';

  @override
  String get settingsDefaultsCanonicalTitle => 'ダンスの詳細を正式な用語で表示する';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'オンにすると、アクティブなダイアレクトではなく正式なロール名とムーブ名でダンスが表示されます。ダンスを開いている間もビューを切り替えられます。';

  @override
  String get settingsDefaultsAuthoringHeader => 'ダンス作成のデフォルト設定';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'フリーテキスト入力';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'オンにすると、新しいフィギュアを追加する際に「neighbor balance & swing」のように1行で入力できます（フィールドごとに入力する代わりに）。入力した行はフィギュアに解析されます。認識されなかった部分はカスタムフィギュアとして保存され、後で修正できます。既存のフィギュアの編集は常にフルエディターを使用します。';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateTitle => 'フィギュアの拍数を積極的に再計算';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle =>
      'オンにすると、フィギュアのムーブやタイミングに影響するパラメータを変更した際に、拍数が即座に再計算されます — 手動で入力した拍数も上書きされます。オフ(既定)の場合、編集した拍数が自動的に変更されることはありません。';

  @override
  String get settingsDefaultsFigureShorthandsTitle => 'フィギュアのショートハンド';

  @override
  String get settingsDefaultsFigureShorthandsEmptySubtitle =>
      'フリーテキスト入力時に挿入できるフィギュアへの短縮トークンをマッピングします。';

  @override
  String settingsDefaultsFigureShorthandsCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のショートハンドが定義されています。',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsFormTitle => 'ダンス形式';

  @override
  String get settingsDefaultsFormSubtitle =>
      '新しいダンスのデフォルトのダンス形式です。ダンスごとに変更できます。';

  @override
  String get settingsDefaultsFormationTitle => 'フォーメーション';

  @override
  String get settingsDefaultsFormationSubtitle =>
      '新しいダンスのデフォルトのフォーメーションです。ダンスごとに変更できます。';

  @override
  String get settingsDefaultsProgressionTitle => 'プログレッション';

  @override
  String get settingsDefaultsProgressionSubtitle =>
      '新しいダンスのデフォルトのプログレッションです。ダンスごとに変更できます。';

  @override
  String get settingsDefaultsPhraseLabel => 'デフォルトのフレーズ構造';

  @override
  String get settingsDefaultsPhraseHelper =>
      '新しいダンスに事前設定されます。空白 = 標準の4×16（A1 A2 B1 B2）；それ以外は例: 6*8*2';

  @override
  String get settingsDefaultsStartingFiguresTitle => '開始フィギュア';

  @override
  String get settingsDefaultsStartingFiguresSubtitle =>
      '新しいダンスの開始フィギュアです。デフォルトは「静止」（8拍）です。空白の新しいダンスにする場合はクリアしてください。ダンスごとに編集可能です。';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'ムーブのデフォルト設定';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'ダンス入力時にムーブを挿入するときに適用される優先パラメーター値です。これらはムーブの組み込みデフォルトを上書きします。フィギュアのパラメーターは後から変更できます。設定されていないムーブとパラメーターは組み込みのデフォルトを使用します。';

  @override
  String get settingsDefaultsAddMoveButton => 'ムーブのデフォルトを追加';

  @override
  String get settingsDefaultsRemoveMoveTooltip => '削除';

  @override
  String get settingsDefaultsMoveGone => 'このムーブはタクソノミーに存在しなくなりました。';

  @override
  String get settingsDefaultsMoveNoParams => 'このムーブにはデフォルト設定できるパラメーターがありません。';

  @override
  String get settingsFormationColoursTitle => 'フォーメーションの色';

  @override
  String get settingsFormationColoursIntro =>
      'フォーメーションに独自の色を設定すると、ダンスカード、ダンス詳細、パフォームヘッダーのラベルをハイライト表示できます。カスタマイズしたフォーメーションのみハイライトされ、他のフォーメーションは通常どおりラベルが表示されます。フォーメーションは常にテキストでも表示されるため、色なしでも読み取れます。';

  @override
  String get settingsFormationColoursListHeader => 'フォーメーション';

  @override
  String get settingsFormationColoursCustom => 'カスタムカラー';

  @override
  String get settingsFormationColoursFamilyDefault => 'ファミリーデフォルト';

  @override
  String settingsFormationColoursResetTooltip(String label) {
    return '$labelをファミリーデフォルトにリセット';
  }

  @override
  String get settingsGeneralLibraryHeader => 'ライブラリ';

  @override
  String get settingsGeneralSortIgnoreArticlesTitle => '並び替え時に先頭の冠詞を無視する';

  @override
  String get settingsGeneralSortIgnoreArticlesSubtitle =>
      'オンにすると、ダンスリストは「the」「a」「an」などの先頭の冠詞を無視してタイトルをアルファベット順に並べます（例：「The Nice Combination」はNの項目に分類されます）。オフにすると文字通りのタイトルで並べ替えます。';

  @override
  String get settingsGeneralVenuesHeader => '会場';

  @override
  String get settingsGeneralVenueEntityModeTitle => '再利用可能な会場レコードを使用する';

  @override
  String get settingsGeneralVenueEntityModeSubtitle =>
      '会場を住所、連絡先、スケジュール付きの再利用可能なレコードにします。複数のプログラムで共有でき、一箇所で編集できます。オフにすると、プログラムの会場はシンプルなフリーテキストフィールドになります。切り替えはデータを失いません — 入力した会場とリンクされたレコードの両方が保持されます。';

  @override
  String get settingsGeneralManageVenuesTitle => '会場を管理';

  @override
  String get settingsGeneralManageVenuesSubtitle => '再利用可能な会場レコードを閲覧、編集、削除します。';

  @override
  String get settingsGeneralPerformanceHeader => 'パフォーマンス';

  @override
  String get settingsGeneralAutoSizePerformTitle => 'パフォームカードのサイズを自動調整';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      '各カードのサイズを調整して、ダンスまたはスロット全体がスクロールなしで画面に収まるようにします。A- / A+で自分でサイズを設定する場合はオフにしてください。';

  @override
  String get settingsGeneralCallingHistoryHeader => 'コーリング履歴';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      'コーリング履歴には「実施済み」マークが必要';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'オンにすると、ダンスのコーリング履歴には、そのダンスのスロットが「実施済み」とマークされたプログラムのみが表示されます。オフにすると、ダンスを含むプログラムがすぐに表示されます。';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'Track calling history for all callers';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'When off and a default caller is set, calling history and counts include only programs led by that caller. When on — or when no default caller is set — every program that contains the dance is tracked.';

  @override
  String get settingsGeneralAccessibilityHeader => 'アクセシビリティ';

  @override
  String get settingsGeneralReduceMotionTitle => 'モーションを低減';

  @override
  String get settingsGeneralReduceMotionSubtitle =>
      '検索結果やフィギュア間を移動する際のアニメーションスクロールなど、不要なアニメーションを抑制またはスキップします。';

  @override
  String get settingsGeneralVerboseFiguresTitle => '詳細なフィギュアテキストを常に表示';

  @override
  String get settingsGeneralVerboseFiguresSubtitle =>
      'ダンスビューで、スクリーンリーダーだけでなく画面上にも完全な発話スタイルのフィギュア文を表示します。簡潔な記法にするにはオフにしてください。';

  @override
  String get settingsGeneralDecimalTurnsTitle => 'ターンを小数で表示';

  @override
  String get settingsGeneralDecimalTurnsSubtitle =>
      'ターンと回転量を分数（¾）の代わりに小数（0.75）で表示します。スクリーンリーダーの読み上げには影響しません。';

  @override
  String get settingsGeneralConfirmBeforeDeleteTitle => '削除前に確認する';

  @override
  String get settingsGeneralConfirmBeforeDeleteSubtitle =>
      'ダンスやプログラムを削除する前に確認を求めます。削除は元に戻せます。これはその前に明示的な確認を追加するだけです。';

  @override
  String get settingsGeneralDeletedItemsHeader => '削除済みアイテム';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle => '削除したダンスを保持する期間';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      '削除したダンスは指定した期間保持され、アプリ起動時に完全に削除されます。「削除しない」を選択すると手動で削除するまで保持されます。';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days日間';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => '削除しない';

  @override
  String get settingsGeneralImportHeader => 'インポート';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Caller\'s Compendium JSONファイルからダンスをコレクションに取り込みます。追加前にすべてのダンスを確認して承認することができます。';

  @override
  String get settingsGeneralImportEllipsisAction => 'インポート…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle => 'カスタムフィギュアを再確認';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'インポート時に認識できなかったためカスタムとして保持されたフィギュアを持つインポートされたダンスを再解析します。解析が改善されるとフィギュアがその場でアップグレードされます — タグ、評価、ノートは保持されます。変更前にプレビューして確認できます。';

  @override
  String get settingsGeneralReparseCustomFiguresAction => '再確認…';

  @override
  String get settingsGeneralBackupRestoreHeader => 'バックアップと復元';

  @override
  String get backupExported => 'バックアップをエクスポートしました。';

  @override
  String get backupExportFailed => 'バックアップをエクスポートできませんでした。';

  @override
  String get backupRestoreIntegrityFailed =>
      'このバックアップは整合性チェックに失敗しました。破損しているか、エクスポート後に変更された可能性があります。復元はキャンセルされ、データは変更されていません。';

  @override
  String get backupRestoreIncompatibleVersion =>
      'このバックアップにはこのバージョンのアプリで読めないアイテムが含まれています（新しいバージョンのものかもしれません）。復元はキャンセルされました。データは変更されていません。';

  @override
  String get backupRestoreInvalidFile =>
      '復元できません：有効なバックアップファイルではありません。データは変更されていません。';

  @override
  String backupRestoreSkippedProblems(int count) {
    return 'バックアップを復元しました（$count件の問題をスキップ）。';
  }

  @override
  String get backupRestored => 'バックアップを復元しました。';

  @override
  String get backupRestoreFailed => 'バックアップを復元できませんでした。';

  @override
  String get backupRestoreSettingsFailed =>
      'Your dances and programs were restored, but applying your saved settings failed. Your restored content is safe — you can retry applying settings.';

  @override
  String get backupRestoreSettingsRetryAction => 'Retry settings';

  @override
  String get backupRestoreSettingsRetried => 'Settings applied.';

  @override
  String get backupExportTitle => 'バックアップをエクスポート';

  @override
  String get backupExportSubtitle =>
      'コレクション、プログラム、カスタムフィールド、ダイアレクト、テーマ、設定をすべてJSON形式の1つのファイルに保存します。安全に保管したり、別のデバイスに移動したりできます。';

  @override
  String get backupExportAction => 'エクスポート';

  @override
  String get backupRestoreTitle => 'バックアップから復元';

  @override
  String get backupRestoreSubtitle =>
      'アプリの現在の内容をすべてバックアップファイルの内容に置き換えます。この操作は元に戻せません。';

  @override
  String get backupRestoreAction => '復元';

  @override
  String get backupReminderTitle => 'バックアップのリマインダー';

  @override
  String get backupLastBackupNever => '前回のバックアップ: なし';

  @override
  String backupLastBackupDate(String date) {
    return '前回のバックアップ: $date';
  }

  @override
  String get backupReminderOff => 'オフ';

  @override
  String get backupReminderWeekly => '毎週';

  @override
  String get backupReminderMonthly => '毎月';

  @override
  String get backupOverdueHint =>
      '前回のバックアップから時間が経っています — 今すぐエクスポートすることを検討してください。';

  @override
  String get backupRestoreDialogBody =>
      '復元すると、アプリの現在の内容（コレクション、プログラム、ダイアレクト、テーマ、設定）がすべてバックアップの内容に置き換えられます。この操作は元に戻せません。';

  @override
  String get backupChooseFileAction => 'ファイルを選択…';

  @override
  String get backupPasteJsonLabel => 'またはバックアップJSONを貼り付け';

  @override
  String get backupReplaceAllDataAction => 'すべてのデータを置き換え';

  @override
  String get diagnosticsNoDiagnosticsToExport => 'エクスポートできる診断情報がありません。';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      '安全（スクラブ済み）エクスポートを準備できなかったため、何も保存されませんでした。もう一度お試しいただくか、意図的に詳細情報を含めてご利用ください。';

  @override
  String get diagnosticsLogExported => '診断ログをエクスポートしました。';

  @override
  String get diagnosticsExportCancelled => 'エクスポートをキャンセルしました。';

  @override
  String get diagnosticsExportFailed => '診断ログをエクスポートできませんでした。';

  @override
  String get diagnosticsClearLogTitle => '診断ログを削除しますか？';

  @override
  String get diagnosticsClearLogBody =>
      'このデバイスのローカルクラッシュログを完全に削除します。この操作は元に戻せません。';

  @override
  String get diagnosticsClearAction => '削除';

  @override
  String get diagnosticsLogCleared => '診断ログを削除しました。';

  @override
  String get diagnosticsHeader => '診断';

  @override
  String get diagnosticsIntro =>
      '問題が発生したとき、アプリは診断に役立てるため技術的なメモをこのデバイスのローカルログに記録します。外部には一切送信されません — テレメトリーは行いません。バグレポートに添付するためにエクスポートするか、いつでも削除できます。';

  @override
  String get diagnosticsRecentEntriesHeader => '最近のエントリー';

  @override
  String get diagnosticsReadFailedTitle => '診断ログを読み取れませんでした';

  @override
  String get diagnosticsReadFailedSubtitle =>
      'このデバイスでローカルログにアクセスできない可能性があります。エクスポートまたは削除は試みることができます。';

  @override
  String get diagnosticsEmptyTitle => 'エラーは記録されていません';

  @override
  String get diagnosticsEmptySubtitle => 'このデバイスでは何もキャプチャされていません。';

  @override
  String get diagnosticsExportHeader => 'エクスポート';

  @override
  String get diagnosticsFullDetailTitle => '詳細情報を含める（コンテンツが含まれる場合があります）';

  @override
  String get diagnosticsFullDetailSubtitle =>
      'デフォルトはオフです。オフの場合、エクスポート時にコンテンツ、ファイルパス、メールアドレス、電話番号が削除されます。';

  @override
  String get diagnosticsExportShareLogTitle => 'ログをエクスポート／共有';

  @override
  String get diagnosticsExportShareFullSubtitle => '完全な非編集済みログを共有します。';

  @override
  String get diagnosticsExportShareScrubbedSubtitle =>
      'バグレポートに安全に添付できるスクラブ済みのコピーを共有します。';

  @override
  String get diagnosticsClearLogRowTitle => 'ログを削除';

  @override
  String get diagnosticsClearLogRowSubtitle => 'このデバイスからローカルクラッシュログを削除します。';

  @override
  String get crashFallbackTitle => 'ここで問題が発生しました';

  @override
  String get crashFallbackBody =>
      'アプリのこの部分で予期しないエラーが発生し、復旧しました。詳細はデバイスを離れないローカル診断ログ（設定 ▸ 診断）に保存されました。';

  @override
  String get crashFallbackCopied => 'コピーしました';

  @override
  String get crashFallbackCopyDetails => '詳細をコピー';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonUndo => '元に戻す';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonDelete => '削除';

  @override
  String get commonDuplicate => '複製';

  @override
  String commonDuplicateTitleSuffix(String title) {
    return '$title（コピー）';
  }

  @override
  String get commonYes => 'はい';

  @override
  String get commonNo => 'いいえ';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => '適用';

  @override
  String get commonCouldntOpenLink => 'リンクを開けませんでした';

  @override
  String get commonProgression => 'プログレッション';

  @override
  String get commonDanceFormContra => 'コントラ';

  @override
  String get commonDanceFormEcd => 'イングリッシュ (ECD)';

  @override
  String get commonDanceFormSquare => 'スクエア';

  @override
  String get commonProgressionNone => 'プログレッションなし';

  @override
  String get commonProgressionSingle => 'シングル';

  @override
  String get commonProgressionDouble => 'ダブル';

  @override
  String get commonProgressionTriple => 'トリプル';

  @override
  String get commonProgressionQuadruple => 'クアドラプル';

  @override
  String get commonProgressionOther => 'その他';

  @override
  String get commonDanceStatusActive => 'アクティブ';

  @override
  String get commonDanceStatusDeprecated => '非推奨';

  @override
  String get commonDanceStatusBroken => '破損';

  @override
  String get commonDanceLevelBeginner => 'ビギナー';

  @override
  String get commonDanceLevelIntermediate => 'インターミディエイト';

  @override
  String get commonDanceLevelAdvanced => 'アドバンスド';

  @override
  String get commonFormationDupleImproper => 'デュープルインプロパー';

  @override
  String get commonFormationBecketCw => 'Becket（CW）';

  @override
  String get commonFormationBecketCcw => 'Becket（CCW）';

  @override
  String get commonFormationDupleProper => 'デュープルプロパー';

  @override
  String get commonFormationDupleIndecent => 'デュープルインディーセント';

  @override
  String get commonFormationTripleMinor => 'トリプルマイナー';

  @override
  String get commonFormationThreeFaceThree => 'スリーフェイススリー';

  @override
  String get commonFormationFourFaceFour => 'フォーフェイスフォー';

  @override
  String get commonFormationCircleMixer => 'サークルミキサー';

  @override
  String get commonFormationSicilianCircle => 'Sicilianサークル';

  @override
  String get commonFormationScatterMixer => 'スキャッターミキサー';

  @override
  String get commonFormationLongways => 'ロングウェイ';

  @override
  String get commonFormationTriplet => 'トリプレット';

  @override
  String get commonFormationGrid => 'グリッド';

  @override
  String get commonFormationOther => 'その他';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonMixedLevel => 'ミックスレベル';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'タグ「$tagName」のダンスを表示';
  }

  @override
  String commonDeletedSnack(String title) {
    return '「$title」を削除しました。';
  }

  @override
  String get importGapMessage => 'このコールを解析できませんでした — カスタムフィギュアとして保持されました。';

  @override
  String get importGapDialogTitle => '認識できないフィギュア';

  @override
  String get importGapSemanticLabel =>
      '認識できないフィギュア。このコールを解析できませんでした — カスタムフィギュアとして保持されました。';

  @override
  String get collectionScreenTitle => 'コレクション';

  @override
  String get collectionNewDance => '新しいダンス';

  @override
  String get collectionSearchTooltip => '検索 (Ctrl/Cmd-K)';

  @override
  String get collectionSelectDancesTooltip => 'ダンスを選択';

  @override
  String get collectionManageCustomFieldsTooltip => 'カスタムフィールドを管理';

  @override
  String get collectionRecentlyDeletedTooltip => '最近削除したアイテム';

  @override
  String collectionSortByTooltip(String sortLabel) {
    return '並び順 ($sortLabel)';
  }

  @override
  String get collectionSortRelevance => '最も一致';

  @override
  String get collectionSortTitle => 'タイトル';

  @override
  String get collectionSortAuthor => '作者';

  @override
  String get collectionSortRecentlyAdded => '最近追加';

  @override
  String get collectionSortLastCalled => '最後に使用';

  @override
  String get collectionSortAscendingTooltip => '昇順（タップで降順）';

  @override
  String get collectionSortDescendingTooltip => '降順（タップで昇順）';

  @override
  String get collectionGroupByCategoryTooltip => 'カテゴリでグループ化';

  @override
  String collectionGroupByCategoryActiveTooltip(String tag) {
    return '$tagでグループ化';
  }

  @override
  String get collectionGroupByNone => 'グループ化なし';

  @override
  String get collectionGroupByHeader => 'カテゴリ';

  @override
  String get collectionGroupOther => 'その他';

  @override
  String collectionGroupSectionSemantics(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
    );
    return '$label、$_temp0';
  }

  @override
  String get collectionExitSelectionTooltip => '選択を終了';

  @override
  String collectionSelectedCount(int count) {
    return '$count件選択中';
  }

  @override
  String get collectionAddTags => 'タグを追加';

  @override
  String get collectionRemoveTags => 'タグを削除';

  @override
  String get collectionSetLevel => 'レベルを設定';

  @override
  String get collectionSearchFieldLabel => 'ダンスを検索';

  @override
  String get collectionSearchFieldHint => 'タイトル、作者、フィギュア、ノートを検索…';

  @override
  String get collectionClearSearchTooltip => '検索とフィルターをクリア';

  @override
  String get collectionLoadError => 'コレクションを読み込めませんでした。';

  @override
  String collectionDuplicatedSnack(String title) {
    return '「$title」として複製しました。';
  }

  @override
  String get collectionEmpty =>
      'コレクションは空です。ダンスを追加またはインポートして始めましょう — または上のオンライン検索をオンにしてオンラインソースからインポートしてください。';

  @override
  String get collectionFiltersTitle => 'フィルター';

  @override
  String collectionFiltersActive(int count) {
    return 'フィルター（$count件有効）';
  }

  @override
  String get collectionByPhraseTitle => 'フレーズで絞り込み';

  @override
  String collectionByPhraseActive(int count) {
    return 'フレーズで絞り込み（$count件有効）';
  }

  @override
  String get collectionAdvancedTitle => '詳細検索';

  @override
  String get collectionUseAdvancedQuery => '詳細クエリを使用';

  @override
  String get collectionUseAdvancedQuerySubtitle =>
      'フィギュアとシーケンスをすべて/いずれか/なしのグループで組み合わせます。';

  @override
  String collectionDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
    );
    return '$_temp0';
  }

  @override
  String get collectionSearchError => '検索の実行中に問題が発生しました。';

  @override
  String get collectionNoResults => '検索に一致するダンスがありません。';

  @override
  String get collectionBatchNoChanges => '変更なし';

  @override
  String collectionBatchTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスにタグを付けました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスからタグを削除しました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスのレベルを設定しました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスのレベルをクリアしました',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchMore => 'その他のバッチアクション';

  @override
  String get collectionSetRating => '評価を設定';

  @override
  String get collectionAddTunes => 'チューンを追加';

  @override
  String get collectionClearTunes => 'チューンをクリア';

  @override
  String get collectionEditCustomField => 'カスタムフィールドを編集';

  @override
  String collectionBatchRatingSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスの評価を設定しました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchRatingCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスの評価をクリアしました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスにチューンを追加しました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスからチューンをクリアしました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスのフィールドを更新しました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスのフィールドをクリアしました',
    );
    return '$_temp0';
  }

  @override
  String collectionSelectDanceLabel(String title) {
    return '$titleを選択';
  }

  @override
  String collectionCalledBadge(int count) {
    return '使用: ×$count';
  }

  @override
  String collectionCalledBadgeSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count回使用',
    );
    return '$_temp0';
  }

  @override
  String collectionRatingSemantic(int rating) {
    return '評価: $rating/5';
  }

  @override
  String collectionRowActionsSemantic(String title) {
    return '「$title」のアクション';
  }

  @override
  String get collectionSplitEmptyTitle => 'ダンスを選択してください';

  @override
  String get collectionSplitEmptySubtitle => 'リストからダンスを選択して詳細を表示してください。';

  @override
  String get collectionFacetType => 'タイプ';

  @override
  String get collectionFacetFormation => 'フォーメーション';

  @override
  String get collectionFacetStatus => 'ステータス';

  @override
  String get collectionFacetLevel => 'レベル';

  @override
  String get collectionFacetMinRating => '最低評価';

  @override
  String collectionFacetMinRatingChip(int min) {
    return '≥$min★';
  }

  @override
  String get collectionFacetTags => 'タグ';

  @override
  String get collectionFacetSource => 'ソース';

  @override
  String get collectionFacetAuthor => '作者';

  @override
  String get collectionFacetNone => 'このコレクションにはまだ利用可能なフィルターがありません。';

  @override
  String get collectionFacetClear => 'フィルターをクリア';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return '$nameを削除';
  }

  @override
  String get collectionFacetAuthorSearchHint => '作者を検索…';

  @override
  String get collectionFacetOpContains => 'を含む';

  @override
  String get collectionFacetOpEquals => 'と等しい';

  @override
  String collectionFacetTextHint(String label) {
    return '$labelでフィルター…';
  }

  @override
  String get collectionFacetNumOpEq => '=';

  @override
  String get collectionFacetNumOpLt => '<';

  @override
  String get collectionFacetNumOpGt => '>';

  @override
  String get collectionFacetNumOpBetween => 'の間';

  @override
  String get collectionFacetNumFrom => 'から';

  @override
  String get collectionFacetNumValue => '値';

  @override
  String get collectionFacetNumTo => 'まで';

  @override
  String get collectionByPhraseOrdinalFirst => '最初のフレーズ';

  @override
  String get collectionByPhraseOrdinalSecond => '2番目のフレーズ';

  @override
  String get collectionByPhraseOrdinalThird => '3番目のフレーズ';

  @override
  String get collectionByPhraseOrdinalFourth => '4番目のフレーズ';

  @override
  String collectionByPhraseOrdinalN(int number) {
    return 'フレーズ$number';
  }

  @override
  String collectionByPhraseCaption(String ordinal, String label) {
    return '$ordinal（通常 $label）';
  }

  @override
  String collectionByPhraseFieldMatch(String caption) {
    return '$caption、フィギュアが一致';
  }

  @override
  String collectionByPhraseFieldExclude(String caption) {
    return '$caption、一致しない';
  }

  @override
  String collectionByPhraseRemoveMove(String move, String field) {
    return '$fieldから$moveを削除';
  }

  @override
  String get collectionQueryMatchLabel => '一致';

  @override
  String get collectionQueryGroupAll => 'すべてに一致';

  @override
  String get collectionQueryGroupAny => 'いずれかに一致';

  @override
  String get collectionQueryGroupNone => 'どれにも一致しない';

  @override
  String get collectionQueryTheseConditions => 'これらの条件';

  @override
  String get collectionQueryRemoveGroup => 'グループを削除';

  @override
  String get collectionQueryEmptyGroup => '条件がまだありません — 下から追加してください。';

  @override
  String get collectionQueryAddCondition => '条件を追加';

  @override
  String get collectionQueryHasFigure => 'フィギュアを含む';

  @override
  String get collectionQuerySequenceThen => 'シーケンス（次に）';

  @override
  String get collectionQueryConditionGroup => '条件グループ';

  @override
  String get collectionQueryAddButton => '追加';

  @override
  String get collectionQueryRemoveFigure => 'フィギュアを削除';

  @override
  String get collectionQueryThenFirst => '最初';

  @override
  String get collectionQueryThenConnector => '次に';

  @override
  String get collectionQueryThenLater => '後で';

  @override
  String get collectionQueryRemoveSequence => 'シーケンスを削除';

  @override
  String get collectionQueryGroupFigures => 'フィギュアをグループ化';

  @override
  String get collectionQueryFigureGroupMatch => 'フィギュアグループの一致';

  @override
  String get collectionQueryOfTheseFigures => 'これらのフィギュアの';

  @override
  String get collectionQuerySingleFigure => '単一のフィギュア';

  @override
  String get collectionQueryAddFigure => 'フィギュアを追加';

  @override
  String get collectionQueryRemoveFigureGroup => 'フィギュアグループを削除';

  @override
  String get collectionQueryMoveLabel => 'ムーブ';

  @override
  String get collectionQueryMoveHint => '例: スイング';

  @override
  String get collectionQuerySectionLabel => 'セクション';

  @override
  String get collectionQueryAnySection => '任意のセクション';

  @override
  String collectionQueryAnyParam(String param) {
    return '任意の$param';
  }

  @override
  String get collectionBatchLevelUnspecified => '未指定（クリア）';

  @override
  String get collectionBatchLevelConfirm => '設定';

  @override
  String get collectionBatchTagEmptyAdd => 'タグがまだありません。下から作成してください。';

  @override
  String get collectionBatchTagEmptyRemove => '選択したダンスには削除できるタグがありません。';

  @override
  String get collectionCreateTagLabel => 'タグを作成';

  @override
  String get collectionCreateTagButton => 'タグを作成';

  @override
  String get collectionCreateTagError => 'タグを作成できませんでした。もう一度お試しください。';

  @override
  String get collectionBatchTagAddConfirm => '追加';

  @override
  String get collectionBatchTagRemoveConfirm => '削除';

  @override
  String collectionBatchRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countつ星',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchRatingUnrated => '評価なし（クリア）';

  @override
  String get collectionBatchRatingConfirm => '設定';

  @override
  String get collectionBatchTunesFieldLabel => 'チューンを追加';

  @override
  String get collectionBatchTunesAddButton => 'チューンをリストに追加';

  @override
  String get collectionBatchTunesEmpty => 'チューン名を入力してリストに追加してください。';

  @override
  String collectionBatchTunesRemove(String tune) {
    return 'リストから$tuneを削除';
  }

  @override
  String get collectionBatchTunesConfirm => '追加';

  @override
  String get collectionBatchClearTunesConfirmTitle => 'チューンをクリアしますか？';

  @override
  String get collectionBatchClearTunesConfirmBody =>
      '選択したダンスからすべてのチューンを削除します。後で元に戻せます。';

  @override
  String get collectionBatchClearTunesConfirmButton => 'チューンをクリア';

  @override
  String get collectionBatchCustomFieldKeyLabel => 'フィールド';

  @override
  String get collectionBatchCustomFieldClearOption => 'このフィールドをクリア';

  @override
  String get collectionBatchCustomFieldEmpty => 'カスタムフィールドがまだ定義されていません。';

  @override
  String get collectionBatchCustomFieldNumberInvalid => '数値を入力してください';

  @override
  String get collectionBatchCustomFieldConfirm => '適用';

  @override
  String get danceFiguresEmpty => 'フィギュアがまだありません。';

  @override
  String danceFigureBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
    );
    return '$_temp0';
  }

  @override
  String get danceFigureProgressionSemantic => 'プログレッション';

  @override
  String danceFigureNote(String note) {
    return 'ノート: $note';
  }

  @override
  String get danceScreenTitle => 'ダンス';

  @override
  String get danceNotFound => 'ダンスが見つかりませんでした。';

  @override
  String get danceEditFab => '編集';

  @override
  String get danceDuplicateTooltip => 'ダンスを複製';

  @override
  String get danceDeleteTooltip => 'ダンスを削除';

  @override
  String get danceMoreActions => 'その他のアクション';

  @override
  String get danceSectionFigures => 'フィギュア';

  @override
  String get danceSectionCallingNotes => 'コーリングノート';

  @override
  String get danceSectionWalkthrough => 'ウォークスルー';

  @override
  String get danceSectionTunes => 'チューン';

  @override
  String get danceSectionLinks => 'リンク';

  @override
  String get danceMissingRelated => '（ダンスが見つかりません）';

  @override
  String get danceSectionPublishedSources => '公開ソース';

  @override
  String get danceSectionCustomFields => 'カスタムフィールド';

  @override
  String get danceSectionCallingHistory => 'コーリング履歴';

  @override
  String get danceCallingHistoryEmpty => 'まだプログラムに含まれていません。';

  @override
  String get danceShowCanonicalTerms => '正式な用語で表示';

  @override
  String get danceCanonicalToggleLabel => '正式用語';

  @override
  String danceProvenanceVia(String source) {
    return '$source経由';
  }

  @override
  String get danceProvenanceSourceManual => '手動入力';

  @override
  String get danceProvenanceSourceJson => 'JSONインポート';

  @override
  String get danceLinkKindVideo => '動画';

  @override
  String get danceLinkKindSource => 'ソースリンク';

  @override
  String get danceLinkKindLink => 'リンク';

  @override
  String danceOpenLinkSemantic(String kind, String display) {
    return '$kindを開く: $display';
  }

  @override
  String danceOpenProgramSemantic(String title, String details) {
    return 'プログラムを開く: $title、$details';
  }

  @override
  String danceHalfStatsFirstHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '前半に$count回使用',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSecondHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '後半に$count回',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '前半を$count回開始',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'イベントのクローズ（後半最後のダンス）を$count回担当',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSemanticLabel(String description) {
    return '前後半の内訳: $description';
  }

  @override
  String get danceSourceUnknown => '（不明なソース）';

  @override
  String danceSourcePage(String page) {
    return 'p. $page';
  }

  @override
  String danceSourceNumber(String number) {
    return 'no. $number';
  }

  @override
  String danceOpenSourceLinkSemantic(String title) {
    return 'ソースリンクを開く: $title';
  }

  @override
  String danceSourceSemanticPrefix(String title) {
    return 'ソース: $title';
  }

  @override
  String danceOpenDanceCrossRefSemantic(String title) {
    return 'ダンスを開く: $title';
  }

  @override
  String get commonAddToProgram => 'プログラムに追加';

  @override
  String get programsEmptyTitle => 'プログラムがまだありません';

  @override
  String get programsAddToProgramEmptyBody => 'セットリストを作成するにはプログラムを作成してください。';

  @override
  String get programsCreateWithDance => 'このダンスで新しいプログラムを作成';

  @override
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  ) {
    return '「$danceTitle」を$programTitle（$details）に追加';
  }

  @override
  String programsAddedToProgramSnack(String danceTitle, String programTitle) {
    return '「$danceTitle」を$programTitleに追加しました。';
  }

  @override
  String get programsNewProgram => '新しいプログラム';

  @override
  String programsCreatedProgramSnack(String programTitle, String danceTitle) {
    return '「$danceTitle」で「$programTitle」を作成しました。';
  }

  @override
  String get dancePerformTooltip => 'このダンスをパフォーム';

  @override
  String get commonSwitchDialectTooltip => 'ダイアレクトを切り替え';

  @override
  String get programsStatusDraft => '下書き';

  @override
  String get programsStatusFinalized => '確定';

  @override
  String get programsStatusPerformed => '実施済み';

  @override
  String get programsNoLongerExists => 'このプログラムはもう存在しません。';

  @override
  String get programsFallbackTitle => 'プログラム';

  @override
  String get programsUntitledDanceFallback => 'ダンス';

  @override
  String programsAddedDanceSnack(String title) {
    return '「$title」を追加しました。';
  }

  @override
  String programsAddedDanceAnnounce(String title) {
    return '$titleをプログラムに追加しました。';
  }

  @override
  String get programsAddedNoteAnnounce => 'ノートをプログラムに追加しました。';

  @override
  String get programsAddedBreakAnnounce => 'ブレイクをプログラムに追加しました。';

  @override
  String get programsMarkedAllPerformed => 'すべてのダンスを実施済みにしました。';

  @override
  String programsSavedSnack(String title) {
    return '「$title」を保存しました。';
  }

  @override
  String get programsSaveError => 'プログラムを保存できませんでした。';

  @override
  String programsDuplicatedSnack(String title) {
    return '「$title」として複製しました。';
  }

  @override
  String programsDeletedSnack(String title) {
    return '「$title」を削除しました。';
  }

  @override
  String get programsDiscardTitle => '変更を破棄しますか？';

  @override
  String get programsDiscardBody => 'このプログラムに未保存の変更があります。';

  @override
  String get programsKeepEditing => '編集を続ける';

  @override
  String get programsDiscard => '破棄';

  @override
  String get programsDraftTitle => '未保存の下書き';

  @override
  String get programsDraftBody => 'このプログラムに未保存の下書きがあります。復元しますか？';

  @override
  String get programsDraftRestore => '復元';

  @override
  String get programsDraftDiscard => '破棄';

  @override
  String get programsBuildProgram => 'プログラムを作成';

  @override
  String get programsBuildTab => '作成';

  @override
  String get programsMatrixTab => 'マトリックス';

  @override
  String get programsPerformTooltip => 'このプログラムをパフォーム';

  @override
  String get programsMarkAllPerformedTooltip => 'すべて実施済みにする';

  @override
  String get programsSaveDirty => '保存 *';

  @override
  String get commonSave => '保存';

  @override
  String get programsLoading => 'プログラムを読み込み中';

  @override
  String get programsLoadError => 'プログラムを読み込めませんでした。';

  @override
  String get programsDeletedDanceFallback => '（削除済みダンス）';

  @override
  String get programsSlotsLabel => 'スロット';

  @override
  String get programsAddDanceButton => 'ダンスを追加';

  @override
  String get programsAddNoteBreakButton => 'ノート／ブレイクを追加';

  @override
  String get programsInsertBreakButton => 'ブレイクを挿入';

  @override
  String get programsAddADanceSheetTitle => 'ダンスを追加';

  @override
  String get commonClose => '閉じる';

  @override
  String get programsNoDateSet => '日付未設定';

  @override
  String get programsTitleLabel => 'タイトル';

  @override
  String get programsTitleHint => '例: 金曜夜のコントラ';

  @override
  String get programsTitleRequired => 'タイトルが必要です。';

  @override
  String get programsEventDateLabel => 'イベント日';

  @override
  String get programsSetDate => '日付を設定';

  @override
  String get programsChangeDate => '変更';

  @override
  String get programsClearEventDate => 'イベント日をクリア';

  @override
  String get programsVenueLabel => '会場';

  @override
  String get programsVenueHint => '例: グレンジホール';

  @override
  String programsVenueLinkedHint(String venueName) {
    return '保存済み会場「$venueName」にもリンクされています。設定で再利用可能な会場をオンにすると表示・変更できます。';
  }

  @override
  String get programsVenueLinkedHintFallbackName => '保存済み会場';

  @override
  String programsVenueLegacyTextHint(String venueText) {
    return '以前に入力した会場: 「$venueText」。再利用可能な詳細を使用するには、下から保存済みの会場をリンクしてください — 入力した会場は保持されます。';
  }

  @override
  String get programsBandLabel => 'バンド';

  @override
  String get programsBandHint => '例: The Fiddleheads';

  @override
  String get programsCallerLabel => 'コーラー';

  @override
  String get programsCallerHint => 'イベントのメインコーラー';

  @override
  String get programsDancerLevelLabel => 'ダンサーレベル';

  @override
  String get programsDancerLevelHint => '例: どなたでも、経験者向け';

  @override
  String get programsNotesLabel => 'ノート';

  @override
  String get programsStatusFieldLabel => 'ステータス';

  @override
  String get programsHideAlternatesTitle => 'セットリストで代替を非表示';

  @override
  String get programsHideAlternatesSubtitle =>
      '概要、PDF、エクスポートされたセットリストからALTスロットを省略します。ビルダーにはすべてのスロットが表示されます。';

  @override
  String programsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の警告',
    );
    return '$_temp0';
  }

  @override
  String get programsAddNoteBreakDialogTitle => 'ノートまたはブレイクを追加';

  @override
  String get programsFreeTextLabel => 'テキスト';

  @override
  String get programsFreeTextHint => '例: ブレイク、ワルツ、アナウンス';

  @override
  String get commonAdd => '追加';

  @override
  String get programsTitle => 'プログラム';

  @override
  String get programsSortTitle => 'タイトル';

  @override
  String get programsSortRecentlyUpdated => '最近更新';

  @override
  String get programsSortEventDate => 'イベント日';

  @override
  String programsSortByTooltip(String label) {
    return '並び順 ($label)';
  }

  @override
  String get programsListLoadError => 'プログラムを読み込めませんでした。';

  @override
  String get programsListEmptyBody =>
      'ここでイベントのセットリストを作成します。最初のプログラムを作成して始めましょう。';

  @override
  String programsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプログラム',
    );
    return '$_temp0';
  }

  @override
  String get programsSummaryTitle => 'プログラム';

  @override
  String get programsEditProgram => 'プログラムを編集';

  @override
  String get programsSummaryUnavailable => 'このプログラムはもう利用できません。';

  @override
  String get programsPerformDisabledTooltip =>
      'このプログラムをパフォームするには少なくとも1つのスロットを追加してください';

  @override
  String programsSummaryBand(String band) {
    return 'バンド: $band';
  }

  @override
  String programsSummaryCaller(String caller) {
    return 'コーラー: $caller';
  }

  @override
  String programsSummaryLevel(String level) {
    return 'レベル: $level';
  }

  @override
  String programsSetListHeader(int count) {
    return 'セットリスト ($count)';
  }

  @override
  String get programsSummaryEmptySetList =>
      'スロットがまだありません — ビルダーを開いてダンスを追加してください。';

  @override
  String programsSummaryGuest(String caller) {
    return 'ゲスト: $caller';
  }

  @override
  String programsPlannedMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get programsAltBadge => 'Alt';

  @override
  String get programsDanceUnavailable => 'ダンスを利用できません';

  @override
  String programsSummaryNote(String note) {
    return 'ノート: $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return '代替: $title';
  }

  @override
  String get programsPerformed => '実施済み';

  @override
  String programsSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countスロット',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'ノート';

  @override
  String get programsSlotEditorEmpty => 'スロットがまだありません。ダンスまたはノートを追加して始めましょう。';

  @override
  String get programsSlotMoved => 'スロットを移動しました。';

  @override
  String get programsSlotMovedUp => 'スロットを上に移動しました。';

  @override
  String get programsSlotMovedDown => 'スロットを下に移動しました。';

  @override
  String programsSlotCutBanner(String name) {
    return '「$name」をカットしました — ペーストして配置してください。';
  }

  @override
  String get programsPasteBeforeFirst => '最初のスロットの前にペースト';

  @override
  String programsPasteAfter(String title) {
    return '$titleの後にペースト';
  }

  @override
  String get programsPasteHere => 'ここにペースト';

  @override
  String get programsMarkedPrimary => 'メインとしてマークしました。';

  @override
  String get programsMarkedAlternate => '代替としてマークしました。';

  @override
  String get programsMarkedPerformed => '実施済みとしてマークしました。';

  @override
  String get programsPerformedCleared => '実施済みマークをクリアしました。';

  @override
  String programsRemovedSlot(String name) {
    return '「$name」を削除しました。';
  }

  @override
  String get programsAltOrdinal => 'ALT';

  @override
  String programsDragToReorder(String title) {
    return '$titleをドラッグして並べ替え';
  }

  @override
  String programsMoveSlotUp(String title) {
    return '$titleを上に移動';
  }

  @override
  String programsMoveSlotDown(String title) {
    return '$titleを下に移動';
  }

  @override
  String programsCutSlot(String title) {
    return '$titleをカット';
  }

  @override
  String programsMoreActionsForSlot(String title) {
    return '$titleのその他のアクション';
  }

  @override
  String get programsEditSlotMenu => 'スロットを編集';

  @override
  String get programsMakePrimaryMenu => 'メインにする';

  @override
  String get programsMarkAlternateMenu => '代替としてマーク';

  @override
  String get programsClearPerformedMenu => '実施済みをクリア';

  @override
  String get programsMarkPerformedMenu => '実施済みとしてマーク';

  @override
  String get programsRemoveSlotMenu => 'スロットを削除';

  @override
  String get programsSlotTextRequiredError => 'このスロットのテキストを入力してください。';

  @override
  String get programsWholeNumberError => '0以上の整数を入力してください。';

  @override
  String get programsEditDanceSlotTitle => 'ダンススロットを編集';

  @override
  String get programsEditNoteTitle => 'ノートを編集';

  @override
  String get programsCallerNoteLabel => 'コーラーノート（任意）';

  @override
  String get programsCallerNoteHint => '例: まずヘイを教える';

  @override
  String get programsGuestCallerLabel => 'ゲストコーラー（任意）';

  @override
  String get programsPlannedMinutesLabel => '予定時間（分、任意）';

  @override
  String get programsAlternateDanceTitle => '代替ダンス';

  @override
  String get programsAlternateDanceSubtitle => 'その上のスロットの下にインデントして表示されます。';

  @override
  String get commonDone => '完了';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    String _temp0 = intl.Intl.pluralLogic(
      moveCount,
      locale: localeName,
      other: '$moveCount件のムーブ',
    );
    return 'プログラミングマトリックス: $danceCount件のダンス × $_temp0';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフリーテキストスロット（ブレイク、ノート）が省略されています — マトリックスはダンスのみ表示。',
    );
    return '$_temp0';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'ムーブ: $label';
  }

  @override
  String programsMatrixHideColumnSemantic(String label) {
    return '$label列を非表示にする';
  }

  @override
  String get programsMatrixShowAllColumnsSemantic => 'すべての列を表示';

  @override
  String programsMatrixRowHeaderSemantic(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '代替ダンス: $title、前半',
      'second': '代替ダンス: $title、後半',
      'other': '代替ダンス: $title',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': 'ダンス: $title、前半',
      'second': 'ダンス: $title、後半',
      'other': 'ダンス: $title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixHalfShort(String half) {
    String _temp0 = intl.Intl.selectLogic(half, {'first': '前半', 'other': '後半'});
    return '$_temp0';
  }

  @override
  String get programsMatrixFormationColumnHeader => 'フォーメーション';

  @override
  String programsMatrixFormationSemantic(String dance, String label) {
    return '$dance、フォーメーション: $label';
  }

  @override
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String collision,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(collision, {
      'yes': '、隣接するダンスと同じフレーズで繰り返される',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(debut, {
      'yes': '、ここで初登場',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(first, {
      'yes': '、ダンスの最初のフィギュア',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(present, {
      'no': '未使用',
      'other': '使用中$_temp0$_temp1$_temp2',
    });
    return '$dance、$move: $_temp3';
  }

  @override
  String programsMatrixChipQualifiedTitle(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '$title（代替ダンス、前半）',
      'second': '$title（代替ダンス、後半）',
      'other': '$title（代替ダンス）',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': '$title（前半）',
      'second': '$title（後半）',
      'other': '$title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixMoveUsedInSemantic(String label, int count, int total) {
    return 'ムーブ: $label、$total件中$count件のダンスで使用';
  }

  @override
  String programsMatrixNOfTotal(int count, int total) {
    return '$total件中$count件';
  }

  @override
  String get programsMatrixNoComparableMoves =>
      'これらのダンスにはまだ構造化されたフィギュアがないため、比較するムーブがありません。';

  @override
  String get programsMatrixRepeatedMovesHeader => '繰り返されるムーブ';

  @override
  String get programsMatrixRepeatedMovesSubtitle =>
      '2つ以上のダンスで共有されているムーブ（最も繰り返されるものが先頭）。';

  @override
  String get programsMatrixNoRepeatsNote =>
      'これらのダンス間で繰り返されるムーブはありません — 以下のすべてのムーブは1つのダンスでのみ使用されています。';

  @override
  String get programsMatrixUsedOnceHeader => '1回のみ使用';

  @override
  String get programsMatrixLegendIntroduced => 'ここで初登場';

  @override
  String get programsMatrixLegendFirstFigure => 'ダンスの最初のフィギュア';

  @override
  String get programsMatrixLegendPresent => '使用中';

  @override
  String get programsMatrixLegendCollision => '隣接ダンスと同じフレーズ';

  @override
  String get programsMatrixEmptyTitle => 'まだ構造化されたフィギュアがありません';

  @override
  String get programsMatrixEmptyBody =>
      'プログラムのダンスに構造化されたフィギュアが追加されると、マトリックスは自動的に埋まります。';

  @override
  String get performTitle => 'パフォーム';

  @override
  String get performExitTooltip => 'パフォームビューを終了';

  @override
  String get performExitTitle => 'パフォームを終了しますか？';

  @override
  String get performExitBody =>
      'パフォームビューを終了しますか？位置と実行中のタイマーは保持されるため、中断した場所から再開できます。';

  @override
  String get performExitCancel => 'パフォームを続ける';

  @override
  String get performExitConfirm => '終了';

  @override
  String get performTapTempo => 'タップテンポ';

  @override
  String performBpmReadout(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get performTapToSetTempo => 'テンポを設定するにはタップ';

  @override
  String performBpmSemantic(int bpm) {
    return '毎分$bpm拍';
  }

  @override
  String get performNoTempoSemantic => 'テンポが未設定です。ターゲットをタップしてテンポを設定してください。';

  @override
  String get performRecordBeatHint => 'ビートを記録';

  @override
  String get performTapRefineHint => 'タップを続けて調整 · リセットして最初から';

  @override
  String get performTapTwiceHint => 'ビートに合わせて少なくとも2回タップしてください';

  @override
  String get performResetTempo => 'リセット';

  @override
  String get performUntitledSlot => '無題のスロット';

  @override
  String performMarkedPerformedAnnounce(String label) {
    return '$labelを実施済みとしてマークしました';
  }

  @override
  String get performClearedPerformedAnnounce => '実施済みマークをクリアしました';

  @override
  String performMovedToPosition(String label, int position) {
    return '$labelをポジション$positionに移動しました';
  }

  @override
  String get performDanceFallback => 'ダンス';

  @override
  String performInsertedAnnounce(String title) {
    return '$titleを挿入しました';
  }

  @override
  String get performAddedNoteAnnounce => 'ノートを追加しました';

  @override
  String get performInsertADance => 'ダンスを挿入';

  @override
  String get performAdjustProgram => 'プログラムを調整';

  @override
  String get performCurrentSlotSection => '現在のスロット';

  @override
  String get performPerformedTapToClear => '実施済み — タップしてクリア';

  @override
  String get performReorderSection => '残りのスロットを並べ替え';

  @override
  String get performNoLaterSlots => '並べ替える後続のスロットがありません。';

  @override
  String get performInsertDanceFromSearch => '検索からダンスを挿入';

  @override
  String get performAdHocNoteLabel => 'アドホックノート／ブレイク';

  @override
  String get performAdHocNoteHint => '例: ワルツ、アナウンス';

  @override
  String get performAddNote => 'ノートを追加';

  @override
  String performAlternatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の代替',
    );
    return '$_temp0';
  }

  @override
  String performMoveLabelUp(String label) {
    return '「$label」を上に移動';
  }

  @override
  String performMoveLabelDown(String label) {
    return '「$label」を下に移動';
  }

  @override
  String performSlotPosition(int current, int total) {
    return 'スロット $current/$total';
  }

  @override
  String performShowingSlot(String label) {
    return '$labelを表示中';
  }

  @override
  String get performAdjustmentUndone => '調整を元に戻しました';

  @override
  String get performProgramAdjustedSnack => 'プログラムを調整しました。';

  @override
  String get performProgramAdjustedAnnounce => 'プログラムを調整しました';

  @override
  String get performNoSlots => 'このプログラムにスロットがありません。';

  @override
  String get performJumpToSlot => 'スロットにジャンプ';

  @override
  String get performShowAlternate => '代替を表示';

  @override
  String get performPreviousSlot => '前のスロット';

  @override
  String get performNextSlot => '次のスロット';

  @override
  String get performResumeTimers => 'タイマーを再開';

  @override
  String get performPauseTimers => 'タイマーを一時停止';

  @override
  String performTimingSemantic(
    String programTime,
    String slotTime,
    String hasPlanned,
    int planned,
    String over,
    String paused,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$planned分',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': '、予定 $_temp0',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(over, {'yes': '、予定超過', 'other': ''});
    String _temp3 = intl.Intl.selectLogic(paused, {
      'yes': '、一時停止中',
      'other': '',
    });
    return 'プログラム経過時間 $programTime、スロット経過時間 $slotTime$_temp1$_temp2$_temp3';
  }

  @override
  String performPlannedMin(int planned) {
    return '予定 $planned分';
  }

  @override
  String get performOverSuffix => ' 超過';

  @override
  String get performCallingNotes => 'コーリングノート';

  @override
  String get performWalkthrough => 'ウォークスルー';

  @override
  String get performShowWalkthrough => 'ウォークスルーを表示';

  @override
  String get performWalkthroughEmpty => 'このダンスのウォークスルーはありません。';

  @override
  String get performNoFigures => 'フィギュアがまだありません。';

  @override
  String get performDecreaseTextSize => '文字サイズを小さく';

  @override
  String get performIncreaseTextSize => '文字サイズを大きく';

  @override
  String get performShowCanonicalTerms => '正式な用語で表示';

  @override
  String get performMoreActions => 'その他のアクション';

  @override
  String get performAutoSizeMenuLabel => 'テキストを画面に自動調整';

  @override
  String get performAutoSizeOnTooltip => '自動サイズオン — タップして手動サイズ設定';

  @override
  String get performAutoSizeOffTooltip => '自動サイズオフ — タップして画面に合わせる';

  @override
  String get performStageThemeOnTooltip => 'ステージテーマオン — タップしてアプリのテーマを使用';

  @override
  String get performStageThemeOffTooltip => 'ステージテーマオフ — タップしてダークステージを使用';

  @override
  String get performProgression => 'プログレッション';

  @override
  String performFigureSemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    int beats,
    String hasNote,
    String note,
  ) {
    String _temp0 = intl.Intl.selectLogic(importGap, {
      'yes': '、$importGapText',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(progression, {
      'yes': '、プログレッション',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': '、ノート: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1、$_temp2$_temp3';
  }

  @override
  String get programsSelectTitle => 'プログラムを選択';

  @override
  String get programsSelectBody => 'リストからプログラムを選択するか、新しいプログラムを作成してください。';

  @override
  String get commonEdit => '編集';

  @override
  String get commonChange => '変更';

  @override
  String get commonTryAgain => '再試行';

  @override
  String get exportTooltip => 'エクスポート';

  @override
  String get exportShareDanceText => 'ダンスを共有（テキスト）';

  @override
  String get exportCopyDance => 'ダンスをコピー';

  @override
  String get exportPrintPdf => 'PDFにエクスポート／印刷';

  @override
  String get exportDanceCopied => 'ダンスをクリップボードにコピーしました。';

  @override
  String get exportShareDanceError => 'このダンスを共有できませんでした';

  @override
  String get exportDanceError => 'このダンスをエクスポートできませんでした';

  @override
  String get exportShareSetListText => 'セットリストを共有（テキスト）';

  @override
  String get exportShareProgramBundle => '共有（プログラム＋ダンス）';

  @override
  String get exportCopySetList => 'セットリストをコピー';

  @override
  String get exportSetListCopied => 'セットリストをクリップボードにコピーしました。';

  @override
  String get exportShareSetListError => 'このセットリストを共有できませんでした';

  @override
  String get exportShareProgramError => 'このプログラムを共有できませんでした';

  @override
  String get exportSetListError => 'このセットリストをエクスポートできませんでした';

  @override
  String get exportMatrixPdfTooltip => 'マトリックスをPDFにエクスポートまたは印刷';

  @override
  String get exportMatrixPdfFilename => 'プログラミングマトリックス';

  @override
  String get exportLabelFormation => 'フォーメーション';

  @override
  String get exportLabelLevel => 'レベル';

  @override
  String get exportLabelStatus => 'ステータス';

  @override
  String get exportLabelPhrase => 'フレーズ';

  @override
  String get exportLabelFigures => 'フィギュア';

  @override
  String get exportLabelCallingNotes => 'コーリングノート';

  @override
  String get exportLabelWalkthrough => 'ウォークスルー';

  @override
  String exportBeatsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count拍',
    );
    return '$_temp0';
  }

  @override
  String get exportLevelMixedOnly => 'ミックス';

  @override
  String exportLevelWithMixed(String level) {
    return '$level（ミックス）';
  }

  @override
  String get exportLabelBand => 'バンド';

  @override
  String get exportLabelCaller => 'コーラー';

  @override
  String get exportLabelNotes => 'ノート';

  @override
  String get exportLabelAlt => '代替';

  @override
  String get exportLabelGuest => 'ゲスト';

  @override
  String get exportLabelPerformed => '実施済み';

  @override
  String get exportUnknownDanceLabel => '無題のダンス';

  @override
  String exportMinutesLabel(int count) {
    return '$count分';
  }

  @override
  String get exportLabelVenue => '会場';

  @override
  String get exportLabelTime => '時間';

  @override
  String get exportLabelSchedule => 'スケジュール';

  @override
  String get exportLabelPrice => '料金';

  @override
  String get exportLabelSponsor => 'スポンサー';

  @override
  String get exportMatrixDefaultTitle => 'プログラミングマトリックス';

  @override
  String get exportMatrixDanceColumn => 'ダンス';

  @override
  String get exportMatrixFormationColumn => 'フォーメーション';

  @override
  String get exportMatrixEmptyState =>
      'まだ構造化されたフィギュアがありません — プログラムのダンスに構造化されたフィギュアが追加されると、マトリックスは自動的に埋まります。';

  @override
  String get exportMatrixLegendDebut => 'ここで初登場';

  @override
  String get exportMatrixLegendFirst => 'ダンスの最初のフィギュア';

  @override
  String get exportMatrixLegendPresent => '使用中';

  @override
  String get exportMatrixLegendCollision => '隣接ダンスと同じフレーズ';

  @override
  String exportMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフリーテキストスロット（ブレイク、ノート）が省略されています — マトリックスはダンスのみ表示。',
    );
    return '$_temp0';
  }

  @override
  String get exportVenueContactTitle => 'このエクスポートに会場の連絡先情報を含めますか？';

  @override
  String get exportVenueContactBody =>
      '会場の個人的な連絡先情報です。含めることを選択しない限り、このエクスポートには含まれません。';

  @override
  String get exportVenueContactConfirm => '続ける';

  @override
  String get exportVenueContact1Name => '連絡先1 名前';

  @override
  String get exportVenueContact1Phone => '連絡先1 電話';

  @override
  String get exportVenueContact1Email => '連絡先1 メール';

  @override
  String get exportVenueContact2Name => '連絡先2 名前';

  @override
  String get exportVenueContact2Phone => '連絡先2 電話';

  @override
  String get exportVenueContact2Email => '連絡先2 メール';

  @override
  String get onlineSearchToggleTitle => 'オンライン検索';

  @override
  String get onlineSearchToggleSubtitle =>
      'オンラインでダンスを検索して直接インポートします（インターネットが必要）。ローカルフィルターは適用されません。';

  @override
  String onlineSearchFieldLabel(String source) {
    return '$sourceを検索';
  }

  @override
  String get onlineSearchFieldHint => 'タイトルでオンラインダンスを検索…';

  @override
  String onlineResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のオンライン結果',
    );
    return '$_temp0';
  }

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'タイトルを入力するかフレーズのフィギュアを追加して$sourceを検索してください。';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'タイトルを入力して$sourceを検索してください。';
  }

  @override
  String onlineNoResults(String source) {
    return '$sourceで検索に一致するダンスがありません。';
  }

  @override
  String onlineLoadError(String source) {
    return '$sourceからそのダンスを読み込めませんでした。';
  }

  @override
  String get onlineImportError => 'そのダンスをインポートできませんでした。';

  @override
  String onlineSearchFailed(String source) {
    return '$sourceを検索できませんでした。もう一度お試しください。';
  }

  @override
  String onlineImportCreated(String title) {
    return '「$title」をインポートしました。';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '「$title」はすでにコレクションにあります。';
  }

  @override
  String get onlineAttributionCallersBox => 'The Caller\'s Box（オンライン）より';

  @override
  String get onlineAttributionContraDb => 'ContraDB（オンライン）より';

  @override
  String get importDances => 'ダンスをインポート';

  @override
  String get importAction => 'インポート';

  @override
  String get importProgramTooltip => 'プログラムをインポート';

  @override
  String get importFromTitleList => 'タイトルリストから';

  @override
  String get importFromContraDb => 'ContraDBから';

  @override
  String get importProgramTitleLabel => 'プログラムタイトル';

  @override
  String get importProgramCreateError => 'インポートしたプログラムを保存できませんでした。';

  @override
  String importProgramCommitted(
    String title,
    int slots,
    int linked,
    int notes,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      slots,
      locale: localeName,
      other: '$slotsスロット',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes件のノート',
    );
    return '「$title」をインポートしました — $_temp0（$linked件リンク済み、$_temp1）。';
  }

  @override
  String get importContraDbTitle => 'ContraDBからインポート';

  @override
  String get importContraDbPasteUrl => 'URLを貼り付け';

  @override
  String get importContraDbSearchByName => '名前で検索';

  @override
  String get importContraDbUrlLabel => 'ContraDBプログラムURL';

  @override
  String get importContraDbUrlHint => '例: https://contradb.com/programs/33';

  @override
  String get importContraDbFetching => '取得中…';

  @override
  String get importContraDbFetch => 'プログラムを取得';

  @override
  String get importContraDbSearchLabel => 'ContraDBプログラムを検索';

  @override
  String get importContraDbSearchHint => 'プログラム名の一部を入力';

  @override
  String get importContraDbListError => 'ContraDBのプログラムリストを読み込めませんでした。';

  @override
  String get importContraDbSearchPrompt => 'プログラム名の一部を入力してContraDBを検索してください。';

  @override
  String get importContraDbNoMatches => '一致するプログラムがありません。';

  @override
  String get importContraDbMarkerImported => 'Imported';

  @override
  String importContraDbMarkerImportedTooltip(String date) {
    return 'Imported on $date';
  }

  @override
  String get importContraDbMarkerImportedTooltipNoDate =>
      'Already imported from ContraDB';

  @override
  String get importContraDbMarkerPossible => 'Possibly imported';

  @override
  String get importContraDbMarkerPossibleTooltip =>
      'A program with this title already exists';

  @override
  String importContraDbFetchError(String error) {
    return 'そのプログラムを取得できませんでした。\n$error';
  }

  @override
  String get importContraDbFetchGenericError => 'そのプログラムを取得できませんでした。';

  @override
  String get importContraDbPastePrompt =>
      '上にContraDBプログラムのURLを貼り付けて「プログラムを取得」をタップしてください。';

  @override
  String get importContraDbEmptyProgram => 'そのプログラムページにダンスやノートが見つかりませんでした。';

  @override
  String get importContraDbResolveError => 'ContraDBプログラムをインポートできませんでした。';

  @override
  String importContraDbActivityCount(int activities, int dances, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      activities,
      locale: localeName,
      other: '$activities件のアクティビティ',
    );
    String _temp1 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances件のダンス',
    );
    String _temp2 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes件のノート',
    );
    return '$_temp0（$_temp1、$_temp2）';
  }

  @override
  String get importContraDbDanceFallback => 'ContraDBダンス';

  @override
  String get importEventDateNone => '日付未設定';

  @override
  String get importEventDateLabel => 'イベント日';

  @override
  String get importEventDateSet => '日付を設定';

  @override
  String get importEventDateClear => 'イベント日をクリア';

  @override
  String get importEventDateDetected => 'タイトルから日付を検出しました — インポート前に確認してください。';

  @override
  String get importTitleListTitle => 'タイトルリストからインポート';

  @override
  String get importCollectionLoadError => 'コレクションを読み込めませんでした。';

  @override
  String get importTitleListDancesLabel => 'ダンスのタイトル（1行に1つ）';

  @override
  String get importTitleListDancesHint =>
      '1行に1つのダンスタイトルを貼り付けてください。\n認識されない行はノートとして保持されます。';

  @override
  String get importTitleListEmptyHint =>
      '上にダンスのタイトルリストを貼り付けてプログラムをプレビューしてください。';

  @override
  String get importResolving => '検索中…';

  @override
  String get importResolveOnline => 'オンラインで未一致を解決';

  @override
  String get importPlaintextImportedOnline => 'Caller\'s Boxからインポート';

  @override
  String get importPlaintextLinked => 'ダンスにリンク';

  @override
  String get importPlaintextAmbiguous => '複数の一致 — ノートとして追加';

  @override
  String get importPlaintextUnmatched => '一致なし — ノートとして追加';

  @override
  String get importPlaintextSearchError => 'The Caller\'s Boxを検索できませんでした。';

  @override
  String importPlaintextSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countスロット',
    );
    return '$_temp0';
  }

  @override
  String importPlaintextResolvedNone(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining件のタイトルをノートとして保持',
    );
    return '自信を持って一致するCaller\'s Boxの結果が見つかりませんでした — $_temp0。';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked件のタイトル',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '；$remaining件はまだノートです。',
      zero: '。',
    );
    return 'The Caller\'s Boxから$_temp0をリンクしました$_temp1';
  }

  @override
  String get importReviewClose => 'インポートを閉じる';

  @override
  String get importReviewSourceLabel => 'ソース';

  @override
  String importReviewFromSource(String source) {
    return '$sourceからインポート。';
  }

  @override
  String importReviewDancesFromSource(String source) {
    return '$sourceからダンスをインポート。';
  }

  @override
  String get importSourceLabelGenericJson => 'Caller\'s Compendium JSONファイル';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'Caller\'s Companion .USRファイル';

  @override
  String get importErrorFileTooLarge => 'そのファイルはインポートするには大きすぎます。';

  @override
  String get archiveIntakeRejectedTooLarge => 'そのファイルはインポートするには大きすぎます。';

  @override
  String get archiveIntakeRejectedUnreadable => '共有ファイルを読み取れませんでした。';

  @override
  String get archiveIntakeRejectedEmpty => 'そのファイルは空です。';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'そのファイルはCaller’s Compendiumの共有ファイルではありません。';

  @override
  String get archiveIntakeRejectedNewerVersion =>
      'そのファイルは新しいバージョンのアプリで作成されました。インポートするにはアプリを更新してください。';

  @override
  String get archiveIntakeRejectedNoContent => 'そのファイルにはダンスもプログラムも含まれていませんでした。';

  @override
  String get importErrorInsecureScheme => 'インポートには安全なhttps:// URLを使用する必要があります。';

  @override
  String get importErrorBlockedHost => 'そのURLはインポートできないネットワークの場所を指しています。';

  @override
  String get importErrorInvalidUrl => '有効なhttp(s) URLのように見えません。';

  @override
  String get importErrorTooManyRedirects => 'そのURLはリダイレクトが多すぎました。';

  @override
  String get importErrorResponseTooLarge => 'そのレスポンスはインポートするには大きすぎます。';

  @override
  String get importErrorEmptyUrl => 'インポート元のURLを入力してください。';

  @override
  String importErrorTimeout(int seconds) {
    return 'リクエストが$seconds秒後にタイムアウトしました。URLと接続を確認して、もう一度お試しください。';
  }

  @override
  String get importErrorUnreachable =>
      'そのURLに到達できませんでした。URLと接続を確認して、もう一度お試しください。';

  @override
  String importErrorHttpStatus(int status) {
    return 'サーバーがHTTP $statusで応答しました。';
  }

  @override
  String get importErrorEmptyResponse => 'そのURLは空のレスポンスを返しました。';

  @override
  String get importErrorCallersBoxEmptyInput =>
      'インポートするCaller\'s BoxのダンスURLまたはIDを入力してください。';

  @override
  String get importErrorCallersBoxInvalidUrl =>
      'Caller\'s BoxのダンスURLまたは数値IDのように見えません。';

  @override
  String get importErrorCallersBoxMissingId =>
      'そのCaller\'s BoxのURLにはダンスID（…dance.php?id=N）がありません。';

  @override
  String get importErrorCallersBoxUnsupportedHost =>
      'そのリンクはサポートされているCaller\'s Boxのホストではありません。ibiblio.orgのリンクを貼り付けるか、ダンスの数値IDを入力してください。';

  @override
  String get importErrorCallersBoxEmptySearch =>
      'The Caller\'s Boxを検索するにはタイトルまたはフレーズのフィギュアを入力してください。';

  @override
  String importErrorSearchTimeout(int seconds) {
    return '検索が$seconds秒後にタイムアウトしました。接続を確認して、もう一度お試しください。';
  }

  @override
  String get importErrorCallersBoxUnreachable =>
      'The Caller\'s Boxに到達できませんでした。接続を確認して、もう一度お試しください。';

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s BoxがHTTP $statusで応答しました。';
  }

  @override
  String get importErrorCallersBoxEmptyPage => 'The Caller\'s Boxが空のページを返しました。';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Boxからインポートできるダンスが返されませんでした。';

  @override
  String get importErrorCallersBoxImportFailed =>
      'The Caller\'s Boxのダンスをインポートできませんでした。';

  @override
  String get importErrorContraDbEmptyTitle => 'ContraDBを検索するにはタイトルを入力してください。';

  @override
  String get importErrorContraDbEmptyDanceInput =>
      'インポートするContraDBのダンスURLまたはIDを入力してください。';

  @override
  String get importErrorContraDbInvalidDanceUrl =>
      'ContraDBのダンスURLまたは数値IDのように見えません。';

  @override
  String get importErrorContraDbMissingDanceId =>
      'そのContraDBのURLにはダンスID（…/dances/N）がありません。';

  @override
  String get importErrorContraDbEmptyProgramInput =>
      'インポートするContraDBのプログラムURLまたはIDを入力してください。';

  @override
  String get importErrorContraDbInvalidProgramUrl =>
      'ContraDBのプログラムURLまたは数値IDのように見えません。';

  @override
  String get importErrorContraDbMissingProgramId =>
      'そのContraDBのURLにはプログラムID（…/programs/N）がありません。';

  @override
  String get importErrorContraDbInvalidProgramLink =>
      'ContraDBのプログラムリンクのように見えません。';

  @override
  String get importErrorContraDbUnsupportedHost =>
      'そのリンクはサポートされているContraDBのホストではありません。contradb.comのリンクを貼り付けるか、ダンスまたはプログラムの数値IDを入力してください。';

  @override
  String get importErrorContraDbUnreachable =>
      'ContraDBに到達できませんでした。接続を確認して、もう一度お試しください。';

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDBがHTTP $statusで応答しました。';
  }

  @override
  String get importErrorContraDbEmptyResponse => 'ContraDBが空のレスポンスを返しました。';

  @override
  String get importErrorContraDbNoDance => 'ContraDBからインポートできるダンスが返されませんでした。';

  @override
  String get importErrorContraDbImportFailed => 'ContraDBのダンスをインポートできませんでした。';

  @override
  String get importIssueGeneric => 'この項目は注記付きでインポートされました。';

  @override
  String get importIssueProgramEmptySlot => 'プログラム内の空のスロットをスキップしました。';

  @override
  String get importIssueProgramUnresolvedDance =>
      'プログラムがインポートされていないダンスを参照していたため、スロットをテキストのプレースホルダーとして保持しました。';

  @override
  String get importIssueProgramUnresolvedVenue =>
      'プログラムがインポートされていない会場を参照していたため、会場リンクなしでプログラムを保持しました。';

  @override
  String get importIssueArchiveReadError => '共有ファイル内のエントリを読み取れなかったため、スキップしました。';

  @override
  String get importIssueArchiveReadWarning => '共有ファイルのデコード中に警告が報告されました。';

  @override
  String get importIssueDirectionUnmapped =>
      'Becketの方向を認識できませんでした。既定で時計回りにしました。';

  @override
  String get importIssueFormationUnclassified =>
      'フォーメーションを認識できませんでした。「other」の詳細として保持しました。';

  @override
  String get importIssuePhraseStructureUnreadable =>
      'フレーズ構造を読み取れませんでした。既定の構造を使用しました。';

  @override
  String get importIssueProgressionUnmapped =>
      'プログレッションを認識できませんでした。「other」として記録しました。';

  @override
  String get importIssueMetadataOnlyStub =>
      'このダンスはメタデータのみ利用可能です（フィギュアなし）。スタブとしてインポートしました。';

  @override
  String importIssueDateAssumedMdy(String field) {
    return 'あいまいな$fieldの日付を月/日（米国式の順序）として読み取りました。元データが日付先の順序を使用していた場合は確認してください。';
  }

  @override
  String importIssueDateReducedPrecision(int year, String field) {
    return '$fieldの日付から年（$year）のみを読み取れました。月や日はありませんでした。';
  }

  @override
  String get importIssueMissingTitle =>
      'ダンスにタイトルがなかったため、プレースホルダーのタイトルを使用しました。確定する前に編集してください。';

  @override
  String get importIssueProgramUnparsedDate => 'イベントの日付を読み取れませんでした。未設定のままです。';

  @override
  String get importIssueRatingOutOfRange => '評価が1〜5の範囲外でした。未評価のままです。';

  @override
  String get importIssueUnmappedFormation =>
      'フォーメーションを認識できませんでした。自由記述の詳細として保持しました。';

  @override
  String get importIssueUnmappedLevel => 'レベルを認識できませんでした。未指定のままです。';

  @override
  String get importIssueUnmappedProgression =>
      'プログレッションを認識できませんでした。既定でシングルにしました。';

  @override
  String get importIssueUnmappedType =>
      'ダンスの種類を認識できませんでした。コントラとしてインポートし、ノートに保持しました。';

  @override
  String importIssueUnparsedDate(String field) {
    return '$fieldの日付を読み取れませんでした。未設定のままです。';
  }

  @override
  String get importIssueUnparsedRating => '評価を読み取れませんでした。未評価のままです。';

  @override
  String get importIssueFiguresUnreadable =>
      'フィギュアを読み取れませんでした。フィギュアはインポートされませんでした。';

  @override
  String get importIssueBeatsUnreadable => '拍数を読み取れませんでした。0を使用しました。';

  @override
  String get importIssueNoFiguresTable =>
      'ページにフィギュアがありませんでした。メタデータのみのスタブとしてインポートしました。';

  @override
  String get importIssueMoveFallback =>
      'フィギュアを既知のムーブに一致させられませんでした。カスタムとしてインポートしました。';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'フィギュア$positionを既知のムーブに一致させられませんでした。カスタムとしてインポートしました。';
  }

  @override
  String get importIssueParamUnmapped =>
      'フィギュアのパラメーターをマッピングできませんでした。タクソノミーの既定値を使用しました。';

  @override
  String importIssueParamValueUnmapped(String param) {
    return 'パラメーター$paramを変換できませんでした。タクソノミーの既定値を使用しました。';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'フィギュアには$provided個のパラメーター値がありましたが、マッピングされているのは$mapped個のみです。余剰分は無視されました。';
  }

  @override
  String get importIssueRelatedDanceUnresolved =>
      '関連ダンスのリンクがインポートされていないダンスを参照していたため、リンクはスキップされました。';

  @override
  String get importDateFieldComposed => '振付';

  @override
  String get importDateFieldRevised => '改訂';

  @override
  String get importRecordErrorDiscover => 'このレコードが見つかりませんでした。';

  @override
  String get importRecordErrorFetch => 'このレコードを取得できませんでした。';

  @override
  String get importRecordErrorParse => 'このレコードを読み取れませんでした。';

  @override
  String get importRecordErrorDedupe => 'このレコードを処理できませんでした。';

  @override
  String get importRecordErrorCommit => 'このレコードを保存できませんでした。';

  @override
  String get importReviewUsrSubtitle =>
      'Caller\'s Companion .USRファイルを選択して、ダンスとプログラム履歴を移行してください。確認して承認するまでコレクションには何も追加されません。';

  @override
  String get importReviewChooseUsr => '.USRファイルを選択…';

  @override
  String importReviewFileReady(int bytes) {
    return 'ファイルの準備ができました（$bytesバイト）。';
  }

  @override
  String get importReviewGenericSubtitle =>
      'ファイルを選択するか、内容を貼り付けるか、URLから取得してください。確認して承認するまでコレクションには何も追加されません。';

  @override
  String get importReviewChooseFile => 'ファイルを選択…';

  @override
  String get importReviewUrlLabel => 'ダンスURLまたはID';

  @override
  String get importReviewUrlLabelGeneric => 'URLからインポート';

  @override
  String get importReviewUrlHint =>
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · または · 1';

  @override
  String get importReviewUrlHintGeneric => 'https://…';

  @override
  String get importReviewFetch => '取得';

  @override
  String get importReviewPasteJson => 'またはJSONを貼り付け';

  @override
  String get importReviewReviewButton => 'インポートを確認';

  @override
  String importReviewWillImport(int importable, int total) {
    return '$total件中$importable件がインポートされます';
  }

  @override
  String get importReviewCouldNotRead => 'インポートを読み取れませんでした';

  @override
  String get importReviewNoDancesTitle => 'ダンスが見つかりませんでした';

  @override
  String get importReviewNoDancesBody => 'ファイルにインポートできるダンスが含まれていませんでした。';

  @override
  String get importReviewTryAnother => '別のファイルを試す';

  @override
  String get importReviewImported => 'インポート済み';

  @override
  String importReviewStructured(int structured, int total) {
    return '$total件中$structured件が構造化';
  }

  @override
  String get importReviewCustom => 'カスタム';

  @override
  String get importReviewOptionNewDance => '新しいダンス';

  @override
  String get importReviewOptionSkip => 'スキップ';

  @override
  String importReviewOptionReimport(String title) {
    return '「$title」に再インポート';
  }

  @override
  String get importReviewOptionDuplicate => '新しい（重複）ダンスとしてインポート';

  @override
  String get importReviewPossibleMatch => '候補が見つかりました — インポート方法を選択してください:';

  @override
  String importReviewOptionLink(String title, int percent) {
    return '「$title」にリンク（$percent%一致）';
  }

  @override
  String importReviewOverwriteWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の既存のダンスが上書きされます',
    );
    return '$_temp0';
  }

  @override
  String importReviewWarningPrefix(String message) {
    return '警告: $message';
  }

  @override
  String get importReviewComplete => 'インポート完了';

  @override
  String sharedImportSoftCapWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'このインポートには$count件のアイテムが含まれています — 通常の共有より多いです。',
    );
    return '$_temp0';
  }

  @override
  String sharedImportComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムをインポートしました。',
      zero: 'インポート完了。',
    );
    return '$_temp0';
  }

  @override
  String sharedImportProgramsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'この共有には$count件のプログラムが含まれており、ダンスはありません。',
    );
    return '$_temp0';
  }

  @override
  String importReviewSummaryCreated(int count) {
    return '作成: $count';
  }

  @override
  String importReviewSummaryReimported(int count) {
    return '再インポート: $count';
  }

  @override
  String importReviewSummaryLinked(int count) {
    return 'リンク: $count';
  }

  @override
  String importReviewSummaryDuplicated(int count) {
    return '複製: $count';
  }

  @override
  String importReviewSummaryVariation(int count) {
    return 'バリエーションとして取り込み: $count';
  }

  @override
  String importReviewSummarySkipped(int count) {
    return 'スキップ: $count';
  }

  @override
  String importReviewSummaryPrograms(int count) {
    return 'プログラム: $count';
  }

  @override
  String importReviewProgramsUpdated(int count) {
    return '$count件更新済み（再インポート）';
  }

  @override
  String importReviewProgramNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプログラムノート:',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のレコードのインポートに失敗しました:',
    );
    return '$_temp0';
  }

  @override
  String importReviewBatchErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のレコードを読み取れませんでした（残りはインポートできます）:',
    );
    return '$_temp0';
  }

  @override
  String get importReviewUntitledProgram => '無題のプログラム';

  @override
  String get importReviewUndoWithPrograms => '元に戻す（インポートしたダンスとプログラムを削除）';

  @override
  String get importReviewUndone => 'インポートを元に戻しました。';

  @override
  String get importReviewEditError => '編集用にそのダンスをインポートできませんでした。';

  @override
  String get importReviewImportError => 'インポートを完了できませんでした。';

  @override
  String importReviewVariationTitle(String title) {
    return '「$title」のバリエーション？';
  }

  @override
  String importReviewVariationBody(String title) {
    return 'このダンスのタイトルとコーラーは「$title」と一致しますが、フィギュアが異なります。違いを確認してから、取り込み方法を選択してください。';
  }

  @override
  String importReviewOptionVariation(String title) {
    return '「$title」のバリエーションとして取り込む';
  }

  @override
  String importReviewOptionSameDance(String title) {
    return '「$title」と同じダンス（リンク/更新）';
  }

  @override
  String importReviewOptionLinkBack(String title) {
    return '「$title」に関連ダンスとしてリンクを追加する';
  }

  @override
  String get importReviewVariationAdded => '追加';

  @override
  String get importReviewVariationRemoved => '削除';

  @override
  String importReviewVariationMoreDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '他に$count件の違いは表示されていません',
      one: '他に1件の違いは表示されていません',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorDetailsSection => '詳細';

  @override
  String get danceEditorTitleRequiredLabel => 'タイトル *';

  @override
  String get danceEditorTitleRequired => 'タイトルが必要です';

  @override
  String get danceEditorAuthorsLabel => '作者';

  @override
  String get danceEditorFormationLabel => 'フォーメーション';

  @override
  String get danceEditorFormationDetailLabel => 'フォーメーションの詳細（任意）';

  @override
  String get danceEditorPhraseStructureLabel => 'フレーズ構造';

  @override
  String get danceEditorPhraseStructureHint =>
      '空白 = 標準のA1 A2 B1 B2；それ以外は例: 6*8*2';

  @override
  String get danceEditorFiguresSection => 'フィギュア';

  @override
  String get danceEditorFiguresHelp =>
      'ムーブを入力して（例: \"sw\" → スイング）Enterキーを押すとデフォルトパラメーターで追加されます。一致しないテキストはカスタムフィギュアになります。';

  @override
  String get danceEditorNotesSection => 'ノート';

  @override
  String get danceEditorCallingNotesLabel => 'コーリングノート';

  @override
  String get danceEditorHookLabel => 'フック';

  @override
  String get danceEditorHookHint => '「なぜこれをコールするか」の1行説明';

  @override
  String get danceEditorWalkthroughLabel => 'ウォークスルー';

  @override
  String get danceEditorWalkthroughHelper => 'ダンスの各ステップと遷移の手順説明';

  @override
  String get danceEditorAddWalkthroughStep => 'ウォークスルーのステップを追加';

  @override
  String get danceEditorWalkthroughStepLabel => 'ウォークスルーのステップ（任意）';

  @override
  String get danceEditorWalkthroughStepHelper =>
      'このフィギュアの既定値として保存され、登場するすべての箇所で再利用されます。';

  @override
  String get danceEditorSnippetDivergenceTitle => '保存済みスニペットを更新しますか？';

  @override
  String get danceEditorSnippetDivergenceBody =>
      'これはこのフィギュアに保存したウォークスルースニペットと異なります。新しいテキストをすべてで使用しますか、それともこのダンスだけにしますか？';

  @override
  String get danceEditorSnippetUseEverywhere => 'すべてで使用';

  @override
  String get danceEditorSnippetJustThisDance => 'このダンスのみ';

  @override
  String get danceEditorFillWalkthroughFromSnippets => 'スニペットから入力';

  @override
  String get danceEditorFillWalkthroughReplaceTitle => 'ウォークスルーを置き換えますか？';

  @override
  String get danceEditorFillWalkthroughReplaceBody =>
      '現在のウォークスルーを、フィギュアのスニペットから組み立てたテキストで置き換えます。';

  @override
  String get danceEditorFillWalkthroughReplaceConfirm => '置き換え';

  @override
  String get danceEditorFillWalkthroughEmpty =>
      'これらのフィギュアにはまだ保存されたウォークスルースニペットがありません。';

  @override
  String get settingsWalkthroughSnippetsTitle => 'ウォークスルースニペット';

  @override
  String get settingsWalkthroughSnippetsSubtitle => 'フィギュアごとに保存したステップ説明';

  @override
  String get settingsWalkthroughSnippetsHeader => '保存されたウォークスルースニペット';

  @override
  String get settingsWalkthroughSnippetsDescription =>
      'これらのフィギュアごとのステップ説明は、ダンスを編集するときにウォークスルーを事前入力します。ここで編集すると、すべてで使われる既定値が更新されます。';

  @override
  String get settingsWalkthroughSnippetsEmpty =>
      '保存されたスニペットはまだありません。ダンスのフィギュアを編集しながらウォークスルーのステップ説明を追加してください。';

  @override
  String settingsWalkthroughSnippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のスニペット',
    );
    return '$_temp0';
  }

  @override
  String get settingsWalkthroughSnippetDeleteTitle => 'スニペットを削除しますか？';

  @override
  String get settingsWalkthroughSnippetDeleteBody =>
      'このフィギュアに保存された既定値を削除します。ダンスにすでに書いたウォークスルーのテキストは保持されます。';

  @override
  String get settingsWalkthroughSnippetEditTitle => 'スニペットを編集';

  @override
  String get danceEditorMoreDetailsTitle => '詳細情報';

  @override
  String get danceEditorStatusLabel => 'ステータス';

  @override
  String get danceEditorMixedLevelSubtitle => '難易度の幅が広い';

  @override
  String get danceEditorComposedLabel => '振付年';

  @override
  String get danceEditorComposedHelper => 'ダンスが作られた日時（年、または月/日を追加）';

  @override
  String get danceEditorRevisedLabel => '改訂年';

  @override
  String get danceEditorRevisedHelper => '作者が最後に改訂した日時';

  @override
  String get danceEditorTagsLabel => 'タグ';

  @override
  String get danceEditorTunesLabel => 'チューン';

  @override
  String get danceEditorLinksLabel => 'リンク';

  @override
  String get danceEditorPublishedSourcesLabel => '公開ソース';

  @override
  String get danceEditorRelatedDancesLabel => '関連ダンス';

  @override
  String get danceEditorCustomFieldsLabel => 'カスタムフィールド';

  @override
  String get danceEditorRatingLabel => '評価';

  @override
  String get danceEditorRatingUnrated => '評価なし';

  @override
  String danceEditorRatingValue(int rating, int max) {
    return '$maxつ星中$rating';
  }

  @override
  String danceEditorSetRatingTooltip(int rating, int max) {
    return '評価を$maxつ星中$ratingに設定';
  }

  @override
  String get danceEditorClearRating => '評価をクリア';

  @override
  String get danceEditorLevelLabel => 'レベル';

  @override
  String get danceEditorLevelUnspecified => '未指定';

  @override
  String get danceEditorYearLabel => '年';

  @override
  String get danceEditorYearHint => '例: 1989';

  @override
  String get danceEditorYearRangeError => '1〜9999';

  @override
  String get danceEditorMonthLabel => '月';

  @override
  String get danceEditorDayLabel => '日';

  @override
  String get danceEditorMonthJan => '1月';

  @override
  String get danceEditorMonthFeb => '2月';

  @override
  String get danceEditorMonthMar => '3月';

  @override
  String get danceEditorMonthApr => '4月';

  @override
  String get danceEditorMonthMay => '5月';

  @override
  String get danceEditorMonthJun => '6月';

  @override
  String get danceEditorMonthJul => '7月';

  @override
  String get danceEditorMonthAug => '8月';

  @override
  String get danceEditorMonthSep => '9月';

  @override
  String get danceEditorMonthOct => '10月';

  @override
  String get danceEditorMonthNov => '11月';

  @override
  String get danceEditorMonthDec => '12月';

  @override
  String get monthFullJanuary => 'January';

  @override
  String get monthFullFebruary => 'February';

  @override
  String get monthFullMarch => 'March';

  @override
  String get monthFullApril => 'April';

  @override
  String get monthFullMay => 'May';

  @override
  String get monthFullJune => 'June';

  @override
  String get monthFullJuly => 'July';

  @override
  String get monthFullAugust => 'August';

  @override
  String get monthFullSeptember => 'September';

  @override
  String get monthFullOctober => 'October';

  @override
  String get monthFullNovember => 'November';

  @override
  String get monthFullDecember => 'December';

  @override
  String get danceEditorAddTuneHint => 'おすすめのチューンを追加…';

  @override
  String get danceEditorAddTuneTooltip => 'チューンを追加';

  @override
  String get danceEditorWarningsTitle => '警告';

  @override
  String validationPhraseBeatMismatch(int actual, int expected) {
    return 'フィギュアの合計は$actual拍ですが、フレーズ構造では$expectedが必要です。';
  }

  @override
  String get validationPhraseInvalid => 'そのフレーズ構造は無効です。';

  @override
  String validationOrphanedAlt(int position) {
    return '位置$positionの代替には、先行する主要スロットがありません。';
  }

  @override
  String validationOrphanedAltNamed(int position, String text) {
    return '位置$position（「$text」）の代替には、先行する主要スロットがありません。';
  }

  @override
  String validationEmptySubstitution(String term) {
    return '「$term」の置換が空です。';
  }

  @override
  String validationDialectCollision(
    String source,
    String existing,
    String substitution,
  ) {
    return '「$source」と「$existing」はどちらも「$substitution」に対応するため、反転するとあいまいになります。';
  }

  @override
  String get validationGeneric => 'この項目には検証上の問題があります。';

  @override
  String danceEditorDiscouragedTermSemantic(String term) {
    return '非推奨の用語: $term';
  }

  @override
  String danceEditorDiscouragedTermText(String term) {
    return '非推奨: $term';
  }

  @override
  String get danceEditorLinkKindSource => 'ソース';

  @override
  String get danceEditorLinkKindVideo => '動画';

  @override
  String get danceEditorLinkKindOther => 'その他';

  @override
  String get danceEditorUrlLabel => 'URL';

  @override
  String get danceEditorLabelOptional => 'ラベル（任意）';

  @override
  String get danceEditorRemoveLinkTooltip => 'リンクを削除';

  @override
  String get danceEditorAddLink => 'リンクを追加';

  @override
  String get danceEditorMissingDance => '（ダンスが見つかりません）';

  @override
  String get danceEditorNoteOptionalLabel => 'ノート（任意）';

  @override
  String get danceEditorRemoveRelatedDanceTooltip => '関連ダンスを削除';

  @override
  String get danceEditorAddRelatedDance => '関連ダンスを追加';

  @override
  String get danceEditorRelatedDanceLabel => '関連ダンス';

  @override
  String get danceEditorTypeToSearchHint => '検索するには入力…';

  @override
  String danceEditorEditItemTooltip(String item) {
    return '$itemを編集';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint => '追加または作成するには入力…';

  @override
  String danceEditorCreateQuotedName(String name) {
    return '「$name」を作成';
  }

  @override
  String get danceEditorUnknownSource => '（不明なソース）';

  @override
  String get danceEditorPageOptionalLabel => 'ページ（任意）';

  @override
  String get danceEditorNumberOptionalLabel => '番号（任意）';

  @override
  String get danceEditorCiteSourceHint => 'ソースを引用: 追加または作成するには入力…';

  @override
  String get danceEditorSaveError => 'ダンスを保存できませんでした。';

  @override
  String get danceEditorFallbackDanceTitle => 'ダンス';

  @override
  String get danceEditorUnsavedDraftTitle => '未保存の下書き';

  @override
  String get danceEditorUnsavedDraftMessage => 'このダンスに未保存の下書きがあります。復元しますか？';

  @override
  String get danceEditorDiscard => '破棄';

  @override
  String get danceEditorRestore => '復元';

  @override
  String get danceEditorDiscardChangesTitle => '変更を破棄しますか？';

  @override
  String get danceEditorDiscardChangesMessage => 'このダンスに未保存の変更があります。';

  @override
  String get danceEditorKeepEditing => '編集を続ける';

  @override
  String get danceEditorNewDanceTitle => '新しいダンス';

  @override
  String get danceEditorEditDanceTitle => 'ダンスを編集';

  @override
  String get danceEditorRedoLabel => 'やり直し';

  @override
  String get danceEditorUndoShortcutTooltip => '元に戻す (Ctrl+Z)';

  @override
  String get danceEditorRedoShortcutTooltip => 'やり直し (Ctrl+Shift+Z)';

  @override
  String get danceEditorDeleteDanceTooltip => 'ダンスを削除';

  @override
  String get danceEditorLoadError => 'ダンスを読み込めませんでした。';

  @override
  String get danceEditorChoreographerDetailsTitle => '振付師の詳細';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'これらの詳細は、この作者のすべてのダンスで共有されます。メールと場所はプライベートです — このデバイスにのみ保存され、共有またはエクスポートされることはありません。';

  @override
  String get danceEditorNameRequiredLabel => '名前 *';

  @override
  String get danceEditorNameRequired => '名前が必要です';

  @override
  String get danceEditorWebsiteLabel => 'ウェブサイト';

  @override
  String get danceEditorEmailPrivateLabel => 'メール（プライベート）';

  @override
  String get danceEditorLocationPrivateLabel => '場所（プライベート）';

  @override
  String get danceEditorNotesLabel => 'ノート';

  @override
  String get danceEditorDeceasedLabel => '故人';

  @override
  String get danceEditorSourceDetailsTitle => 'ソースの詳細';

  @override
  String get danceEditorSourceDetailsIntro =>
      'これらの詳細は、このソースを引用するすべてのダンスで共有されます。ここで編集すると、参照されているすべての場所でソースが更新されます。';

  @override
  String get danceEditorSourceAuthorEditorLabel => '著者／編者';

  @override
  String get danceEditorEnterWholeNumber => '整数を入力してください';

  @override
  String get danceEditorEnterPositiveYear => '正の年を入力してください';

  @override
  String danceEditorAddedFigureChooseMove(int count) {
    return 'フィギュア$countを追加しました。ムーブを選択してください。';
  }

  @override
  String danceEditorFigurePastedAnnouncement(int position) {
    return 'フィギュアをポジション$positionに貼り付けました。';
  }

  @override
  String danceEditorFigureMovedAnnouncement(int position, int total) {
    return '$total件中ポジション$positionに移動しました。';
  }

  @override
  String danceEditorEditingFigureAnnouncement(int position, String name) {
    return 'フィギュア$position「$name」を編集中。';
  }

  @override
  String danceEditorCollapsedFigureAnnouncement(int position) {
    return 'フィギュア$positionを折り畳みました。';
  }

  @override
  String get danceEditorTypeFigureAnnouncement =>
      'フィギュアを入力してEnterキーを押して追加してください。';

  @override
  String danceEditorFreeTextFiguresAddedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフィギュアを追加しました。さらに入力するか、Escキーを押して終了してください。',
    );
    return '$_temp0';
  }

  @override
  String danceEditorDeletedFigureAnnouncement(int position) {
    return 'フィギュア$positionを削除しました。元に戻せます。';
  }

  @override
  String danceEditorDuplicatedFigureAnnouncement(int position) {
    return 'フィギュア$positionを複製しました。';
  }

  @override
  String get danceEditorAddFirstFigure => '最初のフィギュアを追加';

  @override
  String danceEditorCutBanner(String figure) {
    return '「$figure」をカットしました — ペーストして配置してください。';
  }

  @override
  String get danceEditorPasteBeforeFirstFigure => '最初のフィギュアの前にペースト';

  @override
  String danceEditorPasteAfterFigure(String figure) {
    return '$figureの後にペースト';
  }

  @override
  String get danceEditorAddFigure => 'フィギュアを追加';

  @override
  String get danceEditorPasteAtEndOfFigureList => 'フィギュアリストの末尾にペースト';

  @override
  String get danceEditorTypeFigureLabel => 'フィギュアを入力';

  @override
  String get danceEditorTypeFigureHelper =>
      '例: 「neighbor balance & swing」または「16 circle left 3/4」。Enterキーで追加します。認識されないテキストはカスタムフィギュアとして保持されます。';

  @override
  String get danceEditorPasteHere => 'ここにペースト';

  @override
  String get danceEditorEmptyFigureName => '空のフィギュア';

  @override
  String get danceEditorCustomFigureName => 'カスタムフィギュア';

  @override
  String get danceEditorEmptyFigureSummary => '（空 — ムーブを選択してください）';

  @override
  String get danceEditorEmptyFigureSemantic => '空のフィギュア、ムーブを選択してください';

  @override
  String danceEditorFigureSummarySemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    String hasMove,
    int beats,
    String hasNote,
    String note,
    int position,
    int total,
  ) {
    String _temp0 = intl.Intl.selectLogic(importGap, {
      'yes': '、$importGapText',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(progression, {
      'yes': '、プログレッション',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': '、$_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': '、ノート: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1$_temp3$_temp4。$total件中フィギュア$position。';
  }

  @override
  String get danceEditorActivateToEditHint => '編集するにはアクティブにしてください';

  @override
  String danceEditorDragToReorderFigure(String figure) {
    return '$figureをドラッグして並べ替え';
  }

  @override
  String danceEditorFigureActionsTooltip(String figure) {
    return '$figureのアクション';
  }

  @override
  String get danceEditorMoveUp => '上に移動';

  @override
  String get danceEditorMoveDown => '下に移動';

  @override
  String get danceEditorCut => 'カット';

  @override
  String get danceEditorClearProgression => 'プログレッションをクリア';

  @override
  String get danceEditorMarkProgression => 'プログレッションとしてマーク';

  @override
  String get danceEditorGroupWithNext => 'Group with next as meanwhile';

  @override
  String danceEditorMeanwhileGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Meanwhile ($count sides)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorMeanwhileGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count concurrent figures',
      one: '1 concurrent figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats shared beats',
      one: '1 shared beat',
    );
    return 'Meanwhile group, $_temp0, $_temp1.';
  }

  @override
  String danceEditorMeanwhileSideLabel(int number) {
    return 'Side $number';
  }

  @override
  String danceEditorMeanwhileSideSemantic(int number, int total) {
    return 'Side $number of $total.';
  }

  @override
  String get danceEditorAddMeanwhileSide => 'Add side';

  @override
  String get danceEditorRemoveMeanwhileSide => 'Remove this side';

  @override
  String danceEditorMeanwhileSidesCapReached(int max) {
    return 'Maximum of $max concurrent figures.';
  }

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return '認識されないムーブ「$move」— このバージョンのタクソノミーにありません。データを保持するために読み取り専用で表示されています。ムーブが認識されるようになると再び通常通り編集できます。並べ替えや削除はできます。';
  }

  @override
  String get danceEditorFewerOptions => 'オプションを減らす';

  @override
  String danceEditorMoreOptions(int count) {
    return 'オプションをさらに表示 ($count)';
  }

  @override
  String get danceEditorAddNote => 'ノートを追加';

  @override
  String get danceEditorBoldTooltip => '太字 (*テキスト*)';

  @override
  String get danceEditorUnderlineTooltip => '下線 (_テキスト_)';

  @override
  String get danceEditorCustomFigureTextLabel => 'カスタムフィギュアのテキスト';

  @override
  String get danceEditorLingoStylingHelper => 'ムーブ名は点線下線、ロール用語は下線、非推奨用語は取り消し線';

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return '合計: $total / $expected拍';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return '$beats拍超過';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return '$beats拍不足';
  }

  @override
  String get danceEditorLessTooltip => '少なく';

  @override
  String get danceEditorTurnNotStated => '未指定';

  @override
  String get danceEditorTurnClearTooltip => 'クリア（未指定）';

  @override
  String get danceEditorMoreTooltip => '多く';

  @override
  String danceEditorTurnCount(num count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formattedターン',
    );
    return '$_temp0';
  }

  @override
  String get commonBack => '戻る';

  @override
  String get commonRemove => '削除';

  @override
  String updateBannerDownloading(String appName, String version) {
    return '$appName $versionをダウンロード中…';
  }

  @override
  String updateBannerDownloadingPct(String appName, String version, int pct) {
    return '$appName $versionをダウンロード中… $pct%';
  }

  @override
  String updateBannerVerifying(String appName, String version) {
    return '$appName $versionを検証中…';
  }

  @override
  String get updateBannerPreparingInstaller => 'インストーラーを準備中…';

  @override
  String updateBannerCompletedRevealed(String appName, String version) {
    return '$appName $versionをダウンロードして検証しました — インストーラーをファイルマネージャーで表示しました。実行してアップデートを完了してください。';
  }

  @override
  String updateBannerCompletedManual(String appName, String version) {
    return '$appName $versionをダウンロードしました — インストーラーに従ってアップデートを完了してください。';
  }

  @override
  String get updateBannerDownloadFailed => 'アップデートをダウンロードできませんでした。';

  @override
  String updateBannerAvailable(String appName, String version) {
    return '$appNameの新しいバージョン（$version）が利用可能です。';
  }

  @override
  String get updateBannerViewRelease => 'リリースを見る';

  @override
  String get updateBannerDismiss => '閉じる';

  @override
  String get updateBannerDownloadInstall => 'ダウンロードしてインストール';

  @override
  String get commandPaletteBarrierLabel => 'グローバル検索';

  @override
  String get commandPaletteSearchHint => 'ダンスとプログラムを検索…';

  @override
  String get commandPaletteProgramSubtitle => 'プログラム';

  @override
  String get commandPaletteEmptyInitial => 'まだ検索できるものがありません。';

  @override
  String get commandPaletteNoMatches => 'その検索に一致するものがありません。';

  @override
  String get commandPaletteGroupDances => 'ダンス';

  @override
  String get commandPaletteGroupPrograms => 'プログラム';

  @override
  String get collectionPickerSearchLabel => '追加するダンスを検索';

  @override
  String collectionPickerFilters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'フィルター（$count件有効）',
      zero: 'フィルター',
    );
    return '$_temp0';
  }

  @override
  String collectionPickerByPhrase(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'フレーズで絞り込み（$count件有効）',
      zero: 'フレーズで絞り込み',
    );
    return '$_temp0';
  }

  @override
  String get collectionPickerAdvanced => '詳細検索';

  @override
  String get collectionPickerUseAdvancedQuery => '詳細クエリを使用';

  @override
  String get collectionPickerAdvancedQueryHelp =>
      'フィギュアとシーケンスをすべて/いずれか/なしのグループで組み合わせます。';

  @override
  String collectionPickerAddSemantic(String title) {
    return '$titleをプログラムに追加';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return '$titleを追加';
  }

  @override
  String get userGuideTitle => 'ユーザーガイド';

  @override
  String userGuideMissing(String label) {
    return '「$label」ガイドはまだ利用できません。';
  }

  @override
  String get userGuideLoadError => 'ユーザーガイドを読み込めませんでした。';

  @override
  String get userGuideOpenOnline => 'ガイドをオンラインで開く';

  @override
  String get shorthandMappingsTitle => 'フィギュアのショートハンド';

  @override
  String get shorthandMappingsIntro =>
      'ショートハンドを使うと、フリーテキスト入力時に短いトークンを入力してここで設定した1つ以上のフィギュアに展開できます。';

  @override
  String get shorthandMappingsNew => '新しいショートハンド';

  @override
  String get shorthandMappingsEmpty => 'ショートハンドがまだありません。';

  @override
  String get shorthandMappingsDeleteTitle => 'ショートハンドを削除しますか？';

  @override
  String shorthandMappingsDeleteBody(String token) {
    return '「$token」は完全に削除されます。';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'ショートハンドのアクション';

  @override
  String get shorthandEditorTitleNew => '新しいショートハンド';

  @override
  String get shorthandEditorTitleEdit => 'ショートハンドを編集';

  @override
  String get shorthandEditorTokenLabel => 'ショートハンド';

  @override
  String get shorthandEditorTokenHelper =>
      'フリーテキスト入力時にこの正確な行を入力すると、下のフィギュアが挿入されます。大文字と小文字を区別せずに一致します。';

  @override
  String get shorthandEditorExpandsTo => '展開先';

  @override
  String get shorthandEditorExpandsToHelp =>
      'このショートハンドが挿入するフィギュア（順番通り）。通常のフィギュアと全く同様に構築するため、パラメーターと検証は同じです。';

  @override
  String get shorthandEditorErrorEmpty => 'ショートハンドトークンを入力してください。';

  @override
  String shorthandEditorErrorTooLong(int max) {
    return 'ショートハンドが長すぎます（最大$max文字）。';
  }

  @override
  String shorthandEditorErrorDuplicate(String token) {
    return '別のショートハンドがすでに「$token」を使用しています（大文字と小文字を区別せずに一致します）。';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'このショートハンドの展開先に少なくとも1つのフィギュアを追加してください。';

  @override
  String get importShorthandSeedTitle => 'Seed figure shorthands';

  @override
  String get importShorthandSeedIntro =>
      'Your Caller\'s Companion file\'s call buttons can become figure shorthands. Pick the ones you want; each expands to the figures shown. Nothing is added until you confirm, and your existing shorthands are never overwritten.';

  @override
  String get importShorthandSeedAvailableHeader => 'From your call buttons';

  @override
  String get importShorthandSeedUsePrimary => 'Primary';

  @override
  String get importShorthandSeedUseAlt => 'Alternate';

  @override
  String get importShorthandSeedConflictHeader => 'Already defined — skipped';

  @override
  String importShorthandSeedConflictNote(String token) {
    return 'A shorthand named “$token” already exists, so this button was left as-is.';
  }

  @override
  String get importShorthandSeedSkip => 'Skip';

  @override
  String importShorthandSeedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seed $count shorthands',
      one: 'Seed 1 shorthand',
      zero: 'Seed shorthands',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seeded $count shorthands',
      one: 'Seeded 1 shorthand',
    );
    return '$_temp0';
  }

  @override
  String get themeEditorTitle => 'テーマを編集';

  @override
  String get themeEditorNameLabel => 'テーマ名';

  @override
  String get themeEditorContrastAllPass =>
      'チェックされたすべてのペアがWCAG AAコントラストをパスしています。';

  @override
  String themeEditorContrastFailing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のコントラストペアがWCAG AA未満です。保存はできますが、一部のテキストが読みにくい場合があります。',
    );
    return '$_temp0';
  }

  @override
  String themeEditorRatioPass(String ratio) {
    return '$ratio:1 AA';
  }

  @override
  String themeEditorRatioFail(String ratio) {
    return '$ratio:1 不合格';
  }

  @override
  String get themeEditorPreviewHeading => 'Aa プレビュー';

  @override
  String get themeEditorBodySample => '本文テキストのサンプル';

  @override
  String get themeEditorSwatchPrimary => 'プライマリ';

  @override
  String get themeEditorSwatchSecondary => 'セカンダリ';

  @override
  String get themeEditorSwatchTertiary => 'ターシャリ';

  @override
  String get themeEditorSwatchError => 'エラー';

  @override
  String get reparseConfirmTitle => 'カスタムフィギュアをアップグレードしますか？';

  @override
  String reparseConfirmBody(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンス',
    );
    String _temp1 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount件のフィギュア',
    );
    return '$_temp0内の$_temp1を再解析します。各ダンスのタグ、評価、ノート、その他すべてはそのまま保持されます。既知のムーブが認識されたフィギュアのみが置き換えられます。';
  }

  @override
  String get reparseConfirmUpgrade => 'アップグレード';

  @override
  String get reparseFailed => 'フィギュアをアップグレードできませんでした。もう一度お試しください。';

  @override
  String get reparseNothingUpgradedSnack => 'アップグレードするものがありません。';

  @override
  String reparseUpgradedSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンス',
    );
    return '$_temp0のカスタムフィギュアをアップグレードしました。';
  }

  @override
  String get reparseScreenTitle => 'カスタムフィギュアを再確認';

  @override
  String reparseIntro(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンス',
    );
    String _temp1 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount件のフィギュア',
    );
    return 'フィギュア解析の改善により、$_temp0内の$_temp1をアップグレードできます。以下で確認してから承認してください — 承認するまで何も変更されず、タグ、評価、ノートはすべて保持されます。';
  }

  @override
  String reparsePreviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフィギュア',
    );
    return '$_temp0をアップグレード予定';
  }

  @override
  String reparseUpgradeButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンス',
    );
    return '$_temp0をアップグレード';
  }

  @override
  String get reparseEmptyTitle => 'アップグレードするものがありません';

  @override
  String get reparseEmptyBody =>
      '現時点では、インポートされたカスタムフィギュアの中に既知のムーブとして認識できるものはありません。将来のアップデートでフィギュア解析が改善されたら再確認してください。';

  @override
  String get reparseErrorTitle => 'フィギュアを確認できませんでした';

  @override
  String get reparseErrorBody =>
      'コレクションのスキャン中に問題が発生しました。何も変更されていません。もう一度お試しください。';

  @override
  String get customFieldsDeleteTitle => 'カスタムフィールドを削除';

  @override
  String customFieldsDeleteBody(String label) {
    return '「$label」を削除しますか？この操作は元に戻せません。';
  }

  @override
  String customFieldsDeleteInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
    );
    return '「$label」を削除できません: まだ$_temp0で使用されています。すべてのダンスから値を削除してから実行してください。';
  }

  @override
  String customFieldsDeleteInUseUnknown(String label) {
    return '「$label」を削除できません: まだいくつかのダンスで使用されています。すべてのダンスから値を削除してから実行してください。';
  }

  @override
  String get customFieldsTitle => 'カスタムフィールド';

  @override
  String get customFieldsNewField => '新しいフィールド';

  @override
  String get customFieldsLoadError => 'カスタムフィールドを読み込めませんでした。';

  @override
  String get customFieldsEmpty => 'カスタムフィールドがまだありません。\n+ボタンをタップして定義してください。';

  @override
  String get customFieldsFlagInList => 'リストに表示';

  @override
  String get customFieldsSearchable => '検索可能';

  @override
  String get customFieldsTypeText => 'テキスト';

  @override
  String get customFieldsTypeNumber => '数値';

  @override
  String get customFieldsTypeBoolean => 'ブール値';

  @override
  String get customFieldsTypeChoice => '選択肢';

  @override
  String get customFieldsValidatorMinChoice => '少なくとも1つの選択肢を追加してください';

  @override
  String customFieldsRemoveValueError(String value) {
    return '「$value」を削除できません: 少なくとも1件のダンスに設定されています。';
  }

  @override
  String get customFieldsEditorNewTitle => '新しいカスタムフィールド';

  @override
  String get customFieldsEditorEditTitle => 'カスタムフィールドを編集';

  @override
  String get customFieldsLabelLabel => 'ラベル *';

  @override
  String get customFieldsLabelRequired => 'ラベルが必要です';

  @override
  String get customFieldsKeyLabel => 'キー *';

  @override
  String get customFieldsKeyHelper =>
      '安定したマシンキー（文字、数字、アンダースコア；文字またはアンダースコアで始まる必要があります）';

  @override
  String get customFieldsKeyLocked => 'キーはロックされています — フィールドはダンスで使用中';

  @override
  String get customFieldsKeyRequired => 'キーが必要です';

  @override
  String get customFieldsKeyInvalid =>
      'キーは文字またはアンダースコアで始まり、文字、数字、アンダースコアのみを含む必要があります';

  @override
  String get customFieldsTypeFieldLabel => 'タイプ';

  @override
  String get customFieldsTypeLocked => 'タイプはロックされています — フィールドにはダンスの値があります';

  @override
  String get customFieldsShowInList => 'リストに表示';

  @override
  String get customFieldsShowInListSubtitle => 'ダンスリストのタイルにこのフィールドの値を表示します';

  @override
  String get customFieldsSearchableSubtitle => '検索パネルのフィルターとしてこのフィールドを公開します';

  @override
  String get customFieldsChoicesLabel => '選択肢 *';

  @override
  String get customFieldsChoiceInUseTooltip => '使用中 — 削除できません';

  @override
  String get customFieldsNewChoiceHint => '新しい選択肢…';

  @override
  String get customFieldsAddChoiceTooltip => '選択肢を追加';

  @override
  String get customFieldsChoiceDuplicate => 'その選択肢はすでに存在します。';

  @override
  String get customFieldsChoiceEmpty => '選択肢を入力してください。';

  @override
  String customFieldsAddOptionTooltip(String label) {
    return '$labelに選択肢を追加';
  }

  @override
  String customFieldsAddOptionTitle(String label) {
    return '$labelに選択肢を追加';
  }

  @override
  String dialectEditorTitle(String name) {
    return '$nameを編集';
  }

  @override
  String get dialectEditorSectionRoleTerms => 'ロール用語';

  @override
  String get dialectEditorSectionMoveSubs => 'ムーブの置き換え';

  @override
  String get dialectEditorSectionDancerSubs => 'ダンサーの置き換え';

  @override
  String get dialectEditorSectionDiscouraged => '非推奨の用語';

  @override
  String get dialectEditorSectionPreview => 'プレビュー';

  @override
  String get dialectEditorRole1 => 'ロール1';

  @override
  String get dialectEditorRole2 => 'ロール2';

  @override
  String get dialectEditorRolesHelp =>
      'ロールを空白にすると正式な用語が使用されます。省略した場合は複数形が自動導出されます。';

  @override
  String get dialectEditorSingular => '単数形';

  @override
  String get dialectEditorPlural => '複数形';

  @override
  String get dialectEditorMoveSubsAdd => 'ムーブの置き換えを追加';

  @override
  String dialectEditorMoveSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のムーブの置き換え',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorMoveSubHint => '置き換え（左右の指定には%Sを使用）';

  @override
  String get dialectEditorAddMove => 'ムーブを追加…';

  @override
  String get dialectEditorDancerSubsAdd => 'ダンサーの置き換えを追加';

  @override
  String dialectEditorDancerSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンサーの置き換え',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorDancerSubHint => '置き換え';

  @override
  String get dialectEditorAddDancerTerm => 'ダンサー用語を追加…';

  @override
  String get dialectEditorDiscouragedHelp =>
      '入力エディターでフラグが立てられる用語（取り消し線）— 入力はブロックされません。';

  @override
  String get dialectEditorDiscouragedEmpty => '非推奨の用語がありません。';

  @override
  String get dialectEditorAddTermLabel => '用語を追加';

  @override
  String get dialectEditorAddTermTooltip => '用語を追加';

  @override
  String get dialectEditorRestoreDefaults => 'デフォルトに戻す';

  @override
  String get dialectEditorPreviewHelp =>
      'このダイアレクトでレンダリングされたサンプルフィギュア。編集に合わせて更新されます。';

  @override
  String get recentlyDeletedTitle => '最近削除したアイテム';

  @override
  String get recentlyDeletedDeleteTitle => '完全に削除しますか？';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '「$title」はすぐに削除され、復元できません。';
  }

  @override
  String get recentlyDeletedDeleteConfirm => '完全に削除';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '「$title」を完全に削除しました。';
  }

  @override
  String get recentlyDeletedRestore => '復元';

  @override
  String get recentlyDeletedPurgeKept => '手動で削除するまで保持';

  @override
  String recentlyDeletedPurgeCountdown(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days日後に自動削除',
    );
    return '$_temp0';
  }

  @override
  String get recentlyDeletedPurgeScheduled => '削除予定';

  @override
  String get recentlyDeletedLoadingDances => '最近削除したダンスを読み込み中';

  @override
  String get recentlyDeletedLoadingPrograms => '最近削除したプログラムを読み込み中';

  @override
  String get recentlyDeletedEmptyDancesKept =>
      'ゴミ箱は空です。削除したダンスは手動で削除するまでここに保持されます。';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'ゴミ箱は空です。削除したダンスは削除されるまで$days日間ここに表示されます。';
  }

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'ゴミ箱は空です。削除したプログラムは削除されるまで$days日間ここに表示されます。';
  }

  @override
  String recentlyDeletedRestoredDance(String title) {
    return '「$title」をコレクションに復元しました。';
  }

  @override
  String recentlyDeletedRestoredProgram(String title) {
    return '「$title」を復元しました。';
  }

  @override
  String get venueNew => '新しい会場';

  @override
  String get venueLoadError => '会場を読み込めませんでした。';

  @override
  String get venueManagerTitle => '会場';

  @override
  String get venueManagerSearchHint => '会場を検索…';

  @override
  String get venueManagerClearSearchTooltip => '検索をクリア';

  @override
  String get venueManagerEmpty =>
      '会場がまだありません。下のボタンで追加するか、再利用可能な会場をオンにしたプログラムから追加してください。';

  @override
  String get venueManagerNoMatches => '検索に一致する会場がありません。';

  @override
  String get venueManagerDeleteTitle => '会場を削除しますか？';

  @override
  String venueManagerDeleteBody(String name) {
    return '「$name」を完全に削除しますか？この操作は元に戻せません。';
  }

  @override
  String venueManagerDeletedSnack(String name) {
    return '「$name」を削除しました';
  }

  @override
  String venueManagerDeleteBlocked(String name) {
    return '「$name」はまだプログラムにリンクされているため削除できません。まずそれらのプログラムで会場を変更または削除してください。';
  }

  @override
  String venueManagerDeleteTooltip(String name) {
    return '$nameを削除';
  }

  @override
  String get venueEditTitle => '会場を編集';

  @override
  String get venueEditorSharedNote =>
      '会場はここで開催されるすべてのプログラムで共有されます。住所、連絡先、スケジュールを編集するとすべてに反映されます。';

  @override
  String get venueEditorNameLabel => '名前 *';

  @override
  String get venueEditorNameRequired => '名前が必要です';

  @override
  String get venueEditorWebsiteLabel => 'ウェブサイト';

  @override
  String get venueEditorSponsorLabel => 'スポンサー／主催団体';

  @override
  String get venueEditorAddressSection => '住所';

  @override
  String get venueEditorAddress1Label => '住所1';

  @override
  String get venueEditorAddress2Label => '住所2';

  @override
  String get venueEditorCityLabel => '市区町村';

  @override
  String get venueEditorStateLabel => '都道府県';

  @override
  String get venueEditorCountryLabel => '国';

  @override
  String get venueEditorPostalLabel => '郵便番号';

  @override
  String get venueEditorPlus4Label => 'ZIP+4';

  @override
  String get venueEditorScheduleSection => 'スケジュール';

  @override
  String get venueEditorEventNameLabel => 'イベント名';

  @override
  String get venueEditorTimeLabel => '時間';

  @override
  String get venueEditorScheduleLabel => 'スケジュール（例: 「第2土曜日」）';

  @override
  String get venueEditorPriceLabel => '料金';

  @override
  String get venueEditorContactsSection => '連絡先';

  @override
  String get venueEditorContact1NameLabel => '連絡先1 名前';

  @override
  String get venueEditorContact1PhoneLabel => '連絡先1 電話';

  @override
  String get venueEditorContact1EmailLabel => '連絡先1 メール';

  @override
  String get venueEditorContact2NameLabel => '連絡先2 名前';

  @override
  String get venueEditorContact2PhoneLabel => '連絡先2 電話';

  @override
  String get venueEditorContact2EmailLabel => '連絡先2 メール';

  @override
  String get venueEditorNotesSection => 'ノート';

  @override
  String get venuePickerLoading => '会場を読み込み中…';

  @override
  String get venuePickerUnlinkTooltip => '会場のリンクを解除';

  @override
  String get venuePickerUnresolvedTitle => 'リンクされた会場が見つかりません';

  @override
  String get venuePickerUnresolvedSubtitle => '削除された可能性があります。';

  @override
  String get venuePickerClearLinkTooltip => 'リンクをクリア';

  @override
  String get venuePickerSearchHint => '会場を検索または追加…';

  @override
  String get venuePickerChangeHint => '会場を変更…';

  @override
  String venuePickerCreateOption(String name) {
    return '新しい会場「$name」を追加';
  }
}
