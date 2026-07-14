// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DancesTable extends Dances with TableInfo<$DancesTable, DanceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DanceForm, String> form =
      GeneratedColumn<String>(
        'form',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DanceForm>($DancesTable.$converterform);
  @override
  late final GeneratedColumnWithTypeConverter<FormationShape, String>
  formationShape = GeneratedColumn<String>(
    'formation_shape',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<FormationShape>($DancesTable.$converterformationShape);
  static const VerificationMeta _formationDetailMeta = const VerificationMeta(
    'formationDetail',
  );
  @override
  late final GeneratedColumn<String> formationDetail = GeneratedColumn<String>(
    'formation_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Progression, String> progression =
      GeneratedColumn<String>(
        'progression',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Progression>($DancesTable.$converterprogression);
  static const VerificationMeta _phraseStructureMeta = const VerificationMeta(
    'phraseStructure',
  );
  @override
  late final GeneratedColumn<String> phraseStructure = GeneratedColumn<String>(
    'phrase_structure',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _figuresJsonMeta = const VerificationMeta(
    'figuresJson',
  );
  @override
  late final GeneratedColumn<String> figuresJson = GeneratedColumn<String>(
    'figures_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _hookMeta = const VerificationMeta('hook');
  @override
  late final GeneratedColumn<String> hook = GeneratedColumn<String>(
    'hook',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _callingNotesMeta = const VerificationMeta(
    'callingNotes',
  );
  @override
  late final GeneratedColumn<String> callingNotes = GeneratedColumn<String>(
    'calling_notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DanceStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DanceStatus>($DancesTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<DanceLevel?, String> level =
      GeneratedColumn<String>(
        'level',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DanceLevel?>($DancesTable.$converterleveln);
  static const VerificationMeta _mixedLevelMeta = const VerificationMeta(
    'mixedLevel',
  );
  @override
  late final GeneratedColumn<bool> mixedLevel = GeneratedColumn<bool>(
    'mixed_level',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("mixed_level" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _tunesJsonMeta = const VerificationMeta(
    'tunesJson',
  );
  @override
  late final GeneratedColumn<String> tunesJson = GeneratedColumn<String>(
    'tunes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    form,
    formationShape,
    formationDetail,
    progression,
    phraseStructure,
    figuresJson,
    hook,
    callingNotes,
    status,
    level,
    mixedLevel,
    tunesJson,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dances';
  @override
  VerificationContext validateIntegrity(
    Insertable<DanceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('formation_detail')) {
      context.handle(
        _formationDetailMeta,
        formationDetail.isAcceptableOrUnknown(
          data['formation_detail']!,
          _formationDetailMeta,
        ),
      );
    }
    if (data.containsKey('phrase_structure')) {
      context.handle(
        _phraseStructureMeta,
        phraseStructure.isAcceptableOrUnknown(
          data['phrase_structure']!,
          _phraseStructureMeta,
        ),
      );
    }
    if (data.containsKey('figures_json')) {
      context.handle(
        _figuresJsonMeta,
        figuresJson.isAcceptableOrUnknown(
          data['figures_json']!,
          _figuresJsonMeta,
        ),
      );
    }
    if (data.containsKey('hook')) {
      context.handle(
        _hookMeta,
        hook.isAcceptableOrUnknown(data['hook']!, _hookMeta),
      );
    }
    if (data.containsKey('calling_notes')) {
      context.handle(
        _callingNotesMeta,
        callingNotes.isAcceptableOrUnknown(
          data['calling_notes']!,
          _callingNotesMeta,
        ),
      );
    }
    if (data.containsKey('mixed_level')) {
      context.handle(
        _mixedLevelMeta,
        mixedLevel.isAcceptableOrUnknown(data['mixed_level']!, _mixedLevelMeta),
      );
    }
    if (data.containsKey('tunes_json')) {
      context.handle(
        _tunesJsonMeta,
        tunesJson.isAcceptableOrUnknown(data['tunes_json']!, _tunesJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DanceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DanceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      form: $DancesTable.$converterform.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}form'],
        )!,
      ),
      formationShape: $DancesTable.$converterformationShape.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}formation_shape'],
        )!,
      ),
      formationDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}formation_detail'],
      ),
      progression: $DancesTable.$converterprogression.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}progression'],
        )!,
      ),
      phraseStructure: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phrase_structure'],
      )!,
      figuresJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}figures_json'],
      )!,
      hook: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hook'],
      )!,
      callingNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}calling_notes'],
      )!,
      status: $DancesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      level: $DancesTable.$converterleveln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}level'],
        ),
      ),
      mixedLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}mixed_level'],
      )!,
      tunesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tunes_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $DancesTable createAlias(String alias) {
    return $DancesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DanceForm, String, String> $converterform =
      const EnumNameConverter(DanceForm.values);
  static JsonTypeConverter2<FormationShape, String, String>
  $converterformationShape = const EnumNameConverter(FormationShape.values);
  static JsonTypeConverter2<Progression, String, String> $converterprogression =
      const EnumNameConverter(Progression.values);
  static JsonTypeConverter2<DanceStatus, String, String> $converterstatus =
      const EnumNameConverter(DanceStatus.values);
  static JsonTypeConverter2<DanceLevel, String, String> $converterlevel =
      const EnumNameConverter(DanceLevel.values);
  static JsonTypeConverter2<DanceLevel?, String?, String?> $converterleveln =
      JsonTypeConverter2.asNullable($converterlevel);
}

class DanceRow extends DataClass implements Insertable<DanceRow> {
  final String id;
  final String title;
  final DanceForm form;
  final FormationShape formationShape;
  final String? formationDetail;
  final Progression progression;

  /// Persisted [PhraseStructure.raw] (`''` = the standard 4x16 structure).
  final String phraseStructure;

  /// `figures_json` — see `serialization/figure_codec.dart`.
  final String figuresJson;
  final String hook;
  final String callingNotes;
  final DanceStatus status;

  /// Difficulty on the ordered [DanceLevel] scale, persisted by enum name;
  /// nullable (`null` = unspecified). Added in schema v4 (CC-parity `Level`).
  final DanceLevel? level;

  /// Marks a dance that spans the difficulty scale; kept separate from [level]
  /// so the ordered scale stays total. Added in schema v4 (CC `Mixed Level`).
  final bool mixedLevel;

