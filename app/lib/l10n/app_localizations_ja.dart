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
  String get danceEditorAddedMeanwhileAnnouncement => 'Meanwhileコンテナを追加しました。';

  @override
  String get danceEditorAddedModifierAnnouncement => 'モディファイアコンテナを追加しました。';

  @override
  String get danceEditorAddedSequenceAnnouncement => 'シーケンスコンテナを追加しました。';

  @override
  String get navCollection => 'コレクション';

  @override
  String get settingsDefaultsMeanwhileTitle => 'Meanwhileのデフォルト';

  @override
  String get settingsDefaultsMeanwhileSubtitle =>
      'Meanwhileコンテナを追加すると挿入されるサイドのフィギュアです。空にすると2つの空のサイドになり、1つだけ設定すると空のサイドが1つ追加されます。挿入後にコンテナを編集できます。';

  @override
  String get settingsDefaultsModifierTitle => 'モディファイアのデフォルト';

  @override
  String get settingsDefaultsModifierSubtitle =>
      'モディファイアコンテナを追加したときに挿入されるフィギュアです。空にすると空のフィギュア2つになり、設定済みのフィギュア1つには空のフィギュアが1つ追加されます。';

  @override
  String get navPrograms => 'プログラム';

  @override
  String get navSettings => '設定';

  @override
  String get navGlossary => '用語集';

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
  String get menuFile => 'ファイル';

  @override
  String get menuNewDance => '新規ダンス';

  @override
  String get menuImportDances => 'ダンスをインポート…';

  @override
  String get menuClose => '閉じる';

  @override
  String get menuSettings => '設定…';

  @override
  String get menuView => '表示';

  @override
  String get menuWindow => 'ウインドウ';

  @override
  String get menuHelp => 'ヘルプ';

  @override
  String get menuUserGuide => 'ユーザーガイド';

  @override
  String get appBootstrapPreparing => 'ライブラリを準備しています';

  @override
  String get appBootstrapRebuildingIndex => '検索インデックスを再構築しています';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return '検索インデックスを再構築しています… $percent%';
  }

  @override
  String get appBootstrapError => 'ライブラリを準備できませんでした。もう一度お試しください。';

  @override
  String get appBootstrapCopyDetails => '詳細をコピー';

  @override
  String get appBootstrapCopiedDetails => 'コピーしました';

  @override
  String get appBootstrapLogHint => '詳細は、アプリのサポートフォルダ内の診断ログにも書き込まれました。';

  @override
  String get appBootstrapReleasesLink => 'Releases ページを開く';

  @override
  String migrationDowngradeVersions(int fileVersion, int appVersion) {
    final intl.NumberFormat fileVersionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String fileVersionString = fileVersionNumberFormat.format(
      fileVersion,
    );
    final intl.NumberFormat appVersionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String appVersionString = appVersionNumberFormat.format(appVersion);

    return 'お使いのデータの保存形式はバージョン $fileVersionString です。このバージョンのアプリは形式 $appVersionString まで読み込めます。';
  }

  @override
  String get migrationDowngradeMessage =>
      'このデータは新しいバージョンのCaller’s Compendiumで作成されました。アプリを更新してから、もう一度開いてください。';

  @override
  String get migrationRelocationBothExist =>
      '保存データのファイルが新しい場所と以前のバージョンが使っていたフォルダーの両方で見つかったため、Caller’s Compendium を起動できませんでした。変更や削除は行われていません。残したいほうのコピーを選び、もう一方を別の場所へ移動してから、アプリをもう一度開いてください。FAQの「データはどこに保存されますか？」に保存場所が記載されています。';

  @override
  String get migrationRelocationMultipleLegacy =>
      '保存データが以前のバージョンが使っていた複数のフォルダーで見つかったため、Caller’s Compendium を起動できませんでした。変更や削除は行われていません。残したいコピーを選び、ほかのコピーを別の場所へ移動してから、アプリをもう一度開いてください。FAQの「データはどこに保存されますか？」に保存場所が記載されています。';

  @override
  String get migrationRelocationFailed =>
      '保存データを新しい場所へ移す処理を完了できなかったため、Caller’s Compendium を起動できませんでした。削除されたデータはありません。空き容量を確保するか、データを使用している可能性のある他のプログラムを閉じるか、フォルダーのアクセス権を確認してから、アプリをもう一度開いて再試行してください。';

  @override
  String get migrationRelocationLegacyUnreachable =>
      '以前のバージョンが保存データを置いていた「書類」(Documents)フォルダーにアクセスできなかったため、Caller’s Compendium を起動できませんでした。変更や作成は行われていません。「書類」フォルダーが別のドライブやネットワークフォルダーにある場合は、接続し直してからアプリをもう一度開いてください。「書類」フォルダーがない場合は、空のフォルダーを作成してからアプリをもう一度開いてください。詳しくはFAQの「データはどこに保存されますか？」をご覧ください。';

  @override
  String get migrationRelocationCopiesHeading =>
      '各コピーのサイズと最終更新日時（通常は、サイズが大きく最近更新されたほうがあなたのライブラリです）：';

  @override
  String get migrationRelocationCopyNewLocation => '新しい保存場所';

  @override
  String get migrationRelocationCopyDocuments => '「書類」フォルダー';

  @override
  String get migrationRelocationCopyEarlierAppFolder => '以前のアプリデータフォルダー';

  @override
  String migrationRelocationCopyDetails(
    String location,
    int kilobytes,
    String date,
  ) {
    final intl.NumberFormat kilobytesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String kilobytesString = kilobytesNumberFormat.format(kilobytes);

    return '$location：$kilobytesString KB、最終更新 $date';
  }

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return '保存データを変更する前に自動バックアップを作成できなかったため、Caller’s Compendiumを起動できませんでした。$cause空き容量を確保する（またはバックアップフォルダを修復する）か、アプリを再度開いてください。あるいは、再度開いてバックアップなしで続行することもできます。';
  }

  @override
  String get migrationSnapshotCauseDiskFull => 'デバイスの空き容量が不足しているようです。';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      '自動バックアップのフォルダーに書き込めませんでした。';

  @override
  String get migrationSnapshotCauseDatabaseInUse =>
      '別のアプリがライブラリを開いているため、今バックアップを作成すると最新の変更が含まれません。ライブラリを開いている他のアプリをすべて閉じてから、もう一度お試しください。';

  @override
  String get migrationSnapshotInUseConsentBody =>
      '保存データを変更する前に、Caller’s Compendiumは自動バックアップを作成し、問題が起きても変更を元に戻せるようにします。現在、別のアプリがライブラリを開いているため、今バックアップを作成すると最新の変更が含まれません。\n\nバックアップなしで続行して変更が中断されると、一部のダンスやプログラムが失われる可能性があります。Caller’s Compendiumを終了し、ライブラリを開いている他のアプリをすべて閉じてから、Caller’s Compendiumを再度開いてもう一度お試しください。';

  @override
  String get migrationSnapshotInUseAbortedMessage =>
      '別のアプリがライブラリを開いているため、保存データを変更する前の自動バックアップに最新の変更が含まれなくなります。そのため、Caller’s Compendiumを起動できませんでした。ライブラリを開いている他のアプリをすべて閉じてから、Caller’s Compendiumを再度開いてください。あるいは、再度開いてバックアップなしで続行することもできます。';

  @override
  String get migrationSnapshotConsentTitle => 'データをバックアップできませんでした';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return '保存データを変更する前に、Caller’s Compendiumは自動バックアップを作成し、問題が起きても変更を元に戻せるようにします。今回はそのバックアップを作成できませんでした。$cause\n\nバックアップなしで続行して変更が中断されると、一部のダンスやプログラムが失われる可能性があります。アプリを終了し、空き容量を確保（またはバックアップフォルダを修復）してから、アプリを再度開いてもう一度お試しください。';
  }

  @override
  String get migrationSnapshotConsentQuit => '終了';

  @override
  String get migrationSnapshotConsentProceed => 'バックアップなしで続行';

  @override
  String get migrationBelowFloorHeadline => 'このデータは開けないほど古いバージョンのものです';

  @override
  String migrationBelowFloorBody(String bridgeTag) {
    return 'データは復元できます。$bridgeTagをインストールし、データを更新するためにアプリを一度開いてから、このバージョンを再度インストールしてください。\n\n新しく始めたい場合は、下のオプションを使用してください。現在のデータは失われます。';
  }

  @override
  String migrationBelowFloorBodyAndroid(String bridgeTag) {
    return 'データはまだこのデバイスにありますが、このバージョンではここで更新できません。アプリをアンインストールしないでください。アンインストールするとデータが削除されます。また、Androidではこのバージョンの上に$bridgeTagをインストールすることもできません。データを残すには、「データのコピーを共有」を選んで、ファイルをアプリの外（コンピューターやクラウドストレージなど）に保存してください。$bridgeTagを入れたコンピューターでデータを更新でき、その後このアプリで復元できます。詳しくは「コンピューターで更新する方法」をご覧ください。\n\n新しく始めたい場合は、下のオプションを使用してください。現在のデータは失われます。';
  }

  @override
  String migrationBelowFloorBodyIos(String bridgeVersion) {
    return 'データはまだこのデバイスにあります。アプリを削除しないでください。削除するとデータも削除されます。TestFlightでCaller’s Compendiumを開き、「以前のビルド」でバージョン$bridgeVersionを探してください。表示されている場合は、それをインストールし、データを更新するためにアプリを一度開いてから、最新のビルドを再度インストールしてください。表示されていない場合は、「データのコピーを共有」を選んで、代わりにコンピューターで更新してください。詳しくは「コンピューターで更新する方法」をご覧ください。\n\n新しく始めたい場合は、下のオプションを使用してください。現在のデータは失われます。';
  }

  @override
  String get migrationBelowFloorShareCopy => 'データのコピーを共有';

  @override
  String get migrationBelowFloorShareBackup => 'コピーを共有';

  @override
  String get migrationBelowFloorBackupKeptInApp =>
      'バックアップはアプリの中に保存されていて、開くことはできません。コンピューターで使えるコピーを残すには、リセットする前に「コピーを共有」を選んでください。';

  @override
  String get migrationBelowFloorShareCopyFailedTitle => 'コピーを作成できませんでした';

  @override
  String get migrationBelowFloorShareCopyFailedBody =>
      '何も共有されておらず、データも変更されていません。空き容量を増やしてから、もう一度お試しください。';

  @override
  String get migrationBelowFloorComputerGuide => 'コンピューターで更新する方法';

  @override
  String migrationBelowFloorGetBridge(String bridgeTag) {
    return '$bridgeTagを入手';
  }

  @override
  String get migrationBelowFloorStartFresh => '代わりに新しく始める';

  @override
  String get migrationBelowFloorBackUpAndReset => 'バックアップしてリセット';

  @override
  String get migrationBelowFloorResetOnly => 'リセットのみ';

  @override
  String get migrationBelowFloorBackupFailedTitle => 'バックアップ失敗';

  @override
  String get migrationBelowFloorBackupFailedBody =>
      'バックアップを書き込めなかったため、データはリセットされていません。空き容量を確保してから、もう一度お試しください。';

  @override
  String get migrationBelowFloorResetConfirmTitle => 'アプリのデータをリセットしますか？';

  @override
  String get migrationBelowFloorResetConfirmBody =>
      'バックアップは保存されました。リセットすると、現在のデータが新しい空のデータベースに置き換えられます。';

  @override
  String get migrationBelowFloorResetConfirmAction => 'リセット';

  @override
  String migrationBelowFloorBackupSavedAt(String backupPath) {
    return 'バックアップの保存先：$backupPath';
  }

  @override
  String migrationBelowFloorDiagnosticLogSavedAt(String logPath) {
    return '診断ログの保存先：$logPath';
  }

  @override
  String get migrationBelowFloorResetOnlyConfirmBody =>
      'バックアップは作成されません。リセットすると、現在のデータがすべて永久に削除され、新しい空のデータベースに置き換えられます。この操作は元に戻せません。';

  @override
  String get migrationBelowFloorWipeFailedTitle => 'リセットに失敗しました';

  @override
  String get migrationBelowFloorWipeFailedBody =>
      'データベースファイルを削除できませんでした。データは変更されていません。ファイルを使っている可能性のある他のアプリを閉じてから、もう一度お試しください。';

  @override
  String get confirmDeleteTitle => '削除しますか？';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '「$itemLabel」を削除します。元に戻せます。';
  }

  @override
  String confirmDeleteDancesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを削除します。元に戻せます。',
    );
    return '$_temp0';
  }

  @override
  String confirmDeleteDancesNotShownBody(int count, int notShown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを削除します（うち$notShown件は検索で非表示）。元に戻せます。',
    );
    return '$_temp0';
  }

  @override
  String confirmDeleteProgramHistoryBody(String itemLabel, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスのコーリング履歴からこのプログラムが消えます。',
    );
    return '「$itemLabel」を削除します。$_temp0元に戻せます。';
  }

  @override
  String get colorEditHexInvalid => '6桁の16進数を入力してください（例：#804020）。';

  @override
  String get colorEditHexLabel => 'HEX';

  @override
  String get colorEditChannelRed => '赤';

  @override
  String get colorEditChannelGreen => '緑';

  @override
  String get colorEditChannelBlue => '青';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsGeneralTitle => '一般';

  @override
  String get settingsProgramTitle => 'プログラム';

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
  String get settingsExperimentalTitle => '実験的';

  @override
  String get settingsDeveloperOptionsHeader => '開発者向けオプション';

  @override
  String get settingsDeveloperResetTitle => 'データベースをリセット';

  @override
  String get settingsDeveloperResetSubtitle =>
      'このデバイス上のすべてを削除し、新規インストールの状態から始め直します。';

  @override
  String get settingsDeveloperResetConfirmTitle => 'データベースをリセットしますか？';

  @override
  String get settingsDeveloperResetConfirmBody =>
      'このデバイス上のライブラリ全体（すべてのダンス、プログラム、設定、メモ）が完全に削除され、アプリはインストール直後の状態で再起動します。この操作は元に戻せません。';

  @override
  String get settingsDeveloperResetConfirmSyncNote =>
      'このデバイスは同期ストアに接続されています。孤立したデバイスとして残らないよう、最初にストアから自身を削除します。他のデバイスにまだ同期されていない内容は失われます。';

  @override
  String get settingsDeveloperResetConfirmCheckbox =>
      '元に戻せないことを理解しており、必要な場合はすでにバックアップを取っています。';

  @override
  String get settingsDeveloperResetConfirmAction => 'データベースをリセット';

  @override
  String get settingsDeveloperResetLeaveFailed =>
      'このデバイスを同期ストアから削除できなかったため、何もリセットされていません。接続を確認して、もう一度お試しください。';

  @override
  String get settingsDeveloperResetFailed =>
      'データベースをリセットできませんでした。このデバイスが同期ストアに接続されていた場合、すでにストアから切断されています。';

  @override
  String get settingsExperimentalPlaceholder => '開発中の新機能がここに表示される場合があります。';

  @override
  String get glossaryTitle => '用語集';

  @override
  String get glossarySearchHint => 'フィギュアを検索';

  @override
  String glossaryNoMatches(String query) {
    return '「$query」に一致するフィギュアはありません。';
  }

  @override
  String get glossarySelectPrompt => 'フィギュアを選択すると定義が表示されます。';

  @override
  String get glossaryCopyAsOwnFigure => 'カスタムフィギュアにコピー';

  @override
  String glossaryCustomCopiedFrom(String name) {
    return '$nameからコピー';
  }

  @override
  String get importCcTermsTitle => 'このファイルの用語';

  @override
  String get importCcTermsIntro =>
      'Caller\'s Companion ファイルに独自の用語があります。用語集に用語として追加するものを選んでください。説明は最初は定義と同じです。用語を編集すると、説明・定義・名前を変更できます。';

  @override
  String get importCcTermsNameTaken =>
      'フィギュア、ショートハンド、または用語がすでにこの名前を使っています。名前を変更して追加するか、追加しないでください。';

  @override
  String get importCcTermsNeedsDefinition => '定義がありません。編集して定義を加えると追加できます。';

  @override
  String get importCcTermsIncomplete => '名前・定義・説明がすべて必要です。編集して入力すると追加できます。';

  @override
  String get importCcTermsTooLong => '用語集の項目として長すぎます。編集して短くすると追加できます。';

  @override
  String get importCcTermsEditTitle => '用語を編集';

  @override
  String importCcTermsEditLabel(String name) {
    return '$name を編集';
  }

  @override
  String get importCcTermsSkip => 'スキップ';

  @override
  String importCcTermsConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の用語を追加',
      zero: '用語を追加',
    );
    return '$_temp0';
  }

  @override
  String importCcTermsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の用語を用語集に追加しました。',
    );
    return '$_temp0';
  }

  @override
  String importCcTermsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の用語を追加できませんでした。長すぎるか、用語集がいっぱいです。',
    );
    return '$_temp0';
  }

  @override
  String glossaryTermSource(String source) {
    return '出典: $source';
  }

  @override
  String glossaryCustomShippedNameBody(String name) {
    return 'アプリに $name という独自のフィギュアが追加されました。自分のフィギュアの名前を変更するか、ダンスをアプリのフィギュアに切り替えて自分のフィギュアを削除してください。';
  }

  @override
  String get glossaryCustomRenameMine => '自分のものの名前を変更';

  @override
  String get glossaryCustomSwitchToShipped => 'アプリのフィギュアに切り替え';

  @override
  String userFigureSwitchTitle(String name) {
    return '$name に切り替え';
  }

  @override
  String userFigureSwitchIntro(String name) {
    return '自分のフィギュアの各パラメーターが $name のどのパラメーターになるか、また各オプションがその値のどれになるかを選んでください。切り替えるには、すべてを選ぶ必要があります。';
  }

  @override
  String userFigureSwitchParam(String param) {
    return '自分の $param の切り替え先';
  }

  @override
  String userFigureSwitchChoice(String choice) {
    return '自分の $choice の切り替え先';
  }

  @override
  String userFigureSwitchNoTarget(String name, String param) {
    return '$name には自分の $param の切り替え先がありません。先にフィギュアから削除するか、代わりに自分のものの名前を変更してください。';
  }

  @override
  String userFigureSwitchAllTaken(String name, String param) {
    return '自分の $param の切り替え先になりうる $name のパラメーターは、すべて別のパラメーターに選ばれています。先にそちらの選択を変更してください。';
  }

  @override
  String get userFigureSwitchAction => '切り替え';

  @override
  String userFigureSwitchConfirmTitle(String name) {
    return '$name に切り替えますか？';
  }

  @override
  String userFigureSwitchConfirmUses(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count件のダンスが自分のフィギュアを使っており、代わりに $name を使うようになります。自分のフィギュアは用語集から削除されます。',
      zero: 'コレクションに自分のフィギュアを使っているダンスはありません。用語集から削除されます。',
    );
    return '$_temp0';
  }

  @override
  String get userFigureSwitchConfirmDefaults =>
      '既定のフィギュアもこのフィギュアを使っており、同じように切り替わります。';

  @override
  String userFigureSwitchConfirmKeepsWording(String name) {
    return '$name にないダンサーのグループを使っている箇所は、切り替わらず現在の表現のまま残ります。';
  }

  @override
  String userFigureSwitchConfirmShorthands(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のショートハンドは $name を挿入するようになります。',
    );
    return '$_temp0';
  }

  @override
  String get userFigureSwitchFailed =>
      '切り替えられませんでした。フィギュアが変更されたか、削除されています。もう一度開いて切り替えてください。';

  @override
  String get glossaryNoDefinition => '定義はまだありません。';

  @override
  String glossaryVariantOf(String figure) {
    return '$figureのバリエーションです。';
  }

  @override
  String glossaryNameWithDetail(String name, String detail) {
    return '$name（$detail）';
  }

  @override
  String get glossaryExample => '例';

  @override
  String get glossaryParameters => 'パラメーター';

  @override
  String get glossaryAlsoKnownAs => '別名';

  @override
  String get settingsExperimentalGlossaryHeader => '用語集とカスタムフィギュア';

  @override
  String get settingsExperimentalShowGlossaryTitle => '用語集を表示';

  @override
  String get settingsExperimentalShowGlossarySubtitle =>
      '組み込みフィギュアの用語集を、ナビゲーションの「プログラム」と「設定」の間に追加します。';

  @override
  String get settingsSyncHeader => 'デバイス同期';

  @override
  String get settingsSyncIntro =>
      'お手持ちのデバイス間でライブラリを同じ状態に保ちます。デバイス同期は、オンにするまでオフのままで、オフの間は何も送信されません。';

  @override
  String get settingsSyncEnableTitle => 'デバイス同期をオンにする';

  @override
  String get settingsSyncEnableSubtitle =>
      '初期設定ではオフです。オンにしても、ストアを接続するまで何も送信されません。';

  @override
  String get settingsSyncWifiOnlyTitle => 'Wi-Fi接続時のみ同期';

  @override
  String get settingsSyncWifiOnlySubtitle =>
      '初期設定ではオンです。モバイルデータ通信中は、Wi-Fiに接続するまで同期を待機します。';

  @override
  String get settingsSyncExcludeImportsTitle => '未使用の取り込んだダンスをスキップ';

  @override
  String get settingsSyncExcludeImportsSubtitle =>
      '初期設定ではオフです。取り込んだコレクションが多い場合に、このデバイスがアップロードする内容を減らします。プログラムで使われているか、他のダンスからリンクされているダンスは常に含まれます。他のデバイスから何かが削除されることはなく、オフに戻すとスキップしていたダンスが再びアップロードされます。';

  @override
  String get settingsSyncStatusHeader => 'ステータス';

  @override
  String get settingsSyncIdTitle => '同期フレーズ';

  @override
  String get settingsSyncIdMasked => '非表示';

  @override
  String get settingsSyncIdShow => '同期フレーズを表示';

  @override
  String get settingsSyncIdHide => '同期フレーズを非表示';

  @override
  String get settingsSyncIdCopy => '同期フレーズをコピー';

  @override
  String get settingsSyncIdCopied =>
      '同期フレーズをコピーしました。これを持つ人は誰でも共有ライブラリを開けるため、自分のデバイスにのみ貼り付けてください。';

  @override
  String get settingsSyncIdCaution =>
      'もう一方のデバイスでこれを入力すると接続できます。共有ライブラリはそこにあるため、これを持つ人は誰でもそのライブラリを開き、同期しているすべての内容を閲覧し、接続されたすべてのデバイス上でその内容を変更または削除し、ストア全体をサーバーから削除できます。別のフレーズに変えるには、すべてのデバイスをそちらへ移す必要があります。';

  @override
  String get settingsSyncStatusNotPaired => 'まだストアに接続されていません。';

  @override
  String get settingsSyncStatusNeverSynced => '接続済みです。まだ同期されていません。';

  @override
  String settingsSyncStatusLastSynced(String when) {
    return '最終同期: $when';
  }

  @override
  String settingsSyncEndpointStatus(String url) {
    return '$url と同期中';
  }

  @override
  String settingsSyncCustomEndpointStatus(String url) {
    return 'カスタムサーバーと同期中: $url';
  }

  @override
  String settingsSyncMergedDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '重複するダンスを$count件見つけて統合しました。',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncStatusSyncing => '同期中…';

  @override
  String get settingsSyncStatusFailed => '前回の同期は失敗しました。';

  @override
  String get settingsSyncStatusSettingsUnreadable =>
      'デバイス同期の設定を読み込めなかったため、ここに表示されている設定が最新でない可能性があり、オンにしていてもデバイス同期がオフになっている可能性があります。アプリを再起動してもう一度お試しください。';

  @override
  String get settingsSyncFailureUnreachable => '同期サーバーに接続できませんでした。';

  @override
  String get settingsSyncFailureUnreachableAdvice =>
      'このデバイスがオンラインになっているか確認してください。独自のサーバーを運用している場合は、サーバーが動作していること、アドレスが正しいことを確認してください。';

  @override
  String get settingsSyncFailureTimedOut => '同期サーバーの応答に時間がかかりすぎました。';

  @override
  String get settingsSyncFailureTimedOutAdvice =>
      '通常は、接続が遅いか不安定なことが原因です。接続が安定してから、もう一度お試しください。';

  @override
  String get settingsSyncFailureServerError => '同期サーバー側で問題が発生しました。';

  @override
  String get settingsSyncFailureServerErrorAdvice =>
      'このデバイスやライブラリには問題はありません。しばらく待ってから、もう一度お試しください。何度も起こる場合は、サーバーの運営者に知らせ、ここに表示されている詳細を伝えてください。';

  @override
  String get settingsSyncFailureRateLimited =>
      '同期サーバーから、このデバイスのリクエストを減らすよう求められました。';

  @override
  String get settingsSyncFailureRateLimitedAdvice =>
      '短時間にリクエストが多すぎました。数分待ってから、もう一度お試しください。';

  @override
  String get settingsSyncFailureStoreFull => '同期サーバーは現在、これ以上保存できません。';

  @override
  String get settingsSyncFailureStoreFullAdvice =>
      '空きができるまで、このデバイスの変更は保存できません。「未使用の取り込んだダンスをスキップ」をオンにすると、このデバイスがアップロードする量を減らせる場合があります。独自のサーバーを運用している場合は、ストレージの上限を引き上げるか、ディスクの空き容量を確保してください。';

  @override
  String get settingsSyncFailureTooLarge =>
      'このデバイスがアップロードしようとしたデータが、同期サーバーで受け付けられるサイズを超えています。';

  @override
  String get settingsSyncFailureTooLargeAdvice =>
      '取り込んだコレクションが大きい場合は、「未使用の取り込んだダンスをスキップ」をオンにすると上限内に収まることがあります。独自のサーバーを運用している場合は、アップロードサイズの上限を確認してください。';

  @override
  String get settingsSyncFailureRejected => 'このデバイスが送信した内容を、同期サーバーが拒否しました。';

  @override
  String get settingsSyncFailureRejectedAdviceDefaultServer =>
      'このバージョンのアプリは同期サーバーより新しいバージョンです。変更はこのデバイスに保存されており、サーバーが更新されると同期されます。';

  @override
  String get settingsSyncFailureRejectedAdviceCustomServer =>
      'このバージョンのアプリに合わせて、同期サーバーを更新してください。';

  @override
  String get settingsSyncStatusWaiting => '同期を待っています。変更はこのデバイスに保存されています。';

  @override
  String get settingsSyncQuotaNearlyFull => 'ストアの容量がまもなくいっぱいになります。';

  @override
  String get settingsSyncQuotaExcludeImports => '未使用の取り込んだダンスをスキップ';

  @override
  String settingsSyncNoticeNewerVersionItems(String items) {
    return '別のデバイスで新しいバージョンのアプリが使われています。$itemsを受け取るには、このデバイスのアプリを更新してください。更新する前にここでそれらを編集すると、別のデバイスでの変更が失われることがあります。';
  }

  @override
  String settingsSyncNoticeCountDance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ダンス$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountProgram(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'プログラム$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountChoreographer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '作者$count名',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountTag(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'タグ$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountCustomField(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'カスタムフィールド$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountDifficulty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '難易度$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountPublishedSource(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '公開元$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountVenue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '会場$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountSetting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '設定$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountGlossaryEntry(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '自分のフィギュア$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountFigureNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'フィギュア$count件への自分のノート',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncNoticeNewerVersionUncounted =>
      '別のデバイスで新しいバージョンのアプリが使われています。その変更を受け取るには、このデバイスのアプリを更新してください。更新する前に、そのデバイスが変更したものをここで編集すると、その変更が失われることがあります。';

  @override
  String settingsSyncNoticeKeptNewerItems(String items) {
    return '新しいバージョンのアプリのために保持しています：$items。このバージョンでは表示できない詳細を含めたまま、引き続き同期されます。表示するには、このデバイスのアプリを更新してください。';
  }

  @override
  String get settingsSyncCopyDetails => '詳細をコピー';

  @override
  String get settingsSyncDetailsCopied => '詳細をコピーしました。';

  @override
  String get settingsSyncFailureAccessDenied =>
      '同期サーバーが、このデバイスの同期フレーズを受け付けませんでした。';

  @override
  String get settingsSyncFailureAccessDeniedAdvice =>
      'フレーズをもう一方のデバイスのものと照合し、サーバーアドレスが正しいことを確認してください。';

  @override
  String get settingsSyncFailureUnexpectedResponse =>
      '同期サーバーから、このアプリで扱えない応答が返されました。';

  @override
  String get settingsSyncFailureUnexpectedResponseAdvice =>
      '独自のサーバーを運用している場合は、アドレスと、このアプリが対応しているバージョンかどうかを確認してください。それ以外の場合は、アプリを更新して、後でもう一度お試しください。';

  @override
  String get settingsSyncFailurePeerUnavailable =>
      '他のデバイスのいずれかが最後に共有した内容を読み取れませんでした。';

  @override
  String get settingsSyncFailurePeerUnavailableAdvice =>
      'ストアに接続するには、そのストアを使うすべてのデバイスの最新の一覧が必要です。他のデバイスでアプリを開いて同期させてから、もう一度お試しください。もう使わないデバイスがある場合は、「他のデバイス」で削除してください。';

  @override
  String get settingsSyncFailureInternal => 'アプリ内部の問題により、同期が停止しました。';

  @override
  String get settingsSyncFailureInternalAdvice =>
      '接続やサーバーの問題ではありません。もう一度お試しください。何度も起こる場合は、設定 ▸ 診断 からログをエクスポートし、問題を報告するときに添付してください。';

  @override
  String settingsSyncFailureStep(String step) {
    String _temp0 = intl.Intl.selectLogic(step, {
      'lookup': 'ストアの検索中に停止しました。',
      'download': '他のデバイスからのダウンロード中に停止しました。',
      'upload': 'このデバイスの変更のアップロード中に停止しました。',
      'publish': 'このデバイスの変更の公開中に停止しました。',
      'createStore': 'ストアの作成中に停止しました。',
      'other': '途中で停止しました。',
    });
    return '$_temp0';
  }

  @override
  String settingsSyncFailureStatusCode(int code) {
    return 'サーバーのステータスコード: $code。';
  }

  @override
  String settingsSyncFailureDetails(String details) {
    return '詳細: $details';
  }

  @override
  String commonSyncFailed(String explanation) {
    return '同期が完了しませんでした。$explanation';
  }

  @override
  String settingsSyncNoticeAffected(String records) {
    return '対象: $records';
  }

  @override
  String get settingsSyncNoticeListSeparator => '、';

  @override
  String settingsSyncNoticeRecordNamed(String kind, String name) {
    return '$kind「$name」';
  }

  @override
  String settingsSyncNoticeRecordNotHere(String kind) {
    return '$kind（このデバイスにはありません）';
  }

  @override
  String settingsSyncNoticeRecordNewerFigures(String kind, String name) {
    return '$kind「$name」（新しいバージョンでしか読めないフィギュアを含みます）';
  }

  @override
  String settingsSyncNoticeRecordNotHereNewerFigures(String kind) {
    return 'このデバイスにない$kind（新しいバージョンでしか読めないフィギュアを含みます）';
  }

  @override
  String settingsSyncNoticeAffectedMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ほか$count件',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeFromDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '他の$count台のデバイスから。',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncDevicesFailedBecause(String explanation) {
    return 'デバイス一覧を読み込めませんでした。$explanation';
  }

  @override
  String settingsSyncAdminFailedBecause(String message, String explanation) {
    return '$message$explanation';
  }

  @override
  String get settingsSyncStatusStaleStore =>
      '前回の同期以降、このストアは別のデバイスによって置き換えられました。次回の同期で新しいストアに参加します。';

  @override
  String get settingsSyncStatusStoreUnavailable =>
      'このストアは非アクティブにより期限切れになったか、削除された可能性があります。';

  @override
  String get settingsSyncStatusStoreNotFound =>
      'この同期フレーズに一致するストアがありません。もう一方のデバイスと照合してください。';

  @override
  String get settingsSyncStatusPaused =>
      'このデバイスが使っていたストアがもう存在しないため、同期は一時停止しています。「今すぐ同期」をタップすると、もう一度選び直せます。';

  @override
  String get settingsSyncNoticeDivergence =>
      '一部の項目が2台のデバイスで同時に変更され、まだ異なっています。「同期の判断」に表示されている場合はそこで選択してください。表示されていない場合は、どちらかを編集すると解消されます。';

  @override
  String get syncConflictTitle => '残すバージョンを選択';

  @override
  String get syncConflictIntro =>
      'これらの項目は複数のデバイスで変更されており、どちらの変更を優先すべきかアプリでは判断できません。選択するまで両方のバージョンが保持されます。';

  @override
  String get syncConflictThisDevice => 'このデバイス';

  @override
  String get syncConflictOtherDevice => '別のデバイス';

  @override
  String syncConflictOtherDeviceNumbered(int number) {
    return '別のデバイス（$number）';
  }

  @override
  String get syncConflictKeepAllThisDevice => 'すべてこのデバイスのものを残す';

  @override
  String get syncConflictKeepAllOtherDevice => 'すべて別のデバイスのものを残す';

  @override
  String get syncConflictApply => '選択したものを残す';

  @override
  String get syncConflictDecideLater => 'キャンセル';

  @override
  String get syncConflictShowDifferences => '違いを表示';

  @override
  String syncConflictChangedAt(String when) {
    return '$whenに変更';
  }

  @override
  String get syncConflictOnlyHereHeader => 'このデバイスにのみあるもの';

  @override
  String get syncConflictOnlyThereHeader => '別のデバイスにのみあるもの';

  @override
  String get syncConflictDifferentHeader => 'デバイスごとに異なるもの';

  @override
  String syncConflictSameCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ほか$count件は両方で同じです',
    );
    return '$_temp0';
  }

  @override
  String syncConflictSummaryOnlyHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'このデバイスのみ$count件',
    );
    return '$_temp0';
  }

  @override
  String syncConflictSummaryOnlyThere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '別のデバイスのみ$count件',
    );
    return '$_temp0';
  }

  @override
  String syncConflictSummaryChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件が異なる',
    );
    return '$_temp0';
  }

  @override
  String syncConflictDiffersInFields(String fields) {
    return '違い：$fields';
  }

  @override
  String syncConflictComparedWith(String version) {
    return '$versionとの比較';
  }

  @override
  String get syncConflictNothingToShow => 'これらのバージョンの違いは、ここに表示されない詳細のみです。';

  @override
  String get syncConflictFiguresUnreadable => 'ここではフィギュアを比較できません。';

  @override
  String get syncConflictSlotsReordered => '同じダンスで、順序が異なります。';

  @override
  String get syncConflictSlotsDetailsDiffer => '同じダンスで、時間や代替などの詳細が異なります。';

  @override
  String get syncConflictUnknownItem => 'このデバイスにはありません';

  @override
  String syncConflictVersionLine(String device, String value) {
    return '$device：$value';
  }

  @override
  String syncConflictFieldValue(String field, String value) {
    return '$field：$value';
  }

  @override
  String get syncConflictFieldName => '名前';

  @override
  String get syncConflictCombineBoth => '両方を統合';

  @override
  String syncConflictCombineSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '両方のデバイスの$count件をすべて残します',
    );
    return '$_temp0';
  }

  @override
  String syncConflictCombineOverLimit(int count, int limit) {
    return '統合できません：合計$count件になりますが、このリストには最大$limit件までしか保存できません。';
  }

  @override
  String get syncConflictCombinePickEach =>
      '両方のデバイスでこれらが変更されています。それぞれ残すものを選んでください：';

  @override
  String get syncConflictCombineUnavailable => 'これらは統合できないため、何も変更されていません。';

  @override
  String get syncConflictCombineOverLimitError =>
      '合計するとこのリストに保存できる件数を超えるため、何も変更されていません。';

  @override
  String get syncConflictSaved => '選択を保存しました。';

  @override
  String get syncConflictUndo => '元に戻す';

  @override
  String get syncConflictReconsiderIntro =>
      '以前のバージョンからもう一度選んでください。保存するまで何も変わりません。';

  @override
  String get syncConflictUndoChanged => '選択した後に新しい変更が届いたため、何も変更されていません。';

  @override
  String get syncConflictFieldProvenance => '出典';

  @override
  String get syncConflictFieldColour => '色';

  @override
  String get syncConflictThemeBrightness => 'ライトまたはダーク';

  @override
  String syncConflictFigureWalkthrough(String text) {
    return 'ウォークスルー：$text';
  }

  @override
  String syncConflictFigureWording(String text) {
    return '言い回し：$text';
  }

  @override
  String syncConflictFigureDetailsDiffer(String figure) {
    return '$figure（その他の詳細が異なります）';
  }

  @override
  String get syncConflictLinkInGroup => '関連ダンスのグループ内';

  @override
  String get syncConflictValueNotSet => '未設定';

  @override
  String get syncConflictValueOn => 'オン';

  @override
  String get syncConflictValueOff => 'オフ';

  @override
  String syncConflictValueItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件',
      zero: 'なし',
    );
    return '$_temp0';
  }

  @override
  String syncConflictValueNamesAndMore(String names, int count) {
    return '$names ほか$count件';
  }

  @override
  String get syncConflictNone => '現在、選択が必要なものはありません。';

  @override
  String get syncConflictClockWrong =>
      'このデバイスの日付と時刻が正しくないようなので、選択を保存できませんでした。日付と時刻を修正してから、もう一度お試しください。';

  @override
  String get syncConflictFailed => '選択を保存できませんでした。もう一度お試しください。';

  @override
  String get syncSettingActiveCustomTheme => '使用中のカスタムテーマ';

  @override
  String get syncSettingActiveDialect => '使用中のダイアレクト';

  @override
  String get syncSettingLastCollectionSort => 'コレクションの並び替え（前回使用）';

  @override
  String get syncSettingLastCollectionSortDirection => 'コレクションの並び替え方向（前回使用）';

  @override
  String get syncSettingLastProgramSort => 'プログラムの並び替え（前回使用）';

  @override
  String get syncSettingLastProgramSortDirection => 'プログラムの並び替え方向（前回使用）';

  @override
  String get syncSettingDefaultCollectionSortDirection => 'コレクションの並び替え方向（既定）';

  @override
  String get syncSettingDefaultProgramSortDirection => 'プログラムの並び替え方向（既定）';

  @override
  String get syncSettingPerformStageTheme => 'パフォームモードのステージテーマ';

  @override
  String settingsSyncConflictsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の項目が2台のデバイスで変更され、選択を待っています。',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncConflictsCheckFailed => '競合を確認できませんでした。もう一度お試しください。';

  @override
  String commonSyncNowConflictsTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '今すぐ同期（$count件が選択を待っています）',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncNoticeKeptLocalCreation =>
      'このデバイスで作成された項目が、それを一度も見ていない別のデバイスによって削除されるところでした。代わりにこのデバイスで保持しました。';

  @override
  String get settingsSyncNoticeQuarantinedLocal =>
      'このデバイス上の一部の項目には、アプリが信頼できない日付が付いているため、他のデバイスに送信されていません。このデバイスの日付と時刻を確認してから、いずれかの項目を編集して新しい日付を付けてください。';

  @override
  String get settingsSyncNoticeWithheldUnreadable =>
      'このデバイス上の一部のダンスには、アプリが読み取れない保存済みのフィギュアまたはチューンが含まれているため、他のデバイスに送信されていません。何も削除されていません。いずれかを開いて、フィギュアまたはチューンを入力し直すと同期の対象になります。';

  @override
  String get settingsSyncNoticeSkippedRecord =>
      '別のデバイスからの一部のレコードは使用できず、スキップされました。他のデバイスが同じアプリのバージョンかどうか確認してから、もう一度同期してください。';

  @override
  String get settingsSyncNoticeClock =>
      '別のデバイスの時計が、このデバイスと大きくずれているようです。各デバイスの日付と時刻を確認してください。同期はそれを使って、どちらの編集が新しいかを判断します。';

  @override
  String get settingsSyncNoticeDeferredInbound =>
      '同じレコードを編集している間に別のデバイスからの更新が届いたため、適用されませんでした。次回の同期で取り込まれます。';

  @override
  String settingsSyncNoticePeerNotTaking(int count, String tag) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'デバイス $tag は同期していますが、このデバイスからの$count件の変更を受け取っていません。変更はこのデバイスに安全に残っています。そのデバイスでアプリの更新が必要か、このデバイスの日付と時刻が正しくない可能性があります。',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeAwaitingDevice(String tag) {
    return 'このデバイスの一部の新しい種類のデータは、デバイス $tag がアプリの最新バージョンに更新されるか、「他のデバイス」から削除されると同期が始まります。データはこのデバイスに安全に残っています。';
  }

  @override
  String get settingsSyncNoticeNeedsYou => '対応が必要';

  @override
  String get settingsSyncNoticeSeeDevices => '他のデバイスを表示';

  @override
  String get settingsSyncNotBackup =>
      '同期はバックアップではありません。30日間使われなかったストアは削除されるため、ファイルのバックアップは引き続き取ってください。';

  @override
  String get settingsSyncExpiryWarning =>
      'このストアはしばらく同期されておらず、30日間使われないと削除されます。接続済みのデバイスでアプリを開いて同期すると、保持できます。';

  @override
  String get settingsSyncNowTitle => '今すぐ同期';

  @override
  String get settingsSyncDisconnectTitle => 'このデバイスの接続を解除';

  @override
  String get settingsSyncDisconnectSubtitle =>
      'このデバイスでの同期を停止します。ライブラリは、このデバイスでも他のデバイスでもそのまま残ります。';

  @override
  String get settingsSyncDisconnectConfirmTitle => 'このデバイスの接続を解除しますか?';

  @override
  String get settingsSyncDisconnectConfirmBody =>
      'このデバイスは同期を停止し、同期フレーズを削除します。このデバイスのライブラリはそのまま残り、他のデバイスのライブラリも同様です。他のデバイスがこのデバイスの内容をすべて受け取っている場合、接続を解除するとこのデバイスは同期ストアから削除されます。受け取っていない場合は、「他のデバイス」で削除するまで一覧に残ります。後で再接続するにはフレーズが必要なので、手元にあることを確認してください。';

  @override
  String get settingsSyncDisconnectConfirmAction => '接続を解除';

  @override
  String get settingsSyncDisconnectFailed =>
      'このデバイスの接続を解除できませんでした。接続はまだ有効です。もう一度お試しください。';

  @override
  String get settingsSyncDevicesTitle => '他のデバイス';

  @override
  String get settingsSyncDevicesSubtitle =>
      'このストアに接続されている他のデバイスを確認し、使わなくなったデバイスを削除します。';

  @override
  String get settingsSyncDevicesScreenTitle => '他のデバイス';

  @override
  String get settingsSyncDevicesCaution =>
      '各デバイスは接続するたびに新しいランダムな識別子を自分で作成するため、ここではデバイスを名前ではなく、その識別子から取った短いタグで表示します。このデバイスは一覧に含まれませんが、他のデバイスで見分けられるよう、このデバイスのタグを下に表示しています。どれを削除すべきか分からない場合は、そのままにしておいても問題ありません。削除したデバイスは同期フレーズがあれば再び接続できます。';

  @override
  String settingsSyncDevicesThisDevice(String tag) {
    return 'このデバイス: $tag';
  }

  @override
  String settingsSyncDeviceTag(String tag) {
    return 'デバイス $tag';
  }

  @override
  String get settingsSyncDeviceLastSharedToday => '最後に変更を共有したのは今日';

  @override
  String settingsSyncDeviceLastSharedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最後に変更を共有したのは$count日前',
      one: '最後に変更を共有したのは昨日',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncDeviceLastSharedWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最後に変更を共有したのは約$count週間前',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncDeviceWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'このデバイスからの$count件の変更が、そのデバイスへの反映を待っています。',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncDevicesEmptyTitle => '他のデバイスはまだありません';

  @override
  String get settingsSyncDevicesEmptyBody => 'このストアに接続された他のデバイスはここに表示されます。';

  @override
  String get settingsSyncDevicesFailed =>
      'デバイス一覧を読み込めませんでした。接続を確認して、もう一度お試しください。';

  @override
  String get settingsSyncDevicesStoreMissing =>
      'このストアはサーバー上に存在しないため、表示できるデバイスはありません。';

  @override
  String get settingsSyncDevicesRetry => 'もう一度試す';

  @override
  String get settingsSyncDeviceRemoveTooltip => 'このデバイスを削除';

  @override
  String get settingsSyncDeviceRemoveTitle => 'このデバイスを削除しますか?';

  @override
  String get settingsSyncDeviceRemoveBody =>
      'そのデバイスが共有した内容の一覧がストアから削除され、使っていた枠が解放されます。そのデバイスからも、このデバイスからも、データは削除されません。これは完全に使わなくなったデバイス向けの操作です。削除してもそのデバイスの接続は解除されないため、まだ動作しているデバイスは次回の同期で一覧を再び公開します。また、どのデバイスも同期フレーズがあれば再接続できます。';

  @override
  String get settingsSyncDeviceRemoveAction => '削除';

  @override
  String get settingsSyncDeviceRemoveFailed =>
      'そのデバイスを削除できませんでした。まだ接続されています。もう一度お試しください。';

  @override
  String get settingsSyncWipeTitle => 'すべてのデバイスの接続を解除してストアを削除';

  @override
  String get settingsSyncWipeSubtitle => 'このストアの内容をすべてのデバイスから一度に削除します。取り消せません。';

  @override
  String get settingsSyncWipeConfirmTitle => 'このストアをサーバーから削除しますか?';

  @override
  String get settingsSyncWipeConfirmBody =>
      'ストアの内容がサーバーからすべて削除され、すべてのデバイスに一度に影響します。この操作は取り消せません。ライブラリはこのデバイスにも他のデバイスにもそのまま残りますが、同期を通じて他のデバイスにしか届いていなかったものは、ここには届きません。このデバイスは接続を解除し、同期フレーズを削除します。他のデバイスは次回の同期でストアがなくなっていることに気づき、新しいフレーズの設定を提案します。このストアのアドレスを使うのをやめたいときに使ってください。ストアの内容をただちに取り除ける唯一の方法です。同期を続けるには、各デバイスで新しいフレーズを設定してください。古いフレーズで再接続すると、同じアドレスに新しいストアが再び作られます。';

  @override
  String get settingsSyncWipeConfirmAction => 'ストアを削除';

  @override
  String get settingsSyncWipeFailed =>
      'ストアを削除できなかったか、削除されたことを確認できませんでした。このデバイスはまだ接続されています。もう一度試す前に、他のデバイスを確認してください。';

  @override
  String get settingsSyncWipeDetachFailed =>
      'ストアはサーバーから削除されましたが、このデバイスの接続を解除できませんでした。ストアは失われ、元に戻すことはできません。「このデバイスの接続を解除」で完了してください。';

  @override
  String get settingsSyncWipeDetachFailedTitle =>
      'ストアは削除されましたが、このデバイスはまだ接続されています';

  @override
  String get settingsSyncMeteredRouted =>
      'モバイルデータ通信中で、「Wi-Fi接続時のみ同期」がオンです。今すぐ同期するには、下のこの設定をオフにしてください。';

  @override
  String get settingsSyncOffline => '現在接続がありません。次の機会に同期が実行されます。';

  @override
  String get settingsSyncNotPairedNow => '同期する前にストアを接続してください。';

  @override
  String get commonSyncNowTooltip => '今すぐ同期';

  @override
  String get commonSyncMeteredBlocked =>
      'モバイルデータ通信中で、「Wi-Fi接続時のみ同期」がオンです。今すぐ同期するには、設定でこの設定をオフにしてください。';

  @override
  String get settingsSyncConnectTitle => '接続';

  @override
  String get settingsSyncPairingTitle => 'デバイス同期を接続';

  @override
  String get settingsSyncPairingChooseHeading =>
      'これは最初のデバイスですか、それとも追加のデバイスですか?';

  @override
  String get settingsSyncPairingCreateTitle => '新しいストアを作成';

  @override
  String get settingsSyncPairingCreateSubtitle =>
      '最初から始めます。他のデバイスに読み上げるためのフレーズが表示されます。';

  @override
  String get settingsSyncPairingConnectTitle => '既存のストアに接続';

  @override
  String get settingsSyncPairingConnectSubtitle =>
      'すでに設定済みのデバイスに表示されているフレーズを入力してください。';

  @override
  String get settingsSyncPairingYourPhrase => '同期フレーズ';

  @override
  String get settingsSyncPairingYourPhraseHelper =>
      'ハイフンで区切られた4つの単語です。生成されたフレーズをそのまま使うか、自分で入力してください。';

  @override
  String get settingsSyncPairingRegenerate => '別のフレーズを生成';

  @override
  String get settingsSyncPairingPersonalInfoTitle => 'フレーズに個人情報を入れないでください';

  @override
  String get settingsSyncPairingPersonalInfoBody =>
      '自分でフレーズを入力する場合は、氏名、住所、生年月日など自分に関する情報を含めないでください。フレーズはリクエストのたびにサーバーへ送られ、接続する各デバイスで読み上げたり入力したりします。私的な情報を書き込む場所ではなく、箱の外側に書く宛名のようなものだと考えてください。';

  @override
  String get settingsSyncPairingWeakPhraseTitle => 'このフレーズは推測されやすい可能性があります';

  @override
  String get settingsSyncPairingWeakPhraseBody =>
      '推測した人は、同期するすべてのデータを閲覧・変更できます。生成されたフレーズのほうがはるかに推測されにくくなります。このまま使用することもできます。';

  @override
  String get settingsSyncPairingEnterPhrase => '同期フレーズ';

  @override
  String get settingsSyncPairingEnterPhraseHint => '単語-単語-単語-単語';

  @override
  String get settingsSyncPairingEndpointLabel => 'サーバー';

  @override
  String get settingsSyncPairingEndpointHelper =>
      '独自の同期サーバーを運用している場合を除き、このままにしてください。';

  @override
  String get settingsSyncPairingInvalidPhrase => '完全な同期フレーズのようには見えません。';

  @override
  String get settingsSyncPairingInvalidEndpoint =>
      'このサーバーアドレスは無効です。ユーザー名や ?・# 以降の部分を含まない https:// のアドレスを使用してください(http:// は localhost または 127.0.0.1 の場合のみ使用できます)。';

  @override
  String get settingsSyncPairingNotFound =>
      'そのフレーズに一致するストアがありません。もう一方のデバイスと照合して、もう一度お試しください。';

  @override
  String get settingsSyncPairingAlreadyInUse =>
      'そのフレーズはすでに別のストアで使用されています。別のフレーズを生成してください。';

  @override
  String settingsSyncPairingCustomEndpointTitle(String host) {
    return 'カスタムサーバー: $host';
  }

  @override
  String get settingsSyncPairingCustomEndpointBody =>
      'これはデフォルトのデバイス同期サーバーではありません。このサーバーの運営者は、同期するすべてのデータを閲覧・変更・削除できます。信頼できるサーバーのみを使用してください。';

  @override
  String get settingsSyncPairingSharingTitle => '共有は共同編集ではありません';

  @override
  String get settingsSyncPairingSharingBody =>
      'もう一人が同じフレーズを自分のデバイスで使用できます。同じダンスやプログラムを同時に編集すると、一方の編集がもう一方を警告なく静かに上書きし、両方を統合する方法はありません。';

  @override
  String get settingsSyncPairingNewerDataTitle => 'すべてのデバイスでアプリを最新にしてください';

  @override
  String get settingsSyncPairingNewerDataBody =>
      'このバージョンは、以前のバージョンのアプリでは読み取れない一部のデータを同期します。接続する前に各デバイスをアップデートしてください。以前のバージョンのデバイスは接続できない場合があります。接続中のすべてのデバイスが最新になるまで、それらのデータは他のデバイスに送信されません。';

  @override
  String get settingsSyncPairingBearerTitle => 'このフレーズを持つ人は誰でもライブラリを開けます';

  @override
  String get settingsSyncPairingBearerBody =>
      'フレーズは共有ライブラリの置き場所であり、その手前にあるパスワードではありません。サインインするものは何もありません。フレーズを渡した相手も、たまたま知った人も、自分のデバイスからそのライブラリを開けます。同期しているすべての内容を閲覧し、届いている場所すべてでその内容を変更または削除し、全体をサーバーから削除できます。できることを絞ったフレーズというものは存在しません。';

  @override
  String get settingsSyncPairingCredentialTitle =>
      'このフレーズの控えはどこにもなく、取り消すこともできません';

  @override
  String get settingsSyncPairingCredentialBody =>
      'このフレーズを知っているものは他にどこにもありません。紛失すると、その場所にあるライブラリはそのまま残り、誰も再び到達できなくなります。誰かにフレーズを伝えたことも、なかったことにはできません。すべてのデバイスを新しいフレーズに移しても、別の場所に2つ目のライブラリを作るだけです。最初のライブラリはそのまま残り、古いフレーズを持ち続けている人はそれを開いて変更できます。それをただちに取り除けるのはストアの削除だけです。';

  @override
  String get settingsSyncPairingBackupOfferTitle => '先にライブラリをバックアップしますか?';

  @override
  String get settingsSyncPairingBackupOfferBody =>
      'これは任意で、あくまでご自身の安全のためのものです — 接続自体は何もバックアップしません。';

  @override
  String get settingsSyncPairingBackupOfferAccept => '今すぐバックアップ';

  @override
  String get settingsSyncPairingBackupOfferSkip => '今はしない';

  @override
  String get settingsSyncPairingContinue => '続ける';

  @override
  String get settingsSyncPairingComplete => '接続しました';

  @override
  String get settingsSyncPairingCompleteBody => 'ライブラリが接続され、最初の同期が完了しました。';

  @override
  String get settingsSyncPairingCompleteFailed =>
      'ライブラリは接続されましたが、最初の同期は完了しませんでした。自動的に再試行されます。';

  @override
  String get settingsSyncPairingCompleteMetered =>
      'ライブラリが接続されました。「Wi-Fi接続時のみ同期」がオンのため、最初の同期はWi-Fiを待っています。';

  @override
  String get settingsSyncPairingCompleteOffline =>
      'ライブラリが接続されました。最初の同期はオンラインに戻り次第実行されます。';

  @override
  String get settingsSyncPairingCompletePending =>
      'ライブラリが接続されました。最初の同期はまだ実行されていません。このデバイスが次に同期するときに実行されます。';

  @override
  String get settingsSyncReplacementTitle => 'このストアはもう存在しません';

  @override
  String get settingsSyncReplacementBody =>
      'このデバイスが同期していたストアはもう存在しません。非アクティブにより期限切れになったか、削除された可能性があります。このストアのアドレスを使うのをやめるには、新しいフレーズを設定してください。このデバイスは接続を解除し、その後、新しいストアを作成するか、別のデバイスで設定したストアに接続します。これをすべてのデバイスで行ってください。「再接続」を選ぶと、同じアドレスに同じフレーズで新しいストアが作成され、ライブラリ全体がそこへ送られます。別のデバイスがすでにそうしている場合は、このデバイスはそのストアに参加します。';

  @override
  String get settingsSyncReplacementConfirm => '再接続';

  @override
  String get settingsSyncReplacementNewPhrase => '新しいフレーズで設定';

  @override
  String get settingsSyncReplacementCancel => '今はしない';

  @override
  String get settingsSyncReplacementFailed =>
      '前回の再接続は完了しませんでした。もう一度試すか、「今はしない」を選んで後で決めることもできます。';

  @override
  String get settingsAboutTitle => '情報';

  @override
  String get commonSystemDefault => 'システムのデフォルト';

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
      'Caller\'s Compendiumはフリーソフトウェアで、GNU Affero General Public License バージョン3（AGPL-3.0-only）のもとで使用許諾されています。同ライセンスに従い、自由に使用、研究、共有、改変することができます。AGPLの要件により、このアプリを使用するすべての人に完全な対応ソースコードが提供されます。';

  @override
  String get settingsAboutViewSourceTitle => 'GitHubでソースを見る';

  @override
  String get settingsAboutFontsHeader => 'フォント';

  @override
  String get settingsAboutFontsBody =>
      'このアプリにはSIL Open Font License 1.1のもとで以下のフォントが含まれています。ライセンス全文は「ライセンスを見る」から確認できます。';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — 見出しと表示用';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — 本文・UI・パフォームモード用';

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
      'ダンスデータはThe Caller\'s Box（Chris Page & Michael Dyck）を参照しており、同サイトのコレクションはCreative Commons Attribution-NonCommercial（CC BY-NC）ライセンスのもとで公開されています。感謝を込めて。';

  @override
  String get settingsAboutLicensesHeader => 'ライセンス一覧';

  @override
  String get settingsAboutViewLicensesTitle => 'ライセンスを見る';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'バンドルされているフォントを含む、オープンソースライセンスの全文。';

  @override
  String get settingsAboutLegalese =>
      '© The Caller\'s Compendium contributors. AGPL-3.0-onlyのもとで使用許諾。';

  @override
  String get settingsAboutTagline => 'コーラーの道具箱を、あなたの手のひらに';

  @override
  String settingsAboutVersion(String version, String codename) {
    return 'バージョン $version、「$codename」';
  }

  @override
  String settingsAboutVersionLine(
    String appName,
    String codename,
    String license,
  ) {
    return '$appName · 「$codename」 · $license';
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
  String settingsUpdatesStatusCouldNotCheck(String version) {
    return '現在アップデートを確認できませんでした。現在のバージョンは $version です。';
  }

  @override
  String get settingsUpdatesStatusNewerFormat =>
      '新しいバージョンが Releases ページで公開されています。';

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
  String get settingsUpdatesAutoStoreSubtitle =>
      'アプリの起動時に、このバージョンのサポート終了日をバックグラウンドで確認します。初期設定ではオフです。';

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
  String get settingsUpdatesVerifyingSubtitle =>
      'ダウンロードが完全で、改変されていないことを確認しています…';

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
  String get settingsUpdatesMacosReadyTitle => 'アップデートして再起動';

  @override
  String get settingsUpdatesMacosReadySubtitle =>
      'アップデートの準備ができました。ディスクイメージをマウントしてアプリを閉じると、「アプリケーション」フォルダ内で置き換えられます。';

  @override
  String get settingsUpdatesStoreTitle => 'アップデートはアプリストアから届きます';

  @override
  String get settingsUpdatesStoreSubtitle =>
      'このコピーはアプリストアからインストールされているため、ストアが更新します。アプリが確認するのはサポート終了日だけで、新しいバージョンは確認しません。';

  @override
  String get settingsUpdatesPortableTitle => 'ポータブル版：新しいアーカイブをダウンロード';

  @override
  String get settingsUpdatesPortableSubtitle =>
      'このコピーは展開したアーカイブから実行されているため、アプリが代わりにアップデートをインストールすることはできません。リリースから新しい zip または tar.gz をダウンロードして展開してください。';

  @override
  String get settingsUpdatesDownloadTitle => 'アップデートをダウンロードしてインストール';

  @override
  String get settingsUpdatesDownloadError =>
      'アップデートをダウンロードできませんでした。もう一度お試しください。';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'バージョン $version をダウンロードして検証し、インストーラーを起動します。アプリが自動的に上書きされることはありません。';
  }

  @override
  String get settingsDialectHeader => 'ダイアレクト';

  @override
  String get settingsDialectFormHelper =>
      'ダンスのタイプごとに独自のダイアレクトがあります。タイプを選ぶと、そのダイアレクトを表示・設定できます。';

  @override
  String get settingsDialectDanceDetailsHeader => 'ダンスの詳細と略称';

  @override
  String get settingsDialectCanonicalFigureTextTitle => '標準フィガー表記';

  @override
  String get settingsDialectCanonicalFigureTextSubtitle =>
      'オンにすると、ダンスの詳細に標準的な役割名と動きの名前を表示でき、標準以外のダイアレクトでは「標準」スイッチを使用できます。デフォルトではオフです。';

  @override
  String get settingsDialectCanonicalDiscouragedTermsTitle => 'すべての非推奨用語を自動変換';

  @override
  String get settingsDialectCanonicalDiscouragedTermsSubtitle =>
      'オンにすると、ダンスの詳細、メモ、エクスポートで、対応する非推奨用語を標準的な表現に置き換えます。保存済みのテキストと入力欄は変更されません。デフォルトでオンです。';

  @override
  String get settingsDialectNewButton => '新しいダイアレクト';

  @override
  String get settingsDialectNewDefaultName => 'マイダイアレクト';

  @override
  String get settingsDialectCreateConfirm => '作成';

  @override
  String get settingsDialectDuplicateFrom => '複製元を選択…';

  @override
  String get settingsDialectDuplicateFromOtherForm => '別のタイプから複製…';

  @override
  String get settingsDialectDuplicateFromOtherFormEmpty =>
      'ほかのダンスタイプには、まだ自分で作ったダイアレクトがありません。';

  @override
  String get settingsDialectRenameTitle => 'ダイアレクトの名前を変更';

  @override
  String get settingsDialectRename => '名前を変更';

  @override
  String get settingsDialectEditTerms => '用語を編集';

  @override
  String get settingsDialectDuplicateToCustomize => 'カスタマイズのために複製';

  @override
  String settingsDialectEditConflictSnack(String name) {
    return '「$name」は編集中に名前が変更されたか削除されたため、変更は保存されませんでした。';
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
  String get appThemeGroupSystem => 'システム';

  @override
  String get appThemeGroupDefault => 'デフォルト';

  @override
  String get appThemeGroupLight => 'ライト';

  @override
  String get appThemeGroupDark => 'ダーク';

  @override
  String get themeScreenSearchHint => 'テーマを検索…';

  @override
  String get themeScreenClearSearchTooltip => '検索をクリア';

  @override
  String get themeScreenNoMatches => '検索に一致するテーマがありません。';

  @override
  String themeScreenResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のテーマ',
    );
    return '$_temp0';
  }

  @override
  String get themeScreenNewCustomTheme => 'カスタムテーマ';

  @override
  String get themeScreenNewCustomThemeSemantic => '新しいカスタムテーマ';

  @override
  String get appThemeKeywordRed => '赤, 赤い, 紅, 深紅, コーラル, レッド';

  @override
  String get appThemeKeywordOrange => 'オレンジ, だいだい色, アンバー, 銅';

  @override
  String get appThemeKeywordYellow => '黄, 黄色, 金, 金色, からし色, イエロー';

  @override
  String get appThemeKeywordGreen => '緑, 緑色, セージ, オリーブ, 森, グリーン';

  @override
  String get appThemeKeywordTeal => '青緑, シアン, ターコイズ, 水色, ミント, ティール';

  @override
  String get appThemeKeywordBlue => '青, 青い, 紺, 藍, 空色, ブルー';

  @override
  String get appThemeKeywordPurple => '紫, 紫色, すみれ色, ライラック, ラベンダー, パープル';

  @override
  String get appThemeKeywordPink => 'ピンク, 桃色, マゼンタ, ローズ';

  @override
  String get appThemeKeywordBrown => '茶, 茶色, ベージュ, クリーム, セピア, ブラウン';

  @override
  String get appThemeKeywordGrey => '灰, 灰色, グレー, チャコール, 銀';

  @override
  String get appThemeKeywordWarm => '暖かい, 温かみ, 暖色, ウォーム';

  @override
  String get appThemeKeywordCool => '涼しい, 冷たい, 寒色, 氷, クール';

  @override
  String get appThemeKeywordPastel => 'パステル, 淡い, やわらかい';

  @override
  String get appThemeKeywordVivid => '鮮やか, ビビッド, ネオン';

  @override
  String get appThemeKeywordMuted => '落ち着いた, くすんだ, 穏やか, 控えめ';

  @override
  String get appThemeKeywordRetro => 'レトロ, ヴィンテージ, クラシック';

  @override
  String get appThemeKeywordAccessible => 'アクセシブル, 読みやすい, 見やすい, コントラスト';

  @override
  String get appThemeKeywordAutomatic => '自動, オート, デバイス, 端末';

  @override
  String get appThemeLabelSystem => 'システム';

  @override
  String get appThemeLabelLight => 'ライト';

  @override
  String get appThemeLabelDark => 'ダーク';

  @override
  String get appThemeLabelSoftDark => 'ソフトダーク';

  @override
  String get appThemeLabelHighContrast => 'ハイコントラスト';

  @override
  String get appThemeDescriptionSystem => '端末のライト/ダーク設定に合わせます';

  @override
  String get appThemeDescriptionLight => '暖かみのあるライトパレット';

  @override
  String get appThemeDescriptionDark => '暖かみのあるダークパレット';

  @override
  String get appThemeDescriptionSoftDark => 'より柔らかく明るい背景の、暖かみのあるダーク';

  @override
  String get appThemeDescriptionHighContrast => '暗い部屋や弱視向けの最大コントラスト';

  @override
  String get appThemeDescriptionBlulocoLight => 'すっきりしたクールニュートラルの背景と鮮やかな宝石色';

  @override
  String get appThemeDescriptionOneDarkPro => 'One Dark Pro、人気のエディターテーマ';

  @override
  String get appThemeDescriptionMonokai => 'One Monokai — チャコール地にMonokaiの配色';

  @override
  String get appThemeDescriptionNoctis => 'オリジナルの深いティールのNoctisの夜';

  @override
  String get appThemeDescriptionGithubLight => 'GitHubのすっきりしたニュートラルなライト';

  @override
  String get appThemeDescriptionCatppuccinLatte => '柔らかなパステルのライト、コミュニティの人気テーマ';

  @override
  String get appThemeDescriptionGruvboxLight => '暖かいレトロなクリーム色とアースカラー';

  @override
  String get appThemeDescriptionEverforestLight => '目にやさしい穏やかなグリーン';

  @override
  String get appThemeDescriptionRosePineDawn => '暖かい紙色にくすんだローズとアイリス';

  @override
  String get appThemeDescriptionAyuLight => 'アンバーのアクセントが映える明るくミニマルなライト';

  @override
  String get appThemeDescriptionTokyoNightLight =>
      'くっきりしたインディゴの昼、Tokyo Nightの日中版';

  @override
  String get appThemeDescriptionNordLight => 'クールな北極の雪嵐を思わせるニュートラル';

  @override
  String get appThemeDescriptionKanagawaLotus => '墨のアクセントが効いた、暖かい墨絵の紙';

  @override
  String get appThemeDescriptionDracula => '定番の人気、チャコール地にパープル';

  @override
  String get appThemeDescriptionNord => 'クールで控えめな北極のブルー';

  @override
  String get appThemeDescriptionTokyoNight => 'ネオンインディゴの夜の街のパレット';

  @override
  String get appThemeDescriptionGruvboxDark => 'チャコール地に暖かいレトロなアンバー';

  @override
  String get appThemeDescriptionCatppuccinMocha => '居心地のよいパステルダーク、コミュニティの人気テーマ';

  @override
  String get appThemeDescriptionGithubDark => 'GitHubのニュートラルなダーク';

  @override
  String get appThemeDescriptionEverforestDark => '疲れにくい穏やかな森の緑';

  @override
  String get appThemeDescriptionRosePine => '闇の中にくすんだローズとアイリス';

  @override
  String get appThemeDescriptionAyuMirage => 'アンバーのアクセントが映えるなめらかなスレート';

  @override
  String get appThemeDescriptionCutiePro => 'とびきりキュートなダークパステル、ピンク基調';

  @override
  String get appThemeDescriptionPinkAsHeck => 'ベリー色に堂々のホットピンク';

  @override
  String get appThemeDescriptionVitesseLight => 'モダンでくすんだセージ、ティール、ローズ';

  @override
  String get appThemeDescriptionZenburn => '定番の低コントラストな暖かいグレー';

  @override
  String get appThemeDescriptionShadesOfPurple => '深いインディゴに映える大胆なゴールド';

  @override
  String get appThemeDescriptionCatppuccinFrappe => 'やや明るい青灰色のパステルCatppuccin';

  @override
  String get appThemeDescriptionSynthwave84 => 'レトロなパープルに輝くネオン';

  @override
  String get appThemeDescriptionNoctisLilac => '穏やかなライラックのNoctisの昼';

  @override
  String get themeEditorGroupPrimary => 'プライマリ';

  @override
  String get themeEditorGroupSecondary => 'セカンダリ';

  @override
  String get themeEditorGroupTertiary => 'ターシャリ';

  @override
  String get themeEditorGroupError => 'エラー';

  @override
  String get themeEditorGroupSurfaceText => 'サーフェスとテキスト';

  @override
  String get themeEditorGroupSurfaceContainers => 'サーフェスコンテナ';

  @override
  String get themeEditorGroupOutlineEffects => 'アウトラインと効果';

  @override
  String get themeEditorRolePrimary => 'プライマリ';

  @override
  String get themeEditorRoleOnPrimary => 'プライマリ上';

  @override
  String get themeEditorRolePrimaryContainer => 'プライマリコンテナ';

  @override
  String get themeEditorRoleOnPrimaryContainer => 'プライマリコンテナ上';

  @override
  String get themeEditorRoleSecondary => 'セカンダリ';

  @override
  String get themeEditorRoleOnSecondary => 'セカンダリ上';

  @override
  String get themeEditorRoleSecondaryContainer => 'セカンダリコンテナ';

  @override
  String get themeEditorRoleOnSecondaryContainer => 'セカンダリコンテナ上';

  @override
  String get themeEditorRoleTertiary => 'ターシャリ';

  @override
  String get themeEditorRoleOnTertiary => 'ターシャリ上';

  @override
  String get themeEditorRoleTertiaryContainer => 'ターシャリコンテナ';

  @override
  String get themeEditorRoleOnTertiaryContainer => 'ターシャリコンテナ上';

  @override
  String get themeEditorRoleError => 'エラー';

  @override
  String get themeEditorRoleOnError => 'エラー上';

  @override
  String get themeEditorRoleErrorContainer => 'エラーコンテナ';

  @override
  String get themeEditorRoleOnErrorContainer => 'エラーコンテナ上';

  @override
  String get themeEditorRoleSurface => 'サーフェス';

  @override
  String get themeEditorRoleOnSurface => 'サーフェス上';

  @override
  String get themeEditorRoleOnSurfaceVariant => 'サーフェスバリアント上';

  @override
  String get themeEditorRoleInverseSurface => '反転サーフェス';

  @override
  String get themeEditorRoleOnInverseSurface => '反転サーフェス上';

  @override
  String get themeEditorRoleInversePrimary => '反転プライマリ';

  @override
  String get themeEditorRoleSurfaceContainerLowest => 'コンテナ(最低)';

  @override
  String get themeEditorRoleSurfaceContainerLow => 'コンテナ(低)';

  @override
  String get themeEditorRoleSurfaceContainer => 'コンテナ';

  @override
  String get themeEditorRoleSurfaceContainerHigh => 'コンテナ(高)';

  @override
  String get themeEditorRoleSurfaceContainerHighest => 'コンテナ(最高)';

  @override
  String get themeEditorRoleOutline => 'アウトライン';

  @override
  String get themeEditorRoleOutlineVariant => 'アウトラインバリアント';

  @override
  String get themeEditorRoleSurfaceTint => 'サーフェスティント';

  @override
  String get themeEditorRoleShadow => 'シャドウ';

  @override
  String get themeEditorRoleScrim => 'スクリム';

  @override
  String get themeEditorPairOnPrimary => 'プライマリ上のテキスト';

  @override
  String get themeEditorPairOnPrimaryContainer => 'プライマリコンテナ上のテキスト';

  @override
  String get themeEditorPairOnSecondary => 'セカンダリ上のテキスト';

  @override
  String get themeEditorPairOnSecondaryContainer => 'セカンダリコンテナ上のテキスト';

  @override
  String get themeEditorPairOnTertiary => 'ターシャリ上のテキスト';

  @override
  String get themeEditorPairOnTertiaryContainer => 'ターシャリコンテナ上のテキスト';

  @override
  String get themeEditorPairOnError => 'エラー上のテキスト';

  @override
  String get themeEditorPairOnErrorContainer => 'エラーコンテナ上のテキスト';

  @override
  String get themeEditorPairOnSurface => 'サーフェス上の本文テキスト';

  @override
  String get themeEditorPairOnSurfaceVariant => 'サーフェス上のサブテキスト';

  @override
  String get themeEditorPairOnInverseSurface => '反転サーフェス上のテキスト';

  @override
  String get themeEditorPairOutline => 'サーフェス上のアウトライン';

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
      '各ダンス行をフォーメーションファミリー（コントラ、ミキサー、スクエアなど）で着色します。ただし、そのフォーメーションに独自の色を設定している場合は、その色が優先されます。ミキサーに設定されたダンスは、フォーメーションにかかわらず常にミキサーの色が使われます。フォーメーションは常にテキストでも表示されるため、色なしでも読み取れます。';

  @override
  String get settingsAppearanceFormationColoursTitle => 'フォーメーションラベルの色';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      '個々のフォーメーションを独自の色でハイライト表示（例：Becket（CW）を黄色、Becket（CCW）をピンク）します。ダンスカード、ダンス詳細、パフォームヘッダー、セットリストの行に反映されます。';

  @override
  String get settingsAppearanceSelectedBadge => '選択済み';

  @override
  String get settingsAppearancePreviewHeading => 'Aa プレビュー';

  @override
  String get settingsAppearancePreviewBody => '本文テキストのサンプル';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'マイテーマ';

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
  String get settingsDefaultsStartingProgramTitle => '開始プログラム';

  @override
  String get settingsDefaultsStartingProgramPickerTitle => 'ダンスを追加';

  @override
  String get settingsDefaultsStartingProgramTextLabel => 'メモのテキスト';

  @override
  String get settingsDefaultsStartingProgramNoteLabel => 'caller のメモ（任意）';

  @override
  String get settingsDefaultsStartingProgramMoveUp => '上へ移動';

  @override
  String get settingsDefaultsStartingProgramMoveDown => '下へ移動';

  @override
  String get settingsDefaultsStartingProgramUnavailableDance =>
      'このダンスは利用できなくなりました';

  @override
  String get settingsDefaultsDifficultyLevelEmpty => '難易度には名前が必要です。';

  @override
  String settingsDefaultsDifficultyLevelDuplicate(String label) {
    return '「$label」という名前のレベルはすでにあります。';
  }

  @override
  String settingsDefaultsDifficultyLevelInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスが$labelを使用しています。先にそれらを変更してください。',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsDifficultyLevelActionFailed =>
      '難易度を保存できませんでした。もう一度お試しください。';

  @override
  String settingsDefaultsDifficultyLevelDeleted(String label) {
    return '「$label」を削除しました。';
  }

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
  String get settingsDefaultsSortLastUsed => '前回使用した並び順';

  @override
  String get settingsDefaultsProgramSortTitle => 'プログラムの並び順';

  @override
  String get settingsDefaultsProgramSortSubtitle =>
      'プログラム一覧を開いたときの並び順です。閲覧中に並び順を変更することもできます。';

  @override
  String get settingsDefaultsSortLastUsedSubtitle => '前回使用した並び順と方向で開きます。';

  @override
  String get settingsDefaultsSortAscending => '昇順';

  @override
  String get settingsDefaultsSortDescending => '降順';

  @override
  String get settingsDefaultsCanonicalTitle => 'ダンスの詳細を正式な用語で表示する';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      '「標準フィガー表記」がオンの場合、アクティブなダイアレクトではなく正式なロール名とムーブ名でダンスが開きます。オフの場合、詳細はアクティブなダイアレクトで開き、この設定は保持されます。';

  @override
  String get settingsDefaultsCollectionCardHeader => 'コレクションカードの項目';

  @override
  String get settingsDefaultsCollectionCardSubtitle =>
      '各ダンス行に表示する詳細を選択します。既定ではすべての項目が表示されます。';

  @override
  String get settingsDefaultsCollectionCardAuthors => '作者';

  @override
  String get settingsDefaultsCollectionCardCalledCount => '使用回数';

  @override
  String get settingsDefaultsCollectionCardFormation => 'フォーメーション';

  @override
  String get settingsDefaultsCollectionCardStatus => 'ステータス';

  @override
  String get settingsDefaultsCollectionCardLevel => 'レベル';

  @override
  String get settingsDefaultsCollectionCardRating => '評価';

  @override
  String get settingsDefaultsCollectionCardTags => 'タグ';

  @override
  String get settingsDefaultsCollectionCardCustomFields => 'カスタムフィールド';

  @override
  String get settingsDefaultsShareFieldsHeader => '共有するダンス項目';

  @override
  String get settingsDefaultsShareFieldsSubtitle =>
      'プログラムやダンスを共有・コピー・エクスポートする際に表示する項目を選択します。チューン、フック、ソースは有効にするまで非表示です。それ以外は既定で表示されます。';

  @override
  String get settingsDefaultsShareFieldsAuthors => '作者';

  @override
  String get settingsDefaultsShareFieldsFormation => 'フォーメーション';

  @override
  String get settingsDefaultsShareFieldsLevel => 'レベル';

  @override
  String get settingsDefaultsShareFieldsMixer => 'ミキサー';

  @override
  String get settingsDefaultsShareFieldsStatus => 'ステータス';

  @override
  String get settingsDefaultsShareFieldsPhraseStructure => 'フレーズ';

  @override
  String get settingsDefaultsShareFieldsCallingNotes => 'コーリングノート';

  @override
  String get settingsDefaultsShareFieldsWalkthrough => 'ウォークスルー';

  @override
  String get settingsDefaultsShareFieldsTunes => 'チューン';

  @override
  String get settingsDefaultsShareFieldsHook => 'フック';

  @override
  String get settingsDefaultsShareFieldsSources => 'ソース';

  @override
  String get settingsDefaultsShareFieldsMusic => '拍子・調・Barnes';

  @override
  String get settingsDefaultsCollectionFiltersHeader => 'コレクションのフィルター';

  @override
  String get settingsDefaultsCollectionFiltersSubtitle =>
      'コレクションを絞り込むときと、プログラム用にダンスを選ぶときに表示するフィルターを選択します。既定ではすべてのフィルターが表示されます。フィルターを非表示にすると、その選択は解除されます。';

  @override
  String get settingsDefaultsImportHeader => 'インポートのデフォルト設定';

  @override
  String get settingsDefaultsImportTagsTitle => 'インポートしたダンスのタグ';

  @override
  String get settingsDefaultsImportTagsSubtitle =>
      'インポートで新しく作成されたダンスごとに追加されます。共有されたファイルのダンスも含みます。プログラムのインポート中にその枠のために作成されたダンスにはタグは付きません。';

  @override
  String get settingsDefaultsImportTagsEmpty =>
      'まだタグがありません。エディターでダンスにタグを追加してから、ここで選択してください。';

  @override
  String get settingsDefaultsAuthoringHeader => 'ダンス作成のデフォルト設定';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'フリーテキスト入力';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'オンにすると、新しいフィギュアを追加する際に「neighbor balance & swing」のように1行で入力できます（フィールドごとに入力する代わりに）。既存のフィギュアのムーブに1行を入力してEnterキーを押すと、そのフィギュアが置き換えられます。入力した行はフィギュアに変換されます。アプリが読み取れなかった部分は認識できないフィギュアとして保存され、後で修正できます。開始フィギュアを保存していない場合、新しいダンスはフィギュアなしで始まります。';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateTitle => 'フィギュアの拍数を積極的に再計算';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle =>
      'オンにすると、フィギュアのムーブやタイミングに影響するパラメータを変更した際に、拍数が即座に再計算されます — 手動で入力した拍数も上書きされます。オフ(既定)の場合、編集した拍数が自動的に変更されるのは、バランスのオプションをオン/オフにしたときだけで、4拍が加算または減算されます。';

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
  String get settingsDefaultsFormTitle => 'タイプ';

  @override
  String get settingsDefaultsFormSubtitle =>
      '新しいダンスのデフォルトのダンスタイプです。ダンスごとに変更できます。';

  @override
  String get settingsDefaultsFormLastUsed => '前回使用したタイプ';

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
      '新しいダンスの開始フィギュアです。デフォルトは「静止」8つ（各8拍）で、フリーテキスト入力がオンの間はなしです。空白の新しいダンスにする場合はクリアしてください。ダンスごとに編集可能です。';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'ムーブのデフォルト設定';

  @override
  String get settingsDefaultsUserFiguresTitle => 'カスタムフィギュアの既定値';

  @override
  String get settingsDefaultsUserFiguresSubtitle =>
      '自分のフィギュアにはそれぞれ独自の既定値（初期値と拍数）があります。変更するには、フィギュアを選んでください。';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'ダンス入力時にムーブを挿入するときに適用される優先パラメーター値です。これらはムーブの組み込みデフォルトを上書きします。フィギュアのパラメーターは後から変更できます。設定されていないムーブとパラメーターは組み込みのデフォルトを使用します。';

  @override
  String get settingsDefaultsAddMoveButton => 'ムーブのデフォルトを追加';

  @override
  String get settingsDefaultsRemoveMoveTooltip => '削除';

  @override
  String get settingsDefaultsMoveGone => 'このムーブは利用できなくなりました。';

  @override
  String get settingsDefaultsMoveNoParams => 'このムーブにはデフォルト設定できるパラメーターがありません。';

  @override
  String get settingsFormationColoursTitle => 'フォーメーションの色';

  @override
  String get settingsFormationColoursIntro =>
      'フォーメーションに独自の色を設定すると、ダンスカード、ダンス詳細、パフォームヘッダーのラベルをハイライト表示し、セットリストの行にも色が付きます（ミキサーはミキサーの色のままです）。カスタマイズしたフォーメーションのみハイライトされ、他のフォーメーションは通常どおりラベルが表示されます。フォーメーションは常にテキストでも表示されるため、色なしでも読み取れます。';

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
  String get settingsAppearanceTagColoursHeader => 'タグの色';

  @override
  String get settingsAppearanceTagColoursTitle => 'タグの色';

  @override
  String get settingsAppearanceTagColoursSubtitle =>
      'タグに独自の色を設定すると、ダンスカードやダンスの詳細で目立つようになります。タグ名は常に表示されるため、色がなくてもタグは読み取れます。';

  @override
  String get settingsTagColoursEmptyTitle => 'タグはまだありません';

  @override
  String get settingsTagColoursEmptyBody => 'ダンスにタグを追加すると、ここに表示されます。';

  @override
  String get settingsTagColoursSaveError => 'その色を保存できませんでした。もう一度お試しください。';

  @override
  String get settingsTagColoursLoadError =>
      'タグを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get tagManagerTitle => 'タグ';

  @override
  String get tagManagerSearchHint => 'タグを検索';

  @override
  String get tagManagerNameLabel => 'タグ名';

  @override
  String get tagManagerShowDances => 'ダンスを表示';

  @override
  String get tagManagerColour => '色…';

  @override
  String get tagManagerRemoveColour => '色を削除';

  @override
  String tagManagerDeletedSnack(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「$name」を$count件のダンスから削除しました',
      zero: '「$name」を削除しました',
    );
    return '$_temp0';
  }

  @override
  String tagManagerRenamedSnack(String from, String to) {
    return '「$from」を「$to」に名前変更しました';
  }

  @override
  String tagManagerMergedSnack(String from, String into) {
    return '「$from」を「$into」に統合しました';
  }

  @override
  String tagManagerMergedSeveralSnack(int count, String into) {
    return '$count件のタグを「$into」にまとめました';
  }

  @override
  String get authorManagerTitle => '作者';

  @override
  String get authorManagerSearchHint => '作者を検索';

  @override
  String get authorManagerNameLabel => '作者名';

  @override
  String get authorManagerEmptyTitle => '作者はまだいません';

  @override
  String get authorManagerEmptyBody => 'ダンスにクレジットした作者はここに表示されます。';

  @override
  String get authorManagerLoadError => '作者を読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String authorManagerMergedSeveralSnack(int count, String into) {
    return '$count件の作者を「$into」にまとめました';
  }

  @override
  String get sourceManagerTitle => 'ソース';

  @override
  String get sourceManagerSearchHint => 'ソースを検索';

  @override
  String get sourceManagerTitleLabel => 'ソースのタイトル';

  @override
  String get sourceManagerEmptyTitle => 'ソースはまだありません';

  @override
  String get sourceManagerEmptyBody => 'ダンスで引用した書籍やウェブサイトはここに表示されます。';

  @override
  String get sourceManagerLoadError => '出典を読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get libraryManagerClearSearch => '検索をクリア';

  @override
  String get libraryManagerNotUsed => '未使用';

  @override
  String get libraryManagerSortTooltip => '並べ替え';

  @override
  String get libraryManagerSortByName => '名前';

  @override
  String get libraryManagerSortByDanceCount => 'ダンス数';

  @override
  String get libraryManagerNoMatches => '検索に一致するものはありません。';

  @override
  String libraryManagerDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
      zero: '未使用',
    );
    return '$_temp0';
  }

  @override
  String libraryManagerActionsTooltip(String name) {
    return '$nameの操作';
  }

  @override
  String get libraryManagerRename => '名前を変更';

  @override
  String libraryManagerRenameTitle(String name) {
    return '「$name」の名前を変更';
  }

  @override
  String get libraryManagerMergeInto => '統合先を選ぶ…';

  @override
  String libraryManagerMergePickerTitle(String name) {
    return '「$name」の統合先…';
  }

  @override
  String get libraryManagerMergeOfferTitle => 'その名前は使用中です';

  @override
  String libraryManagerMergeOfferOne(String existing, String from) {
    return '「$existing」はすでにあります。「$from」をそこに統合しますか？';
  }

  @override
  String libraryManagerMergeOfferOneRenamed(
    String existing,
    String from,
    String name,
  ) {
    return '「$existing」はすでにあります。「$from」をそこに統合し、名前を「$name」にしますか？';
  }

  @override
  String libraryManagerMergeOfferSeveral(String name, String from) {
    return '「$name」という名前の項目が複数あります。「$from」の統合先を選んでください。ほかの項目もそこに統合されます。';
  }

  @override
  String get libraryManagerMerge => '統合';

  @override
  String libraryManagerUndoConflict(String name) {
    return '元に戻せません：「$name」は現在ほかの項目が使っています。';
  }

  @override
  String get libraryManagerEditFailed => 'その変更を保存できませんでした。もう一度お試しください。';

  @override
  String get libraryManagerEditDetails => '詳細を編集…';

  @override
  String libraryManagerRenamedSnack(String from, String to) {
    return '「$from」を「$to」に名前変更しました';
  }

  @override
  String libraryManagerMergedSnack(String from, String into) {
    return '「$from」を「$into」に統合しました';
  }

  @override
  String libraryManagerDeletedSnack(String name) {
    return '「$name」を削除しました';
  }

  @override
  String libraryManagerMergeConfirmTitle(String from, String into) {
    return '「$from」を「$into」に統合しますか？';
  }

  @override
  String get libraryManagerMergeDropsHeading =>
      '次の詳細が異なります。統合後の項目は自身の値を保持し、以下は破棄されます：';

  @override
  String libraryManagerMergeDroppedLine(String field, String value) {
    return '$field：$value';
  }

  @override
  String get settingsGeneralLibraryHeader => 'ダンス';

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
  String get settingsGeneralProgramsHeader => 'プログラム';

  @override
  String get settingsSharingHeader => '共有';

  @override
  String get settingsSharingTitleTitle => 'セットリストを共有するときにプログラム名を含める';

  @override
  String get settingsSharingCallerBandTitle => 'セットリストを共有するときにコーラーとバンドを含める';

  @override
  String get settingsSharingDateVenueTitle => 'セットリストを共有するときに日付、時刻、会場を含める';

  @override
  String get settingsSharingSubtitle =>
      'セットリストの共有またはコピーに適用されます。プログラム全体を .ccshare または JSON ファイルとして共有する場合は、常にすべてが含まれます。';

  @override
  String get settingsGeneralMatrixExactCollisionTitle => '拍の正確な重なりのみをフラグ';

  @override
  String get settingsGeneralMatrixExactCollisionSubtitle =>
      'プログラムマトリクスでは、連続する2つのダンス間で繰り返される動きは、拍が実際に重なる場合のみフラグが立ちます。同じ名前のフレーズ（A1、A2、B1、B2…）に含まれるだけではフラグは立ちません。オフにすると、拍自体が重ならなくても、同じフレーズ内の繰り返しがすべてフラグとして表示されます。';

  @override
  String get settingsProgramAutoCommitTitle => 'プログラムの変更を自動保存';

  @override
  String get settingsProgramAutoCommitSubtitle =>
      'オンにすると、有効な変更が作業中に保存されるため、エディターを終了するときに破棄するかどうかを確認されません。オフにすると、プログラムを明示的に保存します。';

  @override
  String get settingsProgramShowPayTitle => '報酬を表示';

  @override
  String get settingsProgramShowPaySubtitle =>
      'オフにすると、エディター・概要・プログラムの表計算ファイルで報酬が非表示になります。入力済みの報酬は保持され、再びオンにすると表示されます。';

  @override
  String get settingsMatrixColumnsHeader => 'マトリクスの列';

  @override
  String get settingsMatrixColumnsSubtitle =>
      'プログラミングマトリクスに表示される列を並べ替え、名前変更、または削除します。変更はすべてのプログラムに適用されます。';

  @override
  String settingsMatrixColumnsDragToReorder(String label) {
    return 'ドラッグして$label列を並べ替え';
  }

  @override
  String get settingsMatrixColumnsRenamedBadge => '名前変更済み';

  @override
  String get settingsMatrixColumnsRenameTooltip => '列の名前を変更';

  @override
  String get settingsMatrixColumnsRemoveTooltip => '列を削除';

  @override
  String get settingsMatrixColumnsRestoreTooltip => '列を復元';

  @override
  String get settingsMatrixColumnsRenameTitle => '列の名前を変更';

  @override
  String get settingsMatrixColumnsRenameLabel => '列ラベル';

  @override
  String get settingsMatrixColumnsResetRemoved => '削除した列を復元';

  @override
  String get settingsMatrixColumnsResetTrue => 'すべての既定値に戻す';

  @override
  String get settingsMatrixColumnsResetTrueTitle => 'すべての既定値に戻しますか？';

  @override
  String get settingsMatrixColumnsResetTrueBody =>
      '列の並べ替え、名前変更、削除（カスタム列を含む）をすべて消去し、マトリクスを既定の列に戻します。この操作は元に戻せません。';

  @override
  String get settingsMatrixColumnsResetTrueConfirm => '既定に戻す';

  @override
  String get settingsMatrixColumnsParameterizedAdd => 'パラメーター付き列を追加';

  @override
  String get settingsMatrixColumnsParameterizedTitle => 'パラメーター付き列を追加';

  @override
  String get settingsMatrixColumnsParameterizedEditTitle => 'パラメーター付き列を編集';

  @override
  String get settingsMatrixColumnsParameterizedMove => 'フィギュア';

  @override
  String get settingsMatrixColumnsParameterizedConstraints => '一致させる正確なパラメーター';

  @override
  String get settingsMatrixColumnsParameterizedNoParams =>
      'このフィギュアにはパラメーターがありません。';

  @override
  String get settingsMatrixColumnsParameterizedLabel => '列名';

  @override
  String get settingsMatrixColumnsParameterizedEdit => '一致条件を編集';

  @override
  String get settingsMatrixColumnsParameterizedDelete => 'パラメーター付き列を削除';

  @override
  String get settingsMatrixColumnsCompoundAdd => '複合列を追加';

  @override
  String get settingsMatrixColumnsCompoundTitle => '複合列を追加';

  @override
  String get settingsMatrixColumnsCompoundEditTitle => '複合列を編集';

  @override
  String get settingsMatrixColumnsCompoundSteps => 'ステップ';

  @override
  String get settingsMatrixColumnsCompoundMove => 'フィギュア';

  @override
  String get settingsMatrixColumnsCompoundParameters => '完全一致パラメータ';

  @override
  String get settingsMatrixColumnsCompoundAddStep => 'ステップを追加';

  @override
  String get settingsMatrixColumnsCompoundRemoveStep => 'ステップを削除';

  @override
  String get settingsMatrixColumnsCompoundMoveUp => 'ステップを前へ移動';

  @override
  String get settingsMatrixColumnsCompoundMoveDown => 'ステップを後へ移動';

  @override
  String get settingsMatrixColumnsCompoundLabel => '列名';

  @override
  String get settingsMatrixColumnsCompoundEdit => 'シーケンスを編集';

  @override
  String get settingsMatrixColumnsCompoundDelete => '複合列を削除';

  @override
  String get settingsGeneralPerformanceHeader => 'パフォームモード';

  @override
  String get settingsGeneralAutoSizePerformTitle => 'パフォームカードのサイズを自動調整';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      '各カードを画面に収まるように調整しますが、通常の文字サイズより小さくはしません。長いダンスやスロットはスクロールで表示します。A- / A+で自分でサイズを設定する場合はオフにしてください。';

  @override
  String get settingsShowIndividualPerformTimerTitle => '1曲をパフォームするときにタイマーを表示';

  @override
  String get settingsShowIndividualPerformTimerSubtitle =>
      '1曲だけをパフォームしている間の経過時間を表示します。タイマーが表示されると開始し、一時停止できます。';

  @override
  String get settingsConfirmPerformExitTitle => 'パフォームモードを終了する前に確認する';

  @override
  String get settingsConfirmPerformExitSubtitle =>
      '閉じるボタンや戻る操作でパフォームモードを終了する前に確認します。オフにすると1回のタップで終了します。プログラムのパフォームモードでは、どちらの場合も現在の位置が保持されます。';

  @override
  String get settingsShowProgramSlotCallerNotesTitle =>
      'プログラムのパフォーム時にコーラーのメモを表示';

  @override
  String get settingsShowProgramSlotCallerNotesSubtitle =>
      'プログラムをパフォームするとき、空でないスロットごとのコーラーメモをダンス名の上に表示します。';

  @override
  String get settingsGeneralCallingHistoryHeader => 'コーリング履歴';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      'コーリング履歴には「実施済み」マークが必要';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      '「コール済み」とみなす範囲を決めます。オンにすると、コーリング履歴を参照するすべての場所（履歴リスト、コール回数 ×N、コール済みフィルター、最終コール順）で、「実施済み」とマークされたスロットのみが数えられます。オフにすると、プログラムにそのダンスが含まれていればスロットが数えられます。下の4つの設定より優先されます。';

  @override
  String get settingsGeneralShowPerformedTogglesTitle => '「実施済み」切り替えを表示';

  @override
  String get settingsGeneralShowPerformedTogglesSubtitle =>
      'オンにすると、プログラム表示の各ダンスに、エディターを開かずに実施済みかどうかをマークする切り替えが表示されます。オフにすると、行にはダンスが実施済みかどうかだけが表示されます。';

  @override
  String get settingsGeneralMarkAllSetsStatusTitle => '「すべて実施済みにする」でステータスも設定';

  @override
  String get settingsGeneralMarkAllSetsStatusSubtitle =>
      'オンにすると、「すべて実施済みにする」でプログラムのステータスも「実施済み」になり、「元に戻す」で両方が元に戻ります。オフにすると、ステータスは変わりません。';

  @override
  String get settingsGeneralRequireEventDateForHistoryTitle =>
      'コーリング履歴にはイベント日が必要';

  @override
  String get settingsGeneralRequireEventDateForHistorySubtitle =>
      '「コール済み」とみなす範囲を決めます。オンにすると、イベント日のないプログラムは、日付を設定するまでコーリング履歴を参照するどの場所でも数えられません。複製したプログラムや受け取ったプログラムは日付なしで追加されます。オフにすると、日付の有無にかかわらずプログラムが数えられます。下の4つの設定より優先されます。';

  @override
  String get settingsTrackingHeader => '新しさと履歴の並び順';

  @override
  String get settingsRecencyRequireEventDateTitle => '新しさは日付のあるプログラムのみ対象';

  @override
  String get settingsRecencyRequireEventDateSubtitle =>
      'コール済みフィルターの期間指定にのみ影響し、回数は変わりません。オンにすると、イベント日のないプログラムはどの期間にも含まれませんが、そのダンスはコール済みとして数えられます。オフにすると、日付のないプログラムは、スロットが「実施済み」とマークされた日時、なければ最終編集日時を日付として扱います。';

  @override
  String get settingsRecencyRequirePerformedTitle => '新しさは「実施済み」のスロットのみ対象';

  @override
  String get settingsRecencyRequirePerformedSubtitle =>
      'コール済みフィルターの期間指定にのみ影響し、回数は変わりません。オンにすると、「実施済み」とマークされていないスロットはどの期間にも含まれませんが、コール済みとして数えられます。自分で設定するまでは、上の「実施済み」必須の設定に従います。';

  @override
  String get settingsHistoryOrderIgnoreUndatedTitle =>
      '履歴の並び順と最終コールで日付のないプログラムを無視';

  @override
  String get settingsHistoryOrderIgnoreUndatedSubtitle =>
      'ダンスの履歴の並び順と最終コール順にのみ影響し、回数は変わりません。オンにすると、イベント日のないプログラムは日付のあるものの後ろに表示され、最終コール日にも使われません。オフにすると、スロットが「実施済み」とマークされた日時、なければ最終編集日時で並びます。';

  @override
  String get settingsHistoryOrderIgnoreUnperformedTitle =>
      '履歴の並び順と最終コールで「実施済み」でないスロットを無視';

  @override
  String get settingsHistoryOrderIgnoreUnperformedSubtitle =>
      'ダンスの履歴の並び順と最終コール順にのみ影響し、回数は変わりません。オンにすると、「実施済み」とマークされていないスロットは他のものの後ろに表示され、最終コール日にも使われません。オフにすると、プログラムの日付で並びます。';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'すべてのコーラーのコーリング履歴を記録する';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'オフで既定のコーラーが設定されている場合、コーリング履歴と回数にはそのコーラーが担当したプログラム、およびコーラーが記録されていないプログラム（自分のプログラムとして扱われます）が含まれます。オンの場合、または既定のコーラーが設定されていない場合は、そのダンスを含むすべてのプログラムが記録されます。';

  @override
  String get settingsProgramVenueCallCountTitle => 'コーリング履歴に繰り返し登場する会場';

  @override
  String get settingsProgramVenueCallCountSubtitle =>
      'ダンスを2回以上コールした主な会場を表示します。「表示しない」を選ぶとこの概要を非表示にします。';

  @override
  String settingsProgramVenueCallCountOption(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count会場',
      one: '1会場',
      zero: '表示しない',
    );
    return '$_temp0';
  }

  @override
  String get settingsGeneralCapitalizeFiguresTitle => 'フィギュアを大文字で始める';

  @override
  String get settingsGeneralCapitalizeFiguresSubtitle =>
      'オンにすると、ダンス表示、Perform モード、フィギュアエディターの各フィギュアが大文字で始まります（「Neighbors allemande left」）。オフの場合は、フィギュアは書かれたとおりに表示され、組み込みのフィギュアは ContraDB と同様に小文字で始まります。変更されるのはこれらの場所での表示のみで、エクスポート、検索、同期の比較、スクリーンリーダーの読み上げ文言は変わりません。';

  @override
  String get settingsGeneralLibraryTagsTitle => 'タグ';

  @override
  String get settingsGeneralLibraryTagsSubtitle => 'タグの名前変更、統合、色付け、削除を行います。';

  @override
  String get settingsGeneralLibraryAuthorsTitle => '作者';

  @override
  String get settingsGeneralLibraryAuthorsSubtitle =>
      '作者の名前変更、統合、削除と、詳細の編集を行います。';

  @override
  String get settingsGeneralLibrarySourcesTitle => 'ソース';

  @override
  String get settingsGeneralLibrarySourcesSubtitle =>
      'ソースの名前変更、統合、削除と、詳細の編集を行います。';

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
      '元に戻せる削除の前に確認します。元に戻せない削除は常に確認します。';

  @override
  String get settingsGeneralUndoPromptTitle => '「元に戻す」の表示';

  @override
  String get settingsGeneralUndoPromptSubtitle =>
      '削除や変更のあと「元に戻す」を画面に表示しておく時間です。ポインターを合わせている間やキーボードで移動している間も表示されたままになります。';

  @override
  String settingsGeneralUndoPromptSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds秒',
    );
    return '$_temp0';
  }

  @override
  String get settingsGeneralUndoPromptUntilClosed => '閉じるまで';

  @override
  String get settingsGeneralDeletedItemsHeader => '最近削除したアイテム';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle => '最近削除した項目を保持する期間';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      '削除したダンスとプログラムは指定した期間保持され、アプリ起動時に完全に削除されます。デバイス同期を使っている場合はすべてのデバイスに適用され、共有された項目はどこでも消去されて小さな削除記録だけが残ります。「削除しない」を選択すると手動で削除するまで保持されます。';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days日間';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => '削除しない';

  @override
  String get syncReviewSettingsTitle => '同期の判断';

  @override
  String get syncReviewSettingsSubtitle =>
      '同期だけでは解決できないデバイス間の競合について、解決方法を決めます。';

  @override
  String get syncReviewTitle => '同期の判断';

  @override
  String get syncReviewLoading => '同期の判断を読み込み中';

  @override
  String get syncReviewEmpty => '確認が必要な同期の判断はありません。';

  @override
  String get syncReviewIntro => '別のデバイスからの変更を適用する前に、これらの項目について判断が必要です。';

  @override
  String get syncReviewLoadFailed => '同期の判断事項を読み込めませんでした。もう一度お試しください。';

  @override
  String get syncReviewResolved => '同期の判断を適用しました。';

  @override
  String get syncReviewActionFailed =>
      'その同期の判断を適用できませんでした。項目は残っているので、もう一度お試しください。';

  @override
  String get syncReviewKindChoreographer => '作者';

  @override
  String get syncReviewKindTag => 'タグ';

  @override
  String get syncReviewKindCustomField => 'カスタムフィールド';

  @override
  String get syncReviewKindDifficulty => '難易度';

  @override
  String get syncReviewKindDance => 'ダンス';

  @override
  String get syncReviewKindProgram => 'プログラム';

  @override
  String get syncReviewKindPublishedSource => '公開元';

  @override
  String get syncReviewKindVenue => '会場';

  @override
  String get syncReviewKindSetting => '設定';

  @override
  String get syncReviewKindGlossaryEntry => '自分のフィギュア';

  @override
  String get syncReviewKindFigureNote => 'フィギュアへの自分のノート';

  @override
  String syncConflictFigureNoteTitle(String figure) {
    return '$figureへの自分のノート';
  }

  @override
  String syncReviewLocalRecord(String id) {
    return 'このデバイス: $id';
  }

  @override
  String syncReviewPeerRecord(String identity) {
    return 'もう一方のデバイス: $identity';
  }

  @override
  String get syncReviewTombstoneReason => 'このデバイスで作成した一致する項目が、別のデバイスで削除されました。';

  @override
  String get syncReviewDanceAmbiguityReason => 'ライブのダンスは同じタイトルですが、振り付けが異なります。';

  @override
  String get syncReviewRenameCollisionReason =>
      '別のデバイスがこのレコードの名前を、ここにある別のレコードがすでに使用している名前に変更しました。';

  @override
  String get syncReviewMergeDiscardsContactsTitle => 'これらの作者を統合しますか?';

  @override
  String get syncReviewMergeDiscardsContactsBody =>
      '残るレコードは1件だけです。もう一方のメールアドレス、場所、故人マークはこのデバイスにのみ保存されており、失われます。この操作は元に戻せません。';

  @override
  String get syncReviewCounterpartDeleted =>
      'もう一方のレコードは削除されているため、この 2 件は統合できません。「両方を保持」で別の名前を付けてください。';

  @override
  String get syncReviewUnsupportedReason =>
      'この同期の競合は保留されています。ここでは安全な操作を利用できません。';

  @override
  String get syncReviewUnsupportedAction =>
      '今のところこの項目は保持してください。後の同期やアプリのアップデートで処理できる場合があります。';

  @override
  String get syncReviewMergeAction => '統合';

  @override
  String get syncReviewKeepBothAction => '両方保持';

  @override
  String get syncReviewKeepBothTitle => 'ローカルの新しい名前を選択';

  @override
  String get syncReviewNewNameLabel => '新しいローカル名';

  @override
  String get syncReviewNameRequired => '名前を入力してください。';

  @override
  String get syncReviewNameNotDistinct => '別の名前を選択してください。';

  @override
  String get syncReviewCandidateInvalid => '別のデバイスから保存された変更が無効なため、保持しました。';

  @override
  String get syncReviewCandidateChanged => '別のデバイスから保存された変更は最新でないため、保持しました。';

  @override
  String get syncReviewTargetMissing => 'ローカルレコードが見つからないため、判断を保持しました。';

  @override
  String get syncReviewCandidateAlreadyPresent =>
      'もう一方のデバイスの項目はすでに存在するため、判断を保持しました。';

  @override
  String get settingsGeneralImportHeader => 'インポート';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Caller\'s Compendium JSONファイルからダンスをコレクションに取り込みます。追加前にすべてのダンスを確認して承認することができます。';

  @override
  String get settingsGeneralImportEllipsisAction => 'インポート…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle => '認識できないフィギュアを再確認';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      '取り込み時に認識できなかったため、未認識のフィギュアのまま保存されたダンスを再確認します。アプリが認識できるようになっていれば、そのまま更新されます。タグ、評価、メモは保持されます。変更前にプレビューで確認できます。';

  @override
  String get settingsGeneralReparseCustomFiguresAction => '再確認…';

  @override
  String get settingsGeneralEcdMigrationTitle => 'イングリッシュダンスを変換';

  @override
  String get settingsGeneralEcdMigrationSubtitle =>
      'アプリがイングリッシュのフィギュアに対応する前に保存されたイングリッシュ・カントリーダンスは、まだコントラのムーブを使っています。イングリッシュで同じ意味を持つムーブを変換し、認識できないフィギュアを読み直し、各ダンスにイングリッシュのフォーメーションを設定します。ダンスを選び、何かが変わる前に確認します。';

  @override
  String get settingsGeneralEcdMigrationAction => '変換…';

  @override
  String get settingsGeneralBackupRestoreHeader => 'バックアップと復元';

  @override
  String get backupExported => 'バックアップをエクスポートしました。';

  @override
  String get backupExportFailed =>
      'バックアップをエクスポートできませんでした。データは変更されていません。もう一度お試しください。';

  @override
  String get backupRestoreIntegrityFailed =>
      'このバックアップは安全性チェックに失敗しました。破損しているか、エクスポート後に変更された可能性があります。復元は中止され、データは変更されていません。';

  @override
  String get backupRestoreIncompatibleVersion =>
      'このバックアップにはこのバージョンのアプリで読めないアイテムが含まれています（新しいバージョンのものかもしれません）。復元はキャンセルされました。データは変更されていません。';

  @override
  String get backupRestoreMissingAppSection =>
      'このバックアップにはアプリの設定、テーマ、ダイアレクトが含まれていないため、現在のデータを置き換えることはできません。復元はキャンセルされました。データは変更されていません。';

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
  String get backupRestoreFailed => 'バックアップを復元できませんでした。もう一度お試しください。';

  @override
  String get backupRestoreSettingsFailed =>
      'ダンスとプログラムは復元されましたが、保存された設定の適用に失敗しました。復元された内容は安全です。もう一度適用を試すことができます。';

  @override
  String get backupRestoreSettingsRetryAction => '再試行';

  @override
  String get backupRestoreSettingsRetried => '設定を適用しました。';

  @override
  String get backupExportTitle => 'バックアップをエクスポート';

  @override
  String get backupExportSubtitle =>
      'ライブラリ全体を1つのJSONファイルに保存します。安全に保管したり、別のデバイスに移したりできます。ダンス、プログラム、カスタムフィールド、ダイアレクト、テーマ、設定が含まれます。';

  @override
  String get backupExportAction => 'エクスポート';

  @override
  String get backupRestoreTitle => 'バックアップから復元';

  @override
  String get backupRestoreSubtitle =>
      'アプリ内の現在の内容をすべて、バックアップファイルの内容に置き換えます。この操作は元に戻せません。';

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
  String get backupReminderBannerText =>
      'バックアップの期限が過ぎています。ライブラリを守るため、今すぐエクスポートしてください。';

  @override
  String get backupReminderBannerExport => 'バックアップをエクスポート';

  @override
  String get backupReminderBannerNotNow => '今はしない';

  @override
  String get backupRestoreDialogBody =>
      '復元すると、アプリ内の現在のコレクション、プログラム、ダイアレクト、テーマ、設定がすべて、バックアップの内容に置き換わります。この操作は元に戻せません。';

  @override
  String get backupRestoreDialogSyncNote =>
      'このデバイスはデバイス同期に接続されています。デバイス同期で共有される内容のうち、このバックアップの作成後に同期先のデバイスで変更されたもの（このデバイスで変更して同期済みのものを含む）は、次回の同期でそのデバイスから戻ってきます。それ以外はバックアップの内容になります。';

  @override
  String get backupChooseFileAction => 'ファイルを選択…';

  @override
  String get backupChooseFileFailed =>
      'そのファイルを読み取れませんでした。もう一度選ぶか、別のファイルを選んでください。';

  @override
  String get backupPasteJsonLabel => 'またはバックアップJSONを貼り付け';

  @override
  String get backupReplaceAllDataAction => 'すべてのデータを置き換え';

  @override
  String backupFileSummary(String date, int dances, int programs, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances件',
    );
    String _temp1 = intl.Intl.pluralLogic(
      programs,
      locale: localeName,
      other: '$programs件',
    );
    return '$dateのバックアップ：ダンス$_temp0、プログラム$_temp1、$size MB';
  }

  @override
  String backupFileUnreadable(String size) {
    return 'このファイルは読み取れるバックアップではないようです（$size MB）。復元できない場合は、置き換えを実行するとその理由が表示されます。';
  }

  @override
  String get backupFileClearAction => 'クリア';

  @override
  String backupFileTooLarge(String sizeMb, String limitMb) {
    return 'このファイルはCaller’s Compendiumのバックアップとしては大きすぎます（$sizeMb MB、上限 $limitMb MB）。データは変更されていません。';
  }

  @override
  String backupExportTooLarge(String sizeMb, String limitMb) {
    return 'ライブラリが大きすぎて1つのバックアップとしてエクスポートできないため（$sizeMb MB、上限 $limitMb MB）、何も保存されていません。データは変更されていません。';
  }

  @override
  String backupExportDiskFull(String neededMb, String freeMb) {
    return 'このバックアップを置き換えるための空き容量が足りません（必要 $neededMb MB、空き $freeMb MB）。何も保存されておらず、以前のバックアップは変更されていません。';
  }

  @override
  String get backupExportInProgress => 'バックアップを準備しています…';

  @override
  String get backupRestorePreparing => 'バックアップを読み込んでいます…';

  @override
  String backupRestoreProgress(int done, int total) {
    return '$total件中$done件を復元しています…';
  }

  @override
  String get diagnosticsNoDiagnosticsToExport => 'エクスポートできる診断情報がありません。';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      '安全な（情報を除去した）エクスポートを準備できなかったため、何も保存されていません。もう一度お試しいただくか、意図的に詳細版を使用してください。';

  @override
  String get diagnosticsLogExported => '診断ログをエクスポートしました。';

  @override
  String get diagnosticsExportCancelled => 'エクスポートをキャンセルしました。';

  @override
  String get diagnosticsExportFailed => '診断ログをエクスポートできませんでした。もう一度お試しください。';

  @override
  String get diagnosticsClearFailed => '診断ログを消去できませんでした。もう一度お試しください。';

  @override
  String get diagnosticsClearLogTitle => '診断ログを削除しますか？';

  @override
  String get diagnosticsClearLogBody =>
      'このデバイスのローカルのクラッシュログが完全に削除されます。この操作は元に戻せません。';

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
  String get crashFallbackTitle => 'アプリのこの部分を表示できませんでした';

  @override
  String get crashFallbackBody =>
      'アプリのこの部分で予期しないエラーが発生しました。詳細はデバイスの外に出ないローカル診断ログ（設定 ▸ 診断）に保存されました。前の画面に戻って、もう一度お試しください。';

  @override
  String get crashFallbackCopied => 'コピーしました';

  @override
  String get crashFallbackCopyDetails => '詳細をコピー';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonDiscardChangesTitle => '変更を破棄しますか？';

  @override
  String get commonDiscardChangesBody => '未保存の変更があります。';

  @override
  String get commonKeepEditing => '編集を続ける';

  @override
  String get commonDiscard => '破棄';

  @override
  String get commonContinue => '続ける';

  @override
  String get commonUndo => '元に戻す';

  @override
  String get commonUndoFailed => '元に戻せませんでした。結果を確認してから、もう一度お試しください。';

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
  String get commonDanceStatusDraft => '下書き';

  @override
  String get commonDanceStatusVariation => 'バリエーション';

  @override
  String get commonDanceLevelBeginner => 'ビギナー';

  @override
  String get commonDanceLevelIntermediate => 'インターミディエイト';

  @override
  String get commonDanceLevelAdvanced => 'アドバンスド';

  @override
  String get commonFormationDupleImproper => 'インプロパー';

  @override
  String get commonFormationProgressedImproper => '進行済みインプロパー';

  @override
  String get commonFormationReverseProgressionImproper => '逆進行インプロパー';

  @override
  String get commonFormationBecketCw => 'Becket（CW）';

  @override
  String get commonFormationBecketCcw => 'Becket（CCW）';

  @override
  String get commonFormationDupleProper => 'プロパー';

  @override
  String get commonFormationDupleIndecent => 'インディーセント';

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
  String get commonFormationQuadruplet => 'Quadruplet';

  @override
  String get commonFormationOther => 'その他';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonFormationDupleMinor => 'デュープルマイナー';

  @override
  String get commonFormationThreeCoupleLongways => '3組のロングウェイ';

  @override
  String get commonFormationFourCoupleLongways => '4組のロングウェイ';

  @override
  String get commonFormationFiveCoupleLongways => '5組のロングウェイ';

  @override
  String get commonFormationSixCoupleLongways => '6組のロングウェイ';

  @override
  String get commonFormationCircle => 'サークル';

  @override
  String get commonFormationSquare => 'スクエア';

  @override
  String get commonFormationTwoCoupleSet => '2組のセット';

  @override
  String commonFormationImproperFlag(String shape) {
    return '$shape、インプロパー';
  }

  @override
  String get danceEditorMeterLabel => '拍子';

  @override
  String get danceEditorMusicalKeyLabel => '調';

  @override
  String get danceEditorMeterHint => '例: 3/2';

  @override
  String get danceEditorMusicalKeyHint => '例: ト短調';

  @override
  String get danceEditorAlternateTitlesLabel => '別名';

  @override
  String get danceEditorAlternateTitlesHelper =>
      '1行に1つずつ。タイトル検索でどの名前からも見つかります。';

  @override
  String get danceEditorBarnesReferenceLabel => 'Barnes 掲載箇所';

  @override
  String get danceEditorBarnesReferenceHint => '例: BIII p. 92、NiB';

  @override
  String danceAlsoKnownAs(String titles) {
    return '別名: $titles';
  }

  @override
  String get danceAlsoKnownAsSeparator => '、';

  @override
  String get danceSectionBarnes => 'Barnes 曲集';

  @override
  String danceAuthorsWithYear(String names, String year) {
    return '$names（$year年）';
  }

  @override
  String danceComposedYear(String year) {
    return '$year年振付';
  }

  @override
  String danceInterpretedBy(String names) {
    return '解釈：$names';
  }

  @override
  String danceInterpretedByWithYear(String names, String year) {
    return '解釈：$names（$year年）';
  }

  @override
  String danceInterpretedYear(String year) {
    return '$year年解釈';
  }

  @override
  String danceBarnesValue(String reference) {
    return 'Barnes：$reference';
  }

  @override
  String danceMeterValue(String meter) {
    return '拍子：$meter';
  }

  @override
  String danceMusicalKeyValue(String key) {
    return '調：$key';
  }

  @override
  String get commonMixedLevel => 'ミックスレベル';

  @override
  String get commonMixer => 'ミキサー';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return '「$tagName」をコレクションの絞り込みに追加';
  }

  @override
  String commonDeletedSnack(String title) {
    return '「$title」を削除しました。';
  }

  @override
  String get commonCantBeUndone => 'この操作は元に戻せません。';

  @override
  String get importGapMessage =>
      'このコールを認識できませんでした — 書かれたとおりに認識できないフィギュアとして保持されました。';

  @override
  String get importGapDialogTitle => '認識できないフィギュア';

  @override
  String get importGapSemanticLabel => '認識できないフィギュア。書かれたとおりに保持されました。';

  @override
  String get collectionScreenTitle => 'コレクション';

  @override
  String get collectionNewDance => '新しいダンス';

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
  String collectionGroupSectionSelectedSemantics(
    String label,
    int count,
    int selected,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
    );
    return '$label、$_temp0、$selected件選択中';
  }

  @override
  String get collectionExitSelectionTooltip => '選択を終了';

  @override
  String collectionSelectedCount(int count) {
    return '$count件選択中';
  }

  @override
  String collectionSelectAllTooltip(int count) {
    return '$count件すべてを選択';
  }

  @override
  String collectionDeselectAllTooltip(int count) {
    return '$count件すべての選択を解除';
  }

  @override
  String collectionSelectionNotShown(int selected, int hidden) {
    return '$selected件選択中（$hidden件は非表示）';
  }

  @override
  String get collectionDeselectNotShown => '非表示の選択を解除';

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
  String get collectionSearchScopeLabel => '検索対象';

  @override
  String get collectionSearchScopeOmni => 'すべてのフィールド';

  @override
  String get collectionSearchScopeTitle => 'タイトル';

  @override
  String get collectionSearchScopeAuthor => '作者';

  @override
  String get collectionSearchScopeFigure => 'フィギュア';

  @override
  String get collectionClearSearchTooltip => '検索とフィルターをクリア';

  @override
  String get collectionLoadError =>
      'コレクションを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String collectionDuplicatedSnack(String title) {
    return '「$title」として複製しました。';
  }

  @override
  String get collectionEmptyBody =>
      'ダンスを追加またはインポートして始めましょう — または上のオンライン検索をオンにしてオンラインソースからインポートしてください。';

  @override
  String get collectionEmptyTitle => 'コレクションは空です';

  @override
  String get collectionImportCardTitle => 'ダンスを取り込みましょう';

  @override
  String get collectionImportCardBody =>
      'お持ちのダンスをインポートするか、最初の1曲を作成してください。「The Baby Rose」はサンプルとして入っています。';

  @override
  String get collectionBrowsePublishedCollections => '公開コレクションを見る';

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
  String get collectionAdvancedActive => '詳細検索（オン）';

  @override
  String searchToolActiveCount(String tool, int count) {
    return '$tool・$count';
  }

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
  String get collectionSearchError => '検索を実行できませんでした。何も変更されていません。もう一度お試しください。';

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
  String get collectionSetStatus => 'ステータスを設定';

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
  String collectionBatchStatusSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスのステータスを設定しました',
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
  String collectionBatchDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを削除しました',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchDeletedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを削除しました。「最近削除したアイテム」から復元できます。',
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
  String get collectionFacetCallStatus => 'コール履歴';

  @override
  String get collectionFacetCalled => 'コール済み';

  @override
  String get collectionFacetNotCalled => '未コール';

  @override
  String get collectionFacetHistoryInert => '「コール済み」または「未コール」を選ぶと有効になります';

  @override
  String get collectionFacetVenue => '会場';

  @override
  String get collectionFacetVenueAny => 'すべての会場';

  @override
  String get collectionFacetVenueUnnamed => '名称なしの会場';

  @override
  String get collectionFacetVenueClear => '会場をクリア';

  @override
  String get collectionFacetVenueSheetTitle => '会場';

  @override
  String collectionFacetVenuePrograms(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプログラム',
    );
    return '$_temp0';
  }

  @override
  String get collectionFacetVenueTyped => '入力';

  @override
  String get collectionFacetWithin => '期間';

  @override
  String get collectionFacetWithinAnyTime => 'いつでも';

  @override
  String get collectionFacetWithinNever => '一度もコールされていない';

  @override
  String collectionFacetWithinMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countか月',
    );
    return '$_temp0';
  }

  @override
  String collectionFacetWithinMonthsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countか月(保存済み)',
    );
    return '$_temp0';
  }

  @override
  String get collectionFacetWithinSince => '日付以降…';

  @override
  String collectionFacetWithinSinceDate(String date) {
    return '$date以降';
  }

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
  String get collectionFacetUntagged => 'タグなし';

  @override
  String get collectionFacetTagsMatchLabel => 'タグの一致条件';

  @override
  String get collectionFacetTagsMatchAll => 'すべてのタグ';

  @override
  String get collectionFacetTagsMatchAllTooltip => '選択したタグをすべて持つダンスを表示';

  @override
  String get collectionFacetTagsMatchAny => 'いずれかのタグ';

  @override
  String get collectionFacetTagsMatchAnyTooltip => '選択したタグのうち少なくとも1つを持つダンスを表示';

  @override
  String get collectionFacetMeter => '拍子';

  @override
  String get collectionFacetMusicalKey => '調';

  @override
  String get collectionFacetSource => 'ソース';

  @override
  String get collectionFacetAuthor => '作者';

  @override
  String get collectionFacetNone => 'このコレクションにはまだ利用可能なフィルターがありません。';

  @override
  String get collectionFacetAllHidden => 'すべてのフィルターが非表示です。設定 ▸ 既定値で再表示できます。';

  @override
  String get collectionFacetMissingValue => 'ライブラリにありません';

  @override
  String get collectionFacetStaleFields => '削除または変更されたカスタムフィールド';

  @override
  String collectionFacetStaleFieldValue(String field, String value) {
    return '$field：$value';
  }

  @override
  String get collectionFacetClear => 'フィルターをクリア';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return '$nameを削除';
  }

  @override
  String get collectionFacetAuthorSearchHint => '作者を検索…';

  @override
  String get collectionFacetTunes => 'チューン';

  @override
  String get collectionFacetTunesSearchHint => 'チューンを検索または追加…';

  @override
  String collectionFacetAddTune(String name) {
    return '「$name」を追加';
  }

  @override
  String collectionFacetRemoveTune(String name) {
    return '$nameを削除';
  }

  @override
  String get collectionFacetOpContains => 'を含む';

  @override
  String get collectionFacetOpEquals => 'と等しい';

  @override
  String collectionFacetTextHint(String label) {
    return '$labelでフィルター…';
  }

  @override
  String get collectionFacetTextClearTooltip => 'フィルターをクリア';

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
  String get collectionQueryHasTag => 'タグあり';

  @override
  String collectionQueryHasTagUnavailable(String source) {
    return 'タグあり（$sourceでは使えません）';
  }

  @override
  String get collectionQueryAnyFigure => '任意のフィギュア';

  @override
  String get collectionQueryTagLabel => 'タグ';

  @override
  String get collectionQueryTagHint => 'タグを選択';

  @override
  String get collectionQueryRemoveTag => 'タグを削除';

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
  String get collectionQueryThenNext => '直後';

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
  String collectionQueryParamNotOffered(String param, String value) {
    return '$param: $value(選択肢にありません)';
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
  String get collectionBatchApplyError => '一括変更を適用できませんでした。もう一度お試しください。';

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
  String get collectionBatchStatusConfirm => '設定';

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
  String exportNamedPhrases(String order, String bars) {
    return '$order（$bars）';
  }

  @override
  String get exportNamedPhraseSeparator => '、';

  @override
  String get exportLabelSeparator => '：';

  @override
  String danceFigureBars(String bars, int halfBars) {
    String _temp0 = intl.Intl.pluralLogic(
      halfBars,
      locale: localeName,
      other: '$bars小節',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorBarsLabel => '小節';

  @override
  String get danceEditorStepUntimed => '独自の長さなし';

  @override
  String danceEditorBarsRangeError(int max) {
    return '$maxまでの整数または半小節で入力してください';
  }

  @override
  String danceEditorHalfBarRefused(int beatsPerBar) {
    return '1小節$beatsPerBar拍では小節単位で入力してください';
  }

  @override
  String get danceEditorSequenceSpanLabel => '全体の小節';

  @override
  String get danceEditorSequenceSpanEmptyHelp =>
      '空欄にするとステップの小節を合計します。「A、B、Cを1〜4小節で」のように、シーケンス全体の小節を入力することもできます。';

  @override
  String get danceEditorSequenceSpanHelp =>
      'ステップはこの小節を共有し、各ステップは自分の小節を空欄にできます。';

  @override
  String danceEditorSequenceSpanMismatch(String steps, String span) {
    return 'ステップは$stepsですが、シーケンスは$spanです。';
  }

  @override
  String danceEditorSequenceSpanNoRoom(String steps, String span) {
    return '小節を持つステップがシーケンスの$spanのうち$stepsを使い、残りのステップの分がありません。';
  }

  @override
  String get danceEditorSequenceSpanBeatsLabel => '全体の拍数';

  @override
  String get danceEditorSequenceSpanBeatsEmptyHelp =>
      '空欄にするとステップの拍数を合計します。「forward again and swing (8)」のように、シーケンス全体の拍数を入力することもできます。';

  @override
  String get danceEditorSequenceSpanBeatsHelp =>
      'ステップはこの拍数を共有し、各ステップは自分の拍数を空欄にできます。';

  @override
  String danceEditorSequenceSpanBeatsNoRoom(String steps, String span) {
    return '拍数を持つステップがシーケンスの$spanのうち$stepsを使い、残りのステップの分がありません。';
  }

  @override
  String danceEditorSequenceOverPhraseTimed(String length, String limit) {
    return 'このシーケンスは$lengthで、始まるフレーズ（$limit）より長くなっています。';
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
  String get danceLoadError => 'このダンスを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get danceEditFab => '編集';

  @override
  String get danceDuplicateTooltip => 'ダンスを複製';

  @override
  String get danceDeleteTooltip => 'ダンスを削除';

  @override
  String get danceMoreActions => 'その他のアクション';

  @override
  String get programsMoreActions => 'その他のアクション';

  @override
  String get programsFormMatchLabel => 'タイプの一致条件';

  @override
  String get programsFormMatchOnly => '完全一致';

  @override
  String get programsFormMatchOnlyTooltip => '選んだタイプだけのプログラム';

  @override
  String get programsFormMatchIncludes => '含む';

  @override
  String get programsFormMatchIncludesTooltip => '選んだタイプを含むプログラム';

  @override
  String get danceSectionFigures => 'フィギュア';

  @override
  String get danceSectionCallingNotes => 'コーリングノート';

  @override
  String get danceSectionWalkthrough => 'ウォークスルー';

  @override
  String get danceFiguresUnreadable => 'このフィギュアは読み取れません。';

  @override
  String get danceTunesUnreadable => 'このチューンは読み取れません。';

  @override
  String get danceUnreadableReassurance =>
      '削除されたものはありません。保存された内容はそのまま保持され、このダンスの他の項目を編集しても置き換えられることはありません。';

  @override
  String get danceEditorFiguresUnreadable =>
      '保存されているフィギュアを読み取れないため、ここには表示されません。自分でフィギュアを追加しない限り、そのまま保持されます。';

  @override
  String get danceEditorTunesUnreadable =>
      '保存されたチューンは読み取れないため、ここには表示されません。ご自身でチューンを追加しない限り、そのまま保持されます。';

  @override
  String get danceListUnreadableBadge => '読み取り不可';

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
  String get danceCallingHistoryError =>
      'コーリング履歴を読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String danceVenueCallCount(int count, String venue) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$venueで$count回コール',
      one: '$venueで1回コール',
    );
    return '$_temp0';
  }

  @override
  String get danceShowCanonicalTerms => '正式な用語で表示';

  @override
  String get danceCanonicalToggleLabel => '正式用語';

  @override
  String get danceRoleTermsOverrideNote =>
      'larks と robins で表示しています。作者がこのダンスを常にこの役割名でコールするよう求めているため、ここではあなたのダイアレクトの役割名は使われません。';

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
  String get programsDanceInThisProgram => 'このプログラムに含まれています';

  @override
  String programsDanceInThisProgramCount(int count) {
    return 'このプログラムに含まれています ×$count';
  }

  @override
  String get programsAddAgainTitle => 'すでにこのプログラムにあります';

  @override
  String programsAddAgainBody(
    String danceTitle,
    String programTitle,
    int count,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「$danceTitle」はすでに「$programTitle」に$count回入っています。もう一度追加しますか？',
      one: '「$danceTitle」はすでに「$programTitle」にあります。もう一度追加しますか？',
    );
    return '$_temp0';
  }

  @override
  String get programsAddAgain => 'もう一度追加';

  @override
  String get programsAddToProgramSearchHint => 'プログラムを検索';

  @override
  String get programsAddToProgramSearchClear => '検索をクリア';

  @override
  String get programsAddToProgramNoMatches => '検索に一致するプログラムはありません。';

  @override
  String programsAddToProgramPerformedGroup(int count) {
    return '実施済み（$count）';
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
  String get programsMarkedAllPerformedExceptAlternates =>
      '代替を除くすべてのダンスを実施済みにしました。代替をコールした場合は、ご自身で実施済みにしてください。';

  @override
  String get programsMarkedAllPerformedSetStatus =>
      'すべてのダンスを実施済みにし、ステータスを「実施済み」にしました。';

  @override
  String get programsMarkedAllPerformedExceptAlternatesSetStatus =>
      '代替を除くすべてのダンスを実施済みにし、ステータスを「実施済み」にしました。代替をコールした場合は、ご自身で実施済みにしてください。';

  @override
  String programsSavedSnack(String title) {
    return '「$title」を保存しました。';
  }

  @override
  String get programsSaveError =>
      'プログラムを保存できませんでした。変更内容はここに残っています。もう一度お試しください。';

  @override
  String get programsUndoPerformedError => '元に戻せませんでした。実施済みマークは保存されたままです。';

  @override
  String get programsUndoRefreshError =>
      '元に戻す操作は保存されましたが、エディターを更新できませんでした。プログラムを開き直すと反映されます。';

  @override
  String programsDuplicatedSnack(String title) {
    return '「$title」として複製しました。';
  }

  @override
  String programsDeletedSnack(String title) {
    return '「$title」を削除しました。';
  }

  @override
  String get programsArchive => 'アーカイブ';

  @override
  String get programsUnarchive => 'アーカイブを解除';

  @override
  String programsArchivedSnack(String title) {
    return '「$title」をアーカイブしました。';
  }

  @override
  String programsUnarchivedSnack(String title) {
    return '「$title」のアーカイブを解除しました。';
  }

  @override
  String get programsArchivedLabel => 'アーカイブ済み';

  @override
  String get programsShowArchived => 'アーカイブ済みを表示';

  @override
  String get programsHideArchived => 'アーカイブ済みを非表示';

  @override
  String get programsAllArchivedTitle => '表示するプログラムがありません';

  @override
  String get programsAllArchivedBody => 'すべてのプログラムがアーカイブされています。';

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
  String programsDraftAnotherNewProgramBody(String title) {
    return '別の新しいプログラム「$title」の未保存の下書きがあります。新しく始める代わりに、この下書きを復元しますか？';
  }

  @override
  String get programsDraftAnotherNewProgramUntitledBody =>
      'まだタイトルのない、別の新しいプログラムの未保存の下書きがあります。新しく始める代わりに、この下書きを復元しますか？';

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
  String get commonSave => '保存';

  @override
  String get programsLoading => 'プログラムを読み込み中';

  @override
  String get programsLoadError => 'プログラムを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get programsUndoRecoveryFailed =>
      '元に戻したあと、プログラムを再読み込みできませんでした。前の画面に戻って開き直すと、現在の状態を確認できます。';

  @override
  String get programsDeletedDanceFallback => '（削除済みダンス）';

  @override
  String get programsRestoreDeletedDance => '最近削除したアイテムから復元';

  @override
  String programsRestoreDeletedDanceError(String title) {
    return '「$title」を復元できませんでした。最近削除したアイテムに残っています。';
  }

  @override
  String get programsBlankedDanceTitle => '削除されたダンス';

  @override
  String get programsSlotsLabel => 'スロット';

  @override
  String get programsSlotsHelper =>
      'スロットは、セットリストの1つの枠です。ダンス、メモ、休憩のいずれかを入れられます。';

  @override
  String get programsAddDanceButton => 'ダンスを追加';

  @override
  String get programsAddNoteBreakButton => 'ノートまたはブレイクを追加';

  @override
  String get programsInsertBreakButton => 'ブレイクを挿入';

  @override
  String get programsAddADanceSheetTitle => 'ダンスを追加';

  @override
  String get commonClose => '閉じる';

  @override
  String get viewDetails => '詳細を表示';

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
  String get programsStartTimeLabel => '開始時刻';

  @override
  String get programsEndTimeLabel => '終了時刻';

  @override
  String get programsLessonTimeLabel => '初心者レッスン';

  @override
  String get programsArrivalTimeLabel => '到着時刻';

  @override
  String get programsNoTimeSet => '未設定';

  @override
  String get programsSetTime => '設定';

  @override
  String get programsChangeTime => '変更';

  @override
  String programsSetTimeFor(String field) {
    return '$fieldを設定';
  }

  @override
  String programsChangeTimeFor(String field) {
    return '$fieldを変更';
  }

  @override
  String programsClearTime(String field) {
    return '$fieldをクリア';
  }

  @override
  String get programsTimeNextDay => '翌日に終了';

  @override
  String programsVenueUsualTimeHint(String time) {
    return '会場の通常の時間：$time';
  }

  @override
  String programsSummaryLessonTime(String time) {
    return 'レッスン $time';
  }

  @override
  String programsSummaryDanceTime(String times) {
    return 'ダンス $times';
  }

  @override
  String programsSummaryArriveBy(String time) {
    return '到着 $time';
  }

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
  String get programsPayLabel => '報酬';

  @override
  String get programsPayHint => '例: 250.00';

  @override
  String get programsPayCurrencyLabel => '通貨';

  @override
  String get programsPayInvalid => 'この通貨で 250 や 250.50 のような金額を入力してください。';

  @override
  String get programsStatusFieldLabel => 'ステータス';

  @override
  String get programsStatusHelper =>
      '「実施済み」への変更を保存すると、代替を除く未マークのダンスがすべて実施済みになります。ステータスを戻してもマークは残ります。';

  @override
  String get programsStatusHelperMarkAllSetsStatus =>
      '「実施済み」への変更を保存すると、代替を除く未マークのダンスがすべて実施済みになります。「すべて実施済みにする」でもこのステータスになります。ステータスを戻してもマークは残ります。';

  @override
  String get programsHideAlternatesTitle => 'セットリストで代替を非表示';

  @override
  String get programsHideAlternatesSubtitle =>
      '概要、PDF、エクスポートされたセットリストからALTスロットを省略します。ビルダーにはすべてのスロットが表示されます。';

  @override
  String get programsDialectFieldLabel => 'パフォームのダイアレクト';

  @override
  String get programsDialectUseApp => 'アプリのダイアレクトを使用';

  @override
  String programsDialectUnavailable(String name) {
    return '$name（利用不可）';
  }

  @override
  String get programsDialectHelper =>
      'このプログラムのパフォームモードでのみ使用されます。エディター、概要、エクスポートではアプリのダイアレクトが使われます。';

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
  String get programsSearchTooltip => 'プログラムを検索';

  @override
  String get programsSearchHint => 'プログラムを検索…';

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
  String get programsListLoadError =>
      'プログラムを読み込めませんでした。何も変更されていません。もう一度お試しください。';

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
  String programsSummaryPay(String amount) {
    return '報酬: $amount';
  }

  @override
  String programsSetListHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
    );
    return 'セットリスト ($_temp0)';
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
  String programsDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンス',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'ノート';

  @override
  String get programsSlotEditorEmptyTitle => 'スロットがまだありません';

  @override
  String get programsSlotEditorEmptyBody => 'ダンスまたはノートを追加して始めましょう。';

  @override
  String get programsSlotMovedUp => 'スロットを上に移動しました。';

  @override
  String get programsSlotMovedDown => 'スロットを下に移動しました。';

  @override
  String get programsMarkedPrimary => 'メインとしてマークしました。';

  @override
  String get programsMarkedAlternate => '代替としてマークしました。';

  @override
  String get programsMarkedPerformed => '実施済みとしてマークしました。';

  @override
  String programsSummaryPerformedToggleOn(String title) {
    return '$title：実施済み';
  }

  @override
  String programsSummaryPerformedToggleOff(String title) {
    return '$title：未実施';
  }

  @override
  String programsSummaryMarkPerformedTooltip(String title) {
    return '$titleを実施済みとしてマーク';
  }

  @override
  String programsSummaryClearPerformedTooltip(String title) {
    return '$titleの実施済みマークをクリア';
  }

  @override
  String programsSummaryMarkedPerformedSnack(String title) {
    return '$titleを実施済みとしてマークしました。';
  }

  @override
  String programsSummaryClearedPerformedSnack(String title) {
    return '$titleの実施済みマークをクリアしました。';
  }

  @override
  String get programsSummaryPerformedToggleError =>
      '実施済みマークを更新できませんでした。もう一度お試しください。';

  @override
  String get programsSummaryUndoPerformedToggleError =>
      '実施済みマークの変更を取り消せませんでした。もう一度お試しください。';

  @override
  String get programsPerformedCleared => '実施済みマークをクリアしました。';

  @override
  String programsRemovedSlot(String name) {
    return '「$name」を削除しました。';
  }

  @override
  String programsAlternatePromoted(String name) {
    return '$name が代わりに入ります。';
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
  String get programsAddDanceBeforeMenu => '前にダンスを追加';

  @override
  String get programsAddDanceAfterMenu => '後にダンスを追加';

  @override
  String programsAddBeforeSheetTitle(String title) {
    return '$title の前に追加';
  }

  @override
  String programsAddAfterSheetTitle(String title) {
    return '$title の後に追加';
  }

  @override
  String programsAddingBeforeBanner(String title) {
    return '$title の前に追加中';
  }

  @override
  String programsAddingAfterBanner(String title) {
    return '$title の後に追加中';
  }

  @override
  String programsAddedDanceBeforeAnnounce(String title, String target) {
    return '$title を $target の前に追加しました。';
  }

  @override
  String programsAddedDanceAfterAnnounce(String title, String target) {
    return '$title を $target の後に追加しました。';
  }

  @override
  String get programsInsertionCancelledAnnounce =>
      'キャンセルしました。新しいダンスは最後に追加されます。';

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
  String get programsCreateDanceFromNoteMenu => 'これからダンスを作成';

  @override
  String programsCreatedDanceFromNoteAnnounce(String title) {
    return '$titleを作成し、このスロットにリンクしました。';
  }

  @override
  String get programsSlotTextRequiredError => 'このスロットのテキストを入力してください。';

  @override
  String get programsWholeNumberError => '0以上の整数を入力してください。';

  @override
  String get programsEditDanceSlotTitle => 'ダンススロットを編集';

  @override
  String get programsCurrentDanceLabel => 'ダンス';

  @override
  String get programsReplaceDanceButton => '置き換え…';

  @override
  String get programsReplaceDanceSheetTitle => 'ダンスを置き換え';

  @override
  String programsReplacedDanceAnnounce(String title) {
    return '$titleに置き換えました。';
  }

  @override
  String get programsEditNoteTitle => 'ノートを編集';

  @override
  String get programsCallerNoteLabel => 'コーラーノート（任意）';

  @override
  String get programsCallerNoteHint => '例: まずヘイを教える';

  @override
  String get programsGuestCallerLabel => 'ゲストコーラー（任意）';

  @override
  String get programsPlannedTimingHeader => '予定時間';

  @override
  String get programsWalkthroughMinutesLabel => 'ウォークスルー時間（任意）';

  @override
  String get programsDanceMinutesLabel => 'ダンス時間（任意）';

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
  String get programsMatrixHideAlternatesSemantic => '代替行を非表示';

  @override
  String get programsMatrixShowAlternatesSemantic => '代替行を表示';

  @override
  String get programsMatrixShowPhrasesSemantic => 'フレーズラベルを表示';

  @override
  String get programsMatrixHidePhrasesSemantic => '存在グリフを表示';

  @override
  String programsMatrixSectionShort(String sectionKey, String sectionNumber) {
    String _temp0 = intl.Intl.selectLogic(sectionKey, {
      's1': '1',
      's2': '2',
      's3': '3',
      's4': '4',
      's5': '5',
      's6': '6',
      's7': '7',
      's8': '8',
      's9': '9',
      'other': '$sectionNumber',
    });
    return '$_temp0';
  }

  @override
  String programsMatrixSectionRowHeaderSemantic(
    String title,
    String alt,
    String section,
  ) {
    String _temp0 = intl.Intl.selectLogic(section, {
      'none': '代替ダンス: $title',
      'other': '代替ダンス: $title、セクション $section',
    });
    String _temp1 = intl.Intl.selectLogic(section, {
      'none': 'ダンス: $title',
      'other': 'ダンス: $title、セクション $section',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixSectionChipQualifiedTitle(
    String title,
    String alt,
    String section,
  ) {
    String _temp0 = intl.Intl.selectLogic(section, {
      'none': '$title（代替ダンス）',
      'other': '$title（代替ダンス、セクション $section）',
    });
    String _temp1 = intl.Intl.selectLogic(section, {
      'none': '$title',
      'other': '$title（セクション $section）',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
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
    String phrases,
    String collision,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(collision, {
      'phrase': '、隣接するダンスと同じフレーズで繰り返し',
      'beats': '、隣接するダンスと拍を共有',
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
      'no': 'なし',
      'other': 'あり$_temp0$_temp1$_temp2',
    });
    String _temp4 = intl.Intl.selectLogic(phrases, {
      'none': '',
      'other': '、フレーズ：$phrases',
    });
    return '$dance、$move：$_temp3$_temp4';
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
  String get programsMatrixLegendCollisionBeats => '隣接ダンスと拍が重なる';

  @override
  String get programsMatrixEmptyTitle => 'まだ構造化されたフィギュアがありません';

  @override
  String get programsMatrixEmptyBody =>
      'プログラムのダンスに構造化されたフィギュアが追加されると、マトリックスは自動的に埋まります。';

  @override
  String get performTitle => 'パフォーム';

  @override
  String get performExitTooltip => 'パフォームを終了';

  @override
  String get performExitTitle => 'パフォームを終了しますか？';

  @override
  String get performExitBody =>
      'パフォームを終了しますか？位置と実行中のタイマーは保持されるため、中断した場所から再開できます。';

  @override
  String get performDanceExitBody =>
      'パフォームを終了しますか？単一のダンスのパフォームでは位置は保持されないため、次回は最初から始まります。';

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
  String get performProgramClockLabel => 'プログラム';

  @override
  String get performSlotClockLabel => 'スロット';

  @override
  String performShowingSlot(String label) {
    return '$labelを表示中';
  }

  @override
  String get performAdjustmentUndone => '調整を元に戻しました';

  @override
  String get performUndoNoLongerAvailable => '元に戻せません。その後プログラムが変更されています。';

  @override
  String get performProgramChangedElsewhere =>
      'パフォームモードを開いてから、このプログラムが別の場所で変更されました。パフォームモードには、あなたの変更を含む最新の内容が表示されています。';

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
    int walkthrough,
    int dance,
    String walkthroughComplete,
    String over,
    String paused,
    String manual,
    String actual,
    String direction,
    String delta,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$planned分',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': '、予定 $_temp0: ウォークスルー $walkthrough分、ダンス $dance分',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(direction, {
      'over': '、予定より$delta超過',
      'under': '、予定より$delta短縮',
      'other': '、予定どおり',
    });
    String _temp3 = intl.Intl.selectLogic(manual, {
      'yes': '、ウォークスルーは$actualで終了$_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(walkthroughComplete, {
      'yes': '、ウォークスルー完了',
      'other': '',
    });
    String _temp5 = intl.Intl.selectLogic(over, {'yes': '、予定超過', 'other': ''});
    String _temp6 = intl.Intl.selectLogic(paused, {
      'yes': '、一時停止中',
      'other': '',
    });
    return 'プログラム経過時間 $programTime、スロット経過時間 $slotTime$_temp1$_temp3$_temp4$_temp5$_temp6';
  }

  @override
  String performIndividualTimingSemantic(String elapsedTime, String paused) {
    String _temp0 = intl.Intl.selectLogic(paused, {
      'yes': '、一時停止中',
      'other': '',
    });
    return '経過時間 $elapsedTime$_temp0';
  }

  @override
  String performPlannedSplit(int planned, int walkthrough, int dance) {
    return '予定 $planned分（$walkthrough:$dance）';
  }

  @override
  String get performDanceStartUnused => 'ウォークスルー終了 — ダンスを開始';

  @override
  String get performDanceStartUsed => 'ダンス開始済み — タップで取り消し';

  @override
  String performWalkthroughActual(
    String actual,
    String direction,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'over': ' (+$delta)',
      'under': ' (−$delta)',
      'other': '（予定どおり）',
    });
    return 'ウォークスルー $actual$_temp0';
  }

  @override
  String get performWalkthroughCompleteSuffix => ' ウォークスルー完了';

  @override
  String get performOverSuffix => ' 超過';

  @override
  String get performSlotCallerNote => 'コーラーメモ';

  @override
  String get performCallingNotes => 'コーリングノート';

  @override
  String get performWalkthrough => 'ウォークスルー';

  @override
  String get performShowWalkthrough => 'ウォークスルーを表示';

  @override
  String get performFullScreen => '全画面表示';

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
  String get exportShareDanceBundle => 'ダンスファイルを共有';

  @override
  String get exportSaveDanceBundle => 'ダンスファイルを保存…';

  @override
  String get exportShowCode => 'コードを表示';

  @override
  String get exportShowCodeError => 'コードを表示できませんでした。ダンスは変更されていません。もう一度お試しください。';

  @override
  String get danceCodeScreenTitle => 'ダンスのコード';

  @override
  String danceCodeSemanticLabel(String title) {
    return '$titleのQRコード';
  }

  @override
  String get danceCodeTooLong =>
      'このダンスは長すぎて、コードとして共有できません。代わりにファイルとして共有してください。';

  @override
  String get exportCopyDance => 'ダンスをコピー';

  @override
  String get exportShareDanceJson => 'ダンスをJSONとしてエクスポート';

  @override
  String get exportPrintPdf => 'PDFにエクスポート／印刷';

  @override
  String get exportDanceCopied => 'ダンスをクリップボードにコピーしました。';

  @override
  String get exportShareDanceError =>
      'このダンスを共有できませんでした。ダンスは変更されていません。もう一度お試しください。';

  @override
  String get exportDanceError =>
      'このダンスをエクスポートできませんでした。ダンスは変更されていません。もう一度お試しください。';

  @override
  String get exportShareSetListText => 'セットリストを共有（テキスト）';

  @override
  String get exportShareProgramBundle => 'プログラムとダンスを共有';

  @override
  String get exportSaveProgramBundle => 'プログラムファイルを保存…';

  @override
  String get exportCopySetList => 'セットリストをコピー';

  @override
  String get exportSetListCopied => 'セットリストをクリップボードにコピーしました。';

  @override
  String get exportShareProgramJson => 'JSONファイルとして書き出す';

  @override
  String get exportJsonDialogTitle => 'JSONを書き出す';

  @override
  String get exportJsonDialogMessage => 'このJSONファイルの送信方法を選択してください。';

  @override
  String get exportJsonSave => '保存';

  @override
  String get exportJsonCopy => '生のJSONをコピー';

  @override
  String get exportJsonShare => '共有';

  @override
  String get exportJsonSaveAs => '名前を付けて保存…';

  @override
  String get exportJsonCancel => 'キャンセル';

  @override
  String get exportJsonCopied => 'JSONをクリップボードにコピーしました。';

  @override
  String exportJsonSaved(String fileName) {
    return '\"$fileName\"を保存しました。';
  }

  @override
  String get exportJsonSavedGeneric => 'JSONファイルを保存しました。';

  @override
  String exportJsonSavedTo(String fileName, String destination) {
    return '\"$fileName\"を$destinationに保存しました。';
  }

  @override
  String get exportJsonSaveError => 'このJSONファイルを保存できませんでした。もう一度お試しください。';

  @override
  String get exportJsonCopyError => 'このJSONをコピーできませんでした。もう一度お試しください。';

  @override
  String get exportJsonShareError => 'このJSONファイルを共有できませんでした。もう一度お試しください。';

  @override
  String get exportShareSetListError => 'このセットリストを共有できませんでした。もう一度お試しください。';

  @override
  String get exportShareProgramError =>
      'このプログラムを共有できませんでした。プログラムは変更されていません。もう一度お試しください。';

  @override
  String get exportSetListError => 'このセットリストをエクスポートできませんでした。もう一度お試しください。';

  @override
  String get exportIncludeFiguresTitle => 'フィギュアを含めますか？';

  @override
  String get exportIncludeFiguresSetListOnly => 'セットリストのみ';

  @override
  String get exportIncludeFiguresSetListAndFigures => 'セットリストとフィギュア';

  @override
  String get exportIncludeFiguresAlternate => '代替';

  @override
  String get exportMatrixPdfTooltip => 'マトリックスをPDFにエクスポートまたは印刷';

  @override
  String get exportMatrixPdfFilename => 'プログラミングマトリックス';

  @override
  String get exportLabelFormation => 'フォーメーション';

  @override
  String get exportLabelLevel => 'レベル';

  @override
  String get exportLabelMixer => 'ミキサー';

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
  String get exportLabelTunes => 'チューン';

  @override
  String get exportLabelHook => 'フック';

  @override
  String get exportLabelSources => 'ソース';

  @override
  String exportSlotAuthorSuffix(String names) {
    return '作：$names';
  }

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
  String get exportUnknownDanceLabel => '無題のダンス';

  @override
  String exportMinutesLabel(int count) {
    return '$count分';
  }

  @override
  String exportPageOfPages(int page, int pages) {
    return '$page / $pages ページ';
  }

  @override
  String get exportLabelLesson => 'レッスン';

  @override
  String exportTimeRange(String start, String end) {
    return '$start～$end';
  }

  @override
  String exportEndsAt(String end) {
    return '$endまで';
  }

  @override
  String exportNextDay(String times) {
    return '$times（翌日）';
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
  String get exportMatrixLegendCollisionBeats => '隣接ダンスと拍が重なる';

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
  String get collectionOnlineSearchFieldHint =>
      'タイトル、作者、またはフィギュアでオンラインのダンスを検索…';

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
  String onlineResultCountCapped(int count) {
    return '$count件のオンライン結果を表示しています。ほかにもある可能性があります。下にスクロールすると読み込みます。';
  }

  @override
  String onlineResultCountOfTotal(int count, int total) {
    return '$total件中$count件のオンライン結果を表示しています。下にスクロールすると続きを読み込みます。';
  }

  @override
  String onlineResultCountOfTotalStopped(int count, int total) {
    return '$total件中$count件のオンライン結果を表示しています。';
  }

  @override
  String onlineResultCountMaybeMore(int count) {
    return '$count件のオンライン結果を表示しています。ほかにもある可能性があります。';
  }

  @override
  String get onlineAdvancedPartlyApplied => '一部の詳細検索の条件はContraDBにないため、除外されました。';

  @override
  String onlineSearchHintByPhrase(String source) {
    return '$sourceを検索するには、タイトルまたは作者を入力するか、フレーズ別のフィギュアを追加してください。';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return '$sourceを検索するには、タイトルまたは作者を入力してください。';
  }

  @override
  String collectionOnlineSearchHintByPhrase(String source) {
    return '$sourceを検索するには、タイトル、作者、またはフィギュアを入力するか、フレーズ別のフィギュアを追加してください。';
  }

  @override
  String collectionOnlineSearchHintTitle(String source) {
    return '$sourceを検索するには、タイトル、作者、またはフィギュアを入力してください。';
  }

  @override
  String onlineNoResults(String source) {
    return '$sourceで検索に一致するダンスがありません。';
  }

  @override
  String onlineLoadError(String source) {
    return '$sourceからそのダンスを読み込めませんでした。もう一度お試しください。';
  }

  @override
  String get onlineImportError => 'そのダンスを取り込めませんでした。もう一度お試しください。';

  @override
  String onlineSearchFailed(String source) {
    return '$sourceを検索できませんでした。もう一度お試しください。';
  }

  @override
  String onlineImportCreated(String title) {
    return '「$title」をインポートしました。';
  }

  @override
  String onlineImportUpdated(String title) {
    return '「$title」をオンライン版で更新しました。';
  }

  @override
  String onlineImportUndoKeptChanged(String title) {
    return '「$title」はインポート後に変更されたため、元に戻す操作では変更しませんでした。';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '「$title」はすでにコレクションにあります。';
  }

  @override
  String onlineImportVariationDialogBody(String existingTitle) {
    return 'このダンスのタイトルと作者は「$existingTitle」と一致しますが、フィギュアが異なります。どのようにインポートしますか？';
  }

  @override
  String get onlineImportVariationDialogActionVariation => 'バリエーションとして取り込む';

  @override
  String get onlineImportVariationDialogActionLink => '同じダンス（既存を更新）';

  @override
  String onlineImportVariationDialogLinkWarning(String existingTitle) {
    return '「$existingTitle」のあなたのバージョンは、オンラインの記録に置き換えられます。タイトル、フィギュア、コーリングノート、タグも含まれます。評価、カスタムフィールド、プログラム内の位置、コーリング履歴は保持されます。';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogTitle => 'このダンスはすでにあります';

  @override
  String onlineImportCrossSourceDuplicateDialogBody(String existingTitle) {
    return 'コレクションにはすでに「$existingTitle」があります。どちらのバージョンもムーブの並びは同じです。';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogActionDuplicate =>
      '2つ目のコピーをインポート';

  @override
  String get onlineImportPossibleMatchDialogTitle => 'このダンスはすでにありますか？';

  @override
  String onlineImportPossibleMatchDialogBody(String incomingTitle) {
    return '「$incomingTitle」は、別のタイトルですでにあるダンスかもしれません。このバージョンで置き換えるダンスを選ぶか、新しいダンスとしてインポートしてください。';
  }

  @override
  String get onlineImportPossibleMatchDialogLinkWarning =>
      '選択したダンスは、オンラインの記録に置き換えられます。タイトル、フィギュア、コーリングノート、タグも含まれます。評価、カスタムフィールド、プログラム内の位置、コーリング履歴は保持されます。';

  @override
  String get importFigurelessCannotReplace =>
      'このレコードにはフィギュアがないため、既存のダンスを置き換えることはできません。新しいダンスとしてなら取り込めます。';

  @override
  String get onlineImportPossibleMatchDialogActionNew => '新しいダンスとしてインポート';

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
  String get importProgramFromTitleList => 'タイトルリストからインポート';

  @override
  String get importFromContraDb => 'ContraDBから';

  @override
  String get importProgramFromContraDb => 'ContraDBからインポート';

  @override
  String get importProgramTitleLabel => 'プログラムタイトル';

  @override
  String get importProgramCreateError => '取り込んだプログラムを保存できませんでした。もう一度お試しください。';

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
  String get importContraDbListError =>
      'ContraDBのプログラム一覧を読み込めませんでした。何も取り込まれていません。もう一度お試しください。';

  @override
  String get importContraDbSearchPrompt => 'プログラム名の一部を入力してContraDBを検索してください。';

  @override
  String get importContraDbNoMatches => '一致するプログラムがありません。';

  @override
  String get importContraDbMarkerImported => 'インポート済み';

  @override
  String importContraDbMarkerImportedTooltip(String date) {
    return '$dateにインポート';
  }

  @override
  String get importContraDbMarkerImportedTooltipNoDate => 'ContraDBからインポート済み';

  @override
  String get importContraDbMarkerPossible => 'インポートの可能性あり';

  @override
  String get importContraDbMarkerPossibleTooltip => 'このタイトルのプログラムはすでに存在します';

  @override
  String importContraDbFetchError(String error) {
    return 'そのプログラムを取得できませんでした。\n$error';
  }

  @override
  String get importContraDbFetchGenericError =>
      'そのプログラムを取得できませんでした。もう一度お試しください。';

  @override
  String get importContraDbPastePrompt =>
      '上にContraDBプログラムのURLを貼り付けて「プログラムを取得」をタップしてください。';

  @override
  String get importContraDbEmptyProgram => 'そのプログラムページにダンスやノートが見つかりませんでした。';

  @override
  String get importContraDbResolveError =>
      'ContraDBのプログラムを取り込めませんでした。もう一度お試しください。';

  @override
  String importContraDbProgramProgress(int done, int total) {
    return '$total件中$done件目のダンスをインポート中…';
  }

  @override
  String get importContraDbProgramConnectionFailed =>
      'オンラインアーカイブに接続できなかったため、何もインポートされませんでした。オンラインになってからもう一度お試しください。';

  @override
  String get importContraDbProgramCancelled => 'インポートをキャンセルしました。何も追加されていません。';

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
  String get importCollectionLoadError =>
      'コレクションを読み込めませんでした。何も変更されていません。もう一度お試しください。';

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
  String get importPlaintextImportedOnline => 'オンラインからインポート済み';

  @override
  String get importPlaintextLinked => 'ダンスにリンク';

  @override
  String get importPlaintextAmbiguous => '複数の一致 — ノートとして追加';

  @override
  String get importPlaintextUnmatched => '一致なし — ノートとして追加';

  @override
  String get importPlaintextSearchError => 'オンラインで検索できませんでした。もう一度お試しください。';

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
      other: '$remaining件をメモとして保存',
    );
    return '確実なオンライン一致は見つかりませんでした — $_temp0。';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked件',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '；$remaining件はメモのまま。',
      zero: '。',
    );
    return 'オンラインで$_temp0のタイトルをリンクしました$_temp1';
  }

  @override
  String importPlaintextResolveConnectionFailed(int linked) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '（$linked件のタイトルをオンラインでリンク済み）。',
      zero: '。',
    );
    return '接続エラーのため、タイトルの検索を中止しました$_temp0残りはオンラインになってからもう一度お試しください。';
  }

  @override
  String importPlaintextResolveCancelled(int linked) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '（$linked件のタイトルをオンラインでリンク済み）。',
      zero: '。',
    );
    return 'タイトルの検索を中止しました$_temp0';
  }

  @override
  String get importReviewClose => 'インポートを閉じる';

  @override
  String get importReviewDiscardTitle => 'このインポートを破棄しますか？';

  @override
  String get importReviewDiscardBody => '今ここを離れると、確認中のリストとその選択内容は破棄されます。';

  @override
  String get importReviewKeepReviewing => '確認を続ける';

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
  String get fileDialogTypeBackupJson => 'バックアップ (JSON)';

  @override
  String get fileDialogTypeCompendiumShare => 'Compendium共有ファイル';

  @override
  String get fileDialogTypeCompanionUsr => 'Caller’s Companion .USR';

  @override
  String get fileDialogTypeDiagnosticsLog => '診断ログ';

  @override
  String get fileDialogTypeMacosUpdate => 'Caller’s Compendiumのアップデート';

  @override
  String get fileDialogTypeImages => '画像';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'Caller\'s Companion .USRファイル';

  @override
  String get importSourceLabelTitleList => 'タイトルのリスト';

  @override
  String get importReviewTitleListSubtitle =>
      '1行に1つずつダンスのタイトルを貼り付けてください。すべてのタイトルが確認用に一覧表示されます。すでにお持ちのものは表示されますが、再インポートされることはありません。確認するまでコレクションには何も追加されません。';

  @override
  String get importReviewPasteTitles => 'ダンスのタイトル（1行に1つ）';

  @override
  String importReviewTitleListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のタイトル',
      zero: 'タイトルはまだありません',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の重複タイトルを無視しました',
    );
    return '$_temp0';
  }

  @override
  String importTitleListTooManyTitles(int count, int max) {
    return '$count件のタイトルがあります。一度にインポートできるのは$max件までです。';
  }

  @override
  String get importTitleListTextTooLong =>
      '貼り付けられたテキストが長すぎて、タイトルのリストとして読み取れません。短いリストを貼り付けてみてください。';

  @override
  String importReviewTitleListProgress(int done, int total) {
    return '$total件中$done件を検索中…';
  }

  @override
  String importReviewCommitProgress(int done, int total) {
    return '$done / $total';
  }

  @override
  String importReviewTitleListPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '貼り付けたタイトル$count件',
    );
    return '$_temp0';
  }

  @override
  String importReviewProgramAmbiguousLine(String title) {
    return '「$title」 — 1つ選ぶか、メモのままにしてください';
  }

  @override
  String importReviewAmbiguousGroup(String title) {
    return '「$title」 — 1つ選ぶか、スキップしてください';
  }

  @override
  String importReviewMetadataAuthor(String author) {
    return '作者: $author';
  }

  @override
  String importReviewMetadataFormation(String formation) {
    return '$formation';
  }

  @override
  String importReviewMetadataSource(String source) {
    return '$source から';
  }

  @override
  String importReviewTitleListToImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'インポート可能$count件',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListAmbiguous(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件は選択が必要',
      one: '1件は選択が必要',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'すでにコレクションにあるもの$count件',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListNotFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '見つからなかったもの$count件',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwnedBy(String authors) {
    return 'このダンスはすでにあります（振付：$authors）。';
  }

  @override
  String get importReviewTitleListOwnedUnknownAuthor => 'このダンスはすでにあります。';

  @override
  String importReviewTitleListOwnedMany(int count) {
    return 'このタイトルのダンスが$count件あります。';
  }

  @override
  String get importTitleListReasonNoResults =>
      'The Caller\'s Boxにこの名前のダンスはありません。';

  @override
  String get importTitleListReasonNoExactMatch =>
      '近い候補のみで、このタイトルと完全に一致するものはありません。';

  @override
  String get importTitleListReasonMultipleExactMatches =>
      '複数のダンスがこのタイトルと完全に一致するため、どれを指しているか判断できません。';

  @override
  String get importTitleListReasonFetchError =>
      'このタイトルについてThe Caller\'s Boxに到達できませんでした。';

  @override
  String get importTitleListReasonConnectionFailed =>
      'The Caller\'s Boxに到達できませんでした。接続を確認してください。';

  @override
  String get importTitleListConnectionBanner =>
      '接続エラーのため、タイトルの検索を中止しました。すでにコレクションにあるタイトルは一覧に表示されています。残りはオンラインになってから試してください。';

  @override
  String get importTitleListReasonLineTooLong =>
      'ダンスのタイトルとしては長すぎるため、検索しませんでした。';

  @override
  String get importReviewTitleListNothingToImport =>
      'ここにインポートできるものはありません。すべてのタイトルは、すでにコレクションにあるか、見つかりませんでした。';

  @override
  String importReviewSummaryAlreadyOwned(int count) {
    return 'すでにコレクションにあるもの: $count';
  }

  @override
  String importReviewSummaryNotFound(int count) {
    return '見つかりませんでした: $count';
  }

  @override
  String importErrorFileTooLarge(int megabytes) {
    return 'そのファイルは上限の$megabytes MBを超えています。より小さいファイルを選んで、もう一度お試しください。';
  }

  @override
  String get archiveIntakeRejectedTooLarge => 'そのファイルはインポートするには大きすぎます。';

  @override
  String get archiveIntakeRejectedUnreadable =>
      '共有されたファイルを読み取れませんでした。もう一度お試しいただくか、送信者に共有し直してもらってください。';

  @override
  String get archiveIntakeRejectedEmpty => 'そのファイルは空です。';

  @override
  String get danceLinkRefusedNewerVersion =>
      'このダンスのコードは、新しいバージョンのCaller’s Compendiumで作成されています。開くには、アプリをアップデートしてください。';

  @override
  String get danceLinkRefusedDamaged => 'このダンスのコードは破損しているか不完全なため、開けません。';

  @override
  String get danceLinkRefusedNotADance =>
      'このコードは Caller\'s Compendium のダンスのコードではありません。';

  @override
  String get danceLinkRefusedNoContent => 'このダンスのコードにはダンスもプログラムも含まれていません。';

  @override
  String get importScanDanceCode => 'ダンスのコードをスキャン';

  @override
  String get importScanNoCode =>
      '画像にダンスのコードが見つかりませんでした。コード全体が写り、鮮明であることを確認してください。';

  @override
  String get importScanUnreadable => '画像を読み取れませんでした。';

  @override
  String get importDanceCodePicture => '画像からダンスのコード…';

  @override
  String importScanTooLarge(int limit) {
    return 'この画像は $limit MB を超えているため、読み取りませんでした。小さい画像を選んでください。';
  }

  @override
  String get importScanNoCamera =>
      'この端末には写真を撮るカメラアプリがありません。代わりに「画像からダンスのコード…」を選んでください。';

  @override
  String get importScanCameraOff =>
      'Caller\'s Compendium のカメラへのアクセスがオフになっています。コードをスキャンするには、「設定」アプリでオンにしてください。';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'そのファイルはCaller’s Compendiumの共有ファイルではありません。';

  @override
  String get archiveIntakeRejectedNoContent => 'そのファイルにはダンスもプログラムも含まれていませんでした。';

  @override
  String get archiveIntakeRejectedBackup =>
      'そのファイルは共有ファイルではなくバックアップです。このデバイスに取り込むには、設定 ▸ 一般を開き、「バックアップから復元」を選んでください。';

  @override
  String get importErrorInsecureScheme => 'インポートには安全なhttps:// URLを使用する必要があります。';

  @override
  String get importErrorBlockedHost =>
      'そのURLは、アプリが取り込めないネットワーク上の場所を指しています。URLを確認してから、もう一度お試しください。';

  @override
  String get importErrorInvalidUrl => '有効なhttp(s) URLのように見えません。';

  @override
  String get importErrorUnsupportedSharedLink => 'このリンクはインポートに対応していません。';

  @override
  String get importErrorTooManyRedirects =>
      'そのURLはリダイレクトが多すぎます。ブラウザで開いて最終的なアドレスを確認し、そちらを使用してください。';

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
    return 'サーバーから予期しない応答がありました（コード$status）。URLを確認して、もう一度お試しください。';
  }

  @override
  String get importErrorHttpNotFound =>
      'そのアドレスには何も見つかりませんでした。URLを確認して、もう一度お試しください。';

  @override
  String get importErrorHttpBusy =>
      'サーバーが混み合っているか、問題が発生しています。1分ほど待ってから、もう一度お試しください。';

  @override
  String get importErrorEmptyResponse =>
      'URLから空の応答が返されました。リンクがインポートしたいデータを指しているか確認して、もう一度お試しください。';

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
      'そのリンクはサポートされているCaller\'s Boxのリンクではありません。ibiblio.orgまたはwww.ibiblio.orgの/contradance/thecallersbox/以下のリンクを貼り付けるか、ダンスの数値IDを入力してください。';

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
  String importErrorCallersBoxTimeout(int seconds) {
    return 'The Caller\'s Boxから$seconds秒以内に応答がありませんでした。接続を確認して、もう一度お試しください。';
  }

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Boxから予期しない応答がありました（コード$status）。1分ほど待ってから、もう一度お試しください。';
  }

  @override
  String get importErrorCallersBoxHttpNotFound =>
      'The Caller\'s Boxにそのidのダンスはありません。番号またはリンクを確認して、もう一度お試しください。';

  @override
  String get importErrorCallersBoxHttpBusy =>
      'The Caller\'s Boxは現在混み合っています。1分ほど待ってから、もう一度お試しください。';

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Boxが空のページを返しました。1分ほど待ってから、もう一度お試しください。';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Boxからインポートできるダンスが返されませんでした。idまたはリンクを確認して、もう一度お試しください。';

  @override
  String get importErrorCallersBoxImportFailed =>
      'The Caller\'s Boxのダンスをインポートできませんでした。';

  @override
  String get importErrorContraDbEmptyTitle =>
      'ContraDBを検索するには、タイトルまたは作者を入力してください。';

  @override
  String get importErrorContraDbUnsupportedFigure =>
      'ContraDBのFigure検索には、「box circulate」のような完全な技名を使用してください。';

  @override
  String get importErrorContraDbUnsupportedAdvanced =>
      'ContraDBでは、「フィギュアを含む」と「シーケンス（次に）」の条件を「すべてに一致」「いずれかに一致」「どれにも一致しない」のグループで組み合わせた詳細検索のみ実行できます。ContraDBを検索するには、タグ、フィギュアのセクション、ContraDBに完全に対応するものがない技、その他の条件を削除してください。';

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
      'そのリンクはサポートされているContraDBのホストではありません。contradb.comまたはwww.contradb.comのリンクを貼り付けるか、ダンスまたはプログラムの数値IDを入力してください。';

  @override
  String get importErrorContraDbUnreachable =>
      'ContraDBに到達できませんでした。接続を確認して、もう一度お試しください。';

  @override
  String importErrorContraDbTimeout(int seconds) {
    return 'ContraDBから$seconds秒以内に応答がありませんでした。接続を確認して、もう一度お試しください。';
  }

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDBから予期しない応答がありました（コード$status）。1分ほど待ってから、もう一度お試しください。';
  }

  @override
  String get importErrorContraDbHttpNotFound =>
      'ContraDBにそのidのダンスはありません。番号またはリンクを確認して、もう一度お試しください。';

  @override
  String get importErrorContraDbHttpBusy =>
      'ContraDBは現在混み合っています。1分ほど待ってから、もう一度お試しください。';

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDBが空のレスポンスを返しました。1分ほど待ってから、もう一度お試しください。';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDBからインポートできるダンスが返されませんでした。idまたはリンクを確認して、もう一度お試しください。';

  @override
  String get importErrorContraDbImportFailed => 'ContraDBのダンスをインポートできませんでした。';

  @override
  String get importIssueGeneric => 'この項目は注記付きでインポートされました。';

  @override
  String get importIssueProgramEmptySlot => 'プログラム内の空のスロットをスキップしました。';

  @override
  String get importIssueProgramDeletedDance =>
      'プログラムが Caller\'s Companion で削除されたダンスを参照していたため、そのスロットを省きました。';

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
  String get importIssueArchiveNewerSchema =>
      'これは新しいバージョンの Caller\'s Compendium で作成されました。インポートする前にアプリを更新してください。更新しないと、一部の詳細が含まれない場合があります。';

  @override
  String importIssueArchiveCustomFieldKeyConflict(String label, String key) {
    return 'あなたのカスタムフィールド「$label」は、このファイルでは種類または選択肢が異なるため、ファイルの値は代わりにキー「$key」のフィールドに入ります（まだない場合は追加されます）。あなたのフィールドは変更されません。';
  }

  @override
  String get importIssueArchiveCustomFieldKeyConflictGeneric =>
      'このファイル内のカスタムフィールドは、キーがすでに使われているためそのキーを使えず、代わりに番号付きのキーのフィールドに値が入ります。';

  @override
  String get importIssueUsrFileTruncated =>
      'このファイルは不完全のようです。一部しか読み取れませんでした。元のファイルからもう一度コピーして、再度インポートしてください。';

  @override
  String get importIssueUsrFiguresFromDanceRows =>
      'このファイルから フィギュアを読み取れなかったため、ダンスが フィギュアなしで取り込まれる場合があります。元のファイルを確認するか、Caller\'s Companion から再度エクスポートしてください。';

  @override
  String get importIssueUsrPhraseGroupsOrphaned =>
      '一部のフィギュアをダンスに関連付けられなかったため、除外しました。ダンスが完全に取り込まれているか確認するか、元のファイルからもう一度コピーしてください。';

  @override
  String get importIssueUsrLinesDropped =>
      '非常に長いフィギュアの行の一部を除外しました。各ダンスの残りはインポートされています。';

  @override
  String get importIssueUsrSetsSkipped =>
      'このファイルからプログラムを完全には読み取れなかったため、一部が欠けているか、ダンスなしで取り込まれる場合があります。インポート後に確認してください。';

  @override
  String get importIssueUsrRelatedRowsSkipped =>
      'このファイル内の関連ダンスのリンクの一部が無効だったため、スキップしました。';

  @override
  String get importIssueUsrTermsSkipped =>
      'このファイルの用語集の用語の一部は、長すぎて保持できないか読み取れなかったため、取り込まれませんでした。';

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
      'ダンスの詳細情報のみが利用可能で（フィギュアなし）、フィギュアなしでインポートしました。';

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
  String importIssueNewLevel(String level) {
    return 'レベル「$level」を難易度に追加します。';
  }

  @override
  String get importIssueUnmappedProgression =>
      'プログレッションを認識できませんでした。既定でシングルにしました。';

  @override
  String get importIssueBarsMeterUnstated =>
      'このダンスは小節で数えていますが拍子の記載がないため、1小節を2拍として数えました。カウントを確認してください。';

  @override
  String get importIssueBarsMeterMixed =>
      'このダンスは小節で数えていますが、小節の長さが異なる拍子が記載されているため、1小節を2拍として数えました。カウントを確認してください。';

  @override
  String get importIssueUnmappedType =>
      'ダンスの種類を認識できませんでした。コントラとしてインポートし、ノートに保持しました。';

  @override
  String importIssueUnparsedDate(String field) {
    return '$fieldの日付を読み取れませんでした。未設定のままです。';
  }

  @override
  String get importIssueCcUserFieldKeyAdjusted =>
      'Caller\'s Companionのフィールドのキーを、有効かつ一意になるよう調整しました。名前はそのまま保持されます。';

  @override
  String get importIssueCcUserFieldLabelMissing =>
      'Caller\'s Companionのフィールドに名前がなかったため、汎用的な名前を付けました。';

  @override
  String get importIssueUnparsedRating => '評価を読み取れませんでした。未評価のままです。';

  @override
  String get importIssueFiguresUnreadable =>
      'フィギュアを読み取れませんでした。フィギュアはインポートされませんでした。';

  @override
  String get importIssueBeatsUnreadable => '拍数を読み取れませんでした。0を使用しました。';

  @override
  String get importIssueNoFiguresTable => 'ページにフィギュアがなかったため、フィギュアなしでインポートしました。';

  @override
  String get importIssueMoveFallback =>
      'フィギュアを既知のムーブに一致させられませんでした。認識できないフィギュアとしてインポートしました。';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'フィギュア$positionを既知のムーブに一致させられませんでした。認識できないフィギュアとしてインポートしました。';
  }

  @override
  String get importIssueParamUnmapped => 'フィギュアの設定の1つを対応付けられなかったため、既定値を使用しました。';

  @override
  String importIssueParamValueUnmapped(String param) {
    return '設定「$param」を変換できなかったため、既定値を使用しました。';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'フィギュアに$provided個の設定がありましたが、対応付けられたのは$mapped個のみです。余った分は無視されました。';
  }

  @override
  String get importIssueRelatedDanceUnresolved =>
      '関連ダンスのリンクがインポートされていないダンスを参照していたため、リンクはスキップされました。';

  @override
  String get importIssueDuplicateExternalIdInBatch =>
      'ソースが1回のインポートでこのダンスを2回挙げていました。重複したコピーは除外されました。';

  @override
  String get importDateFieldComposed => '振付';

  @override
  String get importDateFieldRevised => '改訂';

  @override
  String get importRecordErrorDiscover => 'このレコードが見つかりませんでした。';

  @override
  String get importRecordErrorEmptyFile =>
      'このファイルまたはテキストは空です。内容のあるファイルを選ぶか、テキストをもう一度貼り付けてください。';

  @override
  String get importRecordErrorNotJson =>
      'JSONファイルではありません。取得元がエクスポートした .json ファイルを選ぶか、JSONをもう一度貼り付けてください。';

  @override
  String get importRecordErrorNotCompendiumArchive =>
      '共有ファイルではありません。このアプリからエクスポートした .json または .ccshare ファイルを選んでください。';

  @override
  String get importRecordErrorNotCallersBoxDance =>
      'Caller\'s Box のダンスではありません。The Caller\'s Box からダンスをコピーしたか確認して、もう一度お試しください。';

  @override
  String get importRecordErrorNotContraDbDance =>
      'ContraDB のダンスではありません。ContraDB からダンスのページをコピーしたか確認して、もう一度お試しください。';

  @override
  String get importRecordErrorNotUsrDatabase =>
      'これはCaller\'s Companionのデータファイル（.USR）ではありません。Caller\'s Companionのデータフォルダー内にある.USRファイルを探してください。';

  @override
  String get importRecordErrorFileTooLarge =>
      'ファイルが大きすぎてインポートできません。より小さいファイルを選ぶか、いくつかに分割してください。';

  @override
  String get importRecordErrorNoDanceAtId =>
      'ダンスが見つかりませんでした。Caller\'s Box のダンスのIDまたはリンクを確認して、もう一度お試しください。';

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
      'Caller\'s Companion .USRファイルを選択して、ダンスとプログラム履歴を移行してください。確認して承認するまでライブラリには何も追加されません。';

  @override
  String get importReviewChooseUsr => '.USRファイルを選択…';

  @override
  String get importReviewFileReady => 'ファイルの準備ができました。';

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
  String importReviewWillImportPrograms(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプログラムも含まれます。',
    );
    return '$_temp0';
  }

  @override
  String get importReviewCouldNotRead => 'インポートを読み取れませんでした';

  @override
  String get importReviewPlanFailedBody =>
      'この取り込みを読み取れませんでした。何も追加されていません。もう一度お試しください。繰り返し起こる場合は、ファイルが破損している可能性があります。';

  @override
  String get importReviewNoDancesTitle => 'ダンスが見つかりませんでした';

  @override
  String get importReviewNoDancesBody => 'ファイルにインポートできるダンスが含まれていませんでした。';

  @override
  String get importReviewTryAnother => '別のファイルを試す';

  @override
  String get importReviewImported => 'インポート済み';

  @override
  String get importReviewImportAndEdit => 'インポートして編集';

  @override
  String importReviewStructured(int structured, int total) {
    return '$total件中$structured件が構造化';
  }

  @override
  String get importReviewCustom => '認識できない';

  @override
  String get importReviewOptionNewDance => '新しいダンス';

  @override
  String get importReviewBulkSetAllLabel => '一致したすべてのダンスを次に設定:';

  @override
  String get importReviewBulkReimport => '再インポート';

  @override
  String get importReviewBulkSkip => 'スキップ';

  @override
  String get importReviewBulkSkipAmbiguous => '可能性のある一致をすべてスキップ';

  @override
  String get importReviewOptionSkip => 'スキップ';

  @override
  String importReviewOptionReimport(String title) {
    return '「$title」に再インポート';
  }

  @override
  String get importReviewReimportTitleAndCredit => 'タイトルと作者も更新する';

  @override
  String importReviewReimportTitleAndCreditHint(String title) {
    return '「$title」にこのファイルのタイトルと作者を反映します。評価、タグ、メモ、リンクはそのまま残ります。';
  }

  @override
  String get importReviewOptionDuplicate => '新しい（重複）ダンスとしてインポート';

  @override
  String get importReviewPossibleMatch => '候補が見つかりました — インポート方法を選択してください:';

  @override
  String get importReviewPossibleTitleMatch =>
      '別のタイトルで既にあるダンスかもしれません — インポート方法を選択してください:';

  @override
  String importReviewOptionPossibleTitle(String title) {
    return '別のタイトルの同じダンス – 「$title」をこのバージョンで置き換える';
  }

  @override
  String importReviewOptionLink(String title, int percent) {
    return '同じダンス – 「$title」をこのバージョンで置き換える（$percent%一致）';
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
  String importReviewReimportWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '再インポートで$count件の既存のダンスのフィギュア、フォーメーション、プログレッションが置き換えられ、ダンスの形式が変わることもあります。評価、タグ、メモは残ります。',
    );
    return '$_temp0';
  }

  @override
  String importReviewReimportTitleWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'そのうち$count件はファイルのタイトルと作者も反映します。',
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
  String importReviewSummaryFigures(int count) {
    return '用語集に追加または更新したフィギュア: $count';
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
  String importReviewNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のメモ:',
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
  String get importReviewEditError => '編集するためにそのダンスを取り込めませんでした。もう一度お試しください。';

  @override
  String get importUsrEnglishTitle => 'これらはイングリッシュ・カントリーダンスですか？';

  @override
  String get importUsrEnglishBody =>
      'Caller\'s Companion ではイングリッシュ・カントリーダンスが Contra として登録されていることがよくあります。このファイルにイングリッシュのダンスが入っている場合は、イングリッシュのフィギュア、フォーメーション、小節数で読み込み、Square として登録されたダンスはスクエアのセットで踊るイングリッシュのダンスになります。';

  @override
  String get importUsrEnglishNo => 'いいえ、種類どおりに読む';

  @override
  String get importUsrEnglishYes => 'はい、イングリッシュ';

  @override
  String get importReviewEditOverwriteTitle => '既存のダンスを今すぐ置き換えますか？';

  @override
  String importReviewEditOverwriteBody(String title) {
    return '編集のためにインポートすると、コレクション内の「$title」がすぐに置き換えられます。一括インポートの「元に戻す」では復元されません。';
  }

  @override
  String get importReviewEditOverwriteConfirm => '置き換える';

  @override
  String get importReviewEditReimportTitle => '今すぐ既存のダンスに再インポートしますか？';

  @override
  String importReviewEditReimportBody(String title) {
    return '編集のためにインポートすると、コレクション内の「$title」のフィギュア、フォーメーション、プログレッションがすぐに置き換えられ、ダンスの形式が変わることもあります。一括インポートの「元に戻す」では復元されません。';
  }

  @override
  String importReviewEditReimportTitleAndCreditBody(String title) {
    return '編集のためにインポートすると、コレクション内の「$title」のフィギュア、フォーメーション、プログレッション、タイトル、作者がすぐに置き換えられ、ダンスの形式が変わることもあります。一括インポートの「元に戻す」では復元されません。';
  }

  @override
  String get importReviewImportError => '取り込みを完了できませんでした。もう一度お試しください。';

  @override
  String get importFileNotText =>
      'そのファイルを読み込めませんでした。共有ファイルでも、アプリが読めるテキストでもありません。別のアプリでテキストとして保存したファイルなら、UTF-8で保存し直してから、もう一度お試しください。';

  @override
  String get importFileUnreadable =>
      'そのファイルを開けませんでした。別のアプリが使用中か、接続されていないドライブにある可能性があります。';

  @override
  String importReviewVariationTitle(String title) {
    return '「$title」のバリエーション？';
  }

  @override
  String importReviewVariationBody(String title) {
    return 'このダンスのタイトルと作者は「$title」と一致しますが、フィギュアが異なります。違いを確認してから、取り込み方法を選択してください。';
  }

  @override
  String importReviewOptionVariation(String title) {
    return '「$title」のバリエーションとして取り込む';
  }

  @override
  String importReviewOptionSameDance(String title) {
    return '同じダンス – 「$title」をこのバージョンで置き換える';
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
  String get danceEditorTitleRequiredLabel => 'タイトル';

  @override
  String get danceEditorTitleRequired => 'タイトルが必要です';

  @override
  String get danceEditorAuthorsLabel => '作者';

  @override
  String get danceEditorFormLabel => 'タイプ';

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
  String get danceEditorPhrasesNameThem => 'フレーズに名前を付ける';

  @override
  String get danceEditorPhrasesTitle => 'フレーズ';

  @override
  String get danceEditorPhrasesHelp =>
      '曲の各部分にA、B、Cの名前を付け、小節数と1小節の拍数、そして1回演奏するか2回演奏するかを指定します。2回演奏するフレーズはA1、A2と表示されます。';

  @override
  String get danceEditorPhrasesAdd => 'フレーズを追加';

  @override
  String danceEditorPhrasesInvalid(int maxBars, int maxBeats) {
    return '各フレーズの小節数は1から$maxBars、1小節の拍数は1から$maxBeatsで入力してください。それまでは最後の有効なフレーズが保たれ、保存するとそれが保存されます。';
  }

  @override
  String danceEditorPhraseBarsLabel(String name) {
    return '$nameの小節';
  }

  @override
  String danceEditorPhraseBarsRange(int max) {
    return '1〜$max';
  }

  @override
  String danceEditorPhraseBeatsPerBarLabel(String name) {
    return '$nameの1小節の拍数';
  }

  @override
  String danceEditorPhraseBeatsPerBarRange(int max) {
    return '1〜$max';
  }

  @override
  String get danceEditorPhraseNameLabel => 'フレーズ名';

  @override
  String danceEditorPhrasePlaysLabel(String name) {
    return '$nameの演奏回数';
  }

  @override
  String get danceEditorPhrasePlaysOnce => '1回';

  @override
  String get danceEditorPhrasePlaysTwice => '2回';

  @override
  String danceEditorPhraseRemove(String name) {
    return 'フレーズ$nameを削除';
  }

  @override
  String get danceEditorPhraseRowsHelp =>
      '各行は、同じ長さのフレーズの並びです。フレーズの数、各フレーズの小節数、1小節の拍数を指定します。下のフレーズ構造は行に合わせて変わります。';

  @override
  String get danceEditorPhraseRowsPhrasesLabel => 'フレーズ数';

  @override
  String get danceEditorPhraseRowsBarsLabel => 'フレーズごとの小節数';

  @override
  String get danceEditorPhraseRowsBeatsLabel => '1小節の拍数';

  @override
  String danceEditorPhraseRowsRange(int max) {
    return '1〜$max';
  }

  @override
  String get danceEditorPhraseRowsAdd => '行を追加';

  @override
  String danceEditorPhraseRowsRemove(int number) {
    return '$number行目を削除';
  }

  @override
  String danceEditorPhraseRowsInvalid(int max) {
    return '各欄に1から$maxまでの整数を入力してください。長すぎる構造にはできません。それまでは最後の有効なフレーズ構造が保たれます。';
  }

  @override
  String danceEditorPhraseRowsSummary(String labels, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
      one: '1拍',
    );
    return '$labels · $_temp0';
  }

  @override
  String get danceEditorPhraseRowsDisabledNote =>
      'これらの行には最後の有効なフレーズ構造が表示されています。再び編集するには、下のフレーズ構造を修正してください。';

  @override
  String get danceEditorFiguresSection => 'フィギュア';

  @override
  String get danceEditorFiguresHelp =>
      'ムーブを入力して（例: \"sw\" → スイング）Enterキーを押すと既定値で追加されます。アプリが読み取れないテキストは認識できないフィギュアになります。';

  @override
  String get danceEditorFiguresHelpFreeText =>
      '「neighbor balance & swing」のように1行全体を入力してEnterキーを押すとフィギュアを追加できます。既存のフィギュアのムーブに1行を入力すると、そのフィギュアが置き換えられます。アプリが読み取れなかったテキストは認識できないフィギュアになります。';

  @override
  String get danceEditorNotesSection => 'ノート';

  @override
  String get danceEditorCallingNotesLabel => 'コーリングノート';

  @override
  String get danceEditorHookLabel => 'フック';

  @override
  String get danceEditorHookHint => '「なぜこれをコールするか」の1行説明';

  @override
  String get danceEditorHookHelper =>
      'このダンスをコールする理由を1行で。コーリングカードや共有する内容に表示されることがあります。';

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
  String get danceEditorAddWordingOverride => 'このダンスの呼び方をカスタマイズ';

  @override
  String get danceEditorGroupTitleLabel => 'グループ名（任意）';

  @override
  String get danceEditorGroupTitleHelper =>
      'グループ全体の名前（例：Flutterwheel）。グループのフィギュアの前に表示され、そのあとにダッシュが続きます。';

  @override
  String get danceEditorWordingOverrideLabel => 'このダンスでのフィギュアの呼び方';

  @override
  String get danceEditorWordingOverrideHelper =>
      'このダンスでこのフィギュアに表示される行を置き換えます。標準のフィギュアは検索できます。';

  @override
  String get danceEditorResetWordingOverride => '標準の呼び方を使用';

  @override
  String danceEditorWordingOverridePreview(Object text) {
    return 'プレビュー: $text';
  }

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
  String get settingsWalkthroughSnippetsEmptyTitle => '保存されたスニペットはまだありません';

  @override
  String get settingsWalkthroughSnippetsEmptyBody =>
      'ダンスのフィギュアを編集するときに、ウォークスルーの手順の説明を追加してください。';

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
  String get settingsWalkthroughSnippetEditTitle => 'スニペットを編集';

  @override
  String get danceEditorSetupTitle => 'クレジット・フォーメーション・音楽';

  @override
  String get danceEditorMoreDetailsTitle => '詳細情報';

  @override
  String get danceEditorStatusLabel => 'ステータス';

  @override
  String get danceEditorMixedLevelSubtitle => '難易度の幅が広い';

  @override
  String get danceEditorMixerSubtitle => '踊るたびにパートナーが変わります';

  @override
  String danceDetailSquareField(String field, String value) {
    return '$field：$value';
  }

  @override
  String get danceEditorSquareKindLabel => 'スクエアの種類';

  @override
  String get squareKindMain => 'メインパート';

  @override
  String get squareKindBreak => 'ブレイク';

  @override
  String get squareKindPatter => 'パター';

  @override
  String get danceEditorRepeatOrderLabel => '繰り返しの順序';

  @override
  String get squareRepeatOrderUnstated => '記載なし';

  @override
  String get squareRepeatOrderHeadsHeadsSidesSides => 'ヘッズ2回、続いてサイズ2回';

  @override
  String get squareRepeatOrderHeadsSidesHeadsSides => 'ヘッズとサイズを交互に';

  @override
  String get squareRepeatOrderAllFour => '4回、全員がアクティブ';

  @override
  String get squareRepeatOrderOther => 'その他';

  @override
  String get danceEditorRepeatOrderOtherLabel => '繰り返しの順序（自由記述）';

  @override
  String get danceEditorNewPartnerLabel => '新しいパートナー';

  @override
  String get squareNewPartnerUnstated => '記載なし';

  @override
  String get squareNewPartnerNone => 'パートナーは変わらない';

  @override
  String get squareNewPartnerCorner => 'コーナー';

  @override
  String squareNewPartnerRightHand(String role) {
    return '右隣の$role';
  }

  @override
  String get squareNewPartnerOpposite => 'オポジット';

  @override
  String get squareNewPartnerOther => 'その他';

  @override
  String get danceEditorNewPartnerOtherLabel => '新しいパートナー（自由記述）';

  @override
  String get danceEditorSingingLabel => 'シンギングコール';

  @override
  String get danceEditorSingingSubtitle => '曲名はチューンに入力します';

  @override
  String get danceEditorFreeFormLabel => 'フリーフォーム';

  @override
  String get danceEditorFreeFormSubtitle => 'フレーズに従わない：フレーズ名もフレーズの確認もなし';

  @override
  String get danceEditorImproperLabel => 'インプロパーで始まる';

  @override
  String get danceEditorImproperSubtitle => 'プロパーで始まるダンスではオフのままにします。';

  @override
  String get danceEditorComposedLabel => '振付年';

  @override
  String get danceEditorComposedHelper => 'ダンスが作られた日時（年、または月/日を追加）';

  @override
  String get danceEditorInterpretedByLabel => '解釈者';

  @override
  String get danceEditorInterpretedOnLabel => '解釈年';

  @override
  String get danceEditorInterpretedOnHelper => 'ダンスが解釈された日時（年、または月/日を追加）';

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
  String get monthFullJanuary => '1月';

  @override
  String get monthFullFebruary => '2月';

  @override
  String get monthFullMarch => '3月';

  @override
  String get monthFullApril => '4月';

  @override
  String get monthFullMay => '5月';

  @override
  String get monthFullJune => '6月';

  @override
  String get monthFullJuly => '7月';

  @override
  String get monthFullAugust => '8月';

  @override
  String get monthFullSeptember => '9月';

  @override
  String get monthFullOctober => '10月';

  @override
  String get monthFullNovember => '11月';

  @override
  String get monthFullDecember => '12月';

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
  String validationSequenceExceedsPhrase(int position, int actual, int limit) {
    return 'フィギュア$positionのシーケンスは$actual拍で、始まるフレーズ（$limit拍）より長くなっています。';
  }

  @override
  String validationSequenceSpanMismatch(
    int position,
    int actual,
    int expected,
  ) {
    return 'フィギュア$positionのシーケンスのステップは$actual拍ですが、シーケンスは$expected拍です。';
  }

  @override
  String validationPhraseCountMismatch(String actual, String expected) {
    return 'フィギュアの合計は$actualですが、フレーズ構造では$expectedが必要です。';
  }

  @override
  String validationSequenceExceedsPhraseCount(
    int position,
    String actual,
    String limit,
  ) {
    return 'フィギュア$positionのシーケンスは$actualで、始まるフレーズ（$limit）より長くなっています。';
  }

  @override
  String validationSequenceSpanNoRoomCount(
    int position,
    String actual,
    String expected,
  ) {
    return 'フィギュア$positionのシーケンスで長さのあるステップが$actualを使い、$expectedのうち残りのステップの分がありません。';
  }

  @override
  String validationSequenceSpanMismatchCount(
    int position,
    String actual,
    String expected,
  ) {
    return 'フィギュア$positionのシーケンスのステップは$actualですが、シーケンスは$expectedです。';
  }

  @override
  String validationSequenceSpanNoRoom(int position, int actual, int expected) {
    return 'フィギュア$positionのシーケンスで長さのあるステップが$actual拍を使い、$expected拍のうち残りのステップの分がありません。';
  }

  @override
  String validationOtherFormFigures(
    int count,
    String danceForm,
    String figureForm,
    String pickerForm,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のフィギュア',
    );
    return 'これは$danceFormのダンスですが、$_temp0が$figureFormのものです。そのまま残りますが、フィギュアの選択肢には$pickerFormのフィギュアだけが表示されます。';
  }

  @override
  String validationFigureCrossesPhrase(int position, String label) {
    return 'フィギュア$positionが$labelの終わりを越えています。スクエアダンスでは、各フレーズのコールがそのフレーズをちょうど埋めるようにします。';
  }

  @override
  String validationIncompleteFigure(int position) {
    return 'フィギュア$positionは未完成のため、保存しても含まれません。';
  }

  @override
  String get validationPhraseInvalid => 'そのフレーズ構造は無効です。';

  @override
  String get validationPhraseNamedEnglishOnly =>
      'フレーズ名（A:、B:、C:）はイングリッシュダンス専用です。';

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
  String get danceEditorTransitiveGroup => '関連ダンスグループに含める';

  @override
  String get danceEditorTransitiveGroupHint => 'このグループのすべてのダンスを相互にリンクします。';

  @override
  String danceEditorEditItemTooltip(String item) {
    return '$itemを編集';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint => '追加または作成するには入力…';

  @override
  String get danceEditorChooseHint => '選択…';

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
  String get danceEditorSaveError =>
      'ダンスを保存できませんでした。変更内容はここに残っています。もう一度お試しください。';

  @override
  String danceEditorChoreographerDuplicate(String name) {
    return '「$name」という名前の作者はすでに存在します。名前は変更されませんでした。';
  }

  @override
  String danceEditorChoreographerCreateDuplicate(String name) {
    return '「$name」という名前の作者はすでに存在します。新しい作者は作成されませんでした。既存のものを選んでください。';
  }

  @override
  String get danceEditorFallbackDanceTitle => 'ダンス';

  @override
  String get danceEditorUnsavedDraftTitle => '未保存の下書き';

  @override
  String get danceEditorUnsavedDraftMessage => 'このダンスに未保存の下書きがあります。復元しますか？';

  @override
  String danceEditorUnsavedNewDanceDraftMessage(String title) {
    return '別の新しいダンス「$title」の未保存の下書きがあります。新しく始める代わりに、この下書きを復元しますか？';
  }

  @override
  String get danceEditorUnsavedNewDanceDraftUntitledMessage =>
      'まだタイトルのない、別の新しいダンスの未保存の下書きがあります。新しく始める代わりに、この下書きを復元しますか？';

  @override
  String danceEditorUnsavedDraftSavedAt(String when) {
    return '下書きの保存日時: $when';
  }

  @override
  String get danceEditorUnsavedDraftChangedSince =>
      '下書きの保存後に、このダンスは変更されています。下書きを復元すると、それらの変更は置き換えられます。';

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
  String get editorDraftNotSaved => '下書きを保存できていません。直近の変更はまだ保持されていません';

  @override
  String danceEditorUndoShortcutTooltip(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'apple': '元に戻す (⌘Z)',
      'other': '元に戻す (Ctrl+Z)',
    });
    return '$_temp0';
  }

  @override
  String danceEditorRedoShortcutTooltip(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'apple': 'やり直し (⇧⌘Z)',
      'other': 'やり直し (Ctrl+Shift+Z)',
    });
    return '$_temp0';
  }

  @override
  String get danceEditorDeleteDanceTooltip => 'ダンスを削除';

  @override
  String get danceEditorLoadError => 'ダンスを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get danceEditorChoreographerDetailsTitle => '作者の詳細';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'これらの詳細は、この作者のすべてのダンスで共有されます。メール、場所、故人の印はプライベートです — このデバイスにのみ保存され、共有またはエクスポートされることはありません。';

  @override
  String get danceEditorNameRequiredLabel => '名前';

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
  String danceEditorFreeTextFiguresAddedConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフィギュアを追加しました。さらに入力するか、終わったら「追加を終了」を選んでください。',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorFreeTextFinish => '追加を終了';

  @override
  String danceEditorFreeTextFinishedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフィギュアを追加しました。',
    );
    return '$_temp0';
  }

  @override
  String danceEditorFreeTextRowReplacedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'フィギュアを$count件のフィギュアに置き換えました。',
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
  String get danceEditorAddMeanwhile => 'Meanwhileを追加';

  @override
  String get danceEditorAddModifier => 'モディファイアを追加';

  @override
  String get danceEditorAddSequence => 'シーケンスを追加';

  @override
  String get danceEditorAddFiguresFromText => 'テキストからフィギュアを追加…';

  @override
  String get figureTextSheetTitle => 'テキストからフィギュアを追加';

  @override
  String get figureTextSheetHelp =>
      '「(8) neighbor balance & swing」のように、1行に1つのフィギュアを入力または貼り付けてください。フリーテキスト入力がオフでも、各行はオンのときにムーブ欄に入力した行と同じように読み取られます。ダンスを保存するまで何も保存されません。';

  @override
  String get figureTextSheetHelpDropsLabels =>
      '「A1 (8) neighbor balance & swing」のように、1行に1つのフィギュアを入力または貼り付けてください。行頭のA1のようなフレーズラベルは省かれます。フリーテキスト入力がオフでも、各行はオンのときにムーブ欄に入力した行と同じように読み取られます。ダンスを保存するまで何も保存されません。';

  @override
  String get figureTextSheetFieldLabel => 'フィギュア(1行に1つ)';

  @override
  String figureTextSheetSummary(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '追加するフィギュア:$countString件',
      zero: '追加するフィギュアはまだありません',
    );
    return '$_temp0';
  }

  @override
  String figureTextSheetUnrecognizedSummary(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString行が認識できません。テキストを保持した認識できないフィギュアとして追加されるので、後で修正してください。',
    );
    return '$_temp0';
  }

  @override
  String figureTextSheetLineFigures(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'フィギュア$countString件',
      zero: 'フィギュアなし',
    );
    return '$_temp0';
  }

  @override
  String get figureTextSheetLineUnrecognized => '認識できません:認識できないフィギュアとして追加されます';

  @override
  String figureTextSheetTooLong(int max) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return '$maxString文字を超えており、一度に読み取れる量を超えています。何も追加されません。分けて追加してください。';
  }

  @override
  String figureTextSheetTooManyLines(int max) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return '$maxString行を超えており、一度に読み取れる量を超えています。何も追加されません。分けて追加してください。';
  }

  @override
  String figureTextSheetLineTooLong(int max) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return '$maxString文字を超える行があり、1行のフィギュアとして読み取れる長さを超えています。何も追加されません。複数の行に分けてください。';
  }

  @override
  String get figureTextSheetAdd => 'フィギュアを追加';

  @override
  String get figureTextSheetFromImage => '画像から…';

  @override
  String get figureTextSheetTakePhoto => '写真を撮る';

  @override
  String get figureTextSheetCameraOff =>
      'Caller\'s Compendium のカメラへのアクセスがオフになっています。写真を撮るには、「設定」アプリでオンにしてください。';

  @override
  String get figureTextSheetReadingImage => '画像を読み取り中…';

  @override
  String get figureTextSheetImageUnavailable =>
      'このデバイスは、アプリの言語でも英語でも画像の文字を読み取れません。';

  @override
  String get figureTextSheetImageEnglishOnly =>
      'このデバイスは画像を英語で読み取ります。アプリの言語では読み取れません。';

  @override
  String figureTextSheetImageTooLarge(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'この画像は$limitString MBを超えているため、読み取りませんでした。もっと小さい画像を選んでください。';
  }

  @override
  String get figureTextSheetImageTooManyPixels =>
      'この画像はピクセル数が多すぎて読み取れません。もっと小さい画像を選ぶか、トリミングしてください。';

  @override
  String get figureTextSheetImageUnreadable => 'このファイルは、このデバイスで開ける画像ではありません。';

  @override
  String get figureTextSheetImageNoText => 'この画像に文字は見つかりませんでした。';

  @override
  String get figureTextSheetImageFailed => '画像の文字を読み取れませんでした。';

  @override
  String get danceEditorPasteAtEndOfFigureList => 'フィギュアリストの末尾にペースト';

  @override
  String get danceEditorTypeFigureLabel => 'フィギュアを入力';

  @override
  String get danceEditorTypeFigureHelper =>
      '例: 「neighbor balance & swing」または「16 circle left 3/4」。Enterキーで追加します。アプリが読み取れないテキストは認識できないフィギュアとして保持されます。';

  @override
  String get danceEditorPasteHere => 'ここにペースト';

  @override
  String get danceEditorEmptyFigureName => '空のフィギュア';

  @override
  String get danceEditorCustomFigureName => '認識できないフィギュア';

  @override
  String get danceEditorEmptyFigureSummary => '（空 — ムーブを選択してください）';

  @override
  String get danceEditorEmptyFigureSemantic => '空のフィギュア、ムーブを選択してください';

  @override
  String danceEditorCompoundSummary(String name, String values) {
    return '$name：$values';
  }

  @override
  String danceEditorCompoundSemantic(String summary, String unavailable) {
    String _temp0 = intl.Intl.selectLogic(unavailable, {
      'yes': '、展開できません',
      'other': '',
    });
    return '$summary、自分のフィギュア$_temp0';
  }

  @override
  String danceEditorCompoundExpandsTo(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のフィギュア',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
    );
    return 'ダンスを保存すると$_temp0（$_temp1）になります。';
  }

  @override
  String get danceEditorCompoundUnavailable =>
      '自分のフィギュアを展開できません。削除または変更されたか、これらの値を受け付けません。保存すると、名前、拍数、メモ、プログレッションのマークだけが保持されます。';

  @override
  String get danceEditorIncompleteFigure => '未完成のため、保存しても含まれません。';

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
  String commonMoveItemUp(String name) {
    return '$nameを上に移動';
  }

  @override
  String commonMoveItemDown(String name) {
    return '$nameを下に移動';
  }

  @override
  String commonMovedItemPosition(String name, int position, int count) {
    return '$nameを$count件中$position番目に移動しました';
  }

  @override
  String get danceEditorFigureCutState => 'カット済み';

  @override
  String get danceEditorCut => 'カット';

  @override
  String get danceEditorClearProgression => 'プログレッションをクリア';

  @override
  String get danceEditorMarkProgression => 'プログレッションとしてマーク';

  @override
  String get danceEditorGroupWithNext => '次と同時進行としてグループ化';

  @override
  String get danceEditorGroupWithNextAsModifier => '次のフィギュアとモディファイアとしてグループ化';

  @override
  String get danceEditorGroupWithNextAsSequence => '次のフィギュアとシーケンスとしてグループ化';

  @override
  String get danceEditorConvertToMeanwhile => 'Meanwhileに変換';

  @override
  String get danceEditorConvertToModifier => 'モディファイアに変換';

  @override
  String get danceEditorConvertToSequence => 'シーケンスに変換';

  @override
  String get danceEditorUngroupMeanwhile => 'Meanwhileのグループ化を解除';

  @override
  String get danceEditorUngroupModifier => 'モディファイアのグループ化を解除';

  @override
  String get danceEditorUngroupSequence => 'シーケンスのグループ化を解除';

  @override
  String get danceEditorSequenceOptionLabel => 'シーケンス';

  @override
  String danceEditorSequenceGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'シーケンス（$countフィギュア）',
    );
    return '$_temp0';
  }

  @override
  String danceEditorSequenceGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countフィギュア',
      one: '1フィギュア',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
      one: '1拍',
    );
    return 'シーケンスグループ、順に$_temp0、合計$_temp1。';
  }

  @override
  String danceEditorSequenceTotalBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '合計$beats拍',
      one: '合計1拍',
    );
    return '$_temp0';
  }

  @override
  String danceEditorSequenceOverPhrase(int beats, int limit) {
    return 'このシーケンスは$beats拍で、始まるフレーズ（$limit拍）より長くなっています。';
  }

  @override
  String danceEditorSequencePhraseFull(int limit) {
    return 'これらのフィギュアで、始まるフレーズ（$limit拍）が埋まっています。';
  }

  @override
  String danceEditorSequenceStepsCapReached(int max) {
    return 'シーケンスのフィギュアは最大$max件です。';
  }

  @override
  String danceEditorSequenceStepLabel(int number) {
    return 'フィギュア$number';
  }

  @override
  String danceEditorSequenceStepSemantic(int number, int total) {
    return 'シーケンスの$total件中$number番目のフィギュア。';
  }

  @override
  String get danceEditorAddSequenceStep => '次のフィギュアを追加';

  @override
  String get danceEditorRemoveSequenceStep => 'このフィギュアを削除';

  @override
  String danceEditorModifierGroupLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'モディファイア（$countフィギュア）',
    );
    return '$_temp0';
  }

  @override
  String danceEditorModifierGroupSemantic(num beats, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countフィギュア',
      one: '1フィギュア',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats拍',
      one: '1拍',
    );
    return 'モディファイアグループ、$_temp0、$_temp1。';
  }

  @override
  String get danceEditorAddModifierChild => 'モディファイアを追加';

  @override
  String get danceEditorModifierCoreLabel => 'コア';

  @override
  String get danceEditorModifierChildLabel => 'モディファイア';

  @override
  String get danceEditorModifierCoreSemantic => 'モディファイアグループのコアフィギュア。';

  @override
  String danceEditorModifierChildSemantic(int number, int total) {
    return 'モディファイアフィギュア $number/$total。';
  }

  @override
  String get danceEditorRemoveModifierCore => 'コア・フィギュアを削除';

  @override
  String get danceEditorRemoveModifierChild => 'モディファイア・フィギュアを削除';

  @override
  String danceEditorMeanwhileGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '同時進行（$countサイド）',
    );
    return '$_temp0';
  }

  @override
  String danceEditorMeanwhileGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の同時進行フィギュア',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '共有$beats拍',
    );
    return '同時進行グループ、$_temp0、$_temp1。';
  }

  @override
  String danceEditorMeanwhileSideLabel(int number) {
    return 'サイド$number';
  }

  @override
  String danceEditorMeanwhileSideSemantic(int number, int total) {
    return '$total件中$number番目のサイド。';
  }

  @override
  String get danceEditorAddMeanwhileSide => 'サイドを追加';

  @override
  String get danceEditorRemoveMeanwhileSide => 'このサイドを削除';

  @override
  String danceEditorMeanwhileSidesCapReached(int max) {
    return '同時進行フィギュアは最大$max件です。';
  }

  @override
  String danceEditorModifierChildrenCapReached(int max) {
    return '順序付きモディファイアは最大$max件です。';
  }

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return '認識できないムーブ「$move」: このバージョンのアプリはこれを知りません。データを保持するため読み取り専用で表示しており、ムーブが認識されるようになれば通常どおり編集できます。並べ替えや削除は引き続きできます。';
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
  String get danceEditorCustomFigureTextLabel => '認識できないフィギュアのテキスト';

  @override
  String get danceEditorLingoStylingHelper =>
      'ムーブ名は点線の下線、ロール用語は下線、非推奨用語は取り消し線で表示されます';

  @override
  String danceEditorBeatTotalFreeForm(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '合計: $total拍',
    );
    return '$_temp0';
  }

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
  String get danceEditorParamNotStated => '未指定';

  @override
  String get figureParamFacingStarBackingUp => '後退する人';

  @override
  String get danceEditorParamChooseValue => '値を選択';

  @override
  String get danceEditorParamClearTooltip => 'クリア（未指定）';

  @override
  String danceEditorIntParamRangeError(int min, int max) {
    return '$minから$maxまでの整数を入力してください';
  }

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
  String danceEditorFractionAmountValue(String amount) {
    return '$amount×';
  }

  @override
  String get figureParamFractionOther => 'その他の量';

  @override
  String get figureParamFractionOtherPick => 'その他の量…';

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
  String updateBannerMacosReady(String appName, String version) {
    return '$appName $version をインストールできます。';
  }

  @override
  String get updateBannerDownloadFailed => 'アップデートをダウンロードできませんでした。もう一度お試しください。';

  @override
  String get updateDownloadFailureDestination =>
      'アップデートのダウンロード先を選べませんでした。もう一度お試しいただくか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureDestinationOccupied =>
      'その場所にはすでに何かがあります。別の名前またはフォルダを選択するか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureIncomplete =>
      'ダウンロードを完了できず、不完全なファイルは削除されました。もう一度お試しいただくか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureRefusedHost =>
      '想定外の場所を指していたため、アップデートのダウンロードは拒否されました。「リリースを見る」から手動でダウンロードしてください。';

  @override
  String get updateDownloadFailureUnreachable =>
      'アップデートをダウンロードできませんでした。接続を確認してもう一度お試しいただくか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureServerError =>
      'アップデートサーバーがファイルを提供できませんでした。しばらくしてからもう一度お試しいただくか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureDiskFull =>
      'アップデートを保存するための空きディスク容量が足りません。空き容量を確保してからもう一度お試しいただくか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureUnwritable =>
      'ダウンロード先に書き込めないため、アップデートを保存できませんでした。権限を確認してからもう一度お試しいただくか、「リリースを見る」をご利用ください。';

  @override
  String get updateDownloadFailureChecksumMismatch =>
      'ダウンロードしたアップデートがセキュリティチェックに失敗したため、削除されました。もう一度お試しいただくか、「リリースを見る」から手動でダウンロードしてください。';

  @override
  String get updateDownloadFailureHandoffFailed =>
      'アップデートはダウンロードされ検証されましたが、自動的に開けませんでした。「リリースを見る」からインストールを完了してください。';

  @override
  String get updateDownloadFailureInstallFailed =>
      'アップデートをインストールできませんでした。もう一度お試しいただくか、「リリースを見る」から手動でダウンロードしてください。';

  @override
  String get startupIntegrityCheckIncomplete =>
      '今回はデータの確認を完了できず、検証できませんでした。問題が続く場合は、バックアップからの復元をご検討ください。技術的な詳細は設定 ▸ 診断に保存されました。';

  @override
  String get startupIntegrityCheckFailed =>
      'データが安全性チェックに失敗し、破損している可能性があります。バックアップからの復元をご検討ください。';

  @override
  String get startupEcdConvertTitle => 'ECDダンスを変換しますか？';

  @override
  String get startupEcdConvertMessage =>
      'コレクション内の「ECD」タグが付いた英語以外のダンスを、すべて英語のダンスに変換しますか？';

  @override
  String get startupEcdConvertDontShowAgain => '次回から表示しない';

  @override
  String get startupEcdConvertDecline => '今はしない';

  @override
  String get startupEcdConvertConfirm => '変換';

  @override
  String startupEcdConvertSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを英語 (ECD) に変換しました。',
    );
    return '$_temp0';
  }

  @override
  String startupEcdConvertUndoneSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを元に戻しました。',
      zero: '元に戻したダンスはありません。どのダンスもその後に種類またはタグが変更されています。',
    );
    return '$_temp0';
  }

  @override
  String get appClosingMessage => '終了しています…';

  @override
  String updateBannerAvailable(String appName, String version) {
    return '$appNameの新しいバージョン（$version）が利用可能です。';
  }

  @override
  String updateBannerPortable(String appName, String version) {
    return '$appName の新しいバージョン（$version）があります。これはポータブル版のため、リリースから新しい zip または tar.gz をダウンロードしてください。';
  }

  @override
  String retirementNoticeUpcoming(String appName, String version, String date) {
    return 'このバージョンの$appName（$version）のサポートは$dateに終了します。それまでに新しいバージョンに更新してください。';
  }

  @override
  String retirementNoticePast(String appName, String version, String date) {
    return 'このバージョンの$appName（$version）のサポートは$dateに終了しました。今すぐ新しいバージョンに更新してください。';
  }

  @override
  String get retirementBannerGetUpdate => 'アップデートを入手';

  @override
  String get retirementBannerLater => '閉じる';

  @override
  String installLocationBannerMessage(String appName) {
    return '$appNameはインストールされていない可能性があります。ダウンロードしたディスクイメージまたはアーカイブから、あるいはmacOSが一時的に用意した読み取り専用の場所から実行されています。アプリを終了し、Finderで「アプリケーション」フォルダにドラッグまたはコピーしてから、そこから開いてください。すでに「アプリケーション」フォルダにある場合は、この通知を閉じてかまいません。';
  }

  @override
  String get installLocationBannerDismiss => '閉じる';

  @override
  String get settingsUpdatesRetirementTitle => 'サポート終了';

  @override
  String get updateBannerViewRelease => 'リリースを見る';

  @override
  String get updateBannerDismiss => '閉じる';

  @override
  String get updateBannerDownloadInstall => 'ダウンロードしてインストール';

  @override
  String get updateBannerUpdateRestart => 'アップデートして再起動';

  @override
  String get updateMacosReadyTitle => 'アップデートの準備はできましたか？';

  @override
  String get updateMacosReadyBody =>
      'アップデートは検証済みです。今すぐアップデートするとディスクイメージが開き、Caller\'s Compendium が閉じるため、「アプリケーション」フォルダ内で置き換えられます。';

  @override
  String get updateMacosNotNow => '今はしない';

  @override
  String get updateMacosUpdateNow => '今すぐアップデート';

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
  String commandPaletteHighlightedResult(String name, int index, int count) {
    return '$name、$count件中$index件目';
  }

  @override
  String commandPaletteResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の結果',
    );
    return '$_temp0';
  }

  @override
  String commandPaletteResultCountCapped(int shown, int total) {
    return '$total件中$shown件を表示しています';
  }

  @override
  String get collectionPickerSearchLabel => 'ダンスを検索';

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
  String collectionPickerAddSemantic(String title) {
    return '$titleをプログラムに追加';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return '$titleを追加';
  }

  @override
  String collectionPickerAddedTooltip(String title) {
    return '$titleを追加しました';
  }

  @override
  String collectionPickerReplaceSemantic(String title) {
    return '$titleに置き換え';
  }

  @override
  String collectionPickerReplaceTooltip(String title) {
    return '$titleに置き換え';
  }

  @override
  String collectionPickerInProgramSemantic(String title) {
    return '$titleはすでにプログラムに含まれています';
  }

  @override
  String collectionPickerInProgramCountSemantic(String title, int count) {
    return '$titleはプログラムに$count回含まれています';
  }

  @override
  String get userGuideTitle => 'ユーザーガイド';

  @override
  String userGuideMissing(String label) {
    return '「$label」ガイドはまだ利用できません。';
  }

  @override
  String get userGuideLoadError => 'ユーザーガイドを読み込めませんでした。もう一度お試しください。';

  @override
  String get userGuideOpenOnline => 'ガイドをオンラインで開く';

  @override
  String get userGuideEnglishOnly => 'ユーザーガイドは英語で書かれています。';

  @override
  String get shorthandMappingsTitle => 'フィギュアのショートハンド';

  @override
  String get shorthandMappingsIntro =>
      'ショートハンドを使うと、フリーテキスト入力時に短いトークンを入力してここで設定した1つ以上のフィギュアに展開できます。';

  @override
  String get shorthandMappingsNew => '新しいショートハンド';

  @override
  String get shorthandMappingsEmptyTitle => 'ショートハンドはまだありません';

  @override
  String get shorthandMappingsEmptyBody => '「新しいショートハンド」を選ぶと追加できます。';

  @override
  String shorthandMappingsLimitReached(int max) {
    return 'ショートハンドの上限（$max件）に達しました。追加するには、いずれかを削除してください。';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'ショートハンドのアクション';

  @override
  String get shorthandsCompoundTitle => '自分のフィギュア用のショートハンド';

  @override
  String get shorthandsUserFigureSyncLabel => '新しいフィギュア用のショートハンド';

  @override
  String get syncSavedSearchLabel => '保存した検索';

  @override
  String get shorthandsCompoundIntro =>
      'フリーテキスト入力がオンのとき、ダンスの編集中にこれらのいずれかを1行だけ入力すると、ここで選んだ値で自分のフィギュアが追加されます。';

  @override
  String get shorthandsCompoundNew => '自分のフィギュア用の新しいショートハンド';

  @override
  String get shorthandsCompoundEmpty => '自分のフィギュア用のショートハンドはまだありません。';

  @override
  String get shorthandsCompoundUnavailable =>
      '使用できません。フィギュアが削除または変更されたか、これらの値を受け付けません。入力すると通常の行として読み取られます。';

  @override
  String get shorthandsCompoundShadowed =>
      '使用されていません。フィギュアのショートハンドに同じテキストがあります。';

  @override
  String get shorthandsUserFigureShadowedByCompound =>
      '使われません: 組み合わせ用のショートハンドが同じテキストです。';

  @override
  String get compoundShorthandEditorFigureLabel => '自分のフィギュア';

  @override
  String get compoundShorthandEditorNoFigure => '自分のフィギュアを1つ選んでください。';

  @override
  String get compoundShorthandEditorNoCompounds =>
      'カスタムフィギュアがまだありません。先に用語集で追加してください。';

  @override
  String get compoundShorthandEditorInvalidValues =>
      'これらの値はこのフィギュアに合いません。別の値を選んでください。';

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
  String shorthandEditorTokenShadowsFigure(String token) {
    return '「$token」と入力すると、すでにフィギュアが挿入されます。このショートハンドを保存すると、入力時に代わりにここで設定した内容が挿入されます。そのまま保存することもできます。';
  }

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
  String shorthandEditorErrorDuplicateHidden(String token) {
    return '「$token」は自分のフィギュア用のショートハンドとしてすでに使われています。それらはカスタムフィギュアがオンのときにここに表示されます。';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'このショートハンドの展開先に少なくとも1つのフィギュアを追加してください。';

  @override
  String get importShorthandSeedTitle => 'フィギュアのショートハンドを作成';

  @override
  String get importShorthandSeedIntro =>
      'Caller\'s Companionファイルのコールボタンをフィギュアのショートハンドにできます。必要なものを選んでください。それぞれが表示されたフィギュアに展開されます。確認するまで何も追加されず、既存のショートハンドが上書きされることはありません。';

  @override
  String get importShorthandSeedAvailableHeader => 'コールボタンから';

  @override
  String get importShorthandSeedUsePrimary => 'プライマリ';

  @override
  String get importShorthandSeedUseAlt => '代替';

  @override
  String get importShorthandSeedConflictHeader => '定義済みのためスキップ';

  @override
  String importShorthandSeedConflictNote(String token) {
    return '「$token」という名前のショートハンドがすでに存在するため、このボタンはそのままにしました。';
  }

  @override
  String get importShorthandSeedSkip => 'スキップ';

  @override
  String importShorthandSeedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のショートハンドを作成',
      zero: 'ショートハンドを作成',
    );
    return '$_temp0';
  }

  @override
  String get importUserFiguresTitle => 'このファイルのフィギュア';

  @override
  String get importUserFiguresIntro =>
      'インポートしたダンスは、送信者が作成したフィギュアを使っています。用語集に追加するものを選んでください。フィギュアを追加しないダンスは、共有されたときの行を表示します。';

  @override
  String get importUserFiguresNewHeader => '新しいもの';

  @override
  String get importUserFiguresDiffersHeader => '自分のものと異なる';

  @override
  String get importUserFiguresCopyHeader => 'コピーとして追加';

  @override
  String get importUserFiguresCopyNote =>
      'このデバイスはそのIDを以前に使ったため、新しいIDで追加されます。インポートしたダンスはコピーを使います。';

  @override
  String get importUserFiguresSameHeader => 'すでに用語集にあるもの';

  @override
  String get importUserFiguresNameTaken =>
      'この名前はすでに使われているため、用語集で「名前の変更が必要」と表示されます。';

  @override
  String get importUserFiguresKeepMine => '自分のものを残す';

  @override
  String get importUserFiguresUseTheirs => '相手のものを使う';

  @override
  String get importUserFiguresSkip => 'スキップ';

  @override
  String importUserFiguresConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の変更を適用',
      zero: '完了',
    );
    return '$_temp0';
  }

  @override
  String importUserFiguresFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のフィギュアを用語集に保存できませんでした。',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のショートハンドを作成しました',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedUnreadableNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のコールボタンは、テキストをフィギュアとして読み取れないため除外されました。',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedRoomHint(int free, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      free,
      locale: localeName,
      other: 'あと$free件追加できます（上限$max件）。選択したままの先頭$free件だけが追加されます。',
      zero: 'ショートハンドの一覧がいっぱい（$max件）のため、追加できません。',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedLimitSkipped(int skipped, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other:
          '一覧がいっぱい（上限$max件）のため、$skipped件のショートハンドは追加されませんでした。追加するには、いずれかを削除してください。',
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
  String get reparseConfirmTitle => '認識できないフィギュアをアップグレードしますか？';

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
    return '$_temp0内の$_temp1を再確認します。各ダンスのタグ、評価、ノート、その他すべてはそのまま保持されます。既知のムーブが認識されたフィギュアのみが置き換えられます。';
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
    return '$_temp0の認識できないフィギュアをアップグレードしました。';
  }

  @override
  String get reparseScreenTitle => '認識できないフィギュアを再確認';

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
    return 'フィギュア認識の改善により、$_temp0内の$_temp1をアップグレードできます。以下で確認してから承認してください — 承認するまで何も変更されず、タグ、評価、ノートはすべて保持されます。';
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
      '現時点では、インポートされた認識できないフィギュアの中に既知のムーブとして認識できるものはありません。将来のアップデートでフィギュアの認識が改善されたら再確認してください。';

  @override
  String get reparseErrorTitle => 'フィギュアを確認できませんでした';

  @override
  String get reparseErrorBody => 'コレクションをスキャンできませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get ecdMigrationScreenTitle => 'イングリッシュダンスを変換';

  @override
  String ecdMigrationIntro(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のイングリッシュダンス',
    );
    return '$_temp0が、まだコントラのムーブ、認識できないフィギュア、またはコントラのフォーメーションを使っています。変換するダンスを選んでから確認してください。イングリッシュでの意味がはっきりしないムーブはそのまま残ります。';
  }

  @override
  String ecdMigrationPreviewMoves(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '変換するムーブ: $count件',
    );
    return '$_temp0';
  }

  @override
  String ecdMigrationPreviewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '読み取れるようになった認識できないフィギュア: $count件',
    );
    return '$_temp0';
  }

  @override
  String get ecdMigrationPreviewShape => 'イングリッシュのフォーメーション';

  @override
  String ecdMigrationConvertButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンスを変換',
    );
    return '$_temp0';
  }

  @override
  String get ecdMigrationConfirmTitle => 'これらのイングリッシュダンスを変換しますか？';

  @override
  String ecdMigrationConfirmBody(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンス',
    );
    return '$_temp0のフィギュアとフォーメーションが変わります。タグ、評価、メモなどはすべてそのまま残ります。元に戻せないため、先にバックアップをとることをおすすめします。';
  }

  @override
  String get ecdMigrationConfirmAction => '変換';

  @override
  String ecdMigrationDoneSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount件のダンスを変換しました。',
    );
    return '$_temp0';
  }

  @override
  String get ecdMigrationNothingSnack => '変換するものはありません。';

  @override
  String get ecdMigrationFailed => 'ダンスを変換できませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get ecdMigrationEmptyTitle => '変換するものはありません';

  @override
  String get ecdMigrationEmptyBody =>
      '変換できるものがあるイングリッシュ・カントリーダンスはありません。イングリッシュでの意味がはっきりしない動きはそのまま残ります。';

  @override
  String get ecdMigrationErrorTitle => 'イングリッシュダンスを確認できませんでした';

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
  String customFieldsDeleteFailed(String label) {
    return '「$label」を削除できませんでした。もう一度お試しください。';
  }

  @override
  String customFieldsKeyDuplicate(String key) {
    return 'キーが「$key」のフィールドはすでに存在します。キーは変更されませんでした。';
  }

  @override
  String customFieldsKeyDuplicateNew(String key) {
    return 'キーが「$key」のフィールドはすでに存在します。新しいフィールドは作成されませんでした。';
  }

  @override
  String get customFieldsTitle => 'カスタムフィールド';

  @override
  String get customFieldsNewField => '新しいフィールド';

  @override
  String get customFieldsLoadError =>
      'カスタムフィールドを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get customFieldsEmptyTitle => 'カスタムフィールドはまだありません';

  @override
  String get customFieldsEmptyBody => '「新しいフィールド」を選ぶと追加できます。';

  @override
  String get customFieldsFlagInList => 'リストに表示';

  @override
  String get customFieldsSearchable => '検索可能';

  @override
  String get customFieldsTypeText => 'テキスト';

  @override
  String get customFieldsTypeNumber => '数値';

  @override
  String get customFieldsTypeBoolean => 'はい/いいえ';

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
  String get customFieldsLabelLabel => 'ラベル';

  @override
  String get customFieldsLabelRequired => 'ラベルが必要です';

  @override
  String get customFieldsKeyLabel => 'キー';

  @override
  String get customFieldsKeyHelper =>
      'このフィールドの短い識別名です。使えるのは文字・数字・アンダースコアのみで、文字またはアンダースコアで始める必要があります。ダンスで使われ始めると変更できません。';

  @override
  String get customFieldsKeyLocked => 'キーはロックされています — フィールドはダンスで使用中';

  @override
  String get customFieldsKeyRequired => 'キーが必要です';

  @override
  String get customFieldsKeyInvalid =>
      'キーは文字またはアンダースコアで始まり、文字、数字、アンダースコアのみを含む必要があります';

  @override
  String get customFieldsSaveFailed =>
      'フィールドを保存できませんでした。キーと選択肢を確認してから、もう一度お試しください。';

  @override
  String get customFieldsTypeFieldLabel => 'タイプ';

  @override
  String get customFieldsTypeLocked => 'タイプはロックされています — フィールドにはダンスの値があります';

  @override
  String get customFieldsShowInList => 'リストに表示';

  @override
  String get customFieldsShowInListSubtitle => 'ダンスリストのタイルにこのフィールドの値を表示します';

  @override
  String get customFieldsSearchableSubtitle =>
      'このフィールドを「フィルター」パネルに表示し、検索バーでその値を検索できるようにします';

  @override
  String get customFieldsSearchableSubtitleYesNo => 'このフィールドを「フィルター」パネルに表示します';

  @override
  String get customFieldsChoicesLabel => '選択肢';

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
  String get customFieldsShareable => '共有に含める';

  @override
  String get customFieldsShareableSubtitle =>
      'このフィールドの値はコレクションを共有するときに一緒に送られます。バックアップには常に含まれます';

  @override
  String get customFieldsSharingNoticeTitle => 'カスタムフィールドはコレクションと一緒に送られます';

  @override
  String get customFieldsSharingNoticeBody =>
      '作成したカスタムフィールドの内容はバックアップに含まれます。コレクションを共有するときにフィールドを非公開にするには、そのフィールドの設定で「共有に含める」をオフにしてください。';

  @override
  String get customFieldsSharingNoticeOk => '了解';

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
  String get dialectEditorMoveSubHint => '置き換え（左右の指定には%Sを使用）';

  @override
  String get dialectEditorAddMove => 'ムーブを追加…';

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
  String get dialectEditorDiscouragedResetTitle => '推奨されない用語をデフォルトに戻しますか？';

  @override
  String get dialectEditorDiscouragedResetBody => '現在の推奨されない用語をデフォルトに置き換えます。';

  @override
  String get dialectEditorExitTitle => '変更を保存しますか？';

  @override
  String get dialectEditorExitBody => 'この方言には未保存の変更があります。';

  @override
  String get dialectEditorSaveAndExit => '保存して終了';

  @override
  String get dialectEditorExitWithoutSaving => '保存せずに終了';

  @override
  String get dialectEditorPreviewHelp =>
      'このダイアレクトでレンダリングされたサンプルフィギュア。編集に合わせて更新されます。';

  @override
  String get recentlyDeletedTitle => '最近削除したアイテム';

  @override
  String get recentlyDeletedLoadError =>
      '最近削除したアイテムを読み込めませんでした。何も削除されていません。もう一度お試しください。';

  @override
  String get recentlyDeletedDeleteTitle => '完全に削除しますか？';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '「$title」を今すぐ削除します。';
  }

  @override
  String get recentlyDeletedDeleteConfirm => '完全に削除';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '「$title」を完全に削除しました。';
  }

  @override
  String recentlyDeletedDeletedSyncedSnack(String title) {
    return '「$title」を完全に削除しました。他のデバイスでも削除されるよう、小さな削除記録が残ります。';
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
      '最近削除したダンスはありません。削除したダンスは手動で削除するまでここに保持されます。';

  @override
  String get recentlyDeletedEmptyTitle => '削除されたものはありません';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return '最近削除したダンスはありません。削除したダンスは削除されるまで$days日間ここに表示されます。';
  }

  @override
  String get recentlyDeletedEmptyProgramsKept =>
      '最近削除したプログラムはありません。削除したプログラムは手動で削除するまでここに保持されます。';

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return '最近削除したプログラムはありません。削除したプログラムは削除されるまで$days日間ここに表示されます。';
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
  String get venueLoadError => '会場を読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get venueManagerTitle => '会場';

  @override
  String get venueManagerSearchHint => '会場を検索…';

  @override
  String get venueManagerClearSearchTooltip => '検索をクリア';

  @override
  String get venueManagerEmptyBody =>
      'ここから追加するか、再利用可能な会場をオンにしたプログラムから追加してください。';

  @override
  String get venueManagerEmptyTitle => '会場はまだありません';

  @override
  String get venueManagerNoMatches => '検索に一致する会場がありません。';

  @override
  String get venueLinkOfferTitle => '以前のプログラムをリンクしますか？';

  @override
  String get venueLinkOfferBody =>
      '会場がテキストで入力されたプログラムの中に、会場レコードと一致するものがあります。リンクすると、コール履歴で同じ会場として数えられます。入力したテキストは残ります。';

  @override
  String venueLinkOfferRow(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプログラム',
    );
    return '「$name」：$_temp0';
  }

  @override
  String get venueLinkOfferConfirm => 'リンクする';

  @override
  String get venueLinkOfferDecline => '今はしない';

  @override
  String venueLinkOfferDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプログラムをリンクしました。',
    );
    return '$_temp0';
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
  String get venueEditorSaveError =>
      '会場を保存できませんでした。変更内容はここに残っています。もう一度お試しください。';

  @override
  String get venueEditorSharedNote =>
      '会場はここで開催されるすべてのプログラムで共有されます。住所、連絡先、スケジュールを編集するとすべてに反映されます。';

  @override
  String get venueEditorPartialSyncHint =>
      'この会場の下にある住所と連絡先の項目はこのデバイスにのみ残ります — デバイス同期はそれらを他のデバイスに伝えないため、他のデバイスでは空欄になることがあります。メモ欄は同期されるので、連絡先情報をこのデバイスだけに留めたい場合はメモに書かないようにしてください。';

  @override
  String get venueEditorNameLabel => '名前';

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

  @override
  String get danceReimport => '振り付けを再インポート';

  @override
  String get danceReimportJson => 'Caller’s Compendium JSON';

  @override
  String get danceReimportLinkOrId => 'リンクまたはID';

  @override
  String get danceReimportNoResults =>
      '一致するダンスが見つかりませんでした。リンクまたはIDを試すか、別のソースを選ぶか、後でもう一度お試しください。';

  @override
  String get danceReimportFiguresUnavailable =>
      'そのソースからこのダンスのフィギュアが提供されなかったため、振り付けを更新できません。ダンスは変更されていません。';

  @override
  String get danceReimportChooseResult => '再インポートするダンスを選択';

  @override
  String get danceReimportProgramArchive =>
      'このファイルにはプログラムが含まれているため、1つのダンスの再インポートには使用できません。';

  @override
  String get danceReimportInvalidJson => 'ダンスをちょうど1つ含む有効なファイルを選択してください。';

  @override
  String get danceReimportSourceFailed =>
      'その出典からダンスを読み込めませんでした。ダンスは変更されていません。もう一度お試しください。';

  @override
  String get danceReimportApplyFailed =>
      'そのソースからダンスを更新できませんでした。ダンスは変更されていません。もう一度お試しください。';

  @override
  String get danceReimported => '振り付けを更新しました。';

  @override
  String get danceReimportTargetMissing => 'このダンスは更新前に削除されました。';

  @override
  String get danceReimportTargetChanged =>
      'このダンスは更新前に変更されました。内容を確認して、もう一度お試しください。';

  @override
  String get publishedCollectionsTitle => '公開コレクション';

  @override
  String get importSourceLabelPublishedCollection => '公開コレクション';

  @override
  String get publishedCollectionsDescription =>
      'Compendium Analect から署名済みの不変なダンスコレクションをインポートします。';

  @override
  String get publishedCollectionsLoading => '公開コレクションを読み込み中…';

  @override
  String get publishedCollectionsUnavailable => '公開コレクションは一時的に利用できません。';

  @override
  String get publishedCollectionsUnverified =>
      '公開コレクションを検証できなかったため、何も読み込まれていません。繰り返し起こる場合は、アプリをアップデートしてください。';

  @override
  String get publishedCollectionsOffline =>
      '公開コレクションに接続できませんでした。接続を確認してから、もう一度お試しください。';

  @override
  String get publishedCollectionsNeedsNewerApp =>
      'これらの公開コレクションには、より新しいバージョンのアプリが必要です。アプリを更新してご覧ください。';

  @override
  String get publishedCollectionImport => 'コレクションをインポート';

  @override
  String get publishedCollectionUnsupported => 'このコレクションには新しいアプリバージョンが必要です。';

  @override
  String publishedCollectionImportedVersion(String version) {
    return 'インポート済みバージョン: $version';
  }

  @override
  String publishedCollectionHeldCount(int held, int total) {
    return '$total 件中 $held 件のダンスを保持';
  }

  @override
  String publishedCollectionDetails(String id, String version, int count) {
    return '$id · $version · ダンス $count件';
  }

  @override
  String publishedCollectionPermission(
    String license,
    String grantor,
    String holder,
    String basis,
    String fields,
  ) {
    return 'ライセンス: $license\n許可: $grantor が $holder に $basis に基づく利用許可を付与。対象フィールド: $fields';
  }

  @override
  String get publishedCollectionNoCoveredFields => 'なし';

  @override
  String publishedCollectionSupersedes(String version) {
    return 'バージョン $version を置き換え';
  }

  @override
  String get dialectEditorSectionMoveWordings => '動作の文言テンプレート';

  @override
  String get dialectEditorMoveWordingsHelp =>
      '表示専用の任意のテンプレートで、動作の通常の文を置き換えます。正規テキストと検索は変わりません。';

  @override
  String get dialectEditorMoveWordingsConditionalHelp =>
      '条件付き動作テンプレートは図形のパラメーターで選択されます。表示されたすべてのスロットを入力してください。不完全な条件付きテンプレートは無視されます。';

  @override
  String dialectEditorMoveWordingsForceHelp(String example) {
    return '役割からすでに分かる場合など、内容を追加しないスロットは省略されます（たとえばチェーンの手）。スロットの前に ! を付けて $example のようにすると、常に表示されます。';
  }

  @override
  String dialectEditorMoveWordingsConditionalLabel(String move) {
    return '$move（条件付き）';
  }

  @override
  String get dialectEditorMoveWordingBranchInOnly => 'インのみ';

  @override
  String get dialectEditorMoveWordingBranchOutOnly => 'アウトのみ';

  @override
  String get dialectEditorMoveWordingBranchInAndOut => 'インとアウト';

  @override
  String get dialectEditorMoveWordingBranchNeither => 'どちらもなし';

  @override
  String get dialectEditorMoveWordingBranchOrdinary => '通常';

  @override
  String get dialectEditorMoveWordingBranchSingleFile => '一列';

  @override
  String get dialectEditorAddMoveWording => '動作の文言テンプレートを追加…';

  @override
  String get dialectEditorMoveWordingLabel => '表示テンプレート';

  @override
  String dialectEditorMoveWordingSlots(String slots) {
    return '使用可能なスロット: $slots';
  }

  @override
  String get dialectEditorMoveWordingInvalid => 'このテンプレートは無効なため、通常の文言を使用します。';

  @override
  String dialectEditorMoveWordingSaveError(String figures) {
    return '保存する前に無効な動作表現テンプレートを修正してください: $figures';
  }

  @override
  String dialectEditorMoveWordingUnknownSlots(String slots) {
    return '不明なスロットは空になります: $slots';
  }

  @override
  String dialectEditorMoveWordingMissingSlots(String slots) {
    return 'このテンプレートでは利用可能なスロットが省略されています: $slots';
  }

  @override
  String get dialectEditorUserFigureGone => 'このデバイスにない自分のフィギュア';

  @override
  String get dialectEditorUserFigureNameHint => 'この方言でのあなたのフィギュアの呼び名';

  @override
  String get dialectEditorUserFigureNameSide =>
      'このフィギュアには %S で埋める左右がないため、フィギュア自身の名前のままになります。';

  @override
  String dialectEditorUserFigureWordingUnknownSlots(String slots) {
    return 'このフィギュアには $slots がないため、それを削除するまでフィギュア自身の表現で表示されます。';
  }

  @override
  String dialectEditorMoveWordingOptionalSlots(String slots) {
    return 'このテンプレートでは任意のスロットが省略されています: $slots';
  }

  @override
  String dialectEditorMoveWordingPreview(String preview) {
    return 'プレビュー: $preview';
  }

  @override
  String get dialectEditorMoveWordingsReset => '動作の文言テンプレートをリセット';

  @override
  String get dialectEditorMoveWordingsResetTitle => '動作の文言テンプレートをリセットしますか？';

  @override
  String get dialectEditorMoveWordingsResetBody => 'カスタムの動作文言テンプレートをすべて削除します。';

  @override
  String get dialectEditorMoveWordingConfirmTitle => '不完全な文言テンプレートを保存しますか？';

  @override
  String dialectEditorMoveWordingConfirmBody(String figures) {
    return 'これらのテンプレートでは利用可能なスロットが省略されているため、フィギュアの詳細が隠れる可能性があります:\n$figures\n\nそれでも保存しますか？';
  }

  @override
  String get settingsExperimentalShowCustomFiguresTitle => 'カスタムフィギュア';

  @override
  String get settingsExperimentalShowCustomFiguresSubtitle =>
      '自分のフィギュアを追加・編集でき、ダンスの編集時にも選べます。用語集は不要です。オフにすると非表示になりますが、削除はされません。';

  @override
  String get settingsExperimentalCustomFiguresManageTitle => 'カスタムフィギュア';

  @override
  String get settingsExperimentalCustomFiguresManageSubtitle =>
      '自分のフィギュアを追加、編集、削除します。';

  @override
  String get customFiguresTitle => 'カスタムフィギュア';

  @override
  String get customFiguresEmpty => 'カスタムフィギュアはまだありません。+ を選んで追加してください。';

  @override
  String get customFiguresEmptyTitle => 'カスタムフィギュアはまだありません';

  @override
  String get glossaryAddCustomFigure => '自分のフィギュアを追加';

  @override
  String get customFiguresNewFigure => '自分のフィギュアを追加';

  @override
  String get glossaryCustomMarker => 'カスタム';

  @override
  String get glossaryCustomNeedsRepair => '要修復';

  @override
  String get glossaryCustomNeedsRepairBody =>
      'このフィギュアはこのままでは使用できません。含まれるフィギュアまたはパラメーターのいずれかが無効になっています。編集して修復してください。';

  @override
  String get glossaryCustomRenameNeeded => '名前の変更が必要';

  @override
  String get glossaryCustomRenameNeededBody =>
      '別のフィギュアまたはショートハンドがすでにこの名前を使用しています。区別できるように、こちらの名前を変更してください。';

  @override
  String get glossaryCustomUnsupported => '新しいバージョン';

  @override
  String get glossaryCustomUnsupportedBody =>
      'この項目は新しいバージョンのアプリで作成されました。編集または使用するには、このデバイスのアプリを更新してください。';

  @override
  String glossaryCustomExpandsTo(int beats) {
    return '展開先（$beats拍）';
  }

  @override
  String get glossaryCustomGone => 'このフィギュアは削除されました。';

  @override
  String glossaryCustomDeleteTitle(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String get glossaryCustomDeleteBody =>
      '用語集から削除されます。このフィギュアを使ってすでに保存したダンスのフィギュアはそのまま残ります。';

  @override
  String get glossaryNotes => '自分のノート';

  @override
  String get glossaryNotesEmpty => 'ノートはまだありません。';

  @override
  String get glossaryNotesAdd => 'ノートを追加';

  @override
  String get glossaryNotesEdit => 'ノートを編集';

  @override
  String get glossaryNotesEditTitle => '自分のノート';

  @override
  String get glossaryNotesHint => 'コールの仕方、注意点など…';

  @override
  String get glossaryNotesTooLong => 'メモが長すぎるため保存できません。短くしてもう一度お試しください。';

  @override
  String get glossaryOverBudget =>
      '用語集のサイズが上限に達したため、保存できませんでした。ほかのフィギュアやメモを削除するか短くして空きを作り、もう一度お試しください。';

  @override
  String get compoundEditorTitleNew => '自分のフィギュアを追加';

  @override
  String get compoundEditorTitleEdit => 'フィギュアを編集';

  @override
  String get compoundEditorName => '名前';

  @override
  String get compoundEditorDefinition => '定義';

  @override
  String get compoundEditorDefinitionHelper => '1文で入力します。用語集の一覧に表示されます。';

  @override
  String get compoundEditorDescription => '詳細';

  @override
  String get compoundEditorKeywords => '別名';

  @override
  String get compoundEditorKeywordsHelper => '任意。カンマで区切ってください。';

  @override
  String get compoundEditorNotes => 'ノート';

  @override
  String get compoundEditorOptional => '任意。';

  @override
  String get compoundEditorFieldRequired => '必須';

  @override
  String get compoundEditorRequired => 'フィギュアに名前と定義を付けてください。';

  @override
  String get compoundEditorParams => 'パラメーター';

  @override
  String get compoundEditorParamsHelp => 'フィギュアを使うたびに選ぶ項目です（誰が、どちらの手で、など）。';

  @override
  String get compoundEditorParamName => 'パラメーター名';

  @override
  String get compoundEditorParamKind => '種類';

  @override
  String get compoundEditorAddParam => 'パラメーターを追加';

  @override
  String get compoundEditorRemoveParam => 'パラメーターを削除';

  @override
  String get compoundEditorParamNames => '各パラメーターに異なる名前を付けてください。';

  @override
  String get compoundEditorFigures => 'フィギュア';

  @override
  String get compoundEditorFiguresHelp => 'ダンスを保存するときに展開されるフィギュアです（順番どおり）。';

  @override
  String get compoundEditorBindings => 'パラメーターで指定';

  @override
  String get compoundEditorBindingsHelp =>
      '各フィギュアについて、どの設定をパラメーターから取るかを選びます。それ以外は設定したままになります。';

  @override
  String compoundEditorFigureN(int number, String figure) {
    return 'フィギュア$number：$figure';
  }

  @override
  String get compoundBindingFixed => 'フィギュアでの設定どおり';

  @override
  String compoundBindingOpposite(String param) {
    return '$paramの逆';
  }

  @override
  String compoundBindingUnavailable(String option, String reason) {
    return '$option（使用不可：$reason）';
  }

  @override
  String get compoundBindingNoName => 'まだ名前がありません';

  @override
  String compoundBindingWrongKind(String paramKind, String slotKind) {
    return '種類が$paramKindですが、この設定は$slotKindです';
  }

  @override
  String get compoundBindingNoOpposite => 'この種類には逆がありません';

  @override
  String get compoundBindingNoSharedValues => '指定先のすべての設定に合う値がありません';

  @override
  String compoundEditorNameTaken(String name) {
    return '「$name」はすでにフィギュアまたはショートハンドの名前として使われています。別の名前を選んでください。';
  }

  @override
  String compoundEditorNameTakenHidden(String name) {
    return '「$name」はすでにあなた自身のフィギュアの名前として使われています。カスタムフィギュアがオンのとき、用語集に表示されます。別の名前を選んでください。';
  }

  @override
  String compoundEditorNameTakenHiddenTerm(String name) {
    return '「$name」はすでに自分の用語の名前です。用語は「用語集を表示」がオンの間、用語集に表示されます。別の名前を選んでください。';
  }

  @override
  String get compoundEditorNoFigures => 'フィギュアを1つ以上追加してください。';

  @override
  String compoundEditorEmptyDomain(String param) {
    return '$paramには、指定先のすべての設定に合う値がありません。';
  }

  @override
  String get compoundEditorTooLarge =>
      'このフィギュアには、保持できる数を超えるフィギュアまたはパラメーターがあります。';

  @override
  String get compoundEditorBindingInvalid =>
      'フィギュアの設定に、もう合わないパラメーターが指定されています。「パラメーターで指定」を確認してください。';

  @override
  String get compoundEditorInvalidFigures => 'いずれかのフィギュアがまだ不完全か無効です。';

  @override
  String compoundEditorOtherFormFigures(
    int count,
    String figureForm,
    String entryForm,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のフィギュア',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'それら',
    );
    return '$_temp0は$entryFormではなく$figureFormのものです。ダンスの種類を戻すか、$_temp1を削除してください。';
  }

  @override
  String get compoundEditorTooLong => 'いずれかの欄が長すぎます。';

  @override
  String get compoundEditorUnusedTitle => '使われていないパラメーターがあります';

  @override
  String compoundEditorUnusedBody(String params) {
    return '$paramsはどのフィギュアの設定にも使われていないため、選んでも何も変わりません。';
  }

  @override
  String get compoundEditorUnusedBack => 'エディターに戻る';

  @override
  String get compoundEditorUnusedSave => 'このまま保存';

  @override
  String get glossaryEntryKindHeading => '種類';

  @override
  String get glossaryEntryKindHelp =>
      '組み合わせは、ダンスを保存すると組み込みのフィギュアになります。新しいフィギュアは、あなた自身の文言を持つ一つのフィギュアのままです。用語は、フィギュアを持たない、あなたが定義する言葉です。後からフィギュアを与えることができます。';

  @override
  String get glossaryEntryKindHelpFiguresOnly =>
      '組み合わせは、ダンスを保存すると組み込みのフィギュアになります。新しいフィギュアは、あなた自身の文言を持つ一つのフィギュアのままです。';

  @override
  String get glossaryEntryKindCombination => '組み合わせ';

  @override
  String get glossaryEntryKindNewFigure => '新しいフィギュア';

  @override
  String get glossaryEntryKindTerm => '用語';

  @override
  String get glossaryAddTerm => '用語を追加';

  @override
  String get glossaryTermTitleNew => '新しい用語';

  @override
  String get glossaryTermMakeFigure => 'フィギュアにする';

  @override
  String get glossaryTermMakeFigureTitle => 'フィギュアにする';

  @override
  String get glossaryEntryFormLabel => 'ダンスの形式';

  @override
  String get glossaryEntryFormHelper => '対象とするダンスの種類です。';

  @override
  String get userFigureEditorParamNames =>
      '各パラメーター名は文字で始め、文字・数字・_ だけを使い、それぞれ異なる名前にしてください。move、beats、text、役割名、otherHand のような他のパラメーターの反対、条件を書くための語(if、then、else、not、and、or、is)は名前に使えません。';

  @override
  String userFigureEditorChoiceLabel(int number) {
    return '選択肢 $number';
  }

  @override
  String get userFigureEditorAddChoice => '選択肢を追加';

  @override
  String get userFigureEditorRemoveChoice => '選択肢を削除';

  @override
  String get userFigureEditorDefault => '既定値';

  @override
  String get userFigureEditorNoDefault => '既定値なし';

  @override
  String get userFigureEditorFlagOff => 'オフ';

  @override
  String get userFigureEditorFlagLabel => 'オンのときの文言';

  @override
  String get userFigureEditorFlagLabelHelper => 'オンのときに文言に表示されます（例:「華やかに」）。';

  @override
  String get userFigureEditorWording => '文言';

  @override
  String userFigureEditorWordingHelp(String example) {
    return 'ダンスの中でのフィギュアの読み方です。パラメーターは $example のように波かっこで囲みます。角かっこで囲んだ部分は、そのパラメーターが空のときに省略されます。';
  }

  @override
  String userFigureEditorWordingSlots(String slots) {
    return '使えるもの: $slots';
  }

  @override
  String get userFigureEditorDefaultBeats => '既定の拍数';

  @override
  String get userFigureEditorDefaultBeatsHelper =>
      'ダンスごとに、このフィギュアを使うたびに変更できます。';

  @override
  String userFigureEditorPreview(String text) {
    return '表示: $text';
  }

  @override
  String get userFigureEditorPreviewUnavailable => '文言を完成させると、表示を確認できます。';

  @override
  String get userFigureEditorBadWording => '文言が完成していません。波かっこと角かっこを確認してください。';

  @override
  String userFigureEditorUnknownSlot(String slot) {
    return '文言に $slot が使われていますが、このフィギュアのパラメーターではありません。';
  }

  @override
  String userFigureEditorBadChoices(String param) {
    return '$param に少なくとも一つの選択肢を追加し、それぞれ異なる名前にしてください。';
  }

  @override
  String get userFigureEditorBadBeats => '既定の拍数は 0〜64 にしてください。';

  @override
  String userFigureEditorUnusedBody(String params) {
    return '文言に含まれていないため、選んでも何も変わりません: $params。';
  }

  @override
  String get glossaryCustomWording => '文言';

  @override
  String get glossaryCustomExample => '例';

  @override
  String glossaryCustomDeleteTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「最近削除したアイテム」の$count件のダンスがこのフィギュアを使っており、最後に保存した行のまま残ります。',
    );
    return '$_temp0';
  }

  @override
  String get glossaryCustomDeleteDefaults =>
      '設定の既定のフィギュアがこのフィギュアを使っており、現在の文言をプレーンテキストとして残します。';

  @override
  String glossaryCustomDeleteShorthands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'このフィギュアの$count件のショートハンドは残り、入力すると通常の行として読み取られます。',
    );
    return '$_temp0';
  }

  @override
  String glossaryCustomDeleteUses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count件のダンスがこのフィギュアを使っています。用語集から削除され、それらのダンスは現在の文言をプレーンテキストとして残します。',
      one: '1件のダンスがこのフィギュアを使っています。用語集から削除され、そのダンスは現在の文言をプレーンテキストとして残します。',
      zero: 'コレクションにこのフィギュアを使っているダンスはありません。用語集から削除されます。',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorUserFigureUnavailable =>
      '自分のフィギュアが利用できないため、この行は現在の表記のままになります。';

  @override
  String get compoundEditorDiscardBody => 'このフィギュアに未保存の変更があります。';

  @override
  String compoundParamWithKind(String param, String kind) {
    return '$param（$kind）';
  }

  @override
  String get compoundParamKindDancers => 'ダンサー';

  @override
  String get compoundParamKindDancerPair => 'ダンサーのペア';

  @override
  String get compoundParamKindHand => '手';

  @override
  String get compoundParamKindShoulder => '肩';

  @override
  String get compoundParamKindSpin => '回転方向';

  @override
  String get compoundParamKindDirection => '方向';

  @override
  String get compoundParamKindFraction => '分数';

  @override
  String get compoundParamKindRotation => '回転量';

  @override
  String get compoundParamKindPlaces => '位置の数';

  @override
  String get compoundParamKindNumber => '数';

  @override
  String get compoundParamKindBeats => '拍数';

  @override
  String get compoundParamKindFlag => 'オン/オフ';

  @override
  String get compoundParamKindChoice => '選択肢';

  @override
  String get compoundParamKindText => 'テキスト';

  @override
  String wordingConditionsHelp(String example) {
    return '場合によって言い方を変えるには、if・then・else を使った角かっこを使います。例: $example';
  }

  @override
  String wordingConditionsNames(String names) {
    return '条件で調べられるもの: $names';
  }

  @override
  String wordingIssueUnclosedGroup(String context) {
    return '「[」が閉じられていません: 「$context」。その部分が終わるところに「]」を追加してください。';
  }

  @override
  String wordingIssueStrayCloseBracket(String context) {
    return '「$context」の近くに、前に「[」のない「]」があります。削除するか、その部分が始まるところに「[」を追加してください。';
  }

  @override
  String wordingIssueUnclosedSlot(
    String brace,
    String closeBrace,
    String context,
    String example,
  ) {
    return '「$context」の「$brace」が閉じられていません。$example のように、名前の後に「$closeBrace」を追加してください。';
  }

  @override
  String wordingIssueStrayCloseBrace(
    String brace,
    String closeBrace,
    String context,
  ) {
    return '「$context」の近くに、前に「$brace」のない「$closeBrace」があります。削除するか、名前の前に「$brace」を追加してください。';
  }

  @override
  String wordingIssueBadSlot(String found, String fix) {
    return '「$found」はスロットではありません。$fix のように、波かっこには名前を一つだけ入れてください。';
  }

  @override
  String wordingIssueConditionInBraces(String found, String fix) {
    return '波かっこに入れるのは名前一つで、条件ではありません: 「$found」。場合によってだけ文言を表示するには、角かっこを使います: $fix';
  }

  @override
  String wordingIssueTooLongStored(String max) {
    return 'この文言は長すぎて保存できません。保存すると $max 文字を超えます(条件は、入力したときより保存したときのほうが少し長くなることがあります)。短くするか、条件を減らしてください。';
  }

  @override
  String wordingIssueMissingCondition(String word, String example) {
    return '「$word」の後に、調べる内容を書いてください。例: 「$example」。';
  }

  @override
  String wordingIssueMissingThen(String condition) {
    return '条件「$condition」の後に「then」と、その場合に表示する文言を書いてください。';
  }

  @override
  String wordingIssueColonForThen(String condition) {
    return '「$condition」の後には「:」ではなく「then」と書いてください。';
  }

  @override
  String wordingIssueUnknownName(String found, String names) {
    return '「$found」はこの文言で調べられるものではありません。調べられるもの: $names。';
  }

  @override
  String wordingIssueUnknownNameSuggest(
    String found,
    String suggestion,
    String names,
  ) {
    return '「$found」はこの文言で調べられるものではありません。「$suggestion」のことですか？ 調べられるもの: $names。';
  }

  @override
  String wordingIssueUnknownNameAfterIf(String found, String names) {
    return '「if」で始まる角かっこには条件が入りますが、「$found」はこの文言で調べられるものではありません。調べられるもの: $names。';
  }

  @override
  String wordingIssueUnknownNameAfterIfSuggest(
    String found,
    String suggestion,
    String names,
  ) {
    return '「if」で始まる角かっこには条件が入りますが、「$found」はこの文言で調べられるものではありません。「$suggestion」のことですか？ 調べられるもの: $names。';
  }

  @override
  String wordingIssueNameInBraces(String name, String found) {
    return '条件の中では、名前を波かっこなしで書いてください: 「$found」ではなく「$name」。';
  }

  @override
  String wordingIssueIsntForIsNot(String found, String fix) {
    return '「$found」ではなく「is not」と書いてください: 「$fix」。';
  }

  @override
  String wordingIssueSymbolForWord(String word, String found, String fix) {
    return '「$found」ではなく「$word」と書いてください: 「$fix」。';
  }

  @override
  String wordingIssueQuotedValue(String fix) {
    return '引用符を外してください: 「$fix」。';
  }

  @override
  String wordingIssueUnknownValue(String found, String name, String values) {
    return '「$found」は $name が取れる値ではありません。$name の値: $values。';
  }

  @override
  String wordingIssueUnknownValueSuggest(
    String found,
    String name,
    String suggestion,
    String values,
  ) {
    return '「$found」は $name が取れる値ではありません。「$suggestion」のことですか？ $name の値: $values。';
  }

  @override
  String wordingIssueExpectedValue(
    String before,
    String name,
    String example,
    String values,
  ) {
    return '「$before」の後に、$name が取れる値を書いてください。例: 「$example」。$name の値: $values。';
  }

  @override
  String wordingIssueListNeedsParens(String fix) {
    return '「is in」の後の値は丸かっこで囲んでください: 「$fix」。';
  }

  @override
  String wordingIssueOneOfForIsIn(String word, String found, String fix) {
    return '「$found」ではなく「$word」と書いてください: 「$fix」。';
  }

  @override
  String wordingIssueEmptyList(String example) {
    return '「is in」の後の丸かっこが空です。値を一つ以上入れてください。例: 「$example」。';
  }

  @override
  String wordingIssueUnclosedParen(String context, String before) {
    return '「(」が閉じられていません: 「$context」。「$before」の後に「)」を追加してください。';
  }

  @override
  String wordingIssueStrayCloseParen(String context) {
    return '「$context」の近くに、前に「(」のない「)」があります。削除するか、始まるところに「(」を追加してください。';
  }

  @override
  String get wordingIssueEmptyParens =>
      '「(」と「)」の間に何もありません。条件を入れるか、かっこを削除してください。';

  @override
  String wordingIssueExpectedConnective(String before, String found) {
    return '「$before」の後には「and」「or」「then」のいずれかを書いてください。「$found」はそこに置けません。';
  }

  @override
  String wordingIssueExpectedConnectiveInParens(String before, String found) {
    return '「$before」の後には「and」「or」「)」のいずれかを書いてください。「$found」はそこに置けません。';
  }

  @override
  String wordingIssueExpectedConnectiveList(String before, String fix) {
    return '「$before」の後には「and」「or」「then」のいずれかを書いてください。複数の値を調べるには、並べて書きます: 「$fix」。';
  }

  @override
  String wordingIssueExpectedListSeparator(String before, String found) {
    return 'リスト「$before」で、「$found」の前にコンマを入れるか、「)」でリストを閉じてください。';
  }

  @override
  String wordingIssueMixedAndOr(String found, String fixA, String fixB) {
    return '「$found」には「and」と「or」が混ざっていて、どちらが先か分かりません。かっこを付けてください: 「$fixA」または「$fixB」。';
  }

  @override
  String wordingIssueFlagCompare(String name) {
    return '$name はオンかオフのどちらかなので、値とは比べません。オンなら「if $name」、オフなら「if not $name」と書いてください。';
  }

  @override
  String wordingIssuePresenceOnly(String name) {
    return '$name は入力されているかどうかしか調べられません。「$name is empty」「$name is not empty」、または単に「$name」と書いてください。';
  }

  @override
  String wordingIssueNotANumber(String name, String op) {
    return '$name は数値ではないので、「$op」は使えません。「$name is …」か「$name is in (…)」を使ってください。';
  }

  @override
  String wordingIssueExpectedNumber(String op, String example, String found) {
    return '「$op」の後に $example のような数値を書いてください。「$found」は数値ではありません。';
  }

  @override
  String wordingIssueNumberOutOfRange(
    String name,
    String min,
    String max,
    String found,
  ) {
    return '$name は $min から $max までなので、$found は範囲外です。';
  }

  @override
  String wordingIssueNumberNotWhole(String name, String found) {
    return '$name は整数で数えるので、$found は値になりません。';
  }

  @override
  String wordingIssueNumberNotQuarter(String name, String found) {
    return '$name は 0.25、0.5、¾、1½ のように 4 分の 1 回転単位なので、$found は値になりません。';
  }

  @override
  String wordingIssueNegatedComparison(String fix, String found) {
    return '「$found」ではなく「$fix」と書いてください。';
  }

  @override
  String wordingIssueAmbiguous(String found, String readingA, String readingB) {
    return '「$found」は 2 通りに読めます: 「$readingA」または「$readingB」。意図したほうを書いてください。';
  }

  @override
  String get wordingIssueSecondElse =>
      'この部分にはすでに「else」があるので、二つ目は続けられません。ここで「else」が文言の一部なら、「[everyone else]」のように、その言葉を専用の角かっこで囲んでください。';

  @override
  String wordingIssueElseAfterWord(String phrase) {
    return 'ここの「else」は、それ以外のすべての場合の文言の始まりになります。「$phrase」という言葉のつもりなら、専用の角かっこで囲んでください: 「[$phrase]」。';
  }

  @override
  String wordingIssueOtherwiseWord(String found) {
    return '「$found」はここでは文言として表示されます。それ以外のすべての場合の文言を書くには「else」と書いてください。';
  }

  @override
  String wordingIssueEmptyMeansNoValue(String name, String fix) {
    return '「$name is empty」は $name に値がないかを調べるもので、選択肢「empty」を調べるものではありません。その選択肢を調べるには「$fix」と書いてください。';
  }

  @override
  String wordingIssueValueAfterConnective(
    String found,
    String word,
    String fixA,
    String fixB,
  ) {
    return '「$word」の後の「$found」は値で、調べるものではありません。調べる対象をもう一度書くか(「$fixA」)、値を並べて書いてください: 「$fixB」。';
  }

  @override
  String get wordingIssueNothingToTest =>
      'この文言はここでは何も調べられません。この文言のフィギュアがこのデバイスにないか、このバージョンのアプリが知らないため、条件を確認できません。フィギュアがあるデバイスで変更するか、条件を削除してください。';

  @override
  String wordingIssueTooLongTyped(String max) {
    return 'この文言は長すぎて読み取れません。入力した文字数が $max 文字を超えています。短くしてください。';
  }

  @override
  String wordingIssueTooDeep(String max) {
    return 'この文言は角かっこや丸かっこを入れ子にしすぎています。入れ子にできるのは $max 段までです。いくつか外してください。';
  }

  @override
  String wordingIssueTooManyNots(String max) {
    return 'この条件は「not」を入れ子にしすぎています。入れ子にできるのは $max 個までです。いくつか外してください。「not」が二つ続くと打ち消し合います。';
  }

  @override
  String get settingsCallingCardsHeader => 'コーリングカード';

  @override
  String get settingsCallingCardsEnableTitle => 'コーリングカードを印刷';

  @override
  String get settingsCallingCardsEnableSubtitle =>
      'ダンスのエクスポートメニューに「コーリングカードを印刷」を、プログラムのエクスポートメニューに「コーリングカードをまとめて印刷」を追加します。ダンス1つにつき小さなカード1枚を、下で選んだレイアウトで印刷します。';

  @override
  String get settingsCallingCardsSizeTitle => 'カードのサイズ';

  @override
  String settingsCallingCardsSizeIndexCard(String size) {
    return 'インデックスカード（$size）';
  }

  @override
  String settingsCallingCardsSizeIsoA(String name, String size) {
    return '$name（$size）';
  }

  @override
  String settingsCallingCardsSizeInches(String width, String height) {
    return '$width × $height インチ';
  }

  @override
  String settingsCallingCardsSizeMillimetres(String width, String height) {
    return '$width × $height mm';
  }

  @override
  String get settingsCallingCardsSizeCustom => 'カスタムサイズ';

  @override
  String get settingsCallingCardsWidthLabel => '幅';

  @override
  String get settingsCallingCardsHeightLabel => '高さ';

  @override
  String get settingsCallingCardsUnitInches => 'インチ';

  @override
  String get settingsCallingCardsUnitMillimetres => 'ミリメートル';

  @override
  String get settingsCallingCardsSizeInvalid => '各辺は1～14インチ（26～355 mm）にしてください。';

  @override
  String get settingsCallingCardsLandscapeTitle => '横向き';

  @override
  String get settingsCallingCardsLandscapeSubtitle => '長い辺を上にして印刷します。';

  @override
  String get settingsCallingCardsLayoutTitle => 'カードのレイアウト';

  @override
  String get settingsCallingCardsLayoutSubtitle => '各カードに何をどこに載せるかを選びます。';

  @override
  String get callingCardEditorTitle => 'コーリングカードのレイアウト';

  @override
  String get callingCardEditorFieldLabel => 'レイアウト';

  @override
  String get callingCardEditorAutosaveHint => '変更は入力中に保存されます。';

  @override
  String get callingCardEditorReset => 'デフォルトに戻す';

  @override
  String get callingCardEditorResetConfirmTitle => 'レイアウトを戻しますか？';

  @override
  String get callingCardEditorResetConfirmBody =>
      '現在のレイアウトはデフォルトのレイアウトに置き換えられます。';

  @override
  String get callingCardEditorReplaced => 'レイアウトを置き換えました。';

  @override
  String get callingCardEditorPreviewTitle => 'プレビュー';

  @override
  String callingCardEditorPreviewCaption(String size) {
    return '$sizeのカードに載せたサンプルのダンス。';
  }

  @override
  String get callingCardEditorPreviewError => 'プレビューを描画できませんでした。もう一度お試しください。';

  @override
  String callingCardEditorPreviewShrunk(int percent) {
    return 'このカードに収めるため、文字を$percent%に縮小しています。';
  }

  @override
  String get callingCardEditorPreviewOverflow =>
      'このカードは半分の大きさにしても収まらないため、下の部分が切れています。ブロックを1つ減らすか、長いブロックに lines= を付けてください。';

  @override
  String get callingCardEditorIssuesTitle => '読み取れなかった行';

  @override
  String callingCardIssueUnknownBlock(int line, String name) {
    return '$line行目：「$name」はブロックではありません。ブロックの一覧は「レイアウトの書き方」にあります。';
  }

  @override
  String callingCardIssueUnknownOption(int line, String name) {
    return '$line行目：このブロックに「$name」オプションはありません。';
  }

  @override
  String callingCardIssueBadValue(int line, String option, String value) {
    return '$line行目：「$value」は$optionには使えません。';
  }

  @override
  String callingCardIssueUnclosedQuote(int line) {
    return '$line行目：引用符が閉じられていないため、この行全体を飛ばします。';
  }

  @override
  String callingCardIssueMissingText(int line) {
    return '$line行目：text には引用符で囲んだ言葉が必要です（例：text \"Called by me\"）。';
  }

  @override
  String callingCardIssueCardNotAlone(int line) {
    return '$line行目：card はカード全体を設定するため、1行に単独で書いてください。';
  }

  @override
  String callingCardIssueEmptyBlock(int line) {
    return '$line行目：| の片側に何もありません。';
  }

  @override
  String get callingCardHelpTitle => 'レイアウトの書き方';

  @override
  String get callingCardHelpIntro =>
      '1行がカードの1段で、上から下へ並びます。行の最初にブロック名を書き、続けてオプションを付けます。ブロックの間に | を入れると横に並びます。# で始まる行は自分用のメモで、印刷されません。';

  @override
  String get callingCardHelpFields =>
      'ブロックには、ダンスにある内容のうち、設定 ▸ 既定値 ▸ 共有するダンスの項目でオンにした項目だけが印刷されます。印刷する内容のない行は場所を取りません。カードがいっぱいのときは、カード上のすべてが均等に縮小され、最小で半分のサイズになります。';

  @override
  String get callingCardHelpTapToInsert => '名前をタップすると、レイアウトに追加されます。';

  @override
  String get callingCardHelpBlocksTitle => 'ブロック';

  @override
  String get callingCardHelpOptionsTitle => 'オプション';

  @override
  String get callingCardHelpExamplesTitle => '例';

  @override
  String get callingCardHelpExampleUse => 'このレイアウトを使う';

  @override
  String get callingCardHelpBlockTitle => 'ダンスのタイトル。';

  @override
  String get callingCardHelpBlockAuthors => 'ダンスの作者と作られた年、続いて解釈した人とその年。';

  @override
  String get callingCardHelpBlockFormation => 'フォーメーション（Improper、Becket など）。';

  @override
  String get callingCardHelpBlockLevel => 'ダンスのレベル。';

  @override
  String get callingCardHelpBlockMeta =>
      'フォーメーション、レベル、ミキサー、ステータス、フレーズを、それぞれのラベル付きで1行に。';

  @override
  String get callingCardHelpBlockMusic => '曲の拍子と調、Barnes の参照を1行に。';

  @override
  String get callingCardHelpBlockFigures =>
      'フレーズ（A1、A2、B1、B2）ごとにまとめたフィギュアと、その長さ（拍数。イングリッシュのダンスでは小節数）。';

  @override
  String get callingCardHelpBlockNotes => 'コーリングノート。';

  @override
  String get callingCardHelpBlockWalkthrough => 'ウォークスルー。';

  @override
  String get callingCardHelpBlockHook => 'ダンスのフック。';

  @override
  String get callingCardHelpBlockTunes => 'おすすめの曲。';

  @override
  String get callingCardHelpBlockSources => '出典。';

  @override
  String get callingCardHelpBlockProgram => 'プログラムを印刷するときの、プログラムのタイトル。';

  @override
  String get callingCardHelpBlockNumber =>
      'プログラムを印刷するときの、プログラム内でのダンスの順番（1、2、3、または代替）。';

  @override
  String get callingCardHelpBlockText => '引用符で囲んだ自分の言葉。';

  @override
  String get callingCardHelpBlockRule => 'カードを横切る線。';

  @override
  String get callingCardHelpBlockSpace => 'ポイント単位の余白（1インチ＝72ポイント）。';

  @override
  String get callingCardHelpBlockCard => 'カード全体の設定：margin はふちの余白（ポイント単位）です。';

  @override
  String get callingCardHelpOptionSize => '文字の大きさ（ポイント単位）。';

  @override
  String get callingCardHelpOptionStyle => '太字または斜体。';

  @override
  String get callingCardHelpOptionAlign => '文字を置く位置。';

  @override
  String get callingCardHelpOptionColor => '文字や線の色（16進コード）。';

  @override
  String get callingCardHelpOptionLines => '長いブロックを印刷する最大行数。';

  @override
  String get callingCardHelpOptionLabel => '本文の前に付ける言葉。label=\"\" で何も付けません。';

  @override
  String get callingCardHelpOptionWidth =>
      '1つの段の中で、width=2 のブロックは width=1 のブロックの2倍の幅を取ります。';

  @override
  String get callingCardHelpOptionFigures =>
      'figures 用：長さ、フィギュアごとのメモ、フレーズ名、フレーズ間の線を省きます。';

  @override
  String get callingCardHelpOptionThickness => '線の太さ（ポイント単位）。';

  @override
  String get callingCardExampleClassic => 'クラシック';

  @override
  String get callingCardExampleBigPrint => '大きな文字';

  @override
  String get callingCardExampleProgram => 'プログラムの夜';

  @override
  String get callingCardExampleTeaching => 'ティーチング用';

  @override
  String get callingCardSampleTitle => 'サンプル・コントラ';

  @override
  String get callingCardSampleAuthor => 'A. コーラー';

  @override
  String get callingCardSampleNotes => '列に沿って左へスライドして進みます。';

  @override
  String get callingCardSampleFigureNote => '回り終えるまで手を離さずに。';

  @override
  String get callingCardSampleProgram => '金曜の夜のダンス';

  @override
  String get exportPrintCallingCard => 'コーリングカードを印刷';

  @override
  String get exportPrintCallingCards => 'コーリングカードをまとめて印刷';

  @override
  String exportCallingCardsCutOff(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count枚のカードが収まらず、下の部分が切れています。',
    );
    return '$_temp0';
  }

  @override
  String get callingCardHelpOptionHighlight =>
      'figures 用：動きを濃い赤の太字、ダンサーを太字、½ や 3 places などの量を青みがかった灰色で表示します。';

  @override
  String get settingsCallingCardsSheetsTitle => '1ページに複数枚';

  @override
  String get settingsCallingCardsSheetsSubtitle =>
      '普通紙に、入るだけの枚数を並べて、切り取り用の目印を付けて印刷します。用紙は印刷時に選んだものを使います。';

  @override
  String get exportCallingCardsBiggerThanPaper =>
      'カードが用紙より大きいため、1ページに1枚ずつ縮小して印刷しました。';

  @override
  String get settingsProgramTemplatesTitle => 'プログラムのテンプレート';

  @override
  String settingsProgramTemplatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'テンプレート $count 件',
      zero: 'テンプレートはまだありません',
    );
    return '$_temp0';
  }

  @override
  String get settingsProgramTemplateDefaultTitle => '既定のテンプレート';

  @override
  String get settingsProgramTemplateDefaultSubtitle =>
      '選択を求められないときに新しいプログラムの元になるもの。';

  @override
  String get settingsProgramTemplatesMigratedName => '開始プログラム';

  @override
  String get programTemplateBlankProgram => '空のプログラム';

  @override
  String get programTemplateDefaultBadge => '既定';

  @override
  String get programTemplateChooserTitle => 'テンプレートから始める';

  @override
  String get programTemplateNew => '新しいテンプレート';

  @override
  String get programTemplatesEmptyTitle => 'テンプレートはまだありません';

  @override
  String get programTemplatesEmptyBody =>
      'テンプレートは、ある種類の夜のためのダンス・メモ・休憩の初期リストです。2 つ以上あると、新しいプログラムを作るときにどれから始めるかを尋ねます。';

  @override
  String get programTemplateNameLabel => 'テンプレート名';

  @override
  String get programTemplateRename => '名前を変更';

  @override
  String get programTemplateRenameTitle => 'テンプレート名を変更';

  @override
  String programTemplateCopyName(String name) {
    return '$name（コピー）';
  }

  @override
  String get programTemplateUntitled => '名前のないテンプレート';

  @override
  String programTemplateSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 枠',
      zero: '空',
    );
    return '$_temp0';
  }

  @override
  String programTemplateDefaultWithSlots(String slots) {
    return '既定 · $slots';
  }

  @override
  String programTemplateActionsTooltip(String name) {
    return '$name の操作';
  }

  @override
  String get programTemplateEditorTitle => 'テンプレートを編集';

  @override
  String get programTemplateSlotsHeader => '枠';

  @override
  String get programTemplateSlotsSubtitle =>
      'このテンプレートから作るプログラムに最初から入るダンス・メモ・休憩。';

  @override
  String get programTemplatesLoadError => 'プログラムのテンプレートを読み込めませんでした。';

  @override
  String get programTemplateSaveError => 'テンプレートへの変更を保存できませんでした。もう一度お試しください。';

  @override
  String get settingsSuggestionsHeader => '提案';

  @override
  String get settingsSuggestionsEnabledTitle => '次のダンスを提案';

  @override
  String get settingsSuggestionsEnabledSubtitle =>
      'プログラム作成画面のダンス一覧の「並べ替え」メニューに「おすすめ順」を追加します。新しいダンスを入れる位置に合わせてダンスを並べ、その理由を示します。';

  @override
  String get settingsSuggestionsInPerformSwapTitle =>
      'パフォームモードの「このダンスを入れ替え」で使う';

  @override
  String get settingsSuggestionsInPerformSwapSubtitle =>
      'パフォームモードでダンスを入れ替えるとき、「あなたの代替」の下のダンスを、プログラム内のその位置に最も合う順に並べ、理由を示します。どのダンスも除外されません。';

  @override
  String get settingsSuggestionsEditorTitle => '提案で考慮すること';

  @override
  String get settingsSuggestionsEditorSubtitle =>
      'ダンスを提案するときに、それぞれをどれだけ重視するかを選びます。';

  @override
  String get suggestionFactorMatrixVarietyTitle => 'マトリクスの多様さ';

  @override
  String get suggestionFactorMatrixVarietyHelp =>
      'プログラムでまだ使っていない動きのあるダンスを優先します。前のダンスと同じ拍の動きは避けます。';

  @override
  String get suggestionFactorFormationBalanceTitle => '隊形のバランス';

  @override
  String get suggestionFactorFormationBalanceHelp =>
      '前のダンスと同じ隊形や、プログラムにすでに多い隊形を避けます。';

  @override
  String get suggestionFactorDifficultyCurveTitle => '難易度の流れ';

  @override
  String get suggestionFactorDifficultyCurveHelp => '夜全体の難易度を選んだ形に合わせます。';

  @override
  String get suggestionFactorVenueRecencyTitle => 'この会場での最近のコール';

  @override
  String get suggestionFactorVenueRecencyHelp =>
      'プログラムの会場で最近コールしたダンスを避けます。会場のないプログラムではこの項目を使いません。';

  @override
  String get suggestionWeightOff => 'オフ';

  @override
  String get suggestionWeightALittle => '少し';

  @override
  String get suggestionWeightALot => '強く';

  @override
  String suggestionWeightSemantic(String factor) {
    return '$factorの重み';
  }

  @override
  String get suggestionCurveShapeLabel => '形';

  @override
  String get suggestionCurveBuildThenEase => '徐々に上げて、最後は落ち着かせる';

  @override
  String get suggestionCurveEven => '一定';

  @override
  String get suggestionsResetDefaults => '既定に戻す';

  @override
  String get suggestionsResetDone => '提案で考慮することを既定に戻しました。';

  @override
  String get suggestionsNewerVersion =>
      'この設定は新しいバージョンのアプリで保存されたため、ここでは変更できません。変更するにはアプリを更新してください。';

  @override
  String get collectionSortSuggested => 'おすすめ順';

  @override
  String suggestionReasonNewMoves(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '今夜初めての動きが$countつ',
    );
    return '$_temp0';
  }

  @override
  String suggestionReasonBeatOverlapPrevious(String move) {
    return '$moveが前のダンスと同じ拍';
  }

  @override
  String suggestionReasonBeatOverlapNext(String move) {
    return '$moveが次のダンスと同じ拍';
  }

  @override
  String suggestionReasonSameFormationPrevious(String formation) {
    return '$formation（前のダンスと同じ）';
  }

  @override
  String suggestionReasonSameFormationNext(String formation) {
    return '$formation（次のダンスと同じ）';
  }

  @override
  String suggestionReasonFormationCommon(int count, String formation) {
    return '今夜はすでに$formationが$count曲';
  }

  @override
  String suggestionReasonFirstFormation(String formation) {
    return '$formation：今夜初めて';
  }

  @override
  String get suggestionReasonFitsCurve => 'ここでの難易度の流れに合う';

  @override
  String get suggestionReasonHarderThanCurve => 'ここでは難易度の流れより難しい';

  @override
  String get suggestionReasonEasierThanCurve => 'ここでは難易度の流れより易しい';

  @override
  String suggestionReasonCalledHereRecently(String venue, String date) {
    return '$dateに$venueでコール済み';
  }

  @override
  String suggestionReasonNotCalledHereSince(String venue, String date) {
    return '$date以来$venueでコールしていない';
  }

  @override
  String suggestionReasonNeverCalledHere(String venue) {
    return '$venueでコールしたことがない';
  }

  @override
  String get suggestionReasonVenueSkipped =>
      'この会場での最近のコール：プログラムに会場がないため使っていません';

  @override
  String get suggestionReasonNoFactor => 'どの項目もこのダンスの順位を変えていません';

  @override
  String get suggestionReasonEnglishNotCovered => '提案はまだイングリッシュ・ダンスに対応していません';

  @override
  String suggestionReasonPhraseOverlapPrevious(String move) {
    return '$moveが前のダンスと同じフレーズ';
  }

  @override
  String suggestionReasonPhraseOverlapNext(String move) {
    return '$moveが次のダンスと同じフレーズ';
  }

  @override
  String suggestionReasonBeatOverlapAfterDance(String move, String dance) {
    return '$moveが直前の$danceと同じ拍';
  }

  @override
  String suggestionReasonBeatOverlapBeforeDance(String move, String dance) {
    return '$moveが直後の$danceと同じ拍';
  }

  @override
  String suggestionReasonPhraseOverlapAfterDance(String move, String dance) {
    return '$moveが直前の$danceと同じフレーズ';
  }

  @override
  String suggestionReasonPhraseOverlapBeforeDance(String move, String dance) {
    return '$moveが直後の$danceと同じフレーズ';
  }

  @override
  String suggestionReasonSameFormationAfterDance(
    String formation,
    String dance,
  ) {
    return '$formation（直前の$danceと同じ）';
  }

  @override
  String suggestionReasonSameFormationBeforeDance(
    String formation,
    String dance,
  ) {
    return '$formation（直後の$danceと同じ）';
  }

  @override
  String get suggestionReasonAlreadyInProgram => 'すでにこのプログラムにあります';

  @override
  String get suggestionRankingFailed => 'ダンスを並べ替えられなかったため、通常の順序で表示しています。';

  @override
  String suggestionWhyTooltip(String title) {
    return '$titleがここで提案される理由';
  }

  @override
  String suggestionWhyTitle(String title) {
    return '$titleの理由';
  }

  @override
  String suggestionWhyRaises(String reason) {
    return '順位を上げる：$reason';
  }

  @override
  String suggestionWhyLowers(String reason) {
    return '順位を下げる：$reason';
  }

  @override
  String suggestionWouldBreak(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のルールに反します：$rules',
    );
    return '$_temp0';
  }

  @override
  String suggestionWouldBreakSemantic(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のイベントルールに反します：$rules',
    );
    return '$_temp0';
  }

  @override
  String get figureParamSearchDancersHint => 'ダンサーを検索';

  @override
  String get exportAddToCalendar => 'カレンダーに追加（.ics）';

  @override
  String get programsExportCalendar => 'カレンダーを書き出す（.ics）';

  @override
  String get exportCalendarPickTitle => 'カレンダーを書き出す';

  @override
  String get exportCalendarPickBody => 'カレンダーファイルに入れるプログラムを選んでください。';

  @override
  String get exportCalendarShowPast => '過去のプログラムを表示';

  @override
  String get exportCalendarNoUpcoming =>
      '表示できる今後のプログラムはありません。アーカイブ済みのプログラムはここには表示されません。以前のプログラムを選ぶには「過去のプログラムを表示」をオンにしてください。';

  @override
  String get exportCalendarNoDated =>
      '日付のあるプログラムはまだありません。カレンダーに追加するには、プログラムに日付を設定してください。';

  @override
  String get exportCalendarPickConfirm => '書き出す';

  @override
  String get exportCalendarAddressTitle => '会場の住所を含めますか？';

  @override
  String get exportCalendarAddressBody =>
      'カレンダーファイルには会場名が入ります。住所は、含めることを選ばない限り省かれます。カレンダーは同期されたり、他の人と共有されたりすることがよくあります。';

  @override
  String get exportCalendarAddressInclude => '会場の住所を含める';

  @override
  String get exportCalendarDialogTitle => 'カレンダーファイルを書き出す';

  @override
  String get exportCalendarDialogMessage => 'このカレンダーファイルの渡し方を選んでください。';

  @override
  String get exportCalendarSavedGeneric => 'カレンダーファイルを保存しました。';

  @override
  String get exportCalendarSaveError => 'このカレンダーファイルを保存できませんでした。もう一度お試しください。';

  @override
  String get exportCalendarShareError => 'このカレンダーファイルを共有できませんでした。もう一度お試しください。';

  @override
  String get importErrorNotACalendar =>
      'そのアドレスからはカレンダーが返されませんでした。Google カレンダーの場合は、通常のリンクではなく iCal 形式のアドレス（設定と共有 ▸ カレンダーの統合）を使ってください。';

  @override
  String get importFromCalendar => 'カレンダーから';

  @override
  String get importProgramFromCalendar => 'カレンダーからインポート';

  @override
  String get calendarImportTitle => 'カレンダーからインポート';

  @override
  String get calendarImportImport => 'インポート';

  @override
  String get calendarAddressLabel => 'カレンダーのアドレス';

  @override
  String get calendarAddressHelper =>
      'カレンダーの iCal アドレス（https:// または webcal:// で始まるもの）。非公開カレンダーの秘密のアドレスも使えます。他の人には教えないでください。';

  @override
  String get calendarImportFetch => '予定を取得';

  @override
  String get calendarImportFailed => 'カレンダーからインポートできませんでした。もう一度お試しください。';

  @override
  String get calendarImportUntitled => '無題の予定';

  @override
  String calendarImportCommitted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'カレンダーから下書きプログラムを$count件追加しました。',
    );
    return '$_temp0';
  }

  @override
  String get calendarImportNothingFound => '期間内に予定はありません。';

  @override
  String calendarImportSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新しい予定が$count件あります。',
      zero: '新しい予定はありません。',
    );
    return '$_temp0';
  }

  @override
  String get calendarImportNewHeader => 'カレンダーの新しい予定';

  @override
  String get calendarImportDeletedHeader => '削除したプログラム';

  @override
  String get calendarImportDeletedNote =>
      'この予定から作ったプログラムは削除済みです。もう一度インポートするにはチェックを入れてください。';

  @override
  String get calendarImportAlreadyHeader => 'インポート済み';

  @override
  String get calendarImportFromThisAppHeader => 'このアプリから';

  @override
  String get calendarImportUnreadableHeader => 'アプリが読み取れない繰り返しの予定';

  @override
  String get calendarImportUnreadableBody =>
      'アプリが理解できない方法で繰り返しているため、インポートされません。';

  @override
  String calendarImportSkippedNoUid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の予定には識別子がないため、スキップしました。',
    );
    return '$_temp0';
  }

  @override
  String calendarImportTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'カレンダーに$count件を超える予定があります。最初の$count件だけを読み取りました。',
    );
    return '$_temp0';
  }

  @override
  String get calendarSettingsHeader => 'カレンダー';

  @override
  String get calendarSettingsSaveError => '設定を保存できませんでした。もう一度お試しください。';

  @override
  String get calendarAddressSet => '設定済み。タップして変更します。';

  @override
  String get calendarAddressNotSet => '未設定';

  @override
  String get calendarWindowTitle => '対象の予定';

  @override
  String get calendarWindowSubtitle =>
      '今日からこの期間先までの予定。繰り返しの予定は30日先までしか読み取りません。';

  @override
  String calendarWindowOption(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$monthsか月',
    );
    return '$_temp0';
  }

  @override
  String get calendarTitleFilterTitle => 'タイトルにこの語を含む予定のみ';

  @override
  String get calendarTitleFilterHelper =>
      'ほかの予定も入っているカレンダー向けです。すべての予定を対象にするには空欄のままにします。';

  @override
  String get calendarTitleFilterNone => 'すべての予定';

  @override
  String calendarTitleFilterValue(String filter) {
    return '「$filter」';
  }

  @override
  String get calendarPullNowTitle => '今すぐ取得';

  @override
  String get calendarPullNowSubtitle => 'カレンダーを読み取り、下書きプログラムとして追加する予定を選びます。';

  @override
  String get collectionExportCsv => 'CSVでエクスポート';

  @override
  String get settingsExportDancesCsvTitle => 'ダンスを表計算ファイルでエクスポート';

  @override
  String get settingsExportDancesCsvSubtitle =>
      'コレクションのすべてのダンスを、Excel、Numbers、Googleスプレッドシート用のCSVファイルにします。共有と同じルールが適用され、星の評価も含まれます。バックアップではないため、復元はできません。';

  @override
  String get settingsExportDancesCsvAction => 'エクスポート';

  @override
  String get exportCsvDialogTitle => '表計算ファイル（CSV）をエクスポート';

  @override
  String get exportCsvDialogMessage =>
      'ファイルを保存するか、ほかのアプリと共有します。Excel、Numbers、LibreOffice、Googleスプレッドシートで開けます。';

  @override
  String get exportCsvSavedGeneric => '表計算ファイルを保存しました。';

  @override
  String get exportCsvSaveError => 'この表計算ファイルを保存できませんでした。もう一度お試しください。';

  @override
  String get exportCsvShareError => 'この表計算ファイルを共有できませんでした。もう一度お試しください。';

  @override
  String get exportCsvError => 'この表計算ファイルを作成できませんでした。もう一度お試しください。';

  @override
  String get csvDancesFileStem => 'ダンス';

  @override
  String get csvColumnTitle => 'タイトル';

  @override
  String get csvColumnAuthors => '作者';

  @override
  String get csvColumnInterpreters => '解釈者';

  @override
  String get csvColumnForm => 'タイプ';

  @override
  String get csvColumnFormation => 'フォーメーション';

  @override
  String get csvColumnProgression => 'プログレッション';

  @override
  String get csvColumnLevel => 'レベル';

  @override
  String get csvColumnMixedLevel => 'ミックスレベル';

  @override
  String get csvColumnMixer => 'ミキサー';

  @override
  String get csvColumnStatus => 'ステータス';

  @override
  String get csvColumnRating => '評価';

  @override
  String get csvColumnTags => 'タグ';

  @override
  String get csvColumnTunes => 'チューン';

  @override
  String get csvColumnMeter => '拍子';

  @override
  String get csvColumnKey => '調';

  @override
  String get csvColumnSources => '公開ソース';

  @override
  String get csvColumnHook => 'フック';

  @override
  String get csvColumnCallingNotes => 'コーリングノート';

  @override
  String get csvColumnWalkthrough => 'ウォークスルー';

  @override
  String get csvColumnFigures => 'フィギュア';

  @override
  String get csvColumnComposed => '振付年';

  @override
  String get csvColumnInterpreted => '解釈年';

  @override
  String get csvColumnBarnes => 'Barnes 掲載箇所';

  @override
  String get programsExportCsv => 'プログラムをCSVでエクスポート';

  @override
  String get csvProgramsFileStem => 'プログラム';

  @override
  String get csvColumnEventDate => 'イベント日';

  @override
  String get csvColumnVenue => '会場';

  @override
  String get csvColumnCaller => 'コーラー';

  @override
  String get csvColumnBand => 'バンド';

  @override
  String get csvColumnDancerLevel => 'ダンサーレベル';

  @override
  String get csvColumnPayAmount => '報酬';

  @override
  String get csvColumnPayCurrency => '通貨';

  @override
  String get csvColumnNotes => 'ノート';

  @override
  String get csvColumnDanceCount => 'ダンス数';

  @override
  String get csvColumnDances => 'ダンス';

  @override
  String get exportCsvPayHiddenNotice =>
      '報酬は設定で非表示になっているため、含まれません。含めるには、設定 ▸ プログラムで「報酬を表示」をオンにしてください。';

  @override
  String get performSwapThisDance => 'このダンスを入れ替え';

  @override
  String performSwapDanceNamed(String title) {
    return '$titleを入れ替え';
  }

  @override
  String performSwappedAnnounce(String title) {
    return '$titleに入れ替えました';
  }

  @override
  String get performSwapKeepHeader => '維持する条件';

  @override
  String performSwapKeepFormation(String formation) {
    return '同じフォーメーション：$formation';
  }

  @override
  String performSwapKeepLevel(String level) {
    return 'このレベル以下：$level';
  }

  @override
  String performSwapKeepType(String type) {
    return '同じタイプ：$type';
  }

  @override
  String get performSwapKeepNotInProgram => '今夜のプログラムにまだないもの';

  @override
  String get performSwapFiguresHeader => '維持するフィギュア';

  @override
  String performSwapFigureInPhrase(String figure, String phrase) {
    return '$phraseの$figure';
  }

  @override
  String performSwapKeepFigureSemantic(String figure) {
    return '$figureを維持';
  }

  @override
  String performSwapSamePhrase(String phrase) {
    return '同じフレーズ（$phrase）';
  }

  @override
  String performSwapSamePhraseSemantic(String figure, String phrase) {
    return '$figureを同じフレーズ$phraseで維持';
  }

  @override
  String performSwapWithBefore(String figure) {
    return '直前のフィギュアも（$figure）';
  }

  @override
  String performSwapWithBeforeSemantic(String figure, String before) {
    return '$figureを$beforeの直後で維持';
  }

  @override
  String get performSwapMoreFilters => 'その他のフィルター';

  @override
  String get performSwapKeepInPanels => 'ほかの維持する条件は、フィルターと詳細検索に移りました。';

  @override
  String get performSwapEnglishNote =>
      'イングリッシュダンスでは、同じフォーメーションとフィギュアの細かい条件はまだ使えません。';

  @override
  String get performSwapAlternatesHeading => 'あなたの代替';

  @override
  String get performSwapResultsHeading => '条件に合うダンス';

  @override
  String get performSwapRefused =>
      'このプログラムは別のデバイスで変更されたため、変更の一部が保存されませんでした。プログラムを確認し、必要であればもう一度変更してください。';

  @override
  String get settingsPerformSwapTitle => 'ダンスの入れ替え';

  @override
  String get settingsPerformSwapSubtitle =>
      'パフォームモードでダンスを入れ替えるときに、最初からオンにする維持条件を選びます。';

  @override
  String get settingsPerformSwapFormation => '同じフォーメーション';

  @override
  String get settingsPerformSwapLevel => 'このレベル以下';

  @override
  String get settingsPerformSwapType => '同じタイプ';

  @override
  String get settingsPerformSwapTypeSubtitle =>
      'コントラとイングリッシュダンスのように、タイプが混在するプログラムでのみ表示されます。';

  @override
  String get settingsPerformSwapNewerVersion =>
      'この設定は新しいバージョンのアプリで保存されました。このバージョンはすべてオンの初期設定を使い、保存された設定は上書きしません。変更するにはアプリを更新してください。';

  @override
  String get settingsPerformSwapReadError =>
      '「ダンスの入れ替え」の設定を読み込めなかったため、今は変更できません。この画面を閉じて、もう一度お試しください。';

  @override
  String get collectionRepertoireMenuItem => 'レパートリー';

  @override
  String get repertoireTitle => 'レパートリー';

  @override
  String get repertoireLoadError => 'レパートリーを集計できませんでした';

  @override
  String get repertoirePeriodLabel => '期間';

  @override
  String get repertoirePeriodAllTime => '全期間';

  @override
  String repertoirePeriodMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '過去$countか月',
      one: '過去1か月',
    );
    return '$_temp0';
  }

  @override
  String get repertoirePeriodSinceDate => '日付以降…';

  @override
  String repertoirePeriodSince(String date) {
    return '$date以降';
  }

  @override
  String get repertoireTypeLabel => 'ダンスの種類';

  @override
  String get repertoireTypeAll => 'すべての種類';

  @override
  String repertoireSummary(int calls, int called, int total) {
    return 'この期間のコール数：$calls。コールしたダンス：$total件中$called件。';
  }

  @override
  String get repertoireMostCalledHeader => 'コール回数が多い';

  @override
  String get repertoireLeastCalledHeader => 'コール回数が少ない（コールしたダンスのうち）';

  @override
  String get repertoireLeastCalledAllShown =>
      'この期間にコールしたダンスは、すべて「コール回数が多い」に表示されています。';

  @override
  String get repertoireNoCalls => 'この期間にカウントされたコールはありません。';

  @override
  String repertoireDanceCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count回コール',
      one: '1回コール',
    );
    return '$_temp0';
  }

  @override
  String repertoireDanceSemantics(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count回コール',
      one: '1回コール',
    );
    return '$title：$_temp0';
  }

  @override
  String get repertoireNeverCalledHeader => '一度もコールされていない';

  @override
  String get repertoireNeverCalledLabel => '一度もコールされていない';

  @override
  String repertoireOfDances(int count, int total) {
    return '$total件中$count件のダンス';
  }

  @override
  String repertoireNeverCalledSemantics(int count, int total) {
    return '一度もコールされていない：$total件中$count件のダンス';
  }

  @override
  String repertoireNeverCalledDanceSemantics(String title) {
    return '$title：一度もコールされていない';
  }

  @override
  String get repertoireNotCalledInPeriodLabel => 'この期間に未コール';

  @override
  String repertoireNotCalledInPeriodSemantics(int count, int total) {
    return 'この期間に未コール：$total件中$count件のダンス';
  }

  @override
  String get repertoireFigureHeader => 'フィギュアの出現頻度';

  @override
  String get repertoireNoFigures => 'これらのダンスにはフィギュアが入力されていません。';

  @override
  String repertoireFigureValue(int dances, int total, int percent, int calls) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls回コール',
      one: '1回コール',
    );
    return '$total件中$dances件のダンス（$percent%）・$_temp0';
  }

  @override
  String repertoireFigureSemantics(
    String move,
    int dances,
    int total,
    int percent,
    int calls,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls回コール',
      one: '1回コール',
    );
    return '$move：$total件中$dances件のダンス、$percentパーセント。この期間に$_temp0';
  }

  @override
  String repertoireShowAll(int count) {
    return 'すべて表示（$count件）';
  }

  @override
  String get repertoireShowFewer => '表示を減らす';

  @override
  String get repertoireAuthorsHeader => 'コールしている作者';

  @override
  String repertoireAuthorsSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'この期間に$count人の作者のダンスをコールしました。',
      one: 'この期間に1人の作者のダンスをコールしました。',
      zero: 'この期間にコールした作者はいません。',
    );
    return '$_temp0';
  }

  @override
  String repertoireShareValue(int calls, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls回コール',
      one: '1回コール',
    );
    return '$_temp0（$percent%）';
  }

  @override
  String repertoireShareSemantics(String label, int calls, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls回コール',
      one: '1回コール',
    );
    return '$label：$_temp0、この期間のコールの$percentパーセント';
  }

  @override
  String get repertoireFormationHeader => 'フォーメーションの内訳';

  @override
  String get repertoireVenuesHeader => '会場ごとの繰り返し';

  @override
  String get repertoireNoRepeats => 'この期間に同じ会場で2回以上コールされたダンスはありません。';

  @override
  String get repertoireVenueUnnamed => '名前のない会場';

  @override
  String repertoireVenueRepeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを繰り返し',
      one: '1件のダンスを繰り返し',
    );
    return '$_temp0';
  }

  @override
  String repertoireVenueSemantics(String venue, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のダンスを2回以上コール',
      one: '1件のダンスを2回以上コール',
    );
    return '$venue：$_temp0';
  }

  @override
  String get settingsExperimentalRepertoireHeader => 'レパートリー';

  @override
  String get settingsExperimentalShowRepertoireTitle => 'レパートリー';

  @override
  String get settingsExperimentalShowRepertoireSubtitle =>
      'コレクションの「その他のアクション」メニューに「レパートリー」を追加します。コール回数が多いダンスと少ないダンス、一度もコールしていないダンス、フィギュアの出現頻度、作者、フォーメーション、会場ごとの繰り返しを表示します。';

  @override
  String get importSourceLabelCsv => '自分の表計算ファイル（CSV）';

  @override
  String get importCsvPickFile => 'CSV ファイルを選択…';

  @override
  String get importSourceLabelTextDocument => '自分のテキストまたはMarkdownファイル';

  @override
  String get importTextHint =>
      '.txtまたは.mdファイルを選んでください。各ダンスは見出し(## Title)か、空行の後のタイトルで始めます。詳細は「Label: value」の行(Formation: Improper)に、フィギュアは1行に1つ(A1 (8) Neighbor swing)書きます。';

  @override
  String get importTextPickFile => 'テキストまたはMarkdownファイルを選択…';

  @override
  String get importTextMapTitle => 'ラベルの割り当て';

  @override
  String get importTextMapIntro =>
      'ファイル内の各ラベルが何を表すかを選んでください。どの項目にも割り当てられないラベルは、名前付きでコーリングノートに残ります。除外するには「無視」を選びます。確認して確定するまで何も追加されません。';

  @override
  String get importTextDanceStartLabel => '各ダンスの始まり';

  @override
  String importTextDanceStartHeading(String marks) {
    return '$marks 見出し';
  }

  @override
  String get importTextDanceStartBlankLine => '空行の後のタイトル';

  @override
  String get importTextTargetLabelledNotes => 'コーリングノート(ラベル付き)';

  @override
  String get importTextNotUtf8 =>
      'このファイルはUTF-8テキストで保存されていないため、アクセント付きの文字が正しく取り込まれません。UTF-8テキストで保存し直し、そのファイルを選んでください。';

  @override
  String importTextTooManyDances(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'このファイルには$limitString件を超えるダンスがあります。小さなファイルに分けてください。';
  }

  @override
  String importTextLineTooLong(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'このファイルに$limitString文字を超える行があります。';
  }

  @override
  String importTextDanceTooLong(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'このファイルに、フィギュア、ノート、または1つの詳細が$limitString文字を超えるダンスがあります。';
  }

  @override
  String importTextTooManyLabels(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'このファイルは$limitString種類を超えるラベルを使っています。';
  }

  @override
  String get importCsvSaveAsHint =>
      '表計算アプリで［ファイル］▸［名前を付けて保存］（または［ダウンロード］）を選び、「CSV UTF-8」を選んでから、そのファイルをここで選択してください。';

  @override
  String get importCsvMapTitle => '列の割り当て';

  @override
  String get importCsvMapIntro =>
      '各列の内容を選んでください。「無視」にした列は取り込まれません。確認して確定するまで何も追加されません。';

  @override
  String get importCsvSeparatorLabel => '区切り文字';

  @override
  String get importCsvSeparatorComma => 'カンマ（,）';

  @override
  String get importCsvSeparatorSemicolon => 'セミコロン（;）';

  @override
  String get importCsvSeparatorTab => 'タブ';

  @override
  String get importCsvFirstRowHeader => '1 行目は列名';

  @override
  String importCsvColumnFallback(int number) {
    return '列 $number';
  }

  @override
  String get importCsvTargetIgnore => '無視';

  @override
  String importCsvTargetPhrase(String phrase) {
    return 'フィギュア、$phrase';
  }

  @override
  String importCsvTargetNewField(String type) {
    return '新しいカスタムフィールド（$type）';
  }

  @override
  String importCsvTargetExistingField(String name) {
    return 'カスタムフィールド：$name';
  }

  @override
  String get importCsvNeedsTitle => '各ダンスのタイトルが入っている列を選んでください。';

  @override
  String get importCsvContinue => '続ける';

  @override
  String get importCsvPreviewHeading => '最初の行';

  @override
  String get importCsvNotUtf8 =>
      'このファイルは UTF-8 テキストで保存されていないため、アクセント付きの文字が正しく取り込まれません。表計算アプリで「CSV UTF-8」として保存し直し、そのファイルを選択してください。';

  @override
  String get importCsvTooLarge => 'このファイルは大きすぎて取り込めません。小さなファイルに分けてください。';

  @override
  String importCsvTooManyRows(int limit) {
    return 'このファイルには $limit 行を超える行があります。小さなファイルに分けてください。';
  }

  @override
  String importCsvTooManyColumns(int limit) {
    return 'このファイルのある行には $limit を超える列があります。';
  }

  @override
  String importCsvCellTooLong(int limit) {
    return 'このファイルのあるセルは $limit 文字を超えています。';
  }

  @override
  String get importCsvUnterminatedQuote =>
      'このファイルには終わりのない引用符付きのセルがあるため、読み込めません。';

  @override
  String importCsvLargeBatch(int count) {
    return 'このファイルには $count 行あります。確認に時間がかかることがあります。';
  }

  @override
  String get importCsvNoRows => 'このファイルには列名だけで、ダンスの行がありません。';

  @override
  String calendarImportUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'カレンダーからプログラムを$count件更新しました。',
    );
    return '$_temp0';
  }

  @override
  String get calendarImportReviewed => 'カレンダーを確認しました。追加や変更はありません。';

  @override
  String calendarChangeDate(String before, String after) {
    return '日付: $before → $after';
  }

  @override
  String calendarChangeTitle(String before, String after) {
    return 'タイトル: $before → $after';
  }

  @override
  String calendarChangeTime(String before, String after) {
    return '時刻: $before → $after';
  }

  @override
  String calendarChangeVenue(String before, String after) {
    return '会場: $before → $after';
  }

  @override
  String get calendarImportUpdatedHeader => 'カレンダーで更新された予定';

  @override
  String get calendarImportChangedHeader => 'カレンダーで変更された予定';

  @override
  String get calendarImportChangedBody =>
      'これらのプログラムは編集済みのため、チェックを入れない限り何も変わりません。';

  @override
  String get calendarImportFlaggedHeader => 'カレンダーでキャンセルされた、または削除された予定';

  @override
  String get calendarImportFlaggedBody =>
      'これらのプログラムはそのまま残り、ラベルが付きます。不要になったら自分でアーカイブまたは削除してください。';

  @override
  String get calendarFlagCancelled => 'カレンダーでキャンセル済み';

  @override
  String get calendarFlagMissing => 'カレンダーにもうありません';

  @override
  String get calendarFlagOther => 'カレンダーによるフラグ';

  @override
  String get calendarFlagFieldLabel => 'カレンダーのフラグ';

  @override
  String get calendarClearFlag => 'カレンダーのフラグを消す';

  @override
  String get calendarClearFlagError => 'カレンダーのフラグを消せませんでした。もう一度お試しください。';

  @override
  String get calendarOnStartupTitle => 'アプリ起動時にカレンダーをインポート';

  @override
  String get calendarOnStartupSubtitle =>
      '初期設定はオフです。オンにすると、起動のたびにカレンダーを1回読み取ります。読み取れなくても何も表示しません。';

  @override
  String get calendarStartupModeTitle => '起動時';

  @override
  String get calendarStartupModeReport => '新しい予定を知らせる';

  @override
  String get calendarStartupModeAdd => '下書きとして追加';

  @override
  String get calendarStartupModeReportSubtitle =>
      '新しい予定を知らせます。確認するまで何も追加されません。';

  @override
  String get calendarStartupModeAddSubtitle =>
      '新しい予定を下書きプログラムとして追加します（元に戻せます）。変更・キャンセルされた予定は知らせるだけです。';

  @override
  String calendarLastResultFailed(String when) {
    return '起動時にカレンダーに接続できませんでした（$when）';
  }

  @override
  String calendarLastResultAdded(String when, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '下書きを$count件追加',
    );
    return '起動時に確認（$when）: $_temp0';
  }

  @override
  String calendarLastResultNew(String when, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新しい予定が$count件',
      zero: '新しい予定はありません',
    );
    return '起動時に確認（$when）: $_temp0';
  }

  @override
  String calendarStartupFailureNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '直近$count回の起動でカレンダーに接続できませんでした。',
    );
    return '$_temp0';
  }

  @override
  String get calendarStartupFailureHint => 'カレンダーのアドレスか接続を確認してください。';

  @override
  String calendarStartupNewEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'カレンダーに新しい予定が$count件あります。',
    );
    return '$_temp0';
  }

  @override
  String calendarStartupChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '確認が必要な変更が$count件あります。',
    );
    return '$_temp0';
  }

  @override
  String get calendarStartupShow => '表示';

  @override
  String get calendarStartupReview => '確認';

  @override
  String calendarLastResultError(String when) {
    return '起動時にカレンダーからインポートできませんでした（$when）';
  }

  @override
  String get savedSearchSaveThis => 'この検索を保存…';

  @override
  String savedSearchUpdate(String name) {
    return '「$name」を更新';
  }

  @override
  String savedSearchRename(String name) {
    return '「$name」の名前を変更…';
  }

  @override
  String savedSearchDelete(String name) {
    return '「$name」を削除';
  }

  @override
  String get savedSearchNeedsAttention => '確認が必要';

  @override
  String get savedSearchUnreadableItem => '開けない保存した検索';

  @override
  String get savedSearchUnreadableTitle => 'この保存した検索を開けません';

  @override
  String get savedSearchUnreadableBody =>
      '新しいバージョンのアプリで保存されたか、壊れているため、使われません。削除でき、削除は元に戻せます。';

  @override
  String get savedSearchSaveDialogTitle => 'この検索を保存';

  @override
  String get savedSearchRenameDialogTitle => '保存した検索の名前を変更';

  @override
  String get savedSearchNameLabel => '名前';

  @override
  String savedSearchWindowNotCalled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '過去$countか月コールしていない',
    );
    return '$_temp0';
  }

  @override
  String savedSearchWindowCalled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '過去$countか月にコールした',
    );
    return '$_temp0';
  }

  @override
  String savedSearchWindowInert(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保存するコール履歴の期間：過去$countか月',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchTooLargeTitle => '検索が大きすぎます';

  @override
  String get savedSearchTooLargeBody =>
      'この検索はフィルターや行が多すぎて保存できません。いくつか外してから、もう一度保存してください。';

  @override
  String get savedSearchLimitTitle => '保存した検索が多すぎます';

  @override
  String savedSearchLimitBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保存した検索は$count件まで残せます。別の検索を保存するには、どれかを削除してください。',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchNameRefused => 'その名前は使えません。別の名前を試してください。';

  @override
  String get savedSearchFailed => '保存した検索の操作ができませんでした。もう一度試してください。';

  @override
  String savedSearchSavedSnack(String name) {
    return '「$name」を保存しました';
  }

  @override
  String savedSearchUpdatedSnack(String name) {
    return '「$name」を更新しました';
  }

  @override
  String savedSearchDeletedSnack(String name) {
    return '「$name」を削除しました';
  }

  @override
  String savedSearchInUseTitle(String name) {
    return '「$name」を削除できません';
  }

  @override
  String get savedSearchInUseBody =>
      '次のものでまだ使われています。先にそれらを変更するか外してから、削除してください。';

  @override
  String savedSearchNoticeTitle(String name) {
    return '「$name」は、なくなったものを使っています：';
  }

  @override
  String get savedSearchNoticeRest => '検索の残りは表示されています。更新するには、これらをご自分で外してください。';

  @override
  String get savedSearchNoticeFieldSkipped =>
      '削除されたカスタムフィールドのフィルターは、結果に反映されません。';

  @override
  String get savedSearchNoticeClose => 'お知らせを閉じる';

  @override
  String savedSearchMissingTag(String name) {
    return '削除されたタグ「$name」';
  }

  @override
  String get savedSearchMissingTagUnnamed => '削除されたタグ';

  @override
  String savedSearchMissingAuthor(String name) {
    return '削除された作者「$name」';
  }

  @override
  String get savedSearchMissingAuthorUnnamed => '削除された作者';

  @override
  String savedSearchMissingSource(String name) {
    return '削除された出典「$name」';
  }

  @override
  String get savedSearchMissingSourceUnnamed => '削除された出典';

  @override
  String savedSearchMissingLevel(String name) {
    return '削除されたレベル「$name」';
  }

  @override
  String get savedSearchMissingLevelUnnamed => '削除されたレベル';

  @override
  String savedSearchMissingVenue(String name) {
    return '削除された会場「$name」';
  }

  @override
  String get savedSearchMissingVenueUnnamed => '削除された会場';

  @override
  String savedSearchMissingField(String name) {
    return '削除されたカスタムフィールド「$name」';
  }

  @override
  String get savedSearchMissingFieldUnnamed => '削除されたカスタムフィールド';

  @override
  String savedSearchMissingFieldType(String name) {
    return '種類が変わったカスタムフィールド「$name」';
  }

  @override
  String savedSearchMissingFieldChoice(String choice, String name) {
    return '「$name」から外された選択肢「$choice」';
  }

  @override
  String get savedSearchMissingFigureDetail => '表示できない詳細検索のフィギュアの詳細';

  @override
  String get savedSearchMissingUserFigure => '削除された自作のフィギュア';

  @override
  String get savedSearchMissingInvalid => 'このバージョンでは読めないもの';

  @override
  String savedSearchSearchFor(String text) {
    return '「$text」を検索';
  }

  @override
  String savedSearchHighlightedRow(String name, int index, int count) {
    return '$name、$count件中$index件目';
  }

  @override
  String get savedSearchSaveAsNewSearch => '新しい検索として保存…';

  @override
  String get settingsCollectionTitle => 'コレクション';

  @override
  String get settingsSavedSearchesHeader => '保存した検索';

  @override
  String get settingsSavedSearchesLoadError =>
      '保存した検索を読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get settingsSavedSearchesEmpty =>
      '保存した検索はまだありません。コレクションで検索を設定してから、その他のアクションメニューで「この検索を保存…」を選んでください。';

  @override
  String settingsSavedSearchRenameTooltip(String name) {
    return '「$name」の名前を変更';
  }

  @override
  String settingsSavedSearchDeleteTooltip(String name) {
    return '「$name」を削除';
  }

  @override
  String savedSearchGone(String name) {
    return '「$name」はこの端末か別の端末で削除されたため、何も変更されませんでした。';
  }

  @override
  String get settingsExperimentalEventRulesHeader => 'イベントルール';

  @override
  String get settingsExperimentalEventRulesTitle => 'プログラムを自分のルールで確認';

  @override
  String get settingsExperimentalEventRulesSubtitle =>
      'プログラムにルール（例：Becketのダンスを2曲続けない）を追加すると、プログラムがルールに反したときにエディターが警告します。警告によって保存やコールが妨げられることはありません。';

  @override
  String get settingsEventRulesCheckPerformSwapTitle =>
      'パフォームモードの「このダンスを入れ替え」で確認する';

  @override
  String get settingsEventRulesCheckPerformSwapSubtitle =>
      'パフォームモードでダンスを入れ替えるとき、プログラムのルールに反するダンスに印を付けて最後に並べます。どのダンスも除外されません。';

  @override
  String get eventRulesManageTitle => 'ルールを管理';

  @override
  String get eventRulesManageSubtitle => 'ルールを表示、追加、編集、並べ替え、削除します。';

  @override
  String get eventRulesEmpty => 'ルールはまだありません。ルールは保存した検索を使って、対象のダンスを指定します。';

  @override
  String get eventRulesNewRule => '新しいルール…';

  @override
  String get eventRuleDeletedSnack => 'ルールを削除しました。';

  @override
  String get eventRuleEditorNewTitle => '新しいルール';

  @override
  String get eventRuleEditorEditTitle => 'ルールを編集';

  @override
  String get eventRuleSearchLabel => '対象のダンス';

  @override
  String get eventRuleNoSavedSearches =>
      '先にコレクションで検索を保存してください。ルールは保存した検索を使って、対象のダンスを指定します。';

  @override
  String get eventRuleSavedSearchGone =>
      'その保存済み検索は削除されたため、ルールは保存されませんでした。別の検索を選んでください。';

  @override
  String get eventRuleQuantifierLabel => '数';

  @override
  String get eventRuleQuantifierAtMost => '最大';

  @override
  String get eventRuleQuantifierAtLeast => '最小';

  @override
  String get eventRuleQuantifierNone => 'なし';

  @override
  String get eventRuleCountLabel => 'ダンスの数';

  @override
  String eventRuleCountInvalid(int max) {
    return '1から$maxまでの整数を入力してください。';
  }

  @override
  String get eventRuleCountOnlyOne => '1を入力してください（ここで使える数は1だけです）。';

  @override
  String get eventRuleScopeLabel => '範囲';

  @override
  String get eventRuleScopeWholeProgram => 'プログラム全体';

  @override
  String get eventRuleScopeBeforeFirstBreak => '最初のブレイクより前';

  @override
  String get eventRuleScopeAfterFirstBreak => '最初のブレイクより後';

  @override
  String get eventRuleScopeNeighbouring => '隣接する任意の2曲';

  @override
  String get eventRuleNicknameLabel => 'ニックネーム（任意）';

  @override
  String get eventRuleNicknameHelp => 'ルールの文の上に表示され、ルール選択の検索で見つけられます。';

  @override
  String eventRuleSpokenTitle(String nickname, String sentence) {
    return '$nickname（$sentence）';
  }

  @override
  String get eventRulesOrderTitle => 'ルールの並び順';

  @override
  String get eventRulesOrderManual => '自分の順番';

  @override
  String get eventRulesOrderManualSubtitle =>
      'ルール選択では、「ルールを管理」で並べた順番でルールを表示します。';

  @override
  String get eventRulesOrderMostUsed => 'よく使う順';

  @override
  String get eventRulesOrderMostUsedSubtitle =>
      'ルール選択では、プログラムで最もよく使われているルールから表示します。「最近削除したアイテム」にあるプログラムは数えません。';

  @override
  String eventRulesDragToReorder(String rule) {
    return 'ドラッグして$ruleを並べ替え';
  }

  @override
  String eventRuleSentenceAtMostWhole(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'プログラム全体で「$search」に該当するダンスは最大$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtMostBefore(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最初のブレイクより前で「$search」に該当するダンスは最大$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtMostAfter(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最初のブレイクより後で「$search」に該当するダンスは最大$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtMostNeighbouring(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '隣接する任意の2曲で「$search」に該当するダンスは最大$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastWhole(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'プログラム全体で「$search」に該当するダンスは最小$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastBefore(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最初のブレイクより前で「$search」に該当するダンスは最小$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastAfter(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最初のブレイクより後で「$search」に該当するダンスは最小$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastNeighbouring(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '隣接する任意の2曲で「$search」に該当するダンスは最小$count曲',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceNoneWhole(String search) {
    return 'プログラム全体で「$search」に該当するダンスはなし';
  }

  @override
  String eventRuleSentenceNoneBefore(String search) {
    return '最初のブレイクより前で「$search」に該当するダンスはなし';
  }

  @override
  String eventRuleSentenceNoneAfter(String search) {
    return '最初のブレイクより後で「$search」に該当するダンスはなし';
  }

  @override
  String eventRuleSentenceNoneNeighbouring(String search) {
    return '隣接する任意の2曲で「$search」に該当するダンスはなし';
  }

  @override
  String get eventRuleSentenceUnreadable => '新しいバージョンのアプリのルール';

  @override
  String get eventRuleSearchUnknown => '…';

  @override
  String get eventRuleAttentionUnreadable => '新しいバージョンのアプリで作成されたため、確認されません。';

  @override
  String get eventRuleAttentionSearchGone => '保存した検索が削除されたか読み込めないため、確認されません。';

  @override
  String get eventRuleAttentionUnresolvable =>
      '保存した検索が、なくなったものを使っているため、確認されません：';

  @override
  String programsRulesButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ルール（$count）',
      zero: 'ルール',
    );
    return '$_temp0';
  }

  @override
  String get programsRulesLabel => 'ルール';

  @override
  String get programsRulesPickerTitle => 'このプログラムのルール';

  @override
  String get programsRulesPickerEmpty => 'ルールはまだありません。';

  @override
  String get programsRulesPickerSearchHint => 'ルールを検索';

  @override
  String get programsRulesPickerSearchClear => '検索をクリア';

  @override
  String programsRulesPickerNoMatches(String query) {
    return '「$query」に一致するルールはありません。';
  }

  @override
  String programsRulesPickerNewNamed(String nickname) {
    return '新しいルール「$nickname」…';
  }

  @override
  String programsRulesStripBroken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '満たされていないルール：$count件',
    );
    return '$_temp0';
  }

  @override
  String programsRulesStripAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '確認が必要なルール：$count件',
    );
    return '$_temp0';
  }

  @override
  String programsRuleBreachMatching(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '該当するダンス：$count曲',
      zero: '該当するダンスはありません',
    );
    return '$_temp0';
  }

  @override
  String programsRuleBreachPairs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '隣接するダンスの組：$count組',
    );
    return '$_temp0';
  }

  @override
  String programsRuleBreachDances(String titles) {
    return 'ダンス：$titles';
  }

  @override
  String programsRuleBreachIfCalled(String title) {
    return '$titleをコールした場合';
  }

  @override
  String get programsSlotRuleMarker => 'ルールに反します';

  @override
  String get programsSlotRuleMarkerAlternate => 'コールするとルールに反します';

  @override
  String programsSlotRuleMarkerSemantic(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のルールに反します：$rules',
    );
    return '$_temp0';
  }

  @override
  String programsSlotRuleMarkerAlternateSemantic(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'コールした場合、$count件のルールに反します：$rules',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchInUseRulesOff =>
      'イベントルールはオフですが、「ルールを管理」で今すぐルールを変更できます。プログラムをルールで確認するには、設定 ▸ 実験的 ▸ イベントルール で「プログラムを自分のルールで確認」をオンにしてください。';

  @override
  String programsRulesPickerFull(int max) {
    return 'このプログラムはルールを上限の$max件使っています。別のルールを追加するには、どれかのチェックを外してください。';
  }

  @override
  String get programTemplateRulesLabel => 'ルール';

  @override
  String get programTemplateRulesNone => 'なし';

  @override
  String programTemplateDuplicateSearchGone(String label) {
    return '複製できませんでした。枠のルール「$label」の保存済み検索が削除されています。そのルールを編集または削除してから、もう一度お試しください。';
  }

  @override
  String get programTemplateSlotRuleNotSavedSearchGone =>
      'その保存済み検索は削除されたため、枠のルールは保存されませんでした。';

  @override
  String get programTemplateRulesHelp => 'このテンプレートから作る新しいプログラムそれぞれに追加されます。';

  @override
  String programTemplateRuleRemoved(String rule) {
    return '削除済み: $rule';
  }

  @override
  String get programTemplateRuleRemovedUnknown => '削除済み: このデバイスにないルール';

  @override
  String get programTemplateRulesPickerTitle => 'このテンプレートのルール';

  @override
  String programTemplateRulesPickerFull(int max) {
    return 'このテンプレートはルールを上限の$max件使っています。別のルールを追加するには、どれかのチェックを外してください。';
  }

  @override
  String programsRulesPickerNotHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'このデバイスにないルールが$count件あります',
    );
    return '$_temp0';
  }

  @override
  String get programsRulesPickerNotHereHelp =>
      '別のデバイスで追加されてまだ届いていないか、すでに存在しません。「削除」でこのプログラムから外します。';

  @override
  String get programsRulesChangeFailed => 'このプログラムのルールを変更できませんでした。もう一度お試しください。';

  @override
  String get eventRuleCountNeighbouringHelp => '隣接する2曲に含まれる該当ダンスは最大2曲です。';

  @override
  String settingsSyncNoticeCountEventRule(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'イベントルール$count件',
    );
    return '$_temp0';
  }

  @override
  String get syncReviewKindEventRule => 'イベントルール';

  @override
  String get danceEditorFigureNeedsValues => '保存する前に、このフィギュアのすべての項目で値を選んでください。';

  @override
  String get danceEditorSaveNeedsFigureValues =>
      '追加したフィギュアに空欄の項目が残っています。入力すると保存できます。';

  @override
  String get programTemplateAddSlotRule => '枠のルールを追加';

  @override
  String get programTemplateSlotRuleBadge => '枠のルール';

  @override
  String programTemplateSlotRuleSubtitle(String name) {
    return '保存した検索「$name」から埋めます';
  }

  @override
  String get programTemplateSlotRuleSearchGone => '保存した検索は削除されました';

  @override
  String get programTemplateSlotRuleDialogTitle => '枠のルールを追加';

  @override
  String get programTemplateSlotRuleDialogBody =>
      'ダンスを指定する代わりに、ダンスの種類を説明します。このテンプレートから作ったプログラムでは、保存した検索から埋めるプレースホルダーとして表示されます。';

  @override
  String get programTemplateSlotRuleLabel => 'ラベル';

  @override
  String get programTemplateSlotRuleLabelHint => 'やさしいインプロパーのオープナー';

  @override
  String get programTemplateSlotRuleSearch => '保存した検索';

  @override
  String get programTemplateSlotRuleNoSearches =>
      '枠のルールは保存した検索を使います。まずコレクションで検索を保存してから、ここで選んでください。';

  @override
  String get programsPlaceholderSubtitle => 'プレースホルダー';

  @override
  String get programsFillPlaceholderButton => '埋める';

  @override
  String programsFillPlaceholderSemantics(String label) {
    return '「$label」をダンスで埋める';
  }

  @override
  String programsFillSheetTitle(String label) {
    return '「$label」を埋める';
  }

  @override
  String programsFillSearchGone(String label) {
    return '「$label」の保存した検索は削除されたため、すべてのダンスを表示しています。';
  }

  @override
  String programsFillSearchUnresolvable(String label, String name) {
    return '「$label」の保存した検索「$name」は、なくなったものを使っているため使えません。すべてのダンスを表示しています：';
  }

  @override
  String savedSearchUsedBySlotRule(String rule, String template) {
    return 'テンプレート $template の枠のルール「$rule」';
  }

  @override
  String get programTemplateSlotRuleSearchUnreadable => '保存した検索を開けません';

  @override
  String get programTemplateSlotRuleEditTitle => '枠のルールを編集';

  @override
  String get programTemplateSlotRuleLabelBreak =>
      '「Break」はプログラムの休憩を表すため、枠のルールのラベルには使えません。';

  @override
  String programsFillSearchUnreadable(String label) {
    return '「$label」の保存した検索を開けません。新しいバージョンのアプリで保存されたか、破損しています。すべてのダンスを表示しています。';
  }

  @override
  String get settingsExperimentalSeriesHeader => '週末とシリーズ';

  @override
  String get settingsExperimentalSeriesTitle => '複数のプログラムをまとめて確認';

  @override
  String get settingsExperimentalSeriesSubtitle =>
      'プログラム一覧の「その他のアクション」から「プログラムを選択」を選び、2つ以上を選ぶと、それらをまとめた1つのマトリックスと繰り返されるダンスを表示します。新しく保存されるものはありません。';

  @override
  String get programsSelectPrograms => 'プログラムを選択';

  @override
  String programsSelectProgramLabel(String title) {
    return '$titleを選択';
  }

  @override
  String get programsCombinedView => 'まとめて表示';

  @override
  String get programsCombinedViewNeedsTwo => 'プログラムを2つ以上選択してください';

  @override
  String get programsCombinedRepeatsTab => '繰り返し';

  @override
  String get programsCombinedLoadError =>
      'プログラムを読み込めませんでした。何も変更されていません。もう一度お試しください。';

  @override
  String get programsCombinedGoneTitle => 'これらのプログラムはもうありません';

  @override
  String get programsCombinedGoneBody =>
      '選択したプログラムは削除されました。プログラム一覧に戻って別のプログラムを選んでください。';

  @override
  String programsCombinedBlockLabel(String title, String date) {
    return '$title · $date';
  }

  @override
  String programsCombinedRowInProgram(String title, String program) {
    return '$title（$program）';
  }

  @override
  String get programsCombinedPdfTitle => 'まとめたマトリックス';

  @override
  String get programsCombinedRepeatsEmptyTitle => '繰り返されるダンスはありません';

  @override
  String get programsCombinedRepeatsEmptyBody => 'これらのプログラムの複数に含まれるダンスはありません。';

  @override
  String programsCombinedRepeatsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count曲のダンスが複数のプログラムに含まれています',
    );
    return '$_temp0';
  }

  @override
  String programsCombinedRepeatProgramCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countつのプログラムに含まれる',
    );
    return '$_temp0';
  }

  @override
  String get programsCombinedRepeatAlternateChip => '一部では代替のみ';

  @override
  String programsCombinedRepeatUse(String program, String position) {
    return '$program：$position';
  }

  @override
  String programsCombinedPositionDance(int number) {
    return '$number曲目';
  }

  @override
  String programsCombinedPositionAlternateFor(int number) {
    return '$number曲目の代替';
  }

  @override
  String get programsCombinedPositionAlternate => '代替';

  @override
  String get programsCombinedRepeatAlternateEverywhereChip => '代替のみ';
}
