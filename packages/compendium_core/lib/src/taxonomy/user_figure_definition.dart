import 'dart:math';

import '../dialect/renderer.dart';
import '../model/enums.dart';
import '../util/text_sanitizer.dart';
import '../validation/validation.dart';
import 'param_opposites.dart';
import 'param_types.dart';
import 'user_figure_use.dart';

/// Most parameters a figure of your own may declare.
const int maxUserFigureParams = 16;

/// Longest parameter key a figure of your own may declare.
const int maxUserFigureParamKeyLength = 64;

/// Most choices one `choice` parameter may offer.
const int maxUserFigureChoices = 32;

/// Longest label a choice, or a flag parameter, may carry.
const int maxUserFigureLabelLength = 200;

/// Most beats a figure of your own may take by default: the taxonomy's own
/// bound on `beats` ([ParamKind.beats]).
const int maxUserFigureDefaultBeats = 64;

/// The dance form an entry is for when its payload names none (#1023,
/// maintainer decision 8): every entry written before forms were tagged is a
/// contra entry.
const String defaultGlossaryEntryForm = 'contra';

/// The slot every template may use for the figure's own name.
const String userFigureMoveSlot = 'move';

/// The slot every template may use for the use's beats.
const String userFigureBeatsSlot = 'beats';

/// Longest dance form name a payload may carry.
const int maxGlossaryEntryFormLength = 32;

/// Keys a declared parameter may not take, compared ignoring case: the
/// reserved slots, the free-text key a figure's fallback line is stored
/// under, and the role tokens, which read as role words rather than slots.
final Set<String> _reservedParamKeys = {
  userFigureMoveSlot,
  userFigureBeatsSlot,
  'text',
  ...roleTokens,
};

final RegExp _paramKeyShape = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
final RegExp _choiceIdShape = RegExp(r'^[a-z0-9]{1,16}$');
final RegExp _wordingSlot = RegExp(r'\{!?(\w+)\}');

/// [template] with [map] applied to its literal text only, its slots kept
/// exactly as written: how a template's words are canonicalized for storage
/// and rendered in a dialect for editing (#1023), so a role word never
/// reaches inside a `{…}` and a slot's key is never taken for a role word.
String mapUserFigureTemplateText(
  String template,
  String Function(String text) map,
) => template.splitMapJoin(
  _wordingSlot,
  onMatch: (match) => match[0]!,
  onNonMatch: map,
);

final Random _choiceIds = Random.secure();
const String _choiceIdAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// A new choice id, distinct from every id in [taken]: what a choice is stored
/// under in the dances using it, so its label can change.
String newUserFigureChoiceId(Set<String> taken) {
  while (true) {
    final id = String.fromCharCodes([
      for (var i = 0; i < 8; i++)
        _choiceIdAlphabet.codeUnitAt(
          _choiceIds.nextInt(_choiceIdAlphabet.length),
        ),
    ]);
    if (!taken.contains(id)) return id;
  }
}

/// The template slot holding [key]'s opposite: for `hand`, other followed by
/// Hand (#709's "other hand", offered and never declared). Empty for an
/// empty key, which validation refuses.
String userFigureOppositeSlot(String key) =>
    key.isEmpty ? '' : 'other${key[0].toUpperCase()}${key.substring(1)}';