  /// JSON array of tune name strings.
  final String tunesJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const DanceRow({
    required this.id,
    required this.title,
    required this.form,
    required this.formationShape,
    this.formationDetail,
    required this.progression,
    required this.phraseStructure,
    required this.figuresJson,
    required this.hook,
    required this.callingNotes,
    required this.status,
    this.level,
    required this.mixedLevel,
    required this.tunesJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    {
      map['form'] = Variable<String>($DancesTable.$converterform.toSql(form));
    }
    {
      map['formation_shape'] = Variable<String>(
        $DancesTable.$converterformationShape.toSql(formationShape),
      );
    }
    if (!nullToAbsent || formationDetail != null) {
      map['formation_detail'] = Variable<String>(formationDetail);
    }
    {
      map['progression'] = Variable<String>(
        $DancesTable.$converterprogression.toSql(progression),
      );
    }
    map['phrase_structure'] = Variable<String>(phraseStructure);
    map['figures_json'] = Variable<String>(figuresJson);
    map['hook'] = Variable<String>(hook);
    map['calling_notes'] = Variable<String>(callingNotes);
    {
      map['status'] = Variable<String>(
        $DancesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || level != null) {
      map['level'] = Variable<String>(
        $DancesTable.$converterleveln.toSql(level),
      );
    }
    map['mixed_level'] = Variable<bool>(mixedLevel);
    map['tunes_json'] = Variable<String>(tunesJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  DancesCompanion toCompanion(bool nullToAbsent) {
    return DancesCompanion(
      id: Value(id),
      title: Value(title),
      form: Value(form),
      formationShape: Value(formationShape),
      formationDetail: formationDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(formationDetail),
      progression: Value(progression),
      phraseStructure: Value(phraseStructure),
      figuresJson: Value(figuresJson),
      hook: Value(hook),
      callingNotes: Value(callingNotes),
      status: Value(status),
      level: level == null && nullToAbsent
          ? const Value.absent()
          : Value(level),
      mixedLevel: Value(mixedLevel),
      tunesJson: Value(tunesJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory DanceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DanceRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      form: $DancesTable.$converterform.fromJson(
        serializer.fromJson<String>(json['form']),
      ),
      formationShape: $DancesTable.$converterformationShape.fromJson(
        serializer.fromJson<String>(json['formationShape']),
      ),
      formationDetail: serializer.fromJson<String?>(json['formationDetail']),
      progression: $DancesTable.$converterprogression.fromJson(
        serializer.fromJson<String>(json['progression']),
      ),
      phraseStructure: serializer.fromJson<String>(json['phraseStructure']),
      figuresJson: serializer.fromJson<String>(json['figuresJson']),
      hook: serializer.fromJson<String>(json['hook']),
      callingNotes: serializer.fromJson<String>(json['callingNotes']),
      status: $DancesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      level: $DancesTable.$converterleveln.fromJson(
        serializer.fromJson<String?>(json['level']),
      ),
      mixedLevel: serializer.fromJson<bool>(json['mixedLevel']),
      tunesJson: serializer.fromJson<String>(json['tunesJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'form': serializer.toJson<String>(
        $DancesTable.$converterform.toJson(form),
      ),
      'formationShape': serializer.toJson<String>(
        $DancesTable.$converterformationShape.toJson(formationShape),
      ),
      'formationDetail': serializer.toJson<String?>(formationDetail),
      'progression': serializer.toJson<String>(
        $DancesTable.$converterprogression.toJson(progression),
      ),
      'phraseStructure': serializer.toJson<String>(phraseStructure),
      'figuresJson': serializer.toJson<String>(figuresJson),
      'hook': serializer.toJson<String>(hook),
      'callingNotes': serializer.toJson<String>(callingNotes),
      'status': serializer.toJson<String>(
        $DancesTable.$converterstatus.toJson(status),
      ),
      'level': serializer.toJson<String?>(
        $DancesTable.$converterleveln.toJson(level),
      ),
      'mixedLevel': serializer.toJson<bool>(mixedLevel),
      'tunesJson': serializer.toJson<String>(tunesJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  DanceRow copyWith({
    String? id,
    String? title,
    DanceForm? form,
    FormationShape? formationShape,
    Value<String?> formationDetail = const Value.absent(),
    Progression? progression,
    String? phraseStructure,
    String? figuresJson,
    String? hook,
    String? callingNotes,
    DanceStatus? status,
    Value<DanceLevel?> level = const Value.absent(),
    bool? mixedLevel,
    String? tunesJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => DanceRow(
    id: id ?? this.id,
    title: title ?? this.title,
    form: form ?? this.form,
    formationShape: formationShape ?? this.formationShape,
    formationDetail: formationDetail.present
        ? formationDetail.value
        : this.formationDetail,
    progression: progression ?? this.progression,
    phraseStructure: phraseStructure ?? this.phraseStructure,
    figuresJson: figuresJson ?? this.figuresJson,
    hook: hook ?? this.hook,
    callingNotes: callingNotes ?? this.callingNotes,
    status: status ?? this.status,
    level: level.present ? level.value : this.level,
    mixedLevel: mixedLevel ?? this.mixedLevel,
    tunesJson: tunesJson ?? this.tunesJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  DanceRow copyWithCompanion(DancesCompanion data) {
    return DanceRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      form: data.form.present ? data.form.value : this.form,
      formationShape: data.formationShape.present
          ? data.formationShape.value
          : this.formationShape,
      formationDetail: data.formationDetail.present
          ? data.formationDetail.value
          : this.formationDetail,
      progression: data.progression.present
          ? data.progression.value
          : this.progression,
      phraseStructure: data.phraseStructure.present
          ? data.phraseStructure.value
          : this.phraseStructure,
      figuresJson: data.figuresJson.present
          ? data.figuresJson.value
          : this.figuresJson,
      hook: data.hook.present ? data.hook.value : this.hook,
      callingNotes: data.callingNotes.present
          ? data.callingNotes.value
          : this.callingNotes,
      status: data.status.present ? data.status.value : this.status,
      level: data.level.present ? data.level.value : this.level,
      mixedLevel: data.mixedLevel.present
          ? data.mixedLevel.value
          : this.mixedLevel,
      tunesJson: data.tunesJson.present ? data.tunesJson.value : this.tunesJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DanceRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('form: $form, ')
          ..write('formationShape: $formationShape, ')
          ..write('formationDetail: $formationDetail, ')
          ..write('progression: $progression, ')
          ..write('phraseStructure: $phraseStructure, ')
          ..write('figuresJson: $figuresJson, ')
          ..write('hook: $hook, ')
          ..write('callingNotes: $callingNotes, ')
          ..write('status: $status, ')
          ..write('level: $level, ')
          ..write('mixedLevel: $mixedLevel, ')
          ..write('tunesJson: $tunesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    form,
    formationShape,
    formationDetail,
    progression,
    phraseStructure,
    figuresJson,
    hook,
    callingNotes,
    status,
    level,
    mixedLevel,
    tunesJson,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DanceRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.form == this.form &&
          other.formationShape == this.formationShape &&
          other.formationDetail == this.formationDetail &&
          other.progression == this.progression &&
          other.phraseStructure == this.phraseStructure &&
          other.figuresJson == this.figuresJson &&
          other.hook == this.hook &&
          other.callingNotes == this.callingNotes &&
          other.status == this.status &&
          other.level == this.level &&
          other.mixedLevel == this.mixedLevel &&
          other.tunesJson == this.tunesJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class DancesCompanion extends UpdateCompanion<DanceRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<DanceForm> form;
  final Value<FormationShape> formationShape;
  final Value<String?> formationDetail;
  final Value<Progression> progression;
  final Value<String> phraseStructure;
  final Value<String> figuresJson;
  final Value<String> hook;
  final Value<String> callingNotes;
  final Value<DanceStatus> status;
  final Value<DanceLevel?> level;
  final Value<bool> mixedLevel;
  final Value<String> tunesJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const DancesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.form = const Value.absent(),
    this.formationShape = const Value.absent(),
    this.formationDetail = const Value.absent(),
    this.progression = const Value.absent(),
    this.phraseStructure = const Value.absent(),
    this.figuresJson = const Value.absent(),
    this.hook = const Value.absent(),
    this.callingNotes = const Value.absent(),
    this.status = const Value.absent(),
    this.level = const Value.absent(),
    this.mixedLevel = const Value.absent(),
    this.tunesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DancesCompanion.insert({
    required String id,
    required String title,
    required DanceForm form,
    required FormationShape formationShape,
    this.formationDetail = const Value.absent(),
    required Progression progression,
    this.phraseStructure = const Value.absent(),
    this.figuresJson = const Value.absent(),
    this.hook = const Value.absent(),
    this.callingNotes = const Value.absent(),
    required DanceStatus status,
    this.level = const Value.absent(),
    this.mixedLevel = const Value.absent(),
    this.tunesJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       form = Value(form),
       formationShape = Value(formationShape),
       progression = Value(progression),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DanceRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? form,
    Expression<String>? formationShape,
    Expression<String>? formationDetail,
    Expression<String>? progression,
    Expression<String>? phraseStructure,
    Expression<String>? figuresJson,
    Expression<String>? hook,
    Expression<String>? callingNotes,
    Expression<String>? status,
    Expression<String>? level,
    Expression<bool>? mixedLevel,
    Expression<String>? tunesJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (form != null) 'form': form,
      if (formationShape != null) 'formation_shape': formationShape,
      if (formationDetail != null) 'formation_detail': formationDetail,
      if (progression != null) 'progression': progression,
      if (phraseStructure != null) 'phrase_structure': phraseStructure,
      if (figuresJson != null) 'figures_json': figuresJson,
      if (hook != null) 'hook': hook,
      if (callingNotes != null) 'calling_notes': callingNotes,
      if (status != null) 'status': status,
      if (level != null) 'level': level,
      if (mixedLevel != null) 'mixed_level': mixedLevel,
      if (tunesJson != null) 'tunes_json': tunesJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DancesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<DanceForm>? form,
    Value<FormationShape>? formationShape,
    Value<String?>? formationDetail,
    Value<Progression>? progression,
    Value<String>? phraseStructure,
    Value<String>? figuresJson,
    Value<String>? hook,
    Value<String>? callingNotes,
    Value<DanceStatus>? status,
    Value<DanceLevel?>? level,
    Value<bool>? mixedLevel,
    Value<String>? tunesJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return DancesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      form: form ?? this.form,
      formationShape: formationShape ?? this.formationShape,
      formationDetail: formationDetail ?? this.formationDetail,
      progression: progression ?? this.progression,
      phraseStructure: phraseStructure ?? this.phraseStructure,
      figuresJson: figuresJson ?? this.figuresJson,
      hook: hook ?? this.hook,
      callingNotes: callingNotes ?? this.callingNotes,
      status: status ?? this.status,
      level: level ?? this.level,
      mixedLevel: mixedLevel ?? this.mixedLevel,
      tunesJson: tunesJson ?? this.tunesJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (form.present) {
      map['form'] = Variable<String>(
        $DancesTable.$converterform.toSql(form.value),
      );
    }
    if (formationShape.present) {
      map['formation_shape'] = Variable<String>(
        $DancesTable.$converterformationShape.toSql(formationShape.value),
      );
    }
    if (formationDetail.present) {
      map['formation_detail'] = Variable<String>(formationDetail.value);
    }
    if (progression.present) {
      map['progression'] = Variable<String>(
        $DancesTable.$converterprogression.toSql(progression.value),
      );
    }
    if (phraseStructure.present) {
      map['phrase_structure'] = Variable<String>(phraseStructure.value);
    }
    if (figuresJson.present) {
      map['figures_json'] = Variable<String>(figuresJson.value);
    }
    if (hook.present) {
      map['hook'] = Variable<String>(hook.value);
    }
    if (callingNotes.present) {
      map['calling_notes'] = Variable<String>(callingNotes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $DancesTable.$converterstatus.toSql(status.value),
      );
    }
    if (level.present) {
      map['level'] = Variable<String>(
        $DancesTable.$converterleveln.toSql(level.value),
      );
    }
    if (mixedLevel.present) {
      map['mixed_level'] = Variable<bool>(mixedLevel.value);
    }
    if (tunesJson.present) {
      map['tunes_json'] = Variable<String>(tunesJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DancesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('form: $form, ')
          ..write('formationShape: $formationShape, ')
          ..write('formationDetail: $formationDetail, ')
          ..write('progression: $progression, ')
          ..write('phraseStructure: $phraseStructure, ')
          ..write('figuresJson: $figuresJson, ')
          ..write('hook: $hook, ')
          ..write('callingNotes: $callingNotes, ')
          ..write('status: $status, ')
          ..write('level: $level, ')
          ..write('mixedLevel: $mixedLevel, ')
          ..write('tunesJson: $tunesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChoreographersTable extends Choreographers
    with TableInfo<$ChoreographersTable, ChoreographerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChoreographersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _websiteMeta = const VerificationMeta(
    'website',
  );
  @override
  late final GeneratedColumn<String> website = GeneratedColumn<String>(
    'website',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, website, notes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'choreographers';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChoreographerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('website')) {
      context.handle(
        _websiteMeta,
        website.isAcceptableOrUnknown(data['website']!, _websiteMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChoreographerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChoreographerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      website: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}website'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
    );
  }

  @override
  $ChoreographersTable createAlias(String alias) {
    return $ChoreographersTable(attachedDatabase, alias);
  }
}

class ChoreographerRow extends DataClass
    implements Insertable<ChoreographerRow> {
  final String id;
  final String name;
  final String? website;
  final String? notes;
  const ChoreographerRow({
    required this.id,
    required this.name,
    this.website,
    this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || website != null) {
      map['website'] = Variable<String>(website);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  ChoreographersCompanion toCompanion(bool nullToAbsent) {
    return ChoreographersCompanion(
      id: Value(id),
      name: Value(name),
      website: website == null && nullToAbsent
          ? const Value.absent()
          : Value(website),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
    );
  }

  factory ChoreographerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChoreographerRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      website: serializer.fromJson<String?>(json['website']),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'website': serializer.toJson<String?>(website),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  ChoreographerRow copyWith({
    String? id,
    String? name,
    Value<String?> website = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) => ChoreographerRow(
    id: id ?? this.id,
    name: name ?? this.name,
    website: website.present ? website.value : this.website,
    notes: notes.present ? notes.value : this.notes,
  );
  ChoreographerRow copyWithCompanion(ChoreographersCompanion data) {
    return ChoreographerRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      website: data.website.present ? data.website.value : this.website,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChoreographerRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('website: $website, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, website, notes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChoreographerRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.website == this.website &&
          other.notes == this.notes);
}

class ChoreographersCompanion extends UpdateCompanion<ChoreographerRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> website;
  final Value<String?> notes;
  final Value<int> rowid;
  const ChoreographersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.website = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChoreographersCompanion.insert({
    required String id,
    required String name,
    this.website = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ChoreographerRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? website,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (website != null) 'website': website,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChoreographersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? website,
    Value<String?>? notes,
    Value<int>? rowid,
  }) {
    return ChoreographersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      website: website ?? this.website,
      notes: notes ?? this.notes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (website.present) {
      map['website'] = Variable<String>(website.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChoreographersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('website: $website, ')
          ..write('notes: $notes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DanceAuthorsTable extends DanceAuthors
    with TableInfo<$DanceAuthorsTable, DanceAuthorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DanceAuthorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _choreographerIdMeta = const VerificationMeta(
    'choreographerId',
  );
  @override
  late final GeneratedColumn<String> choreographerId = GeneratedColumn<String>(
    'choreographer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES choreographers (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [danceId, choreographerId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dance_authors';
  @override
  VerificationContext validateIntegrity(
    Insertable<DanceAuthorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_danceIdMeta);
    }
    if (data.containsKey('choreographer_id')) {
      context.handle(
        _choreographerIdMeta,
        choreographerId.isAcceptableOrUnknown(
          data['choreographer_id']!,
          _choreographerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_choreographerIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {danceId, choreographerId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {danceId, position},
  ];
  @override
  DanceAuthorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DanceAuthorRow(
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      )!,
      choreographerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}choreographer_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $DanceAuthorsTable createAlias(String alias) {
    return $DanceAuthorsTable(attachedDatabase, alias);
  }
}

class DanceAuthorRow extends DataClass implements Insertable<DanceAuthorRow> {
  final String danceId;
  final String choreographerId;
  final int position;
  const DanceAuthorRow({
    required this.danceId,
    required this.choreographerId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dance_id'] = Variable<String>(danceId);
    map['choreographer_id'] = Variable<String>(choreographerId);
    map['position'] = Variable<int>(position);
    return map;
  }

  DanceAuthorsCompanion toCompanion(bool nullToAbsent) {
    return DanceAuthorsCompanion(
      danceId: Value(danceId),
      choreographerId: Value(choreographerId),
      position: Value(position),
    );
  }

  factory DanceAuthorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DanceAuthorRow(
      danceId: serializer.fromJson<String>(json['danceId']),
      choreographerId: serializer.fromJson<String>(json['choreographerId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'danceId': serializer.toJson<String>(danceId),
      'choreographerId': serializer.toJson<String>(choreographerId),
      'position': serializer.toJson<int>(position),
    };
  }

  DanceAuthorRow copyWith({
    String? danceId,
    String? choreographerId,
    int? position,
  }) => DanceAuthorRow(
    danceId: danceId ?? this.danceId,
    choreographerId: choreographerId ?? this.choreographerId,
    position: position ?? this.position,
  );
  DanceAuthorRow copyWithCompanion(DanceAuthorsCompanion data) {
    return DanceAuthorRow(
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      choreographerId: data.choreographerId.present
          ? data.choreographerId.value
          : this.choreographerId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DanceAuthorRow(')
          ..write('danceId: $danceId, ')
          ..write('choreographerId: $choreographerId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(danceId, choreographerId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DanceAuthorRow &&
          other.danceId == this.danceId &&
          other.choreographerId == this.choreographerId &&
          other.position == this.position);
}

class DanceAuthorsCompanion extends UpdateCompanion<DanceAuthorRow> {
  final Value<String> danceId;
  final Value<String> choreographerId;
  final Value<int> position;
  final Value<int> rowid;
  const DanceAuthorsCompanion({
    this.danceId = const Value.absent(),
    this.choreographerId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DanceAuthorsCompanion.insert({
    required String danceId,
    required String choreographerId,
    required int position,
    this.rowid = const Value.absent(),
  }) : danceId = Value(danceId),
       choreographerId = Value(choreographerId),
       position = Value(position);
  static Insertable<DanceAuthorRow> custom({
    Expression<String>? danceId,
    Expression<String>? choreographerId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (danceId != null) 'dance_id': danceId,
      if (choreographerId != null) 'choreographer_id': choreographerId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DanceAuthorsCompanion copyWith({
    Value<String>? danceId,
    Value<String>? choreographerId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return DanceAuthorsCompanion(
      danceId: danceId ?? this.danceId,
      choreographerId: choreographerId ?? this.choreographerId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (choreographerId.present) {
      map['choreographer_id'] = Variable<String>(choreographerId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DanceAuthorsCompanion(')
          ..write('danceId: $danceId, ')
          ..write('choreographerId: $choreographerId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DanceFiguresTable extends DanceFigures
    with TableInfo<$DanceFiguresTable, DanceFigureRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DanceFiguresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _idxMeta = const VerificationMeta('idx');
  @override
  late final GeneratedColumn<int> idx = GeneratedColumn<int>(
    'idx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moveMeta = const VerificationMeta('move');
  @override
  late final GeneratedColumn<String> move = GeneratedColumn<String>(
    'move',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _beatsMeta = const VerificationMeta('beats');
  @override
  late final GeneratedColumn<int> beats = GeneratedColumn<int>(
    'beats',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressionMeta = const VerificationMeta(
    'progression',
  );
  @override
  late final GeneratedColumn<bool> progression = GeneratedColumn<bool>(
    'progression',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("progression" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _paramsJsonMeta = const VerificationMeta(
    'paramsJson',
  );
  @override
  late final GeneratedColumn<String> paramsJson = GeneratedColumn<String>(
    'params_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _canonicalTextMeta = const VerificationMeta(
    'canonicalText',
  );
  @override
  late final GeneratedColumn<String> canonicalText = GeneratedColumn<String>(
    'canonical_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sectionMeta = const VerificationMeta(
    'section',
  );
  @override
  late final GeneratedColumn<String> section = GeneratedColumn<String>(
    'section',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    danceId,
    idx,
    move,
    beats,
    progression,
    paramsJson,
    canonicalText,
    section,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dance_figures';
  @override
  VerificationContext validateIntegrity(
    Insertable<DanceFigureRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_danceIdMeta);
    }
    if (data.containsKey('idx')) {
      context.handle(
        _idxMeta,
        idx.isAcceptableOrUnknown(data['idx']!, _idxMeta),
      );
    } else if (isInserting) {
      context.missing(_idxMeta);
    }
    if (data.containsKey('move')) {
      context.handle(
        _moveMeta,
        move.isAcceptableOrUnknown(data['move']!, _moveMeta),
      );
    } else if (isInserting) {
      context.missing(_moveMeta);
    }
    if (data.containsKey('beats')) {
      context.handle(
        _beatsMeta,
        beats.isAcceptableOrUnknown(data['beats']!, _beatsMeta),
      );
    }
    if (data.containsKey('progression')) {
      context.handle(
        _progressionMeta,
        progression.isAcceptableOrUnknown(
          data['progression']!,
          _progressionMeta,
        ),
      );
    }
    if (data.containsKey('params_json')) {
      context.handle(
        _paramsJsonMeta,
        paramsJson.isAcceptableOrUnknown(data['params_json']!, _paramsJsonMeta),
      );
    }
    if (data.containsKey('canonical_text')) {
      context.handle(
        _canonicalTextMeta,
        canonicalText.isAcceptableOrUnknown(
          data['canonical_text']!,
          _canonicalTextMeta,
        ),
      );
    }
    if (data.containsKey('section')) {
      context.handle(
        _sectionMeta,
        section.isAcceptableOrUnknown(data['section']!, _sectionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {danceId, idx};
  @override
  DanceFigureRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DanceFigureRow(
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      )!,
      idx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idx'],
      )!,
      move: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}move'],
      )!,
      beats: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}beats'],
      )!,
      progression: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}progression'],
      )!,
      paramsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}params_json'],
      )!,
      canonicalText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_text'],
      )!,
      section: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section'],
      ),
    );
  }

  @override
  $DanceFiguresTable createAlias(String alias) {
    return $DanceFiguresTable(attachedDatabase, alias);
  }
}

class DanceFigureRow extends DataClass implements Insertable<DanceFigureRow> {
  final String danceId;
  final int idx;
  final String move;
  final int beats;
  final bool progression;

  /// Figure `params` as JSON (queried via SQLite JSON1, `params_json ->> ...`).
  final String paramsJson;

  /// Rendered canonical text (dialect-free); feeds `dance_fts.figures_text`.
  final String canonicalText;

  /// Derived phrase label (`A1`, `B2`, …) of the phrase in which this figure
  /// *starts* ([SectionedFigure.label]); nullable to stay forward-compatible
  /// with structureless forms. Added in schema v2 for section-aware search.
  final String? section;
  const DanceFigureRow({
    required this.danceId,
    required this.idx,
    required this.move,
    required this.beats,
    required this.progression,
    required this.paramsJson,
    required this.canonicalText,
    this.section,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dance_id'] = Variable<String>(danceId);
    map['idx'] = Variable<int>(idx);
    map['move'] = Variable<String>(move);
    map['beats'] = Variable<int>(beats);
    map['progression'] = Variable<bool>(progression);
    map['params_json'] = Variable<String>(paramsJson);
    map['canonical_text'] = Variable<String>(canonicalText);
    if (!nullToAbsent || section != null) {
      map['section'] = Variable<String>(section);
    }
    return map;
  }

  DanceFiguresCompanion toCompanion(bool nullToAbsent) {
    return DanceFiguresCompanion(
      danceId: Value(danceId),
      idx: Value(idx),
      move: Value(move),
      beats: Value(beats),
      progression: Value(progression),
      paramsJson: Value(paramsJson),
      canonicalText: Value(canonicalText),
      section: section == null && nullToAbsent
          ? const Value.absent()
          : Value(section),
    );
  }

  factory DanceFigureRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DanceFigureRow(
      danceId: serializer.fromJson<String>(json['danceId']),
      idx: serializer.fromJson<int>(json['idx']),
      move: serializer.fromJson<String>(json['move']),
      beats: serializer.fromJson<int>(json['beats']),
      progression: serializer.fromJson<bool>(json['progression']),
      paramsJson: serializer.fromJson<String>(json['paramsJson']),
      canonicalText: serializer.fromJson<String>(json['canonicalText']),
      section: serializer.fromJson<String?>(json['section']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'danceId': serializer.toJson<String>(danceId),
      'idx': serializer.toJson<int>(idx),
      'move': serializer.toJson<String>(move),
      'beats': serializer.toJson<int>(beats),
      'progression': serializer.toJson<bool>(progression),
      'paramsJson': serializer.toJson<String>(paramsJson),
      'canonicalText': serializer.toJson<String>(canonicalText),
      'section': serializer.toJson<String?>(section),
    };
  }

  DanceFigureRow copyWith({
    String? danceId,
    int? idx,
    String? move,
    int? beats,
    bool? progression,
    String? paramsJson,
    String? canonicalText,
    Value<String?> section = const Value.absent(),
  }) => DanceFigureRow(
    danceId: danceId ?? this.danceId,
    idx: idx ?? this.idx,
    move: move ?? this.move,
    beats: beats ?? this.beats,
    progression: progression ?? this.progression,
    paramsJson: paramsJson ?? this.paramsJson,
    canonicalText: canonicalText ?? this.canonicalText,
    section: section.present ? section.value : this.section,
  );
  DanceFigureRow copyWithCompanion(DanceFiguresCompanion data) {
    return DanceFigureRow(
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      idx: data.idx.present ? data.idx.value : this.idx,
      move: data.move.present ? data.move.value : this.move,
      beats: data.beats.present ? data.beats.value : this.beats,
      progression: data.progression.present
          ? data.progression.value
          : this.progression,
      paramsJson: data.paramsJson.present
          ? data.paramsJson.value
          : this.paramsJson,
      canonicalText: data.canonicalText.present
          ? data.canonicalText.value
          : this.canonicalText,
      section: data.section.present ? data.section.value : this.section,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DanceFigureRow(')
          ..write('danceId: $danceId, ')
          ..write('idx: $idx, ')
          ..write('move: $move, ')
          ..write('beats: $beats, ')
          ..write('progression: $progression, ')
          ..write('paramsJson: $paramsJson, ')
          ..write('canonicalText: $canonicalText, ')
          ..write('section: $section')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    danceId,
    idx,
    move,
    beats,
    progression,
    paramsJson,
    canonicalText,
    section,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DanceFigureRow &&
          other.danceId == this.danceId &&
          other.idx == this.idx &&
          other.move == this.move &&
          other.beats == this.beats &&
          other.progression == this.progression &&
          other.paramsJson == this.paramsJson &&
          other.canonicalText == this.canonicalText &&
          other.section == this.section);
}

class DanceFiguresCompanion extends UpdateCompanion<DanceFigureRow> {
  final Value<String> danceId;
  final Value<int> idx;
  final Value<String> move;
  final Value<int> beats;
  final Value<bool> progression;
  final Value<String> paramsJson;
  final Value<String> canonicalText;
  final Value<String?> section;
  final Value<int> rowid;
  const DanceFiguresCompanion({
    this.danceId = const Value.absent(),
    this.idx = const Value.absent(),
    this.move = const Value.absent(),
    this.beats = const Value.absent(),
    this.progression = const Value.absent(),
    this.paramsJson = const Value.absent(),
    this.canonicalText = const Value.absent(),
    this.section = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DanceFiguresCompanion.insert({
    required String danceId,
    required int idx,
    required String move,
    this.beats = const Value.absent(),
    this.progression = const Value.absent(),
    this.paramsJson = const Value.absent(),
    this.canonicalText = const Value.absent(),
    this.section = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : danceId = Value(danceId),
       idx = Value(idx),
       move = Value(move);
  static Insertable<DanceFigureRow> custom({
    Expression<String>? danceId,
    Expression<int>? idx,
    Expression<String>? move,
    Expression<int>? beats,
    Expression<bool>? progression,
    Expression<String>? paramsJson,
    Expression<String>? canonicalText,
    Expression<String>? section,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (danceId != null) 'dance_id': danceId,
      if (idx != null) 'idx': idx,
      if (move != null) 'move': move,
      if (beats != null) 'beats': beats,
      if (progression != null) 'progression': progression,
      if (paramsJson != null) 'params_json': paramsJson,
      if (canonicalText != null) 'canonical_text': canonicalText,
      if (section != null) 'section': section,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DanceFiguresCompanion copyWith({
    Value<String>? danceId,
    Value<int>? idx,
    Value<String>? move,
    Value<int>? beats,
    Value<bool>? progression,
    Value<String>? paramsJson,
    Value<String>? canonicalText,
    Value<String?>? section,
    Value<int>? rowid,
  }) {
    return DanceFiguresCompanion(
      danceId: danceId ?? this.danceId,
      idx: idx ?? this.idx,
      move: move ?? this.move,
      beats: beats ?? this.beats,
      progression: progression ?? this.progression,
      paramsJson: paramsJson ?? this.paramsJson,
      canonicalText: canonicalText ?? this.canonicalText,
      section: section ?? this.section,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (idx.present) {
      map['idx'] = Variable<int>(idx.value);
    }
    if (move.present) {
      map['move'] = Variable<String>(move.value);
    }
    if (beats.present) {
      map['beats'] = Variable<int>(beats.value);
    }
    if (progression.present) {
      map['progression'] = Variable<bool>(progression.value);
    }
    if (paramsJson.present) {
      map['params_json'] = Variable<String>(paramsJson.value);
    }
    if (canonicalText.present) {
      map['canonical_text'] = Variable<String>(canonicalText.value);
    }
    if (section.present) {
      map['section'] = Variable<String>(section.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DanceFiguresCompanion(')
          ..write('danceId: $danceId, ')
          ..write('idx: $idx, ')
          ..write('move: $move, ')
          ..write('beats: $beats, ')
          ..write('progression: $progression, ')
          ..write('paramsJson: $paramsJson, ')
          ..write('canonicalText: $canonicalText, ')
          ..write('section: $section, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramsTable extends Programs
    with TableInfo<$ProgramsTable, ProgramRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventDateMeta = const VerificationMeta(
    'eventDate',
  );
  @override
  late final GeneratedColumn<DateTime> eventDate = GeneratedColumn<DateTime>(
    'event_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _venueMeta = const VerificationMeta('venue');
  @override
  late final GeneratedColumn<String> venue = GeneratedColumn<String>(
    'venue',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bandMeta = const VerificationMeta('band');
  @override
  late final GeneratedColumn<String> band = GeneratedColumn<String>(
    'band',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _callerMeta = const VerificationMeta('caller');
  @override
  late final GeneratedColumn<String> caller = GeneratedColumn<String>(
    'caller',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dancerLevelMeta = const VerificationMeta(
    'dancerLevel',
  );
  @override
  late final GeneratedColumn<String> dancerLevel = GeneratedColumn<String>(
    'dancer_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ProgramStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ProgramStatus>($ProgramsTable.$converterstatus);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    eventDate,
    venue,
    band,
    caller,
    dancerLevel,
    notes,
    status,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'programs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgramRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('event_date')) {
      context.handle(
        _eventDateMeta,
        eventDate.isAcceptableOrUnknown(data['event_date']!, _eventDateMeta),
      );
    }
    if (data.containsKey('venue')) {
      context.handle(
        _venueMeta,
        venue.isAcceptableOrUnknown(data['venue']!, _venueMeta),
      );
    }
    if (data.containsKey('band')) {
      context.handle(
        _bandMeta,
        band.isAcceptableOrUnknown(data['band']!, _bandMeta),
      );
    }
    if (data.containsKey('caller')) {
      context.handle(
        _callerMeta,
        caller.isAcceptableOrUnknown(data['caller']!, _callerMeta),
      );
    }
    if (data.containsKey('dancer_level')) {
      context.handle(
        _dancerLevelMeta,
        dancerLevel.isAcceptableOrUnknown(
          data['dancer_level']!,
          _dancerLevelMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgramRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgramRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      eventDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}event_date'],
      ),
      venue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}venue'],
      ),
      band: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}band'],
      ),
      caller: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caller'],
      ),
      dancerLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dancer_level'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      status: $ProgramsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ProgramsTable createAlias(String alias) {
    return $ProgramsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ProgramStatus, String, String> $converterstatus =
      const EnumNameConverter(ProgramStatus.values);
}

class ProgramRow extends DataClass implements Insertable<ProgramRow> {
  final String id;
  final String title;
  final DateTime? eventDate;
  final String? venue;
  final String? band;
  final String? caller;
  final String? dancerLevel;
  final String notes;
  final ProgramStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ProgramRow({
    required this.id,
    required this.title,
    this.eventDate,
    this.venue,
    this.band,
    this.caller,
    this.dancerLevel,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || eventDate != null) {
      map['event_date'] = Variable<DateTime>(eventDate);
    }
    if (!nullToAbsent || venue != null) {
      map['venue'] = Variable<String>(venue);
    }
    if (!nullToAbsent || band != null) {
      map['band'] = Variable<String>(band);
    }
    if (!nullToAbsent || caller != null) {
      map['caller'] = Variable<String>(caller);
    }
    if (!nullToAbsent || dancerLevel != null) {
      map['dancer_level'] = Variable<String>(dancerLevel);
    }
    map['notes'] = Variable<String>(notes);
    {
      map['status'] = Variable<String>(
        $ProgramsTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProgramsCompanion toCompanion(bool nullToAbsent) {
    return ProgramsCompanion(
      id: Value(id),
      title: Value(title),
      eventDate: eventDate == null && nullToAbsent
          ? const Value.absent()
          : Value(eventDate),
      venue: venue == null && nullToAbsent
          ? const Value.absent()
          : Value(venue),
      band: band == null && nullToAbsent ? const Value.absent() : Value(band),
      caller: caller == null && nullToAbsent
          ? const Value.absent()
          : Value(caller),
      dancerLevel: dancerLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(dancerLevel),
      notes: Value(notes),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProgramRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgramRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      eventDate: serializer.fromJson<DateTime?>(json['eventDate']),
      venue: serializer.fromJson<String?>(json['venue']),
      band: serializer.fromJson<String?>(json['band']),
      caller: serializer.fromJson<String?>(json['caller']),
      dancerLevel: serializer.fromJson<String?>(json['dancerLevel']),
      notes: serializer.fromJson<String>(json['notes']),
      status: $ProgramsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'eventDate': serializer.toJson<DateTime?>(eventDate),
      'venue': serializer.toJson<String?>(venue),
      'band': serializer.toJson<String?>(band),
      'caller': serializer.toJson<String?>(caller),
      'dancerLevel': serializer.toJson<String?>(dancerLevel),
      'notes': serializer.toJson<String>(notes),
      'status': serializer.toJson<String>(
        $ProgramsTable.$converterstatus.toJson(status),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ProgramRow copyWith({
    String? id,
    String? title,
    Value<DateTime?> eventDate = const Value.absent(),
    Value<String?> venue = const Value.absent(),
    Value<String?> band = const Value.absent(),
    Value<String?> caller = const Value.absent(),
    Value<String?> dancerLevel = const Value.absent(),
    String? notes,
    ProgramStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ProgramRow(
    id: id ?? this.id,
    title: title ?? this.title,
    eventDate: eventDate.present ? eventDate.value : this.eventDate,
    venue: venue.present ? venue.value : this.venue,
    band: band.present ? band.value : this.band,
    caller: caller.present ? caller.value : this.caller,
    dancerLevel: dancerLevel.present ? dancerLevel.value : this.dancerLevel,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ProgramRow copyWithCompanion(ProgramsCompanion data) {
    return ProgramRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      eventDate: data.eventDate.present ? data.eventDate.value : this.eventDate,
      venue: data.venue.present ? data.venue.value : this.venue,
      band: data.band.present ? data.band.value : this.band,
      caller: data.caller.present ? data.caller.value : this.caller,
      dancerLevel: data.dancerLevel.present
          ? data.dancerLevel.value
          : this.dancerLevel,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('eventDate: $eventDate, ')
          ..write('venue: $venue, ')
          ..write('band: $band, ')
          ..write('caller: $caller, ')
          ..write('dancerLevel: $dancerLevel, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    eventDate,
    venue,
    band,
    caller,
    dancerLevel,
    notes,
    status,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgramRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.eventDate == this.eventDate &&
          other.venue == this.venue &&
          other.band == this.band &&
          other.caller == this.caller &&
          other.dancerLevel == this.dancerLevel &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProgramsCompanion extends UpdateCompanion<ProgramRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<DateTime?> eventDate;
  final Value<String?> venue;
  final Value<String?> band;
  final Value<String?> caller;
  final Value<String?> dancerLevel;
  final Value<String> notes;
  final Value<ProgramStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProgramsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.eventDate = const Value.absent(),
    this.venue = const Value.absent(),
    this.band = const Value.absent(),
    this.caller = const Value.absent(),
    this.dancerLevel = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramsCompanion.insert({
    required String id,
    required String title,
    this.eventDate = const Value.absent(),
    this.venue = const Value.absent(),
    this.band = const Value.absent(),
    this.caller = const Value.absent(),
    this.dancerLevel = const Value.absent(),
    this.notes = const Value.absent(),
    required ProgramStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProgramRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<DateTime>? eventDate,
    Expression<String>? venue,
    Expression<String>? band,
    Expression<String>? caller,
    Expression<String>? dancerLevel,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (eventDate != null) 'event_date': eventDate,
      if (venue != null) 'venue': venue,
      if (band != null) 'band': band,
      if (caller != null) 'caller': caller,
      if (dancerLevel != null) 'dancer_level': dancerLevel,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<DateTime?>? eventDate,
    Value<String?>? venue,
    Value<String?>? band,
    Value<String?>? caller,
    Value<String?>? dancerLevel,
    Value<String>? notes,
    Value<ProgramStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ProgramsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      eventDate: eventDate ?? this.eventDate,
      venue: venue ?? this.venue,
      band: band ?? this.band,
      caller: caller ?? this.caller,
      dancerLevel: dancerLevel ?? this.dancerLevel,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (eventDate.present) {
      map['event_date'] = Variable<DateTime>(eventDate.value);
    }
    if (venue.present) {
      map['venue'] = Variable<String>(venue.value);
    }
    if (band.present) {
      map['band'] = Variable<String>(band.value);
    }
    if (caller.present) {
      map['caller'] = Variable<String>(caller.value);
    }
    if (dancerLevel.present) {
      map['dancer_level'] = Variable<String>(dancerLevel.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ProgramsTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('eventDate: $eventDate, ')
          ..write('venue: $venue, ')
          ..write('band: $band, ')
          ..write('caller: $caller, ')
          ..write('dancerLevel: $dancerLevel, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramSlotsTable extends ProgramSlots
    with TableInfo<$ProgramSlotsTable, ProgramSlotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramSlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _programIdMeta = const VerificationMeta(
    'programId',
  );
  @override
  late final GeneratedColumn<String> programId = GeneratedColumn<String>(
    'program_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES programs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _text_Meta = const VerificationMeta('text_');
  @override
  late final GeneratedColumn<String> text_ = GeneratedColumn<String>(
    'text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isAltMeta = const VerificationMeta('isAlt');
  @override
  late final GeneratedColumn<bool> isAlt = GeneratedColumn<bool>(
    'is_alt',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_alt" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _guestCallerMeta = const VerificationMeta(
    'guestCaller',
  );
  @override
  late final GeneratedColumn<String> guestCaller = GeneratedColumn<String>(
    'guest_caller',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedMinutesMeta = const VerificationMeta(
    'plannedMinutes',
  );
  @override
  late final GeneratedColumn<int> plannedMinutes = GeneratedColumn<int>(
    'planned_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _performedAtMeta = const VerificationMeta(
    'performedAt',
  );
  @override
  late final GeneratedColumn<DateTime> performedAt = GeneratedColumn<DateTime>(
    'performed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    programId,
    position,
    danceId,
    text_,
    isAlt,
    guestCaller,
    plannedMinutes,
    performedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'program_slots';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgramSlotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('program_id')) {
      context.handle(
        _programIdMeta,
        programId.isAcceptableOrUnknown(data['program_id']!, _programIdMeta),
      );
    } else if (isInserting) {
      context.missing(_programIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _text_Meta,
        text_.isAcceptableOrUnknown(data['text']!, _text_Meta),
      );
    }
    if (data.containsKey('is_alt')) {
      context.handle(
        _isAltMeta,
        isAlt.isAcceptableOrUnknown(data['is_alt']!, _isAltMeta),
      );
    }
    if (data.containsKey('guest_caller')) {
      context.handle(
        _guestCallerMeta,
        guestCaller.isAcceptableOrUnknown(
          data['guest_caller']!,
          _guestCallerMeta,
        ),
      );
    }
    if (data.containsKey('planned_minutes')) {
      context.handle(
        _plannedMinutesMeta,
        plannedMinutes.isAcceptableOrUnknown(
          data['planned_minutes']!,
          _plannedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('performed_at')) {
      context.handle(
        _performedAtMeta,
        performedAt.isAcceptableOrUnknown(
          data['performed_at']!,
          _performedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgramSlotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgramSlotRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      programId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}program_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      ),
      text_: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      ),
      isAlt: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_alt'],
      )!,
      guestCaller: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}guest_caller'],
      ),
      plannedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_minutes'],
      ),
      performedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}performed_at'],
      ),
    );
  }

  @override
  $ProgramSlotsTable createAlias(String alias) {
    return $ProgramSlotsTable(attachedDatabase, alias);
  }
}

class ProgramSlotRow extends DataClass implements Insertable<ProgramSlotRow> {
  final String id;
  final String programId;
  final int position;
  final String? danceId;
  final String? text_;
  final bool isAlt;
  final String? guestCaller;
  final int? plannedMinutes;
  final DateTime? performedAt;
  const ProgramSlotRow({
    required this.id,
    required this.programId,
    required this.position,
    this.danceId,
    this.text_,
    required this.isAlt,
    this.guestCaller,
    this.plannedMinutes,
    this.performedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['program_id'] = Variable<String>(programId);
    map['position'] = Variable<int>(position);
    if (!nullToAbsent || danceId != null) {
      map['dance_id'] = Variable<String>(danceId);
    }
    if (!nullToAbsent || text_ != null) {
      map['text'] = Variable<String>(text_);
    }
    map['is_alt'] = Variable<bool>(isAlt);
    if (!nullToAbsent || guestCaller != null) {
      map['guest_caller'] = Variable<String>(guestCaller);
    }
    if (!nullToAbsent || plannedMinutes != null) {
      map['planned_minutes'] = Variable<int>(plannedMinutes);
    }
    if (!nullToAbsent || performedAt != null) {
      map['performed_at'] = Variable<DateTime>(performedAt);
    }
    return map;
  }

  ProgramSlotsCompanion toCompanion(bool nullToAbsent) {
    return ProgramSlotsCompanion(
      id: Value(id),
      programId: Value(programId),
      position: Value(position),
      danceId: danceId == null && nullToAbsent
          ? const Value.absent()
          : Value(danceId),
      text_: text_ == null && nullToAbsent
          ? const Value.absent()
          : Value(text_),
      isAlt: Value(isAlt),
      guestCaller: guestCaller == null && nullToAbsent
          ? const Value.absent()
          : Value(guestCaller),
      plannedMinutes: plannedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedMinutes),
      performedAt: performedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(performedAt),
    );
  }

  factory ProgramSlotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgramSlotRow(
      id: serializer.fromJson<String>(json['id']),
      programId: serializer.fromJson<String>(json['programId']),
      position: serializer.fromJson<int>(json['position']),
      danceId: serializer.fromJson<String?>(json['danceId']),
      text_: serializer.fromJson<String?>(json['text_']),
      isAlt: serializer.fromJson<bool>(json['isAlt']),
      guestCaller: serializer.fromJson<String?>(json['guestCaller']),
      plannedMinutes: serializer.fromJson<int?>(json['plannedMinutes']),
      performedAt: serializer.fromJson<DateTime?>(json['performedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'programId': serializer.toJson<String>(programId),
      'position': serializer.toJson<int>(position),
      'danceId': serializer.toJson<String?>(danceId),
      'text_': serializer.toJson<String?>(text_),
      'isAlt': serializer.toJson<bool>(isAlt),
      'guestCaller': serializer.toJson<String?>(guestCaller),
      'plannedMinutes': serializer.toJson<int?>(plannedMinutes),
      'performedAt': serializer.toJson<DateTime?>(performedAt),
    };
  }

  ProgramSlotRow copyWith({
    String? id,
    String? programId,
    int? position,
    Value<String?> danceId = const Value.absent(),
    Value<String?> text_ = const Value.absent(),
    bool? isAlt,
    Value<String?> guestCaller = const Value.absent(),
    Value<int?> plannedMinutes = const Value.absent(),
    Value<DateTime?> performedAt = const Value.absent(),
  }) => ProgramSlotRow(
    id: id ?? this.id,
    programId: programId ?? this.programId,
    position: position ?? this.position,
    danceId: danceId.present ? danceId.value : this.danceId,
    text_: text_.present ? text_.value : this.text_,
    isAlt: isAlt ?? this.isAlt,
    guestCaller: guestCaller.present ? guestCaller.value : this.guestCaller,
    plannedMinutes: plannedMinutes.present
        ? plannedMinutes.value
        : this.plannedMinutes,
    performedAt: performedAt.present ? performedAt.value : this.performedAt,
  );
  ProgramSlotRow copyWithCompanion(ProgramSlotsCompanion data) {
    return ProgramSlotRow(
      id: data.id.present ? data.id.value : this.id,
      programId: data.programId.present ? data.programId.value : this.programId,
      position: data.position.present ? data.position.value : this.position,
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      text_: data.text_.present ? data.text_.value : this.text_,
      isAlt: data.isAlt.present ? data.isAlt.value : this.isAlt,
      guestCaller: data.guestCaller.present
          ? data.guestCaller.value
          : this.guestCaller,
      plannedMinutes: data.plannedMinutes.present
          ? data.plannedMinutes.value
          : this.plannedMinutes,
      performedAt: data.performedAt.present
          ? data.performedAt.value
          : this.performedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgramSlotRow(')
          ..write('id: $id, ')
          ..write('programId: $programId, ')
          ..write('position: $position, ')
          ..write('danceId: $danceId, ')
          ..write('text_: $text_, ')
          ..write('isAlt: $isAlt, ')
          ..write('guestCaller: $guestCaller, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('performedAt: $performedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    programId,
    position,
    danceId,
    text_,
    isAlt,
    guestCaller,
    plannedMinutes,
    performedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgramSlotRow &&
          other.id == this.id &&
          other.programId == this.programId &&
          other.position == this.position &&
          other.danceId == this.danceId &&
          other.text_ == this.text_ &&
          other.isAlt == this.isAlt &&
          other.guestCaller == this.guestCaller &&
          other.plannedMinutes == this.plannedMinutes &&
          other.performedAt == this.performedAt);
}

class ProgramSlotsCompanion extends UpdateCompanion<ProgramSlotRow> {
  final Value<String> id;
  final Value<String> programId;
  final Value<int> position;
  final Value<String?> danceId;
  final Value<String?> text_;
  final Value<bool> isAlt;
  final Value<String?> guestCaller;
  final Value<int?> plannedMinutes;
  final Value<DateTime?> performedAt;
  final Value<int> rowid;
  const ProgramSlotsCompanion({
    this.id = const Value.absent(),
    this.programId = const Value.absent(),
    this.position = const Value.absent(),
    this.danceId = const Value.absent(),
    this.text_ = const Value.absent(),
    this.isAlt = const Value.absent(),
    this.guestCaller = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    this.performedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramSlotsCompanion.insert({
    required String id,
    required String programId,
    required int position,
    this.danceId = const Value.absent(),
    this.text_ = const Value.absent(),
    this.isAlt = const Value.absent(),
    this.guestCaller = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    this.performedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       programId = Value(programId),
       position = Value(position);
  static Insertable<ProgramSlotRow> custom({
    Expression<String>? id,
    Expression<String>? programId,
    Expression<int>? position,
    Expression<String>? danceId,
    Expression<String>? text_,
    Expression<bool>? isAlt,
    Expression<String>? guestCaller,
    Expression<int>? plannedMinutes,
    Expression<DateTime>? performedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (programId != null) 'program_id': programId,
      if (position != null) 'position': position,
      if (danceId != null) 'dance_id': danceId,
      if (text_ != null) 'text': text_,
      if (isAlt != null) 'is_alt': isAlt,
      if (guestCaller != null) 'guest_caller': guestCaller,
      if (plannedMinutes != null) 'planned_minutes': plannedMinutes,
      if (performedAt != null) 'performed_at': performedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramSlotsCompanion copyWith({
    Value<String>? id,
    Value<String>? programId,
    Value<int>? position,
    Value<String?>? danceId,
    Value<String?>? text_,
    Value<bool>? isAlt,
    Value<String?>? guestCaller,
    Value<int?>? plannedMinutes,
    Value<DateTime?>? performedAt,
    Value<int>? rowid,
  }) {
    return ProgramSlotsCompanion(
      id: id ?? this.id,
      programId: programId ?? this.programId,
      position: position ?? this.position,
      danceId: danceId ?? this.danceId,
      text_: text_ ?? this.text_,
      isAlt: isAlt ?? this.isAlt,
      guestCaller: guestCaller ?? this.guestCaller,
      plannedMinutes: plannedMinutes ?? this.plannedMinutes,
      performedAt: performedAt ?? this.performedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (programId.present) {
      map['program_id'] = Variable<String>(programId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (text_.present) {
      map['text'] = Variable<String>(text_.value);
    }
    if (isAlt.present) {
      map['is_alt'] = Variable<bool>(isAlt.value);
    }
    if (guestCaller.present) {
      map['guest_caller'] = Variable<String>(guestCaller.value);
    }
    if (plannedMinutes.present) {
      map['planned_minutes'] = Variable<int>(plannedMinutes.value);
    }
    if (performedAt.present) {
      map['performed_at'] = Variable<DateTime>(performedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramSlotsCompanion(')
          ..write('id: $id, ')
          ..write('programId: $programId, ')
          ..write('position: $position, ')
          ..write('danceId: $danceId, ')
          ..write('text_: $text_, ')
          ..write('isAlt: $isAlt, ')
          ..write('guestCaller: $guestCaller, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('performedAt: $performedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomFieldDefsTable extends CustomFieldDefs
    with TableInfo<$CustomFieldDefsTable, CustomFieldDefRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomFieldDefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CustomFieldType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CustomFieldType>($CustomFieldDefsTable.$convertertype);
  static const VerificationMeta _choicesJsonMeta = const VerificationMeta(
    'choicesJson',
  );
  @override
  late final GeneratedColumn<String> choicesJson = GeneratedColumn<String>(
    'choices_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _showInListMeta = const VerificationMeta(
    'showInList',
  );
  @override
  late final GeneratedColumn<bool> showInList = GeneratedColumn<bool>(
    'show_in_list',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_in_list" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _searchableMeta = const VerificationMeta(
    'searchable',
  );
  @override
  late final GeneratedColumn<bool> searchable = GeneratedColumn<bool>(
    'searchable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("searchable" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    key,
    label,
    type,
    choicesJson,
    showInList,
    searchable,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_field_defs';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomFieldDefRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('choices_json')) {
      context.handle(
        _choicesJsonMeta,
        choicesJson.isAcceptableOrUnknown(
          data['choices_json']!,
          _choicesJsonMeta,
        ),
      );
    }
    if (data.containsKey('show_in_list')) {
      context.handle(
        _showInListMeta,
        showInList.isAcceptableOrUnknown(
          data['show_in_list']!,
          _showInListMeta,
        ),
      );
    }
    if (data.containsKey('searchable')) {
      context.handle(
        _searchableMeta,
        searchable.isAcceptableOrUnknown(data['searchable']!, _searchableMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomFieldDefRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomFieldDefRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      type: $CustomFieldDefsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      choicesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}choices_json'],
      ),
      showInList: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_in_list'],
      )!,
      searchable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}searchable'],
      )!,
    );
  }

  @override
  $CustomFieldDefsTable createAlias(String alias) {
    return $CustomFieldDefsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<CustomFieldType, String, String> $convertertype =
      const EnumNameConverter(CustomFieldType.values);
}

class CustomFieldDefRow extends DataClass
    implements Insertable<CustomFieldDefRow> {
  final String id;
  final String key;
  final String label;
  final CustomFieldType type;

  /// JSON array of choice strings; only meaningful for `choice` fields.
  final String? choicesJson;
  final bool showInList;
  final bool searchable;
  const CustomFieldDefRow({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    this.choicesJson,
    required this.showInList,
    required this.searchable,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['key'] = Variable<String>(key);
    map['label'] = Variable<String>(label);
    {
      map['type'] = Variable<String>(
        $CustomFieldDefsTable.$convertertype.toSql(type),
      );
    }
    if (!nullToAbsent || choicesJson != null) {
      map['choices_json'] = Variable<String>(choicesJson);
    }
    map['show_in_list'] = Variable<bool>(showInList);
    map['searchable'] = Variable<bool>(searchable);
    return map;
  }

  CustomFieldDefsCompanion toCompanion(bool nullToAbsent) {
    return CustomFieldDefsCompanion(
      id: Value(id),
      key: Value(key),
      label: Value(label),
      type: Value(type),
      choicesJson: choicesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(choicesJson),
      showInList: Value(showInList),
      searchable: Value(searchable),
    );
  }

  factory CustomFieldDefRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomFieldDefRow(
      id: serializer.fromJson<String>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      label: serializer.fromJson<String>(json['label']),
      type: $CustomFieldDefsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      choicesJson: serializer.fromJson<String?>(json['choicesJson']),
      showInList: serializer.fromJson<bool>(json['showInList']),
      searchable: serializer.fromJson<bool>(json['searchable']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'key': serializer.toJson<String>(key),
      'label': serializer.toJson<String>(label),
      'type': serializer.toJson<String>(
        $CustomFieldDefsTable.$convertertype.toJson(type),
      ),
      'choicesJson': serializer.toJson<String?>(choicesJson),
      'showInList': serializer.toJson<bool>(showInList),
      'searchable': serializer.toJson<bool>(searchable),
    };
  }

  CustomFieldDefRow copyWith({
    String? id,
    String? key,
    String? label,
    CustomFieldType? type,
    Value<String?> choicesJson = const Value.absent(),
    bool? showInList,
    bool? searchable,
  }) => CustomFieldDefRow(
    id: id ?? this.id,
    key: key ?? this.key,
    label: label ?? this.label,
    type: type ?? this.type,
    choicesJson: choicesJson.present ? choicesJson.value : this.choicesJson,
    showInList: showInList ?? this.showInList,
    searchable: searchable ?? this.searchable,
  );
  CustomFieldDefRow copyWithCompanion(CustomFieldDefsCompanion data) {
    return CustomFieldDefRow(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      label: data.label.present ? data.label.value : this.label,
      type: data.type.present ? data.type.value : this.type,
      choicesJson: data.choicesJson.present
          ? data.choicesJson.value
          : this.choicesJson,
      showInList: data.showInList.present
          ? data.showInList.value
          : this.showInList,
      searchable: data.searchable.present
          ? data.searchable.value
          : this.searchable,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomFieldDefRow(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('label: $label, ')
          ..write('type: $type, ')
          ..write('choicesJson: $choicesJson, ')
          ..write('showInList: $showInList, ')
          ..write('searchable: $searchable')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, key, label, type, choicesJson, showInList, searchable);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomFieldDefRow &&
          other.id == this.id &&
          other.key == this.key &&
          other.label == this.label &&
          other.type == this.type &&
          other.choicesJson == this.choicesJson &&
          other.showInList == this.showInList &&
          other.searchable == this.searchable);
}

class CustomFieldDefsCompanion extends UpdateCompanion<CustomFieldDefRow> {
  final Value<String> id;
  final Value<String> key;
  final Value<String> label;
  final Value<CustomFieldType> type;
  final Value<String?> choicesJson;
  final Value<bool> showInList;
  final Value<bool> searchable;
  final Value<int> rowid;
  const CustomFieldDefsCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.label = const Value.absent(),
    this.type = const Value.absent(),
    this.choicesJson = const Value.absent(),
    this.showInList = const Value.absent(),
    this.searchable = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomFieldDefsCompanion.insert({
    required String id,
    required String key,
    required String label,
    required CustomFieldType type,
    this.choicesJson = const Value.absent(),
    this.showInList = const Value.absent(),
    this.searchable = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       key = Value(key),
       label = Value(label),
       type = Value(type);
  static Insertable<CustomFieldDefRow> custom({
    Expression<String>? id,
    Expression<String>? key,
    Expression<String>? label,
    Expression<String>? type,
    Expression<String>? choicesJson,
    Expression<bool>? showInList,
    Expression<bool>? searchable,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (label != null) 'label': label,
      if (type != null) 'type': type,
      if (choicesJson != null) 'choices_json': choicesJson,
      if (showInList != null) 'show_in_list': showInList,
      if (searchable != null) 'searchable': searchable,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomFieldDefsCompanion copyWith({
    Value<String>? id,
    Value<String>? key,
    Value<String>? label,
    Value<CustomFieldType>? type,
    Value<String?>? choicesJson,
    Value<bool>? showInList,
    Value<bool>? searchable,
    Value<int>? rowid,
  }) {
    return CustomFieldDefsCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      choicesJson: choicesJson ?? this.choicesJson,
      showInList: showInList ?? this.showInList,
      searchable: searchable ?? this.searchable,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $CustomFieldDefsTable.$convertertype.toSql(type.value),
      );
    }
    if (choicesJson.present) {
      map['choices_json'] = Variable<String>(choicesJson.value);
    }
    if (showInList.present) {
      map['show_in_list'] = Variable<bool>(showInList.value);
    }
    if (searchable.present) {
      map['searchable'] = Variable<bool>(searchable.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomFieldDefsCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('label: $label, ')
          ..write('type: $type, ')
          ..write('choicesJson: $choicesJson, ')
          ..write('showInList: $showInList, ')
          ..write('searchable: $searchable, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomFieldValuesTable extends CustomFieldValues
    with TableInfo<$CustomFieldValuesTable, CustomFieldValueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomFieldValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fieldIdMeta = const VerificationMeta(
    'fieldId',
  );
  @override
  late final GeneratedColumn<String> fieldId = GeneratedColumn<String>(
    'field_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES custom_field_defs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _valueTextMeta = const VerificationMeta(
    'valueText',
  );
  @override
  late final GeneratedColumn<String> valueText = GeneratedColumn<String>(
    'value_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueNumMeta = const VerificationMeta(
    'valueNum',
  );
  @override
  late final GeneratedColumn<double> valueNum = GeneratedColumn<double>(
    'value_num',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [danceId, fieldId, valueText, valueNum];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_field_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomFieldValueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_danceIdMeta);
    }
    if (data.containsKey('field_id')) {
      context.handle(
        _fieldIdMeta,
        fieldId.isAcceptableOrUnknown(data['field_id']!, _fieldIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldIdMeta);
    }
    if (data.containsKey('value_text')) {
      context.handle(
        _valueTextMeta,
        valueText.isAcceptableOrUnknown(data['value_text']!, _valueTextMeta),
      );
    }
    if (data.containsKey('value_num')) {
      context.handle(
        _valueNumMeta,
        valueNum.isAcceptableOrUnknown(data['value_num']!, _valueNumMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {danceId, fieldId};
  @override
  CustomFieldValueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomFieldValueRow(
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      )!,
      fieldId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_id'],
      )!,
      valueText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_text'],
      ),
      valueNum: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value_num'],
      ),
    );
  }

  @override
  $CustomFieldValuesTable createAlias(String alias) {
    return $CustomFieldValuesTable(attachedDatabase, alias);
  }
}

class CustomFieldValueRow extends DataClass
    implements Insertable<CustomFieldValueRow> {
  final String danceId;
  final String fieldId;
  final String? valueText;
  final double? valueNum;
  const CustomFieldValueRow({
    required this.danceId,
    required this.fieldId,
    this.valueText,
    this.valueNum,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dance_id'] = Variable<String>(danceId);
    map['field_id'] = Variable<String>(fieldId);
    if (!nullToAbsent || valueText != null) {
      map['value_text'] = Variable<String>(valueText);
    }
    if (!nullToAbsent || valueNum != null) {
      map['value_num'] = Variable<double>(valueNum);
    }
    return map;
  }

  CustomFieldValuesCompanion toCompanion(bool nullToAbsent) {
    return CustomFieldValuesCompanion(
      danceId: Value(danceId),
      fieldId: Value(fieldId),
      valueText: valueText == null && nullToAbsent
          ? const Value.absent()
          : Value(valueText),
      valueNum: valueNum == null && nullToAbsent
          ? const Value.absent()
          : Value(valueNum),
    );
  }

  factory CustomFieldValueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomFieldValueRow(
      danceId: serializer.fromJson<String>(json['danceId']),
      fieldId: serializer.fromJson<String>(json['fieldId']),
      valueText: serializer.fromJson<String?>(json['valueText']),
      valueNum: serializer.fromJson<double?>(json['valueNum']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'danceId': serializer.toJson<String>(danceId),
      'fieldId': serializer.toJson<String>(fieldId),
      'valueText': serializer.toJson<String?>(valueText),
      'valueNum': serializer.toJson<double?>(valueNum),
    };
  }

  CustomFieldValueRow copyWith({
    String? danceId,
    String? fieldId,
    Value<String?> valueText = const Value.absent(),
    Value<double?> valueNum = const Value.absent(),
  }) => CustomFieldValueRow(
    danceId: danceId ?? this.danceId,
    fieldId: fieldId ?? this.fieldId,
    valueText: valueText.present ? valueText.value : this.valueText,
    valueNum: valueNum.present ? valueNum.value : this.valueNum,
  );
  CustomFieldValueRow copyWithCompanion(CustomFieldValuesCompanion data) {
    return CustomFieldValueRow(
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      fieldId: data.fieldId.present ? data.fieldId.value : this.fieldId,
      valueText: data.valueText.present ? data.valueText.value : this.valueText,
      valueNum: data.valueNum.present ? data.valueNum.value : this.valueNum,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomFieldValueRow(')
          ..write('danceId: $danceId, ')
          ..write('fieldId: $fieldId, ')
          ..write('valueText: $valueText, ')
          ..write('valueNum: $valueNum')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(danceId, fieldId, valueText, valueNum);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomFieldValueRow &&
          other.danceId == this.danceId &&
          other.fieldId == this.fieldId &&
          other.valueText == this.valueText &&
          other.valueNum == this.valueNum);
}

class CustomFieldValuesCompanion extends UpdateCompanion<CustomFieldValueRow> {
  final Value<String> danceId;
  final Value<String> fieldId;
  final Value<String?> valueText;
  final Value<double?> valueNum;
  final Value<int> rowid;
  const CustomFieldValuesCompanion({
    this.danceId = const Value.absent(),
    this.fieldId = const Value.absent(),
    this.valueText = const Value.absent(),
    this.valueNum = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomFieldValuesCompanion.insert({
    required String danceId,
    required String fieldId,
    this.valueText = const Value.absent(),
    this.valueNum = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : danceId = Value(danceId),
       fieldId = Value(fieldId);
  static Insertable<CustomFieldValueRow> custom({
    Expression<String>? danceId,
    Expression<String>? fieldId,
    Expression<String>? valueText,
    Expression<double>? valueNum,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (danceId != null) 'dance_id': danceId,
      if (fieldId != null) 'field_id': fieldId,
      if (valueText != null) 'value_text': valueText,
      if (valueNum != null) 'value_num': valueNum,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomFieldValuesCompanion copyWith({
    Value<String>? danceId,
    Value<String>? fieldId,
    Value<String?>? valueText,
    Value<double?>? valueNum,
    Value<int>? rowid,
  }) {
    return CustomFieldValuesCompanion(
      danceId: danceId ?? this.danceId,
      fieldId: fieldId ?? this.fieldId,
      valueText: valueText ?? this.valueText,
      valueNum: valueNum ?? this.valueNum,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (fieldId.present) {
      map['field_id'] = Variable<String>(fieldId.value);
    }
    if (valueText.present) {
      map['value_text'] = Variable<String>(valueText.value);
    }
    if (valueNum.present) {
      map['value_num'] = Variable<double>(valueNum.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomFieldValuesCompanion(')
          ..write('danceId: $danceId, ')
          ..write('fieldId: $fieldId, ')
          ..write('valueText: $valueText, ')
          ..write('valueNum: $valueNum, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      ),
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRow extends DataClass implements Insertable<TagRow> {
  final String id;
  final String name;
  final int? color;
  const TagRow({required this.id, required this.name, this.color});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<int>(color);
    }
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int?>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int?>(color),
    };
  }

  TagRow copyWith({
    String? id,
    String? name,
    Value<int?> color = const Value.absent(),
  }) => TagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color.present ? color.value : this.color,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int?> color;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<TagRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int?>? color,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DanceTagsTable extends DanceTags
    with TableInfo<$DanceTagsTable, DanceTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DanceTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [danceId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dance_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<DanceTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_danceIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {danceId, tagId};
  @override
  DanceTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DanceTagRow(
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $DanceTagsTable createAlias(String alias) {
    return $DanceTagsTable(attachedDatabase, alias);
  }
}

class DanceTagRow extends DataClass implements Insertable<DanceTagRow> {
  final String danceId;
  final String tagId;
  const DanceTagRow({required this.danceId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dance_id'] = Variable<String>(danceId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  DanceTagsCompanion toCompanion(bool nullToAbsent) {
    return DanceTagsCompanion(danceId: Value(danceId), tagId: Value(tagId));
  }

  factory DanceTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DanceTagRow(
      danceId: serializer.fromJson<String>(json['danceId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'danceId': serializer.toJson<String>(danceId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  DanceTagRow copyWith({String? danceId, String? tagId}) =>
      DanceTagRow(danceId: danceId ?? this.danceId, tagId: tagId ?? this.tagId);
  DanceTagRow copyWithCompanion(DanceTagsCompanion data) {
    return DanceTagRow(
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DanceTagRow(')
          ..write('danceId: $danceId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(danceId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DanceTagRow &&
          other.danceId == this.danceId &&
          other.tagId == this.tagId);
}

class DanceTagsCompanion extends UpdateCompanion<DanceTagRow> {
  final Value<String> danceId;
  final Value<String> tagId;
  final Value<int> rowid;
  const DanceTagsCompanion({
    this.danceId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DanceTagsCompanion.insert({
    required String danceId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : danceId = Value(danceId),
       tagId = Value(tagId);
  static Insertable<DanceTagRow> custom({
    Expression<String>? danceId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (danceId != null) 'dance_id': danceId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DanceTagsCompanion copyWith({
    Value<String>? danceId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return DanceTagsCompanion(
      danceId: danceId ?? this.danceId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DanceTagsCompanion(')
          ..write('danceId: $danceId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DanceLinksTable extends DanceLinks
    with TableInfo<$DanceLinksTable, DanceLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DanceLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<LinkKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LinkKind>($DanceLinksTable.$converterkind);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetDanceIdMeta = const VerificationMeta(
    'targetDanceId',
  );
  @override
  late final GeneratedColumn<String> targetDanceId = GeneratedColumn<String>(
    'target_dance_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    danceId,
    kind,
    url,
    targetDanceId,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dance_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<DanceLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_danceIdMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('target_dance_id')) {
      context.handle(
        _targetDanceIdMeta,
        targetDanceId.isAcceptableOrUnknown(
          data['target_dance_id']!,
          _targetDanceIdMeta,
        ),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DanceLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DanceLinkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      )!,
      kind: $DanceLinksTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      targetDanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_dance_id'],
      ),
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
    );
  }

  @override
  $DanceLinksTable createAlias(String alias) {
    return $DanceLinksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<LinkKind, String, String> $converterkind =
      const EnumNameConverter(LinkKind.values);
}

class DanceLinkRow extends DataClass implements Insertable<DanceLinkRow> {
  final String id;
  final String danceId;
  final LinkKind kind;
  final String? url;
  final String? targetDanceId;
  final String? label;
  const DanceLinkRow({
    required this.id,
    required this.danceId,
    required this.kind,
    this.url,
    this.targetDanceId,
    this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['dance_id'] = Variable<String>(danceId);
    {
      map['kind'] = Variable<String>(
        $DanceLinksTable.$converterkind.toSql(kind),
      );
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || targetDanceId != null) {
      map['target_dance_id'] = Variable<String>(targetDanceId);
    }
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    return map;
  }

  DanceLinksCompanion toCompanion(bool nullToAbsent) {
    return DanceLinksCompanion(
      id: Value(id),
      danceId: Value(danceId),
      kind: Value(kind),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      targetDanceId: targetDanceId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDanceId),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
    );
  }

  factory DanceLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DanceLinkRow(
      id: serializer.fromJson<String>(json['id']),
      danceId: serializer.fromJson<String>(json['danceId']),
      kind: $DanceLinksTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      url: serializer.fromJson<String?>(json['url']),
      targetDanceId: serializer.fromJson<String?>(json['targetDanceId']),
      label: serializer.fromJson<String?>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'danceId': serializer.toJson<String>(danceId),
      'kind': serializer.toJson<String>(
        $DanceLinksTable.$converterkind.toJson(kind),
      ),
      'url': serializer.toJson<String?>(url),
      'targetDanceId': serializer.toJson<String?>(targetDanceId),
      'label': serializer.toJson<String?>(label),
    };
  }

  DanceLinkRow copyWith({
    String? id,
    String? danceId,
    LinkKind? kind,
    Value<String?> url = const Value.absent(),
    Value<String?> targetDanceId = const Value.absent(),
    Value<String?> label = const Value.absent(),
  }) => DanceLinkRow(
    id: id ?? this.id,
    danceId: danceId ?? this.danceId,
    kind: kind ?? this.kind,
    url: url.present ? url.value : this.url,
    targetDanceId: targetDanceId.present
        ? targetDanceId.value
        : this.targetDanceId,
    label: label.present ? label.value : this.label,
  );
  DanceLinkRow copyWithCompanion(DanceLinksCompanion data) {
    return DanceLinkRow(
      id: data.id.present ? data.id.value : this.id,
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      url: data.url.present ? data.url.value : this.url,
      targetDanceId: data.targetDanceId.present
          ? data.targetDanceId.value
          : this.targetDanceId,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DanceLinkRow(')
          ..write('id: $id, ')
          ..write('danceId: $danceId, ')
          ..write('kind: $kind, ')
          ..write('url: $url, ')
          ..write('targetDanceId: $targetDanceId, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, danceId, kind, url, targetDanceId, label);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DanceLinkRow &&
          other.id == this.id &&
          other.danceId == this.danceId &&
          other.kind == this.kind &&
          other.url == this.url &&
          other.targetDanceId == this.targetDanceId &&
          other.label == this.label);
}

class DanceLinksCompanion extends UpdateCompanion<DanceLinkRow> {
  final Value<String> id;
  final Value<String> danceId;
  final Value<LinkKind> kind;
  final Value<String?> url;
  final Value<String?> targetDanceId;
  final Value<String?> label;
  final Value<int> rowid;
  const DanceLinksCompanion({
    this.id = const Value.absent(),
    this.danceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.url = const Value.absent(),
    this.targetDanceId = const Value.absent(),
    this.label = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DanceLinksCompanion.insert({
    required String id,
    required String danceId,
    required LinkKind kind,
    this.url = const Value.absent(),
    this.targetDanceId = const Value.absent(),
    this.label = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       danceId = Value(danceId),
       kind = Value(kind);
  static Insertable<DanceLinkRow> custom({
    Expression<String>? id,
    Expression<String>? danceId,
    Expression<String>? kind,
    Expression<String>? url,
    Expression<String>? targetDanceId,
    Expression<String>? label,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (danceId != null) 'dance_id': danceId,
      if (kind != null) 'kind': kind,
      if (url != null) 'url': url,
      if (targetDanceId != null) 'target_dance_id': targetDanceId,
      if (label != null) 'label': label,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DanceLinksCompanion copyWith({
    Value<String>? id,
    Value<String>? danceId,
    Value<LinkKind>? kind,
    Value<String?>? url,
    Value<String?>? targetDanceId,
    Value<String?>? label,
    Value<int>? rowid,
  }) {
    return DanceLinksCompanion(
      id: id ?? this.id,
      danceId: danceId ?? this.danceId,
      kind: kind ?? this.kind,
      url: url ?? this.url,
      targetDanceId: targetDanceId ?? this.targetDanceId,
      label: label ?? this.label,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $DanceLinksTable.$converterkind.toSql(kind.value),
      );
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (targetDanceId.present) {
      map['target_dance_id'] = Variable<String>(targetDanceId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DanceLinksCompanion(')
          ..write('id: $id, ')
          ..write('danceId: $danceId, ')
          ..write('kind: $kind, ')
          ..write('url: $url, ')
          ..write('targetDanceId: $targetDanceId, ')
          ..write('label: $label, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProvenanceTable extends Provenance
    with TableInfo<$ProvenanceTable, ProvenanceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProvenanceTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _danceIdMeta = const VerificationMeta(
    'danceId',
  );
  @override
  late final GeneratedColumn<String> danceId = GeneratedColumn<String>(
    'dance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dances (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ProvenanceSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ProvenanceSource>($ProvenanceTable.$convertersource);
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _permissionMeta = const VerificationMeta(
    'permission',
  );
  @override
  late final GeneratedColumn<String> permission = GeneratedColumn<String>(
    'permission',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _licenseMeta = const VerificationMeta(
    'license',
  );
  @override
  late final GeneratedColumn<String> license = GeneratedColumn<String>(
    'license',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawPayloadMeta = const VerificationMeta(
    'rawPayload',
  );
  @override
  late final GeneratedColumn<String> rawPayload = GeneratedColumn<String>(
    'raw_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceVersionMeta = const VerificationMeta(
    'sourceVersion',
  );
  @override
  late final GeneratedColumn<String> sourceVersion = GeneratedColumn<String>(
    'source_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    danceId,
    source,
    externalId,
    importedAt,
    permission,
    license,
    rawPayload,
    sourceVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provenance';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProvenanceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dance_id')) {
      context.handle(
        _danceIdMeta,
        danceId.isAcceptableOrUnknown(data['dance_id']!, _danceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_danceIdMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('permission')) {
      context.handle(
        _permissionMeta,
        permission.isAcceptableOrUnknown(data['permission']!, _permissionMeta),
      );
    }
    if (data.containsKey('license')) {
      context.handle(
        _licenseMeta,
        license.isAcceptableOrUnknown(data['license']!, _licenseMeta),
      );
    }
    if (data.containsKey('raw_payload')) {
      context.handle(
        _rawPayloadMeta,
        rawPayload.isAcceptableOrUnknown(data['raw_payload']!, _rawPayloadMeta),
      );
    }
    if (data.containsKey('source_version')) {
      context.handle(
        _sourceVersionMeta,
        sourceVersion.isAcceptableOrUnknown(
          data['source_version']!,
          _sourceVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {danceId};
  @override
  ProvenanceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProvenanceRow(
      danceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dance_id'],
      )!,
      source: $ProvenanceTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
      permission: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permission'],
      ),
      license: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license'],
      ),
      rawPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_payload'],
      ),
      sourceVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_version'],
      ),
    );
  }

  @override
  $ProvenanceTable createAlias(String alias) {
    return $ProvenanceTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ProvenanceSource, String, String> $convertersource =
      const EnumNameConverter(ProvenanceSource.values);
}

class ProvenanceRow extends DataClass implements Insertable<ProvenanceRow> {
  final String danceId;
  final ProvenanceSource source;
  final String? externalId;
  final DateTime importedAt;
  final String? permission;
  final String? license;
  final String? rawPayload;
  final String? sourceVersion;
  const ProvenanceRow({
    required this.danceId,
    required this.source,
    this.externalId,
    required this.importedAt,
    this.permission,
    this.license,
    this.rawPayload,
    this.sourceVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dance_id'] = Variable<String>(danceId);
    {
      map['source'] = Variable<String>(
        $ProvenanceTable.$convertersource.toSql(source),
      );
    }
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    map['imported_at'] = Variable<DateTime>(importedAt);
    if (!nullToAbsent || permission != null) {
      map['permission'] = Variable<String>(permission);
    }
    if (!nullToAbsent || license != null) {
      map['license'] = Variable<String>(license);
    }
    if (!nullToAbsent || rawPayload != null) {
      map['raw_payload'] = Variable<String>(rawPayload);
    }
    if (!nullToAbsent || sourceVersion != null) {
      map['source_version'] = Variable<String>(sourceVersion);
    }
    return map;
  }

  ProvenanceCompanion toCompanion(bool nullToAbsent) {
    return ProvenanceCompanion(
      danceId: Value(danceId),
      source: Value(source),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      importedAt: Value(importedAt),
      permission: permission == null && nullToAbsent
          ? const Value.absent()
          : Value(permission),
      license: license == null && nullToAbsent
          ? const Value.absent()
          : Value(license),
      rawPayload: rawPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(rawPayload),
      sourceVersion: sourceVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceVersion),
    );
  }

  factory ProvenanceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProvenanceRow(
      danceId: serializer.fromJson<String>(json['danceId']),
      source: $ProvenanceTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      externalId: serializer.fromJson<String?>(json['externalId']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
      permission: serializer.fromJson<String?>(json['permission']),
      license: serializer.fromJson<String?>(json['license']),
      rawPayload: serializer.fromJson<String?>(json['rawPayload']),
      sourceVersion: serializer.fromJson<String?>(json['sourceVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'danceId': serializer.toJson<String>(danceId),
      'source': serializer.toJson<String>(
        $ProvenanceTable.$convertersource.toJson(source),
      ),
      'externalId': serializer.toJson<String?>(externalId),
      'importedAt': serializer.toJson<DateTime>(importedAt),
      'permission': serializer.toJson<String?>(permission),
      'license': serializer.toJson<String?>(license),
      'rawPayload': serializer.toJson<String?>(rawPayload),
      'sourceVersion': serializer.toJson<String?>(sourceVersion),
    };
  }

  ProvenanceRow copyWith({
    String? danceId,
    ProvenanceSource? source,
    Value<String?> externalId = const Value.absent(),
    DateTime? importedAt,
    Value<String?> permission = const Value.absent(),
    Value<String?> license = const Value.absent(),
    Value<String?> rawPayload = const Value.absent(),
    Value<String?> sourceVersion = const Value.absent(),
  }) => ProvenanceRow(
    danceId: danceId ?? this.danceId,
    source: source ?? this.source,
    externalId: externalId.present ? externalId.value : this.externalId,
    importedAt: importedAt ?? this.importedAt,
    permission: permission.present ? permission.value : this.permission,
    license: license.present ? license.value : this.license,
    rawPayload: rawPayload.present ? rawPayload.value : this.rawPayload,
    sourceVersion: sourceVersion.present
        ? sourceVersion.value
        : this.sourceVersion,
  );
  ProvenanceRow copyWithCompanion(ProvenanceCompanion data) {
    return ProvenanceRow(
      danceId: data.danceId.present ? data.danceId.value : this.danceId,
      source: data.source.present ? data.source.value : this.source,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      permission: data.permission.present
          ? data.permission.value
          : this.permission,
      license: data.license.present ? data.license.value : this.license,
      rawPayload: data.rawPayload.present
          ? data.rawPayload.value
          : this.rawPayload,
      sourceVersion: data.sourceVersion.present
          ? data.sourceVersion.value
          : this.sourceVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProvenanceRow(')
          ..write('danceId: $danceId, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('importedAt: $importedAt, ')
          ..write('permission: $permission, ')
          ..write('license: $license, ')
          ..write('rawPayload: $rawPayload, ')
          ..write('sourceVersion: $sourceVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    danceId,
    source,
    externalId,
    importedAt,
    permission,
    license,
    rawPayload,
    sourceVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProvenanceRow &&
          other.danceId == this.danceId &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.importedAt == this.importedAt &&
          other.permission == this.permission &&
          other.license == this.license &&
          other.rawPayload == this.rawPayload &&
          other.sourceVersion == this.sourceVersion);
}

class ProvenanceCompanion extends UpdateCompanion<ProvenanceRow> {
  final Value<String> danceId;
  final Value<ProvenanceSource> source;
  final Value<String?> externalId;
  final Value<DateTime> importedAt;
  final Value<String?> permission;
  final Value<String?> license;
  final Value<String?> rawPayload;
  final Value<String?> sourceVersion;
  final Value<int> rowid;
  const ProvenanceCompanion({
    this.danceId = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.permission = const Value.absent(),
    this.license = const Value.absent(),
    this.rawPayload = const Value.absent(),
    this.sourceVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProvenanceCompanion.insert({
    required String danceId,
    required ProvenanceSource source,
    this.externalId = const Value.absent(),
    required DateTime importedAt,
    this.permission = const Value.absent(),
    this.license = const Value.absent(),
    this.rawPayload = const Value.absent(),
    this.sourceVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : danceId = Value(danceId),
       source = Value(source),
       importedAt = Value(importedAt);
  static Insertable<ProvenanceRow> custom({
    Expression<String>? danceId,
    Expression<String>? source,
    Expression<String>? externalId,
    Expression<DateTime>? importedAt,
    Expression<String>? permission,
    Expression<String>? license,
    Expression<String>? rawPayload,
    Expression<String>? sourceVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (danceId != null) 'dance_id': danceId,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (importedAt != null) 'imported_at': importedAt,
      if (permission != null) 'permission': permission,
      if (license != null) 'license': license,
      if (rawPayload != null) 'raw_payload': rawPayload,
      if (sourceVersion != null) 'source_version': sourceVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProvenanceCompanion copyWith({
    Value<String>? danceId,
    Value<ProvenanceSource>? source,
    Value<String?>? externalId,
    Value<DateTime>? importedAt,
    Value<String?>? permission,
    Value<String?>? license,
    Value<String?>? rawPayload,
    Value<String?>? sourceVersion,
    Value<int>? rowid,
  }) {
    return ProvenanceCompanion(
      danceId: danceId ?? this.danceId,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      importedAt: importedAt ?? this.importedAt,
      permission: permission ?? this.permission,
      license: license ?? this.license,
      rawPayload: rawPayload ?? this.rawPayload,
      sourceVersion: sourceVersion ?? this.sourceVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (danceId.present) {
      map['dance_id'] = Variable<String>(danceId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $ProvenanceTable.$convertersource.toSql(source.value),
      );
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (permission.present) {
      map['permission'] = Variable<String>(permission.value);
    }
    if (license.present) {
      map['license'] = Variable<String>(license.value);
    }
    if (rawPayload.present) {
      map['raw_payload'] = Variable<String>(rawPayload.value);
    }
    if (sourceVersion.present) {
      map['source_version'] = Variable<String>(sourceVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProvenanceCompanion(')
          ..write('danceId: $danceId, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('importedAt: $importedAt, ')
          ..write('permission: $permission, ')
          ..write('license: $license, ')
          ..write('rawPayload: $rawPayload, ')
          ..write('sourceVersion: $sourceVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String valueJson;
  const SettingRow({required this.key, required this.valueJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), valueJson: Value(valueJson));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
    };
  }

  SettingRow copyWith({String? key, String? valueJson}) =>
      SettingRow(key: key ?? this.key, valueJson: valueJson ?? this.valueJson);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.valueJson == this.valueJson);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String valueJson,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnapshotsTable extends Snapshots
    with TableInfo<$SnapshotsTable, SnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotDateMeta = const VerificationMeta(
    'snapshotDate',
  );
  @override
  late final GeneratedColumn<DateTime> snapshotDate = GeneratedColumn<DateTime>(
    'snapshot_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifest_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    snapshotDate,
    manifestJson,
    importedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('snapshot_date')) {
      context.handle(
        _snapshotDateMeta,
        snapshotDate.isAcceptableOrUnknown(
          data['snapshot_date']!,
          _snapshotDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotDateMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifest_json']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source};
  @override
  SnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotRow(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      snapshotDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}snapshot_date'],
      )!,
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_json'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
    );
  }

  @override
  $SnapshotsTable createAlias(String alias) {
    return $SnapshotsTable(attachedDatabase, alias);
  }
}

class SnapshotRow extends DataClass implements Insertable<SnapshotRow> {
  final String source;
  final DateTime snapshotDate;
  final String manifestJson;
  final DateTime importedAt;
  const SnapshotRow({
    required this.source,
    required this.snapshotDate,
    required this.manifestJson,
    required this.importedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    map['snapshot_date'] = Variable<DateTime>(snapshotDate);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['imported_at'] = Variable<DateTime>(importedAt);
    return map;
  }

  SnapshotsCompanion toCompanion(bool nullToAbsent) {
    return SnapshotsCompanion(
      source: Value(source),
      snapshotDate: Value(snapshotDate),
      manifestJson: Value(manifestJson),
      importedAt: Value(importedAt),
    );
  }

  factory SnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotRow(
      source: serializer.fromJson<String>(json['source']),
      snapshotDate: serializer.fromJson<DateTime>(json['snapshotDate']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'snapshotDate': serializer.toJson<DateTime>(snapshotDate),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'importedAt': serializer.toJson<DateTime>(importedAt),
    };
  }

  SnapshotRow copyWith({
    String? source,
    DateTime? snapshotDate,
    String? manifestJson,
    DateTime? importedAt,
  }) => SnapshotRow(
    source: source ?? this.source,
    snapshotDate: snapshotDate ?? this.snapshotDate,
    manifestJson: manifestJson ?? this.manifestJson,
    importedAt: importedAt ?? this.importedAt,
  );
  SnapshotRow copyWithCompanion(SnapshotsCompanion data) {
    return SnapshotRow(
      source: data.source.present ? data.source.value : this.source,
      snapshotDate: data.snapshotDate.present
          ? data.snapshotDate.value
          : this.snapshotDate,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotRow(')
          ..write('source: $source, ')
          ..write('snapshotDate: $snapshotDate, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('importedAt: $importedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(source, snapshotDate, manifestJson, importedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotRow &&
          other.source == this.source &&
          other.snapshotDate == this.snapshotDate &&
          other.manifestJson == this.manifestJson &&
          other.importedAt == this.importedAt);
}

class SnapshotsCompanion extends UpdateCompanion<SnapshotRow> {
  final Value<String> source;
  final Value<DateTime> snapshotDate;
  final Value<String> manifestJson;
  final Value<DateTime> importedAt;
  final Value<int> rowid;
  const SnapshotsCompanion({
    this.source = const Value.absent(),
    this.snapshotDate = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotsCompanion.insert({
    required String source,
    required DateTime snapshotDate,
    required String manifestJson,
    required DateTime importedAt,
    this.rowid = const Value.absent(),
  }) : source = Value(source),
       snapshotDate = Value(snapshotDate),
       manifestJson = Value(manifestJson),
       importedAt = Value(importedAt);
  static Insertable<SnapshotRow> custom({
    Expression<String>? source,
    Expression<DateTime>? snapshotDate,
    Expression<String>? manifestJson,
    Expression<DateTime>? importedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (snapshotDate != null) 'snapshot_date': snapshotDate,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (importedAt != null) 'imported_at': importedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotsCompanion copyWith({
    Value<String>? source,
    Value<DateTime>? snapshotDate,
    Value<String>? manifestJson,
    Value<DateTime>? importedAt,
    Value<int>? rowid,
  }) {
    return SnapshotsCompanion(
      source: source ?? this.source,
      snapshotDate: snapshotDate ?? this.snapshotDate,
      manifestJson: manifestJson ?? this.manifestJson,
      importedAt: importedAt ?? this.importedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (snapshotDate.present) {
      map['snapshot_date'] = Variable<DateTime>(snapshotDate.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotsCompanion(')
          ..write('source: $source, ')
          ..write('snapshotDate: $snapshotDate, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('importedAt: $importedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CompendiumDatabase extends GeneratedDatabase {
  _$CompendiumDatabase(QueryExecutor e) : super(e);
  $CompendiumDatabaseManager get managers => $CompendiumDatabaseManager(this);
  late final $DancesTable dances = $DancesTable(this);
  late final $ChoreographersTable choreographers = $ChoreographersTable(this);
  late final $DanceAuthorsTable danceAuthors = $DanceAuthorsTable(this);
  late final $DanceFiguresTable danceFigures = $DanceFiguresTable(this);
  late final $ProgramsTable programs = $ProgramsTable(this);
  late final $ProgramSlotsTable programSlots = $ProgramSlotsTable(this);
  late final $CustomFieldDefsTable customFieldDefs = $CustomFieldDefsTable(
    this,
  );
  late final $CustomFieldValuesTable customFieldValues =
      $CustomFieldValuesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $DanceTagsTable danceTags = $DanceTagsTable(this);
  late final $DanceLinksTable danceLinks = $DanceLinksTable(this);
  late final $ProvenanceTable provenance = $ProvenanceTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $SnapshotsTable snapshots = $SnapshotsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dances,
    choreographers,
    danceAuthors,
    danceFigures,
    programs,
    programSlots,
    customFieldDefs,
    customFieldValues,
    tags,
    danceTags,
    danceLinks,
    provenance,
    settings,
    snapshots,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_authors', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'choreographers',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_authors', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_figures', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'programs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('program_slots', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('program_slots', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('custom_field_values', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'custom_field_defs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('custom_field_values', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_links', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dance_links', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('provenance', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$DancesTableCreateCompanionBuilder =
    DancesCompanion Function({
      required String id,
      required String title,
      required DanceForm form,
      required FormationShape formationShape,
      Value<String?> formationDetail,
      required Progression progression,
      Value<String> phraseStructure,
      Value<String> figuresJson,
      Value<String> hook,
      Value<String> callingNotes,
      required DanceStatus status,
      Value<DanceLevel?> level,
      Value<bool> mixedLevel,
      Value<String> tunesJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$DancesTableUpdateCompanionBuilder =
    DancesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<DanceForm> form,
      Value<FormationShape> formationShape,
      Value<String?> formationDetail,
      Value<Progression> progression,
      Value<String> phraseStructure,
      Value<String> figuresJson,
      Value<String> hook,
      Value<String> callingNotes,
      Value<DanceStatus> status,
      Value<DanceLevel?> level,
      Value<bool> mixedLevel,
      Value<String> tunesJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$DancesTableReferences
    extends BaseReferences<_$CompendiumDatabase, $DancesTable, DanceRow> {
  $$DancesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DanceAuthorsTable, List<DanceAuthorRow>>
  _danceAuthorsRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.danceAuthors,
        aliasName: 'dances__id__dance_authors__dance_id',
      );

  $$DanceAuthorsTableProcessedTableManager get danceAuthorsRefs {
    final manager = $$DanceAuthorsTableTableManager(
      $_db,
      $_db.danceAuthors,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_danceAuthorsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DanceFiguresTable, List<DanceFigureRow>>
  _danceFiguresRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.danceFigures,
        aliasName: 'dances__id__dance_figures__dance_id',
      );

  $$DanceFiguresTableProcessedTableManager get danceFiguresRefs {
    final manager = $$DanceFiguresTableTableManager(
      $_db,
      $_db.danceFigures,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_danceFiguresRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProgramSlotsTable, List<ProgramSlotRow>>
  _programSlotsRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.programSlots,
        aliasName: 'dances__id__program_slots__dance_id',
      );

  $$ProgramSlotsTableProcessedTableManager get programSlotsRefs {
    final manager = $$ProgramSlotsTableTableManager(
      $_db,
      $_db.programSlots,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_programSlotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CustomFieldValuesTable, List<CustomFieldValueRow>>
  _customFieldValuesRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.customFieldValues,
        aliasName: 'dances__id__custom_field_values__dance_id',
      );

  $$CustomFieldValuesTableProcessedTableManager get customFieldValuesRefs {
    final manager = $$CustomFieldValuesTableTableManager(
      $_db,
      $_db.customFieldValues,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _customFieldValuesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DanceTagsTable, List<DanceTagRow>>
  _danceTagsRefsTable(_$CompendiumDatabase db) => MultiTypedResultKey.fromTable(
    db.danceTags,
    aliasName: 'dances__id__dance_tags__dance_id',
  );

  $$DanceTagsTableProcessedTableManager get danceTagsRefs {
    final manager = $$DanceTagsTableTableManager(
      $_db,
      $_db.danceTags,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_danceTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DanceLinksTable, List<DanceLinkRow>>
  _danceLinksRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.danceLinks,
        aliasName: 'dances__id__dance_links__dance_id',
      );

  $$DanceLinksTableProcessedTableManager get danceLinksRefs {
    final manager = $$DanceLinksTableTableManager(
      $_db,
      $_db.danceLinks,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_danceLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DanceLinksTable, List<DanceLinkRow>>
  _relatedDanceLinksTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.danceLinks,
        aliasName: 'dances__id__dance_links__target_dance_id',
      );

  $$DanceLinksTableProcessedTableManager get relatedDanceLinks {
    final manager = $$DanceLinksTableTableManager(
      $_db,
      $_db.danceLinks,
    ).filter((f) => f.targetDanceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_relatedDanceLinksTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProvenanceTable, List<ProvenanceRow>>
  _provenanceRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.provenance,
        aliasName: 'dances__id__provenance__dance_id',
      );

  $$ProvenanceTableProcessedTableManager get provenanceRefs {
    final manager = $$ProvenanceTableTableManager(
      $_db,
      $_db.provenance,
    ).filter((f) => f.danceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_provenanceRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DancesTableFilterComposer
    extends Composer<_$CompendiumDatabase, $DancesTable> {
  $$DancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DanceForm, DanceForm, String> get form =>
      $composableBuilder(
        column: $table.form,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<FormationShape, FormationShape, String>
  get formationShape => $composableBuilder(
    column: $table.formationShape,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get formationDetail => $composableBuilder(
    column: $table.formationDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Progression, Progression, String>
  get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get phraseStructure => $composableBuilder(
    column: $table.phraseStructure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get figuresJson => $composableBuilder(
    column: $table.figuresJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hook => $composableBuilder(
    column: $table.hook,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get callingNotes => $composableBuilder(
    column: $table.callingNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DanceStatus, DanceStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DanceLevel?, DanceLevel, String> get level =>
      $composableBuilder(
        column: $table.level,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get mixedLevel => $composableBuilder(
    column: $table.mixedLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tunesJson => $composableBuilder(
    column: $table.tunesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> danceAuthorsRefs(
    Expression<bool> Function($$DanceAuthorsTableFilterComposer f) f,
  ) {
    final $$DanceAuthorsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceAuthors,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceAuthorsTableFilterComposer(
            $db: $db,
            $table: $db.danceAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> danceFiguresRefs(
    Expression<bool> Function($$DanceFiguresTableFilterComposer f) f,
  ) {
    final $$DanceFiguresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceFigures,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceFiguresTableFilterComposer(
            $db: $db,
            $table: $db.danceFigures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> programSlotsRefs(
    Expression<bool> Function($$ProgramSlotsTableFilterComposer f) f,
  ) {
    final $$ProgramSlotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programSlots,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramSlotsTableFilterComposer(
            $db: $db,
            $table: $db.programSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> customFieldValuesRefs(
    Expression<bool> Function($$CustomFieldValuesTableFilterComposer f) f,
  ) {
    final $$CustomFieldValuesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customFieldValues,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomFieldValuesTableFilterComposer(
            $db: $db,
            $table: $db.customFieldValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> danceTagsRefs(
    Expression<bool> Function($$DanceTagsTableFilterComposer f) f,
  ) {
    final $$DanceTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceTags,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceTagsTableFilterComposer(
            $db: $db,
            $table: $db.danceTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> danceLinksRefs(
    Expression<bool> Function($$DanceLinksTableFilterComposer f) f,
  ) {
    final $$DanceLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceLinks,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceLinksTableFilterComposer(
            $db: $db,
            $table: $db.danceLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> relatedDanceLinks(
    Expression<bool> Function($$DanceLinksTableFilterComposer f) f,
  ) {
    final $$DanceLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceLinks,
      getReferencedColumn: (t) => t.targetDanceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceLinksTableFilterComposer(
            $db: $db,
            $table: $db.danceLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> provenanceRefs(
    Expression<bool> Function($$ProvenanceTableFilterComposer f) f,
  ) {
    final $$ProvenanceTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.provenance,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProvenanceTableFilterComposer(
            $db: $db,
            $table: $db.provenance,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DancesTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $DancesTable> {
  $$DancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get form => $composableBuilder(
    column: $table.form,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formationShape => $composableBuilder(
    column: $table.formationShape,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formationDetail => $composableBuilder(
    column: $table.formationDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phraseStructure => $composableBuilder(
    column: $table.phraseStructure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get figuresJson => $composableBuilder(
    column: $table.figuresJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hook => $composableBuilder(
    column: $table.hook,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get callingNotes => $composableBuilder(
    column: $table.callingNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mixedLevel => $composableBuilder(
    column: $table.mixedLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tunesJson => $composableBuilder(
    column: $table.tunesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DancesTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $DancesTable> {
  $$DancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DanceForm, String> get form =>
      $composableBuilder(column: $table.form, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FormationShape, String> get formationShape =>
      $composableBuilder(
        column: $table.formationShape,
        builder: (column) => column,
      );

  GeneratedColumn<String> get formationDetail => $composableBuilder(
    column: $table.formationDetail,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Progression, String> get progression =>
      $composableBuilder(
        column: $table.progression,
        builder: (column) => column,
      );

  GeneratedColumn<String> get phraseStructure => $composableBuilder(
    column: $table.phraseStructure,
    builder: (column) => column,
  );

  GeneratedColumn<String> get figuresJson => $composableBuilder(
    column: $table.figuresJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hook =>
      $composableBuilder(column: $table.hook, builder: (column) => column);

  GeneratedColumn<String> get callingNotes => $composableBuilder(
    column: $table.callingNotes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DanceStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DanceLevel?, String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<bool> get mixedLevel => $composableBuilder(
    column: $table.mixedLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tunesJson =>
      $composableBuilder(column: $table.tunesJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> danceAuthorsRefs<T extends Object>(
    Expression<T> Function($$DanceAuthorsTableAnnotationComposer a) f,
  ) {
    final $$DanceAuthorsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceAuthors,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceAuthorsTableAnnotationComposer(
            $db: $db,
            $table: $db.danceAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> danceFiguresRefs<T extends Object>(
    Expression<T> Function($$DanceFiguresTableAnnotationComposer a) f,
  ) {
    final $$DanceFiguresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceFigures,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceFiguresTableAnnotationComposer(
            $db: $db,
            $table: $db.danceFigures,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> programSlotsRefs<T extends Object>(
    Expression<T> Function($$ProgramSlotsTableAnnotationComposer a) f,
  ) {
    final $$ProgramSlotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programSlots,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramSlotsTableAnnotationComposer(
            $db: $db,
            $table: $db.programSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> customFieldValuesRefs<T extends Object>(
    Expression<T> Function($$CustomFieldValuesTableAnnotationComposer a) f,
  ) {
    final $$CustomFieldValuesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.customFieldValues,
          getReferencedColumn: (t) => t.danceId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CustomFieldValuesTableAnnotationComposer(
                $db: $db,
                $table: $db.customFieldValues,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> danceTagsRefs<T extends Object>(
    Expression<T> Function($$DanceTagsTableAnnotationComposer a) f,
  ) {
    final $$DanceTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceTags,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.danceTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> danceLinksRefs<T extends Object>(
    Expression<T> Function($$DanceLinksTableAnnotationComposer a) f,
  ) {
    final $$DanceLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceLinks,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.danceLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> relatedDanceLinks<T extends Object>(
    Expression<T> Function($$DanceLinksTableAnnotationComposer a) f,
  ) {
    final $$DanceLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceLinks,
      getReferencedColumn: (t) => t.targetDanceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.danceLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> provenanceRefs<T extends Object>(
    Expression<T> Function($$ProvenanceTableAnnotationComposer a) f,
  ) {
    final $$ProvenanceTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.provenance,
      getReferencedColumn: (t) => t.danceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProvenanceTableAnnotationComposer(
            $db: $db,
            $table: $db.provenance,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DancesTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $DancesTable,
          DanceRow,
          $$DancesTableFilterComposer,
          $$DancesTableOrderingComposer,
          $$DancesTableAnnotationComposer,
          $$DancesTableCreateCompanionBuilder,
          $$DancesTableUpdateCompanionBuilder,
          (DanceRow, $$DancesTableReferences),
          DanceRow,
          PrefetchHooks Function({
            bool danceAuthorsRefs,
            bool danceFiguresRefs,
            bool programSlotsRefs,
            bool customFieldValuesRefs,
            bool danceTagsRefs,
            bool danceLinksRefs,
            bool relatedDanceLinks,
            bool provenanceRefs,
          })
        > {
  $$DancesTableTableManager(_$CompendiumDatabase db, $DancesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DancesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DanceForm> form = const Value.absent(),
                Value<FormationShape> formationShape = const Value.absent(),
                Value<String?> formationDetail = const Value.absent(),
                Value<Progression> progression = const Value.absent(),
                Value<String> phraseStructure = const Value.absent(),
                Value<String> figuresJson = const Value.absent(),
                Value<String> hook = const Value.absent(),
                Value<String> callingNotes = const Value.absent(),
                Value<DanceStatus> status = const Value.absent(),
                Value<DanceLevel?> level = const Value.absent(),
                Value<bool> mixedLevel = const Value.absent(),
                Value<String> tunesJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DancesCompanion(
                id: id,
                title: title,
                form: form,
                formationShape: formationShape,
                formationDetail: formationDetail,
                progression: progression,
                phraseStructure: phraseStructure,
                figuresJson: figuresJson,
                hook: hook,
                callingNotes: callingNotes,
                status: status,
                level: level,
                mixedLevel: mixedLevel,
                tunesJson: tunesJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required DanceForm form,
                required FormationShape formationShape,
                Value<String?> formationDetail = const Value.absent(),
                required Progression progression,
                Value<String> phraseStructure = const Value.absent(),
                Value<String> figuresJson = const Value.absent(),
                Value<String> hook = const Value.absent(),
                Value<String> callingNotes = const Value.absent(),
                required DanceStatus status,
                Value<DanceLevel?> level = const Value.absent(),
                Value<bool> mixedLevel = const Value.absent(),
                Value<String> tunesJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DancesCompanion.insert(
                id: id,
                title: title,
                form: form,
                formationShape: formationShape,
                formationDetail: formationDetail,
                progression: progression,
                phraseStructure: phraseStructure,
                figuresJson: figuresJson,
                hook: hook,
                callingNotes: callingNotes,
                status: status,
                level: level,
                mixedLevel: mixedLevel,
                tunesJson: tunesJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$DancesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                danceAuthorsRefs = false,
                danceFiguresRefs = false,
                programSlotsRefs = false,
                customFieldValuesRefs = false,
                danceTagsRefs = false,
                danceLinksRefs = false,
                relatedDanceLinks = false,
                provenanceRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (danceAuthorsRefs) db.danceAuthors,
                    if (danceFiguresRefs) db.danceFigures,
                    if (programSlotsRefs) db.programSlots,
                    if (customFieldValuesRefs) db.customFieldValues,
                    if (danceTagsRefs) db.danceTags,
                    if (danceLinksRefs) db.danceLinks,
                    if (relatedDanceLinks) db.danceLinks,
                    if (provenanceRefs) db.provenance,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (danceAuthorsRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          DanceAuthorRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._danceAuthorsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).danceAuthorsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (danceFiguresRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          DanceFigureRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._danceFiguresRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).danceFiguresRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (programSlotsRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          ProgramSlotRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._programSlotsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).programSlotsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (customFieldValuesRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          CustomFieldValueRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._customFieldValuesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).customFieldValuesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (danceTagsRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          DanceTagRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._danceTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).danceTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (danceLinksRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          DanceLinkRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._danceLinksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).danceLinksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (relatedDanceLinks)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          DanceLinkRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._relatedDanceLinksTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).relatedDanceLinks,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.targetDanceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (provenanceRefs)
                        await $_getPrefetchedData<
                          DanceRow,
                          $DancesTable,
                          ProvenanceRow
                        >(
                          currentTable: table,
                          referencedTable: $$DancesTableReferences
                              ._provenanceRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DancesTableReferences(
                                db,
                                table,
                                p0,
                              ).provenanceRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.danceId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DancesTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $DancesTable,
      DanceRow,
      $$DancesTableFilterComposer,
      $$DancesTableOrderingComposer,
      $$DancesTableAnnotationComposer,
      $$DancesTableCreateCompanionBuilder,
      $$DancesTableUpdateCompanionBuilder,
      (DanceRow, $$DancesTableReferences),
      DanceRow,
      PrefetchHooks Function({
        bool danceAuthorsRefs,
        bool danceFiguresRefs,
        bool programSlotsRefs,
        bool customFieldValuesRefs,
        bool danceTagsRefs,
        bool danceLinksRefs,
        bool relatedDanceLinks,
        bool provenanceRefs,
      })
    >;
typedef $$ChoreographersTableCreateCompanionBuilder =
    ChoreographersCompanion Function({
      required String id,
      required String name,
      Value<String?> website,
      Value<String?> notes,
      Value<int> rowid,
    });
typedef $$ChoreographersTableUpdateCompanionBuilder =
    ChoreographersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> website,
      Value<String?> notes,
      Value<int> rowid,
    });

final class $$ChoreographersTableReferences
    extends
        BaseReferences<
          _$CompendiumDatabase,
          $ChoreographersTable,
          ChoreographerRow
        > {
  $$ChoreographersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$DanceAuthorsTable, List<DanceAuthorRow>>
  _danceAuthorsRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.danceAuthors,
        aliasName: 'choreographers__id__dance_authors__choreographer_id',
      );

  $$DanceAuthorsTableProcessedTableManager get danceAuthorsRefs {
    final manager = $$DanceAuthorsTableTableManager($_db, $_db.danceAuthors)
        .filter(
          (f) => f.choreographerId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(_danceAuthorsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChoreographersTableFilterComposer
    extends Composer<_$CompendiumDatabase, $ChoreographersTable> {
  $$ChoreographersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get website => $composableBuilder(
    column: $table.website,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> danceAuthorsRefs(
    Expression<bool> Function($$DanceAuthorsTableFilterComposer f) f,
  ) {
    final $$DanceAuthorsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceAuthors,
      getReferencedColumn: (t) => t.choreographerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceAuthorsTableFilterComposer(
            $db: $db,
            $table: $db.danceAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChoreographersTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $ChoreographersTable> {
  $$ChoreographersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get website => $composableBuilder(
    column: $table.website,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChoreographersTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $ChoreographersTable> {
  $$ChoreographersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get website =>
      $composableBuilder(column: $table.website, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  Expression<T> danceAuthorsRefs<T extends Object>(
    Expression<T> Function($$DanceAuthorsTableAnnotationComposer a) f,
  ) {
    final $$DanceAuthorsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceAuthors,
      getReferencedColumn: (t) => t.choreographerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceAuthorsTableAnnotationComposer(
            $db: $db,
            $table: $db.danceAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChoreographersTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $ChoreographersTable,
          ChoreographerRow,
          $$ChoreographersTableFilterComposer,
          $$ChoreographersTableOrderingComposer,
          $$ChoreographersTableAnnotationComposer,
          $$ChoreographersTableCreateCompanionBuilder,
          $$ChoreographersTableUpdateCompanionBuilder,
          (ChoreographerRow, $$ChoreographersTableReferences),
          ChoreographerRow,
          PrefetchHooks Function({bool danceAuthorsRefs})
        > {
  $$ChoreographersTableTableManager(
    _$CompendiumDatabase db,
    $ChoreographersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChoreographersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChoreographersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChoreographersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> website = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChoreographersCompanion(
                id: id,
                name: name,
                website: website,
                notes: notes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> website = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChoreographersCompanion.insert(
                id: id,
                name: name,
                website: website,
                notes: notes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChoreographersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceAuthorsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (danceAuthorsRefs) db.danceAuthors],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (danceAuthorsRefs)
                    await $_getPrefetchedData<
                      ChoreographerRow,
                      $ChoreographersTable,
                      DanceAuthorRow
                    >(
                      currentTable: table,
                      referencedTable: $$ChoreographersTableReferences
                          ._danceAuthorsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ChoreographersTableReferences(
                            db,
                            table,
                            p0,
                          ).danceAuthorsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.choreographerId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChoreographersTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $ChoreographersTable,
      ChoreographerRow,
      $$ChoreographersTableFilterComposer,
      $$ChoreographersTableOrderingComposer,
      $$ChoreographersTableAnnotationComposer,
      $$ChoreographersTableCreateCompanionBuilder,
      $$ChoreographersTableUpdateCompanionBuilder,
      (ChoreographerRow, $$ChoreographersTableReferences),
      ChoreographerRow,
      PrefetchHooks Function({bool danceAuthorsRefs})
    >;
typedef $$DanceAuthorsTableCreateCompanionBuilder =
    DanceAuthorsCompanion Function({
      required String danceId,
      required String choreographerId,
      required int position,
      Value<int> rowid,
    });
typedef $$DanceAuthorsTableUpdateCompanionBuilder =
    DanceAuthorsCompanion Function({
      Value<String> danceId,
      Value<String> choreographerId,
      Value<int> position,
      Value<int> rowid,
    });

final class $$DanceAuthorsTableReferences
    extends
        BaseReferences<
          _$CompendiumDatabase,
          $DanceAuthorsTable,
          DanceAuthorRow
        > {
  $$DanceAuthorsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('dance_authors__dance_id__dances__id');

  $$DancesTableProcessedTableManager get danceId {
    final $_column = $_itemColumn<String>('dance_id')!;

    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ChoreographersTable _choreographerIdTable(_$CompendiumDatabase db) =>
      db.choreographers.createAlias(
        'dance_authors__choreographer_id__choreographers__id',
      );

  $$ChoreographersTableProcessedTableManager get choreographerId {
    final $_column = $_itemColumn<String>('choreographer_id')!;

    final manager = $$ChoreographersTableTableManager(
      $_db,
      $_db.choreographers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_choreographerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DanceAuthorsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $DanceAuthorsTable> {
  $$DanceAuthorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ChoreographersTableFilterComposer get choreographerId {
    final $$ChoreographersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreographerId,
      referencedTable: $db.choreographers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreographersTableFilterComposer(
            $db: $db,
            $table: $db.choreographers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceAuthorsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $DanceAuthorsTable> {
  $$DanceAuthorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ChoreographersTableOrderingComposer get choreographerId {
    final $$ChoreographersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreographerId,
      referencedTable: $db.choreographers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreographersTableOrderingComposer(
            $db: $db,
            $table: $db.choreographers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceAuthorsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $DanceAuthorsTable> {
  $$DanceAuthorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ChoreographersTableAnnotationComposer get choreographerId {
    final $$ChoreographersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.choreographerId,
      referencedTable: $db.choreographers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChoreographersTableAnnotationComposer(
            $db: $db,
            $table: $db.choreographers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceAuthorsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $DanceAuthorsTable,
          DanceAuthorRow,
          $$DanceAuthorsTableFilterComposer,
          $$DanceAuthorsTableOrderingComposer,
          $$DanceAuthorsTableAnnotationComposer,
          $$DanceAuthorsTableCreateCompanionBuilder,
          $$DanceAuthorsTableUpdateCompanionBuilder,
          (DanceAuthorRow, $$DanceAuthorsTableReferences),
          DanceAuthorRow,
          PrefetchHooks Function({bool danceId, bool choreographerId})
        > {
  $$DanceAuthorsTableTableManager(
    _$CompendiumDatabase db,
    $DanceAuthorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DanceAuthorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DanceAuthorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DanceAuthorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> danceId = const Value.absent(),
                Value<String> choreographerId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanceAuthorsCompanion(
                danceId: danceId,
                choreographerId: choreographerId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String danceId,
                required String choreographerId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => DanceAuthorsCompanion.insert(
                danceId: danceId,
                choreographerId: choreographerId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DanceAuthorsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceId = false, choreographerId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable: $$DanceAuthorsTableReferences
                                    ._danceIdTable(db),
                                referencedColumn: $$DanceAuthorsTableReferences
                                    ._danceIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (choreographerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.choreographerId,
                                referencedTable: $$DanceAuthorsTableReferences
                                    ._choreographerIdTable(db),
                                referencedColumn: $$DanceAuthorsTableReferences
                                    ._choreographerIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DanceAuthorsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $DanceAuthorsTable,
      DanceAuthorRow,
      $$DanceAuthorsTableFilterComposer,
      $$DanceAuthorsTableOrderingComposer,
      $$DanceAuthorsTableAnnotationComposer,
      $$DanceAuthorsTableCreateCompanionBuilder,
      $$DanceAuthorsTableUpdateCompanionBuilder,
      (DanceAuthorRow, $$DanceAuthorsTableReferences),
      DanceAuthorRow,
      PrefetchHooks Function({bool danceId, bool choreographerId})
    >;
typedef $$DanceFiguresTableCreateCompanionBuilder =
    DanceFiguresCompanion Function({
      required String danceId,
      required int idx,
      required String move,
      Value<int> beats,
      Value<bool> progression,
      Value<String> paramsJson,
      Value<String> canonicalText,
      Value<String?> section,
      Value<int> rowid,
    });
typedef $$DanceFiguresTableUpdateCompanionBuilder =
    DanceFiguresCompanion Function({
      Value<String> danceId,
      Value<int> idx,
      Value<String> move,
      Value<int> beats,
      Value<bool> progression,
      Value<String> paramsJson,
      Value<String> canonicalText,
      Value<String?> section,
      Value<int> rowid,
    });

final class $$DanceFiguresTableReferences
    extends
        BaseReferences<
          _$CompendiumDatabase,
          $DanceFiguresTable,
          DanceFigureRow
        > {
  $$DanceFiguresTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('dance_figures__dance_id__dances__id');

  $$DancesTableProcessedTableManager get danceId {
    final $_column = $_itemColumn<String>('dance_id')!;

    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DanceFiguresTableFilterComposer
    extends Composer<_$CompendiumDatabase, $DanceFiguresTable> {
  $$DanceFiguresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get move => $composableBuilder(
    column: $table.move,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get beats => $composableBuilder(
    column: $table.beats,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paramsJson => $composableBuilder(
    column: $table.paramsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalText => $composableBuilder(
    column: $table.canonicalText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get section => $composableBuilder(
    column: $table.section,
    builder: (column) => ColumnFilters(column),
  );

  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceFiguresTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $DanceFiguresTable> {
  $$DanceFiguresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get idx => $composableBuilder(
    column: $table.idx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get move => $composableBuilder(
    column: $table.move,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get beats => $composableBuilder(
    column: $table.beats,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paramsJson => $composableBuilder(
    column: $table.paramsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalText => $composableBuilder(
    column: $table.canonicalText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get section => $composableBuilder(
    column: $table.section,
    builder: (column) => ColumnOrderings(column),
  );

  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceFiguresTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $DanceFiguresTable> {
  $$DanceFiguresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get idx =>
      $composableBuilder(column: $table.idx, builder: (column) => column);

  GeneratedColumn<String> get move =>
      $composableBuilder(column: $table.move, builder: (column) => column);

  GeneratedColumn<int> get beats =>
      $composableBuilder(column: $table.beats, builder: (column) => column);

  GeneratedColumn<bool> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paramsJson => $composableBuilder(
    column: $table.paramsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get canonicalText => $composableBuilder(
    column: $table.canonicalText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get section =>
      $composableBuilder(column: $table.section, builder: (column) => column);

  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceFiguresTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $DanceFiguresTable,
          DanceFigureRow,
          $$DanceFiguresTableFilterComposer,
          $$DanceFiguresTableOrderingComposer,
          $$DanceFiguresTableAnnotationComposer,
          $$DanceFiguresTableCreateCompanionBuilder,
          $$DanceFiguresTableUpdateCompanionBuilder,
          (DanceFigureRow, $$DanceFiguresTableReferences),
          DanceFigureRow,
          PrefetchHooks Function({bool danceId})
        > {
  $$DanceFiguresTableTableManager(
    _$CompendiumDatabase db,
    $DanceFiguresTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DanceFiguresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DanceFiguresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DanceFiguresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> danceId = const Value.absent(),
                Value<int> idx = const Value.absent(),
                Value<String> move = const Value.absent(),
                Value<int> beats = const Value.absent(),
                Value<bool> progression = const Value.absent(),
                Value<String> paramsJson = const Value.absent(),
                Value<String> canonicalText = const Value.absent(),
                Value<String?> section = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanceFiguresCompanion(
                danceId: danceId,
                idx: idx,
                move: move,
                beats: beats,
                progression: progression,
                paramsJson: paramsJson,
                canonicalText: canonicalText,
                section: section,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String danceId,
                required int idx,
                required String move,
                Value<int> beats = const Value.absent(),
                Value<bool> progression = const Value.absent(),
                Value<String> paramsJson = const Value.absent(),
                Value<String> canonicalText = const Value.absent(),
                Value<String?> section = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanceFiguresCompanion.insert(
                danceId: danceId,
                idx: idx,
                move: move,
                beats: beats,
                progression: progression,
                paramsJson: paramsJson,
                canonicalText: canonicalText,
                section: section,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DanceFiguresTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable: $$DanceFiguresTableReferences
                                    ._danceIdTable(db),
                                referencedColumn: $$DanceFiguresTableReferences
                                    ._danceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DanceFiguresTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $DanceFiguresTable,
      DanceFigureRow,
      $$DanceFiguresTableFilterComposer,
      $$DanceFiguresTableOrderingComposer,
      $$DanceFiguresTableAnnotationComposer,
      $$DanceFiguresTableCreateCompanionBuilder,
      $$DanceFiguresTableUpdateCompanionBuilder,
      (DanceFigureRow, $$DanceFiguresTableReferences),
      DanceFigureRow,
      PrefetchHooks Function({bool danceId})
    >;
typedef $$ProgramsTableCreateCompanionBuilder =
    ProgramsCompanion Function({
      required String id,
      required String title,
      Value<DateTime?> eventDate,
      Value<String?> venue,
      Value<String?> band,
      Value<String?> caller,
      Value<String?> dancerLevel,
      Value<String> notes,
      required ProgramStatus status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ProgramsTableUpdateCompanionBuilder =
    ProgramsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<DateTime?> eventDate,
      Value<String?> venue,
      Value<String?> band,
      Value<String?> caller,
      Value<String?> dancerLevel,
      Value<String> notes,
      Value<ProgramStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$ProgramsTableReferences
    extends BaseReferences<_$CompendiumDatabase, $ProgramsTable, ProgramRow> {
  $$ProgramsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProgramSlotsTable, List<ProgramSlotRow>>
  _programSlotsRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.programSlots,
        aliasName: 'programs__id__program_slots__program_id',
      );

  $$ProgramSlotsTableProcessedTableManager get programSlotsRefs {
    final manager = $$ProgramSlotsTableTableManager(
      $_db,
      $_db.programSlots,
    ).filter((f) => f.programId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_programSlotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProgramsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $ProgramsTable> {
  $$ProgramsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get eventDate => $composableBuilder(
    column: $table.eventDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get venue => $composableBuilder(
    column: $table.venue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get band => $composableBuilder(
    column: $table.band,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caller => $composableBuilder(
    column: $table.caller,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dancerLevel => $composableBuilder(
    column: $table.dancerLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ProgramStatus, ProgramStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> programSlotsRefs(
    Expression<bool> Function($$ProgramSlotsTableFilterComposer f) f,
  ) {
    final $$ProgramSlotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programSlots,
      getReferencedColumn: (t) => t.programId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramSlotsTableFilterComposer(
            $db: $db,
            $table: $db.programSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProgramsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $ProgramsTable> {
  $$ProgramsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get eventDate => $composableBuilder(
    column: $table.eventDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get venue => $composableBuilder(
    column: $table.venue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get band => $composableBuilder(
    column: $table.band,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caller => $composableBuilder(
    column: $table.caller,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dancerLevel => $composableBuilder(
    column: $table.dancerLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgramsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $ProgramsTable> {
  $$ProgramsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get eventDate =>
      $composableBuilder(column: $table.eventDate, builder: (column) => column);

  GeneratedColumn<String> get venue =>
      $composableBuilder(column: $table.venue, builder: (column) => column);

  GeneratedColumn<String> get band =>
      $composableBuilder(column: $table.band, builder: (column) => column);

  GeneratedColumn<String> get caller =>
      $composableBuilder(column: $table.caller, builder: (column) => column);

  GeneratedColumn<String> get dancerLevel => $composableBuilder(
    column: $table.dancerLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ProgramStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> programSlotsRefs<T extends Object>(
    Expression<T> Function($$ProgramSlotsTableAnnotationComposer a) f,
  ) {
    final $$ProgramSlotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programSlots,
      getReferencedColumn: (t) => t.programId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramSlotsTableAnnotationComposer(
            $db: $db,
            $table: $db.programSlots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProgramsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $ProgramsTable,
          ProgramRow,
          $$ProgramsTableFilterComposer,
          $$ProgramsTableOrderingComposer,
          $$ProgramsTableAnnotationComposer,
          $$ProgramsTableCreateCompanionBuilder,
          $$ProgramsTableUpdateCompanionBuilder,
          (ProgramRow, $$ProgramsTableReferences),
          ProgramRow,
          PrefetchHooks Function({bool programSlotsRefs})
        > {
  $$ProgramsTableTableManager(_$CompendiumDatabase db, $ProgramsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime?> eventDate = const Value.absent(),
                Value<String?> venue = const Value.absent(),
                Value<String?> band = const Value.absent(),
                Value<String?> caller = const Value.absent(),
                Value<String?> dancerLevel = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<ProgramStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramsCompanion(
                id: id,
                title: title,
                eventDate: eventDate,
                venue: venue,
                band: band,
                caller: caller,
                dancerLevel: dancerLevel,
                notes: notes,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<DateTime?> eventDate = const Value.absent(),
                Value<String?> venue = const Value.absent(),
                Value<String?> band = const Value.absent(),
                Value<String?> caller = const Value.absent(),
                Value<String?> dancerLevel = const Value.absent(),
                Value<String> notes = const Value.absent(),
                required ProgramStatus status,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramsCompanion.insert(
                id: id,
                title: title,
                eventDate: eventDate,
                venue: venue,
                band: band,
                caller: caller,
                dancerLevel: dancerLevel,
                notes: notes,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProgramsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({programSlotsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (programSlotsRefs) db.programSlots],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (programSlotsRefs)
                    await $_getPrefetchedData<
                      ProgramRow,
                      $ProgramsTable,
                      ProgramSlotRow
                    >(
                      currentTable: table,
                      referencedTable: $$ProgramsTableReferences
                          ._programSlotsRefsTable(db),
                      managerFromTypedResult: (p0) => $$ProgramsTableReferences(
                        db,
                        table,
                        p0,
                      ).programSlotsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.programId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ProgramsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $ProgramsTable,
      ProgramRow,
      $$ProgramsTableFilterComposer,
      $$ProgramsTableOrderingComposer,
      $$ProgramsTableAnnotationComposer,
      $$ProgramsTableCreateCompanionBuilder,
      $$ProgramsTableUpdateCompanionBuilder,
      (ProgramRow, $$ProgramsTableReferences),
      ProgramRow,
      PrefetchHooks Function({bool programSlotsRefs})
    >;
typedef $$ProgramSlotsTableCreateCompanionBuilder =
    ProgramSlotsCompanion Function({
      required String id,
      required String programId,
      required int position,
      Value<String?> danceId,
      Value<String?> text_,
      Value<bool> isAlt,
      Value<String?> guestCaller,
      Value<int?> plannedMinutes,
      Value<DateTime?> performedAt,
      Value<int> rowid,
    });
typedef $$ProgramSlotsTableUpdateCompanionBuilder =
    ProgramSlotsCompanion Function({
      Value<String> id,
      Value<String> programId,
      Value<int> position,
      Value<String?> danceId,
      Value<String?> text_,
      Value<bool> isAlt,
      Value<String?> guestCaller,
      Value<int?> plannedMinutes,
      Value<DateTime?> performedAt,
      Value<int> rowid,
    });

final class $$ProgramSlotsTableReferences
    extends
        BaseReferences<
          _$CompendiumDatabase,
          $ProgramSlotsTable,
          ProgramSlotRow
        > {
  $$ProgramSlotsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProgramsTable _programIdTable(_$CompendiumDatabase db) =>
      db.programs.createAlias('program_slots__program_id__programs__id');

  $$ProgramsTableProcessedTableManager get programId {
    final $_column = $_itemColumn<String>('program_id')!;

    final manager = $$ProgramsTableTableManager(
      $_db,
      $_db.programs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_programIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('program_slots__dance_id__dances__id');

  $$DancesTableProcessedTableManager? get danceId {
    final $_column = $_itemColumn<String>('dance_id');
    if ($_column == null) return null;
    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProgramSlotsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $ProgramSlotsTable> {
  $$ProgramSlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAlt => $composableBuilder(
    column: $table.isAlt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get guestCaller => $composableBuilder(
    column: $table.guestCaller,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get performedAt => $composableBuilder(
    column: $table.performedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProgramsTableFilterComposer get programId {
    final $$ProgramsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.programId,
      referencedTable: $db.programs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramsTableFilterComposer(
            $db: $db,
            $table: $db.programs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramSlotsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $ProgramSlotsTable> {
  $$ProgramSlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAlt => $composableBuilder(
    column: $table.isAlt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get guestCaller => $composableBuilder(
    column: $table.guestCaller,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get performedAt => $composableBuilder(
    column: $table.performedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProgramsTableOrderingComposer get programId {
    final $$ProgramsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.programId,
      referencedTable: $db.programs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramsTableOrderingComposer(
            $db: $db,
            $table: $db.programs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramSlotsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $ProgramSlotsTable> {
  $$ProgramSlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get text_ =>
      $composableBuilder(column: $table.text_, builder: (column) => column);

  GeneratedColumn<bool> get isAlt =>
      $composableBuilder(column: $table.isAlt, builder: (column) => column);

  GeneratedColumn<String> get guestCaller => $composableBuilder(
    column: $table.guestCaller,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get performedAt => $composableBuilder(
    column: $table.performedAt,
    builder: (column) => column,
  );

  $$ProgramsTableAnnotationComposer get programId {
    final $$ProgramsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.programId,
      referencedTable: $db.programs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramsTableAnnotationComposer(
            $db: $db,
            $table: $db.programs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramSlotsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $ProgramSlotsTable,
          ProgramSlotRow,
          $$ProgramSlotsTableFilterComposer,
          $$ProgramSlotsTableOrderingComposer,
          $$ProgramSlotsTableAnnotationComposer,
          $$ProgramSlotsTableCreateCompanionBuilder,
          $$ProgramSlotsTableUpdateCompanionBuilder,
          (ProgramSlotRow, $$ProgramSlotsTableReferences),
          ProgramSlotRow,
          PrefetchHooks Function({bool programId, bool danceId})
        > {
  $$ProgramSlotsTableTableManager(
    _$CompendiumDatabase db,
    $ProgramSlotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramSlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramSlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramSlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> programId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String?> danceId = const Value.absent(),
                Value<String?> text_ = const Value.absent(),
                Value<bool> isAlt = const Value.absent(),
                Value<String?> guestCaller = const Value.absent(),
                Value<int?> plannedMinutes = const Value.absent(),
                Value<DateTime?> performedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramSlotsCompanion(
                id: id,
                programId: programId,
                position: position,
                danceId: danceId,
                text_: text_,
                isAlt: isAlt,
                guestCaller: guestCaller,
                plannedMinutes: plannedMinutes,
                performedAt: performedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String programId,
                required int position,
                Value<String?> danceId = const Value.absent(),
                Value<String?> text_ = const Value.absent(),
                Value<bool> isAlt = const Value.absent(),
                Value<String?> guestCaller = const Value.absent(),
                Value<int?> plannedMinutes = const Value.absent(),
                Value<DateTime?> performedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramSlotsCompanion.insert(
                id: id,
                programId: programId,
                position: position,
                danceId: danceId,
                text_: text_,
                isAlt: isAlt,
                guestCaller: guestCaller,
                plannedMinutes: plannedMinutes,
                performedAt: performedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProgramSlotsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({programId = false, danceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (programId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.programId,
                                referencedTable: $$ProgramSlotsTableReferences
                                    ._programIdTable(db),
                                referencedColumn: $$ProgramSlotsTableReferences
                                    ._programIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable: $$ProgramSlotsTableReferences
                                    ._danceIdTable(db),
                                referencedColumn: $$ProgramSlotsTableReferences
                                    ._danceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProgramSlotsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $ProgramSlotsTable,
      ProgramSlotRow,
      $$ProgramSlotsTableFilterComposer,
      $$ProgramSlotsTableOrderingComposer,
      $$ProgramSlotsTableAnnotationComposer,
      $$ProgramSlotsTableCreateCompanionBuilder,
      $$ProgramSlotsTableUpdateCompanionBuilder,
      (ProgramSlotRow, $$ProgramSlotsTableReferences),
      ProgramSlotRow,
      PrefetchHooks Function({bool programId, bool danceId})
    >;
typedef $$CustomFieldDefsTableCreateCompanionBuilder =
    CustomFieldDefsCompanion Function({
      required String id,
      required String key,
      required String label,
      required CustomFieldType type,
      Value<String?> choicesJson,
      Value<bool> showInList,
      Value<bool> searchable,
      Value<int> rowid,
    });
typedef $$CustomFieldDefsTableUpdateCompanionBuilder =
    CustomFieldDefsCompanion Function({
      Value<String> id,
      Value<String> key,
      Value<String> label,
      Value<CustomFieldType> type,
      Value<String?> choicesJson,
      Value<bool> showInList,
      Value<bool> searchable,
      Value<int> rowid,
    });

final class $$CustomFieldDefsTableReferences
    extends
        BaseReferences<
          _$CompendiumDatabase,
          $CustomFieldDefsTable,
          CustomFieldDefRow
        > {
  $$CustomFieldDefsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$CustomFieldValuesTable, List<CustomFieldValueRow>>
  _customFieldValuesRefsTable(_$CompendiumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.customFieldValues,
        aliasName: 'custom_field_defs__id__custom_field_values__field_id',
      );

  $$CustomFieldValuesTableProcessedTableManager get customFieldValuesRefs {
    final manager = $$CustomFieldValuesTableTableManager(
      $_db,
      $_db.customFieldValues,
    ).filter((f) => f.fieldId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _customFieldValuesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CustomFieldDefsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $CustomFieldDefsTable> {
  $$CustomFieldDefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CustomFieldType, CustomFieldType, String>
  get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get choicesJson => $composableBuilder(
    column: $table.choicesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showInList => $composableBuilder(
    column: $table.showInList,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get searchable => $composableBuilder(
    column: $table.searchable,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> customFieldValuesRefs(
    Expression<bool> Function($$CustomFieldValuesTableFilterComposer f) f,
  ) {
    final $$CustomFieldValuesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customFieldValues,
      getReferencedColumn: (t) => t.fieldId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomFieldValuesTableFilterComposer(
            $db: $db,
            $table: $db.customFieldValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CustomFieldDefsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $CustomFieldDefsTable> {
  $$CustomFieldDefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get choicesJson => $composableBuilder(
    column: $table.choicesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showInList => $composableBuilder(
    column: $table.showInList,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get searchable => $composableBuilder(
    column: $table.searchable,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomFieldDefsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $CustomFieldDefsTable> {
  $$CustomFieldDefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CustomFieldType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get choicesJson => $composableBuilder(
    column: $table.choicesJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showInList => $composableBuilder(
    column: $table.showInList,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get searchable => $composableBuilder(
    column: $table.searchable,
    builder: (column) => column,
  );

  Expression<T> customFieldValuesRefs<T extends Object>(
    Expression<T> Function($$CustomFieldValuesTableAnnotationComposer a) f,
  ) {
    final $$CustomFieldValuesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.customFieldValues,
          getReferencedColumn: (t) => t.fieldId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CustomFieldValuesTableAnnotationComposer(
                $db: $db,
                $table: $db.customFieldValues,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CustomFieldDefsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $CustomFieldDefsTable,
          CustomFieldDefRow,
          $$CustomFieldDefsTableFilterComposer,
          $$CustomFieldDefsTableOrderingComposer,
          $$CustomFieldDefsTableAnnotationComposer,
          $$CustomFieldDefsTableCreateCompanionBuilder,
          $$CustomFieldDefsTableUpdateCompanionBuilder,
          (CustomFieldDefRow, $$CustomFieldDefsTableReferences),
          CustomFieldDefRow,
          PrefetchHooks Function({bool customFieldValuesRefs})
        > {
  $$CustomFieldDefsTableTableManager(
    _$CompendiumDatabase db,
    $CustomFieldDefsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomFieldDefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomFieldDefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomFieldDefsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<CustomFieldType> type = const Value.absent(),
                Value<String?> choicesJson = const Value.absent(),
                Value<bool> showInList = const Value.absent(),
                Value<bool> searchable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomFieldDefsCompanion(
                id: id,
                key: key,
                label: label,
                type: type,
                choicesJson: choicesJson,
                showInList: showInList,
                searchable: searchable,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String key,
                required String label,
                required CustomFieldType type,
                Value<String?> choicesJson = const Value.absent(),
                Value<bool> showInList = const Value.absent(),
                Value<bool> searchable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomFieldDefsCompanion.insert(
                id: id,
                key: key,
                label: label,
                type: type,
                choicesJson: choicesJson,
                showInList: showInList,
                searchable: searchable,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CustomFieldDefsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({customFieldValuesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (customFieldValuesRefs) db.customFieldValues,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (customFieldValuesRefs)
                    await $_getPrefetchedData<
                      CustomFieldDefRow,
                      $CustomFieldDefsTable,
                      CustomFieldValueRow
                    >(
                      currentTable: table,
                      referencedTable: $$CustomFieldDefsTableReferences
                          ._customFieldValuesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CustomFieldDefsTableReferences(
                            db,
                            table,
                            p0,
                          ).customFieldValuesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.fieldId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CustomFieldDefsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $CustomFieldDefsTable,
      CustomFieldDefRow,
      $$CustomFieldDefsTableFilterComposer,
      $$CustomFieldDefsTableOrderingComposer,
      $$CustomFieldDefsTableAnnotationComposer,
      $$CustomFieldDefsTableCreateCompanionBuilder,
      $$CustomFieldDefsTableUpdateCompanionBuilder,
      (CustomFieldDefRow, $$CustomFieldDefsTableReferences),
      CustomFieldDefRow,
      PrefetchHooks Function({bool customFieldValuesRefs})
    >;
typedef $$CustomFieldValuesTableCreateCompanionBuilder =
    CustomFieldValuesCompanion Function({
      required String danceId,
      required String fieldId,
      Value<String?> valueText,
      Value<double?> valueNum,
      Value<int> rowid,
    });
typedef $$CustomFieldValuesTableUpdateCompanionBuilder =
    CustomFieldValuesCompanion Function({
      Value<String> danceId,
      Value<String> fieldId,
      Value<String?> valueText,
      Value<double?> valueNum,
      Value<int> rowid,
    });

final class $$CustomFieldValuesTableReferences
    extends
        BaseReferences<
          _$CompendiumDatabase,
          $CustomFieldValuesTable,
          CustomFieldValueRow
        > {
  $$CustomFieldValuesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('custom_field_values__dance_id__dances__id');

  $$DancesTableProcessedTableManager get danceId {
    final $_column = $_itemColumn<String>('dance_id')!;

    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CustomFieldDefsTable _fieldIdTable(_$CompendiumDatabase db) => db
      .customFieldDefs
      .createAlias('custom_field_values__field_id__custom_field_defs__id');

  $$CustomFieldDefsTableProcessedTableManager get fieldId {
    final $_column = $_itemColumn<String>('field_id')!;

    final manager = $$CustomFieldDefsTableTableManager(
      $_db,
      $_db.customFieldDefs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fieldIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CustomFieldValuesTableFilterComposer
    extends Composer<_$CompendiumDatabase, $CustomFieldValuesTable> {
  $$CustomFieldValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get valueText => $composableBuilder(
    column: $table.valueText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get valueNum => $composableBuilder(
    column: $table.valueNum,
    builder: (column) => ColumnFilters(column),
  );

  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomFieldDefsTableFilterComposer get fieldId {
    final $$CustomFieldDefsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.customFieldDefs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomFieldDefsTableFilterComposer(
            $db: $db,
            $table: $db.customFieldDefs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomFieldValuesTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $CustomFieldValuesTable> {
  $$CustomFieldValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get valueText => $composableBuilder(
    column: $table.valueText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get valueNum => $composableBuilder(
    column: $table.valueNum,
    builder: (column) => ColumnOrderings(column),
  );

  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomFieldDefsTableOrderingComposer get fieldId {
    final $$CustomFieldDefsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.customFieldDefs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomFieldDefsTableOrderingComposer(
            $db: $db,
            $table: $db.customFieldDefs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomFieldValuesTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $CustomFieldValuesTable> {
  $$CustomFieldValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get valueText =>
      $composableBuilder(column: $table.valueText, builder: (column) => column);

  GeneratedColumn<double> get valueNum =>
      $composableBuilder(column: $table.valueNum, builder: (column) => column);

  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomFieldDefsTableAnnotationComposer get fieldId {
    final $$CustomFieldDefsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.customFieldDefs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomFieldDefsTableAnnotationComposer(
            $db: $db,
            $table: $db.customFieldDefs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomFieldValuesTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $CustomFieldValuesTable,
          CustomFieldValueRow,
          $$CustomFieldValuesTableFilterComposer,
          $$CustomFieldValuesTableOrderingComposer,
          $$CustomFieldValuesTableAnnotationComposer,
          $$CustomFieldValuesTableCreateCompanionBuilder,
          $$CustomFieldValuesTableUpdateCompanionBuilder,
          (CustomFieldValueRow, $$CustomFieldValuesTableReferences),
          CustomFieldValueRow,
          PrefetchHooks Function({bool danceId, bool fieldId})
        > {
  $$CustomFieldValuesTableTableManager(
    _$CompendiumDatabase db,
    $CustomFieldValuesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomFieldValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomFieldValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomFieldValuesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> danceId = const Value.absent(),
                Value<String> fieldId = const Value.absent(),
                Value<String?> valueText = const Value.absent(),
                Value<double?> valueNum = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomFieldValuesCompanion(
                danceId: danceId,
                fieldId: fieldId,
                valueText: valueText,
                valueNum: valueNum,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String danceId,
                required String fieldId,
                Value<String?> valueText = const Value.absent(),
                Value<double?> valueNum = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomFieldValuesCompanion.insert(
                danceId: danceId,
                fieldId: fieldId,
                valueText: valueText,
                valueNum: valueNum,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CustomFieldValuesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceId = false, fieldId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable:
                                    $$CustomFieldValuesTableReferences
                                        ._danceIdTable(db),
                                referencedColumn:
                                    $$CustomFieldValuesTableReferences
                                        ._danceIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (fieldId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fieldId,
                                referencedTable:
                                    $$CustomFieldValuesTableReferences
                                        ._fieldIdTable(db),
                                referencedColumn:
                                    $$CustomFieldValuesTableReferences
                                        ._fieldIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CustomFieldValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $CustomFieldValuesTable,
      CustomFieldValueRow,
      $$CustomFieldValuesTableFilterComposer,
      $$CustomFieldValuesTableOrderingComposer,
      $$CustomFieldValuesTableAnnotationComposer,
      $$CustomFieldValuesTableCreateCompanionBuilder,
      $$CustomFieldValuesTableUpdateCompanionBuilder,
      (CustomFieldValueRow, $$CustomFieldValuesTableReferences),
      CustomFieldValueRow,
      PrefetchHooks Function({bool danceId, bool fieldId})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      Value<int?> color,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int?> color,
      Value<int> rowid,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$CompendiumDatabase, $TagsTable, TagRow> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DanceTagsTable, List<DanceTagRow>>
  _danceTagsRefsTable(_$CompendiumDatabase db) => MultiTypedResultKey.fromTable(
    db.danceTags,
    aliasName: 'tags__id__dance_tags__tag_id',
  );

  $$DanceTagsTableProcessedTableManager get danceTagsRefs {
    final manager = $$DanceTagsTableTableManager(
      $_db,
      $_db.danceTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_danceTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> danceTagsRefs(
    Expression<bool> Function($$DanceTagsTableFilterComposer f) f,
  ) {
    final $$DanceTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceTagsTableFilterComposer(
            $db: $db,
            $table: $db.danceTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  Expression<T> danceTagsRefs<T extends Object>(
    Expression<T> Function($$DanceTagsTableAnnotationComposer a) f,
  ) {
    final $$DanceTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.danceTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DanceTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.danceTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, $$TagsTableReferences),
          TagRow,
          PrefetchHooks Function({bool danceTagsRefs})
        > {
  $$TagsTableTableManager(_$CompendiumDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  TagsCompanion(id: id, name: name, color: color, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                color: color,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({danceTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (danceTagsRefs) db.danceTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (danceTagsRefs)
                    await $_getPrefetchedData<TagRow, $TagsTable, DanceTagRow>(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences
                          ._danceTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).danceTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, $$TagsTableReferences),
      TagRow,
      PrefetchHooks Function({bool danceTagsRefs})
    >;
typedef $$DanceTagsTableCreateCompanionBuilder =
    DanceTagsCompanion Function({
      required String danceId,
      required String tagId,
      Value<int> rowid,
    });
typedef $$DanceTagsTableUpdateCompanionBuilder =
    DanceTagsCompanion Function({
      Value<String> danceId,
      Value<String> tagId,
      Value<int> rowid,
    });

final class $$DanceTagsTableReferences
    extends BaseReferences<_$CompendiumDatabase, $DanceTagsTable, DanceTagRow> {
  $$DanceTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('dance_tags__dance_id__dances__id');

  $$DancesTableProcessedTableManager get danceId {
    final $_column = $_itemColumn<String>('dance_id')!;

    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$CompendiumDatabase db) =>
      db.tags.createAlias('dance_tags__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DanceTagsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $DanceTagsTable> {
  $$DanceTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceTagsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $DanceTagsTable> {
  $$DanceTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceTagsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $DanceTagsTable> {
  $$DanceTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceTagsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $DanceTagsTable,
          DanceTagRow,
          $$DanceTagsTableFilterComposer,
          $$DanceTagsTableOrderingComposer,
          $$DanceTagsTableAnnotationComposer,
          $$DanceTagsTableCreateCompanionBuilder,
          $$DanceTagsTableUpdateCompanionBuilder,
          (DanceTagRow, $$DanceTagsTableReferences),
          DanceTagRow,
          PrefetchHooks Function({bool danceId, bool tagId})
        > {
  $$DanceTagsTableTableManager(_$CompendiumDatabase db, $DanceTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DanceTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DanceTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DanceTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> danceId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanceTagsCompanion(
                danceId: danceId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String danceId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => DanceTagsCompanion.insert(
                danceId: danceId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DanceTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable: $$DanceTagsTableReferences
                                    ._danceIdTable(db),
                                referencedColumn: $$DanceTagsTableReferences
                                    ._danceIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$DanceTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$DanceTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DanceTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $DanceTagsTable,
      DanceTagRow,
      $$DanceTagsTableFilterComposer,
      $$DanceTagsTableOrderingComposer,
      $$DanceTagsTableAnnotationComposer,
      $$DanceTagsTableCreateCompanionBuilder,
      $$DanceTagsTableUpdateCompanionBuilder,
      (DanceTagRow, $$DanceTagsTableReferences),
      DanceTagRow,
      PrefetchHooks Function({bool danceId, bool tagId})
    >;
typedef $$DanceLinksTableCreateCompanionBuilder =
    DanceLinksCompanion Function({
      required String id,
      required String danceId,
      required LinkKind kind,
      Value<String?> url,
      Value<String?> targetDanceId,
      Value<String?> label,
      Value<int> rowid,
    });
typedef $$DanceLinksTableUpdateCompanionBuilder =
    DanceLinksCompanion Function({
      Value<String> id,
      Value<String> danceId,
      Value<LinkKind> kind,
      Value<String?> url,
      Value<String?> targetDanceId,
      Value<String?> label,
      Value<int> rowid,
    });

final class $$DanceLinksTableReferences
    extends
        BaseReferences<_$CompendiumDatabase, $DanceLinksTable, DanceLinkRow> {
  $$DanceLinksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('dance_links__dance_id__dances__id');

  $$DancesTableProcessedTableManager get danceId {
    final $_column = $_itemColumn<String>('dance_id')!;

    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $DancesTable _targetDanceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('dance_links__target_dance_id__dances__id');

  $$DancesTableProcessedTableManager? get targetDanceId {
    final $_column = $_itemColumn<String>('target_dance_id');
    if ($_column == null) return null;
    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_targetDanceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DanceLinksTableFilterComposer
    extends Composer<_$CompendiumDatabase, $DanceLinksTable> {
  $$DanceLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LinkKind, LinkKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DancesTableFilterComposer get targetDanceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetDanceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceLinksTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $DanceLinksTable> {
  $$DanceLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DancesTableOrderingComposer get targetDanceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetDanceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceLinksTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $DanceLinksTable> {
  $$DanceLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LinkKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DancesTableAnnotationComposer get targetDanceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.targetDanceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DanceLinksTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $DanceLinksTable,
          DanceLinkRow,
          $$DanceLinksTableFilterComposer,
          $$DanceLinksTableOrderingComposer,
          $$DanceLinksTableAnnotationComposer,
          $$DanceLinksTableCreateCompanionBuilder,
          $$DanceLinksTableUpdateCompanionBuilder,
          (DanceLinkRow, $$DanceLinksTableReferences),
          DanceLinkRow,
          PrefetchHooks Function({bool danceId, bool targetDanceId})
        > {
  $$DanceLinksTableTableManager(_$CompendiumDatabase db, $DanceLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DanceLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DanceLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DanceLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> danceId = const Value.absent(),
                Value<LinkKind> kind = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> targetDanceId = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanceLinksCompanion(
                id: id,
                danceId: danceId,
                kind: kind,
                url: url,
                targetDanceId: targetDanceId,
                label: label,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String danceId,
                required LinkKind kind,
                Value<String?> url = const Value.absent(),
                Value<String?> targetDanceId = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanceLinksCompanion.insert(
                id: id,
                danceId: danceId,
                kind: kind,
                url: url,
                targetDanceId: targetDanceId,
                label: label,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DanceLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceId = false, targetDanceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable: $$DanceLinksTableReferences
                                    ._danceIdTable(db),
                                referencedColumn: $$DanceLinksTableReferences
                                    ._danceIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (targetDanceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.targetDanceId,
                                referencedTable: $$DanceLinksTableReferences
                                    ._targetDanceIdTable(db),
                                referencedColumn: $$DanceLinksTableReferences
                                    ._targetDanceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DanceLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $DanceLinksTable,
      DanceLinkRow,
      $$DanceLinksTableFilterComposer,
      $$DanceLinksTableOrderingComposer,
      $$DanceLinksTableAnnotationComposer,
      $$DanceLinksTableCreateCompanionBuilder,
      $$DanceLinksTableUpdateCompanionBuilder,
      (DanceLinkRow, $$DanceLinksTableReferences),
      DanceLinkRow,
      PrefetchHooks Function({bool danceId, bool targetDanceId})
    >;
typedef $$ProvenanceTableCreateCompanionBuilder =
    ProvenanceCompanion Function({
      required String danceId,
      required ProvenanceSource source,
      Value<String?> externalId,
      required DateTime importedAt,
      Value<String?> permission,
      Value<String?> license,
      Value<String?> rawPayload,
      Value<String?> sourceVersion,
      Value<int> rowid,
    });
typedef $$ProvenanceTableUpdateCompanionBuilder =
    ProvenanceCompanion Function({
      Value<String> danceId,
      Value<ProvenanceSource> source,
      Value<String?> externalId,
      Value<DateTime> importedAt,
      Value<String?> permission,
      Value<String?> license,
      Value<String?> rawPayload,
      Value<String?> sourceVersion,
      Value<int> rowid,
    });

final class $$ProvenanceTableReferences
    extends
        BaseReferences<_$CompendiumDatabase, $ProvenanceTable, ProvenanceRow> {
  $$ProvenanceTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DancesTable _danceIdTable(_$CompendiumDatabase db) =>
      db.dances.createAlias('provenance__dance_id__dances__id');

  $$DancesTableProcessedTableManager get danceId {
    final $_column = $_itemColumn<String>('dance_id')!;

    final manager = $$DancesTableTableManager(
      $_db,
      $_db.dances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_danceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProvenanceTableFilterComposer
    extends Composer<_$CompendiumDatabase, $ProvenanceTable> {
  $$ProvenanceTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<ProvenanceSource, ProvenanceSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawPayload => $composableBuilder(
    column: $table.rawPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceVersion => $composableBuilder(
    column: $table.sourceVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$DancesTableFilterComposer get danceId {
    final $$DancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableFilterComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProvenanceTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $ProvenanceTable> {
  $$ProvenanceTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawPayload => $composableBuilder(
    column: $table.rawPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceVersion => $composableBuilder(
    column: $table.sourceVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$DancesTableOrderingComposer get danceId {
    final $$DancesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableOrderingComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProvenanceTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $ProvenanceTable> {
  $$ProvenanceTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<ProvenanceSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get permission => $composableBuilder(
    column: $table.permission,
    builder: (column) => column,
  );

  GeneratedColumn<String> get license =>
      $composableBuilder(column: $table.license, builder: (column) => column);

  GeneratedColumn<String> get rawPayload => $composableBuilder(
    column: $table.rawPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceVersion => $composableBuilder(
    column: $table.sourceVersion,
    builder: (column) => column,
  );

  $$DancesTableAnnotationComposer get danceId {
    final $$DancesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.danceId,
      referencedTable: $db.dances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DancesTableAnnotationComposer(
            $db: $db,
            $table: $db.dances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProvenanceTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $ProvenanceTable,
          ProvenanceRow,
          $$ProvenanceTableFilterComposer,
          $$ProvenanceTableOrderingComposer,
          $$ProvenanceTableAnnotationComposer,
          $$ProvenanceTableCreateCompanionBuilder,
          $$ProvenanceTableUpdateCompanionBuilder,
          (ProvenanceRow, $$ProvenanceTableReferences),
          ProvenanceRow,
          PrefetchHooks Function({bool danceId})
        > {
  $$ProvenanceTableTableManager(_$CompendiumDatabase db, $ProvenanceTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProvenanceTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProvenanceTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProvenanceTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> danceId = const Value.absent(),
                Value<ProvenanceSource> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<String?> permission = const Value.absent(),
                Value<String?> license = const Value.absent(),
                Value<String?> rawPayload = const Value.absent(),
                Value<String?> sourceVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProvenanceCompanion(
                danceId: danceId,
                source: source,
                externalId: externalId,
                importedAt: importedAt,
                permission: permission,
                license: license,
                rawPayload: rawPayload,
                sourceVersion: sourceVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String danceId,
                required ProvenanceSource source,
                Value<String?> externalId = const Value.absent(),
                required DateTime importedAt,
                Value<String?> permission = const Value.absent(),
                Value<String?> license = const Value.absent(),
                Value<String?> rawPayload = const Value.absent(),
                Value<String?> sourceVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProvenanceCompanion.insert(
                danceId: danceId,
                source: source,
                externalId: externalId,
                importedAt: importedAt,
                permission: permission,
                license: license,
                rawPayload: rawPayload,
                sourceVersion: sourceVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProvenanceTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({danceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (danceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.danceId,
                                referencedTable: $$ProvenanceTableReferences
                                    ._danceIdTable(db),
                                referencedColumn: $$ProvenanceTableReferences
                                    ._danceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProvenanceTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $ProvenanceTable,
      ProvenanceRow,
      $$ProvenanceTableFilterComposer,
      $$ProvenanceTableOrderingComposer,
      $$ProvenanceTableAnnotationComposer,
      $$ProvenanceTableCreateCompanionBuilder,
      $$ProvenanceTableUpdateCompanionBuilder,
      (ProvenanceRow, $$ProvenanceTableReferences),
      ProvenanceRow,
      PrefetchHooks Function({bool danceId})
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String valueJson,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> valueJson,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$CompendiumDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$CompendiumDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String valueJson,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (
        SettingRow,
        BaseReferences<_$CompendiumDatabase, $SettingsTable, SettingRow>,
      ),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$SnapshotsTableCreateCompanionBuilder =
    SnapshotsCompanion Function({
      required String source,
      required DateTime snapshotDate,
      required String manifestJson,
      required DateTime importedAt,
      Value<int> rowid,
    });
typedef $$SnapshotsTableUpdateCompanionBuilder =
    SnapshotsCompanion Function({
      Value<String> source,
      Value<DateTime> snapshotDate,
      Value<String> manifestJson,
      Value<DateTime> importedAt,
      Value<int> rowid,
    });

class $$SnapshotsTableFilterComposer
    extends Composer<_$CompendiumDatabase, $SnapshotsTable> {
  $$SnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get snapshotDate => $composableBuilder(
    column: $table.snapshotDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SnapshotsTableOrderingComposer
    extends Composer<_$CompendiumDatabase, $SnapshotsTable> {
  $$SnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get snapshotDate => $composableBuilder(
    column: $table.snapshotDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnapshotsTableAnnotationComposer
    extends Composer<_$CompendiumDatabase, $SnapshotsTable> {
  $$SnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get snapshotDate => $composableBuilder(
    column: $table.snapshotDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );
}

class $$SnapshotsTableTableManager
    extends
        RootTableManager<
          _$CompendiumDatabase,
          $SnapshotsTable,
          SnapshotRow,
          $$SnapshotsTableFilterComposer,
          $$SnapshotsTableOrderingComposer,
          $$SnapshotsTableAnnotationComposer,
          $$SnapshotsTableCreateCompanionBuilder,
          $$SnapshotsTableUpdateCompanionBuilder,
          (
            SnapshotRow,
            BaseReferences<_$CompendiumDatabase, $SnapshotsTable, SnapshotRow>,
          ),
          SnapshotRow,
          PrefetchHooks Function()
        > {
  $$SnapshotsTableTableManager(_$CompendiumDatabase db, $SnapshotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<DateTime> snapshotDate = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnapshotsCompanion(
                source: source,
                snapshotDate: snapshotDate,
                manifestJson: manifestJson,
                importedAt: importedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                required DateTime snapshotDate,
                required String manifestJson,
                required DateTime importedAt,
                Value<int> rowid = const Value.absent(),
              }) => SnapshotsCompanion.insert(
                source: source,
                snapshotDate: snapshotDate,
                manifestJson: manifestJson,
                importedAt: importedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$CompendiumDatabase,
      $SnapshotsTable,
      SnapshotRow,
      $$SnapshotsTableFilterComposer,
      $$SnapshotsTableOrderingComposer,
      $$SnapshotsTableAnnotationComposer,
      $$SnapshotsTableCreateCompanionBuilder,
      $$SnapshotsTableUpdateCompanionBuilder,
      (
        SnapshotRow,
        BaseReferences<_$CompendiumDatabase, $SnapshotsTable, SnapshotRow>,
      ),
      SnapshotRow,
      PrefetchHooks Function()
    >;

class $CompendiumDatabaseManager {
  final _$CompendiumDatabase _db;
  $CompendiumDatabaseManager(this._db);
  $$DancesTableTableManager get dances =>
      $$DancesTableTableManager(_db, _db.dances);
  $$ChoreographersTableTableManager get choreographers =>
      $$ChoreographersTableTableManager(_db, _db.choreographers);
  $$DanceAuthorsTableTableManager get danceAuthors =>
      $$DanceAuthorsTableTableManager(_db, _db.danceAuthors);
  $$DanceFiguresTableTableManager get danceFigures =>
      $$DanceFiguresTableTableManager(_db, _db.danceFigures);
  $$ProgramsTableTableManager get programs =>
      $$ProgramsTableTableManager(_db, _db.programs);
  $$ProgramSlotsTableTableManager get programSlots =>
      $$ProgramSlotsTableTableManager(_db, _db.programSlots);
  $$CustomFieldDefsTableTableManager get customFieldDefs =>
      $$CustomFieldDefsTableTableManager(_db, _db.customFieldDefs);
  $$CustomFieldValuesTableTableManager get customFieldValues =>
      $$CustomFieldValuesTableTableManager(_db, _db.customFieldValues);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$DanceTagsTableTableManager get danceTags =>
      $$DanceTagsTableTableManager(_db, _db.danceTags);
  $$DanceLinksTableTableManager get danceLinks =>
      $$DanceLinksTableTableManager(_db, _db.danceLinks);
  $$ProvenanceTableTableManager get provenance =>
      $$ProvenanceTableTableManager(_db, _db.provenance);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$SnapshotsTableTableManager get snapshots =>
      $$SnapshotsTableTableManager(_db, _db.snapshots);
}