/// One choice of a `choice` parameter (#1023): a stable [id] stored in the
/// dances that use it, and an editable [label] shown in its place, so
/// renaming a choice never detaches a use (implementer's choice; storing the
/// label instead would detach every use on a rename).
final class UserFigureChoice {
  const UserFigureChoice({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is UserFigureChoice && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// One parameter a figure of your own declares (#1023): a key the user
/// names, of one of the taxonomy's parameter kinds, with an optional default.
final class UserFigureParam {
  UserFigureParam({
    required this.key,
    required this.kind,
    List<UserFigureChoice> choices = const [],
    this.defaultValue,
    this.label,
  }) : choices = List.unmodifiable(choices);

  final String key;
  final ParamKind kind;

  /// The choices a [ParamKind.choice] parameter offers; empty for any other
  /// kind.
  final List<UserFigureChoice> choices;

  /// The value a use takes when it states none, or null for none: the slot
  /// then renders empty. Defaults live on the definition (maintainer decision
  /// 13), not in Settings ▸ Defaults.
  final Object? defaultValue;

  /// What a true [ParamKind.flag] renders as; ignored for other kinds. A flag
  /// with no label renders its key.
  final String? label;

  /// The parameter as a taxonomy [ParamSpec]: what its values are validated
  /// and rendered against. A choice's values are its ids.
  ParamSpec get spec => ParamSpec(
    kind,
    defaultValue: defaultValue,
    choices: kind == ParamKind.choice ? [for (final c in choices) c.id] : null,
  );

  /// The label of the choice [id], or null when there is none.
  String? choiceLabel(Object? id) {
    for (final choice in choices) {
      if (choice.id == id) return choice.label;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'kind': kind.name,
    if (kind == ParamKind.choice)
      'choices': [for (final c in choices) c.toJson()],
    if (defaultValue != null) 'default': defaultValue,
    if (label != null) 'label': label,
  };
}

/// A figure of your own (#1023): its parameters and the template its line is
/// rendered from, in the #822 wording syntax (`{slot}`, `{!slot}`,
/// `[optional group]`).
///
/// The payload of a `customFigure` glossary entry; the entry carries the
/// name, definition and description. Like a compound it carries no taxonomy
/// stamp and is validated whenever it is read (#709 consolidated spec,
/// decision 2).
final class UserFigureDefinition {
  UserFigureDefinition({
    this.form = defaultGlossaryEntryForm,
    required this.template,
    required this.defaultBeats,
    required List<UserFigureParam> params,
    this.copiedFrom,
    Map<String, Object?> extra = const {},
  }) : params = List.unmodifiable(params),
       extra = Map.unmodifiable(extra);

  /// The dance form's name ([DanceForm.name]) the figure is offered in, kept
  /// as stored text so a form a later build adds survives an edit here.
  final String form;

  /// The wording template, with role words as canonical tokens.
  final String template;

  /// The beats a use takes until the dance states its own.
  final int defaultBeats;

  final List<UserFigureParam> params;

  /// The built-in move this figure was copied from (maintainer decision 6),
  /// for display only: a copy is an independent figure.
  final String? copiedFrom;

  /// Payload keys this build does not know, carried through unchanged so an
  /// edit here cannot drop what a later build stored (implementer's choice).
  final Map<String, Object?> extra;

  /// The dance form, or null for one this build does not know.
  DanceForm? get danceForm {
    for (final value in DanceForm.values) {
      if (value.name == form) return value;
    }
    return null;
  }

  UserFigureParam? param(String key) {
    for (final p in params) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// Every slot the template may use: the reserved [userFigureMoveSlot] and
  /// [userFigureBeatsSlot], each declared parameter, and the opposite of
  /// each parameter whose kind has one.
  Set<String> get slots => {
    userFigureMoveSlot,
    userFigureBeatsSlot,
    for (final p in params) ...{
      p.key,
      if (p.key.isNotEmpty &&
          ParamOpposites.coverage(p.kind) != OppositeCoverage.none)
        userFigureOppositeSlot(p.key),
    },
  };

  /// The declared parameters the template never uses, by key. A parameter
  /// whose opposite is used counts as used.
  Set<String> get unusedParams {
    final used = userFigureTemplateSlots(template);
    return {
      for (final p in params)
        if (!used.contains(p.key) &&
            !used.contains(userFigureOppositeSlot(p.key)))
          p.key,
    };
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'form': form,
    'template': template,
    'defaultBeats': defaultBeats,
    'params': [for (final p in params) p.toJson()],
    if (copiedFrom != null) 'copiedFrom': copiedFrom,
  };
}

/// The slot names [template] uses, without a `!` force marker.
Set<String> userFigureTemplateSlots(String template) => {
  for (final match in _wordingSlot.allMatches(template)) match[1]!,
};

/// The keys of a stored figure [payload] this build does not know, which an
/// edit carries through ([UserFigureDefinition.extra]).
Map<String, Object?> userFigurePayloadExtra(Object? payload) => {
  if (payload is Map)
    for (final entry in payload.entries)
      if (entry.key is String && !_knownPayloadKeys.contains(entry.key))
        entry.key as String: entry.value,
};

const Set<String> _knownPayloadKeys = {
  'form',
  'template',
  'defaultBeats',
  'params',
  'copiedFrom',
};

/// The dance form's name a glossary entry's [payload] names, or
/// [defaultGlossaryEntryForm] when it names none. For every kind of entry:
/// compounds, terms and figures of your own (maintainer decision 8).
String glossaryEntryForm(Object? payload) {
  if (payload is Map) {
    final form = payload['form'];
    if (form is String && form.isNotEmpty) return form;
  }
  return defaultGlossaryEntryForm;
}

/// Decodes a stored [UserFigureDefinition], or returns null when [raw] is not
/// one this build can use: malformed, over a bound, or with any error from
/// [validateUserFigure]. Never throws.
UserFigureDefinition? decodeUserFigureDefinition(Object? raw) {
  try {
    if (raw is! Map) return null;
    final form = raw['form'] ?? defaultGlossaryEntryForm;
    final template = raw['template'];
    final defaultBeats = raw['defaultBeats'];
    final rawParams = raw['params'];
    final copiedFrom = raw['copiedFrom'];
    if (form is! String ||
        form.length > maxGlossaryEntryFormLength ||
        template is! String ||
        defaultBeats is! int ||
        rawParams is! List ||
        (copiedFrom != null &&
            (copiedFrom is! String ||
                copiedFrom.length > maxUserFigureParamKeyLength))) {
      return null;
    }
    if (rawParams.length > maxUserFigureParams) return null;
    final params = <UserFigureParam>[];
    for (final p in rawParams) {
      final param = _decodeParam(p);
      if (param == null) return null;
      params.add(param);
    }
    final definition = UserFigureDefinition(
      form: form,
      template: sanitizeImportedText(template, allowLineBreaks: false),
      defaultBeats: defaultBeats,
      params: params,
      copiedFrom: copiedFrom as String?,
      extra: userFigurePayloadExtra(raw),
    );
    final hasError = validateUserFigure(
      definition,
    ).any((issue) => issue.severity == ValidationSeverity.error);
    return hasError ? null : definition;
  } on Object {
    // A throw on hostile input is "not usable", never a crash.
    return null;
  }
}

UserFigureParam? _decodeParam(Object? raw) {
  if (raw is! Map) return null;
  final key = raw['key'];
  final kindName = raw['kind'];
  final label = raw['label'];
  if (key is! String || kindName is! String) return null;
  if (label != null && label is! String) return null;
  final kind = ParamKind.values.where((k) => k.name == kindName).firstOrNull;
  if (kind == null) return null;
  final choices = <UserFigureChoice>[];
  final rawChoices = raw['choices'];
  if (rawChoices != null) {
    if (rawChoices is! List || rawChoices.length > maxUserFigureChoices) {
      return null;
    }
    for (final c in rawChoices) {
      if (c is! Map) return null;
      final id = c['id'];
      final choiceLabel = c['label'];
      if (id is! String || choiceLabel is! String) return null;
      choices.add(
        UserFigureChoice(
          id: id,
          label: sanitizeImportedText(choiceLabel, allowLineBreaks: false),
        ),
      );
    }
  }
  final defaultValue = raw['default'];
  if (defaultValue is String &&
      defaultValue.length > maxUserFigureTextArgLength) {
    return null;
  }
  return UserFigureParam(
    key: key,
    kind: kind,
    choices: choices,
    defaultValue: defaultValue,
    label: label == null
        ? null
        : sanitizeImportedText(label as String, allowLineBreaks: false),
  );
}

/// The issue codes [validateUserFigure] reports.
abstract final class UserFigureIssueCodes {
  /// The template is empty, too long, or not well formed.
  static const badTemplate = 'user_figure_bad_template';

  /// The template uses a slot the figure does not offer.
  static const unknownSlot = 'user_figure_unknown_slot';

  /// More parameters or choices than the bounds allow.
  static const tooLarge = 'user_figure_too_large';

  /// A parameter's key is badly shaped, reserved, taken twice, or equal to
  /// another parameter's opposite slot.
  static const badParamKey = 'user_figure_bad_param_key';

  /// A parameter's kind is one a figure may not declare (`beats`, which is
  /// the use's own).
  static const badParamKind = 'user_figure_bad_param_kind';

  /// A `choice` parameter offers no choices, a choice is badly shaped or
  /// repeated, or another kind carries choices.
  static const badChoices = 'user_figure_bad_choices';

  /// A label is empty or too long.
  static const badLabel = 'user_figure_bad_label';

  /// A parameter's default is not one of its values.
  static const badDefault = 'user_figure_bad_default';

  /// The default beats are out of range.
  static const badBeats = 'user_figure_bad_beats';

  /// The form is empty.
  static const badForm = 'user_figure_bad_form';

  /// A declared parameter the template never uses. A warning: the user may
  /// save anyway (#822's missing-slot confirm, maintainer decision 12).
  static const unusedParam = 'user_figure_unused_param';
}

/// Validates [definition].
///
/// Errors make it unusable. The one warning, [UserFigureIssueCodes.unusedParam],
/// is #822's incomplete-template rule: saving asks first. An opposite slot the
/// template leaves unused is never reported: it is offered, not declared.
List<ValidationIssue> validateUserFigure(UserFigureDefinition definition) {
  final issues = <ValidationIssue>[];
  void error(
    String code,
    String message, [
    Map<String, Object?> data = const {},
  ]) => issues.add(
    ValidationIssue(
      severity: ValidationSeverity.error,
      code: code,
      message: message,
      data: data,
    ),
  );

  if (definition.form.isEmpty) {
    error(UserFigureIssueCodes.badForm, 'the form is empty');
  }
  if (!FigureRenderer.isValidMoveWordingTemplate(definition.template)) {
    error(UserFigureIssueCodes.badTemplate, 'the template is not well formed');
  }
  if (definition.defaultBeats < 0 ||
      definition.defaultBeats > maxUserFigureDefaultBeats) {
    error(
      UserFigureIssueCodes.badBeats,
      'default beats ${definition.defaultBeats} are out of range',
    );
  }
  if (definition.params.length > maxUserFigureParams) {
    error(UserFigureIssueCodes.tooLarge, 'too many parameters');
  }

  // Compared ignoring case: two keys differing only in case would share an
  // opposite slot.
  final keys = <String>{};
  final opposites = <String>{};
  for (final p in definition.params) {
    if (p.key.isNotEmpty &&
        ParamOpposites.coverage(p.kind) != OppositeCoverage.none) {
      opposites.add(userFigureOppositeSlot(p.key).toLowerCase());
    }
  }
  for (final p in definition.params) {
    final data = {'param': p.key};
    final badShape =
        p.key.length > maxUserFigureParamKeyLength ||
        !_paramKeyShape.hasMatch(p.key);
    if (badShape ||
        _reservedParamKeys.contains(p.key.toLowerCase()) ||
        !keys.add(p.key.toLowerCase()) ||
        opposites.contains(p.key.toLowerCase())) {
      error(
        UserFigureIssueCodes.badParamKey,
        'parameter "${p.key}" has a bad, reserved or repeated key',
        data,
      );
    }
    if (p.kind == ParamKind.beats) {
      error(
        UserFigureIssueCodes.badParamKind,
        'parameter "${p.key}" may not be beats',
        data,
      );
    }
    if (p.kind == ParamKind.choice) {
      final ids = <String>{};
      final valid =
          p.choices.isNotEmpty &&
          p.choices.length <= maxUserFigureChoices &&
          p.choices.every(
            (c) =>
                _choiceIdShape.hasMatch(c.id) &&
                ids.add(c.id) &&
                _isGoodLabel(c.label),
          );
      if (!valid) {
        error(
          UserFigureIssueCodes.badChoices,
          'parameter "${p.key}" has missing, bad or repeated choices',
          data,
        );
      }
    } else if (p.choices.isNotEmpty) {
      error(
        UserFigureIssueCodes.badChoices,
        'parameter "${p.key}" is not a choice but has choices',
        data,
      );
    }
    final label = p.label;
    if (label != null && !_isGoodLabel(label)) {
      error(
        UserFigureIssueCodes.badLabel,
        'parameter "${p.key}" has a bad label',
        data,
      );
    }
    final defaultValue = p.defaultValue;
    if (defaultValue != null && !p.spec.validate(defaultValue)) {
      error(
        UserFigureIssueCodes.badDefault,
        'parameter "${p.key}" has a default outside its values',
        data,
      );
    }
  }

  final offered = definition.slots;
  for (final slot in userFigureTemplateSlots(definition.template)) {
    if (!offered.contains(slot)) {
      error(
        UserFigureIssueCodes.unknownSlot,
        'the template uses {$slot}, which the figure does not offer',
        {'slot': slot},
      );
    }
  }
  for (final key in definition.unusedParams) {
    issues.add(
      ValidationIssue(
        severity: ValidationSeverity.warning,
        code: UserFigureIssueCodes.unusedParam,
        message: 'the template never uses parameter "$key"',
        data: {'param': key},
      ),
    );
  }
  return issues;
}

bool _isGoodLabel(String label) =>
    label.trim().isNotEmpty && label.length <= maxUserFigureLabelLength;
