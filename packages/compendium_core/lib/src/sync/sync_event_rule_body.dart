import '../model/event_rule.dart';

/// The body of an `eventRule` record (#2340): the rule as stored, its
/// quantifier and scope as their stored names, so a rule a newer build wrote
/// travels on as it came. `nickname` is sent only when the rule has one; a
/// receiver reads a missing one as none ([withOmittedEventRuleDefaults]).
Map<String, Object?> syncEventRuleBody(EventRule rule) => {
  'id': rule.id,
  'savedSearchId': rule.savedSearchId,
  'quantifier': rule.quantifierName,
  'count': rule.count,
  'scope': rule.scopeName,
  if (rule.nickname != null) 'nickname': rule.nickname,
  'position': rule.position,
};

/// The `eventRule` body keys [syncEventRuleBody] leaves out when they are
/// empty, with that empty value.
const Map<String, Object?> omittedEventRuleDefaults = {'nickname': null};

/// [body], an `eventRule` body, with each omitted empty value
/// ([omittedEventRuleDefaults]) written in where it is missing, so a nickname
/// removed on one device is removed on the others: Device Sync overlays an
/// inbound body on the stored record key by key, and would otherwise keep the
/// stored nickname (sync-spec §4.1, §6.7). A body with no `savedSearchId` is
/// not a whole rule body and is returned as is.
Map<String, Object?> withOmittedEventRuleDefaults(Map<String, Object?> body) {
  if (!body.containsKey('savedSearchId')) return body;
  return {...omittedEventRuleDefaults, ...body};
}

/// Reads an `eventRule` body, throwing [FormatException] for one this build
/// cannot store. A quantifier or scope it does not know is kept: the rule is
/// stored, shown as needing attention and never checked.
EventRule decodeSyncEventRuleBody(Map<String, Object?> body) {
  final nickname = body['nickname'];
  if (nickname != null &&
      (nickname is! String ||
          nickname.isEmpty ||
          nickname.length > maxEventRuleNicknameLength)) {
    throw const FormatException('event rule nickname must be short text');
  }
  return EventRule(
    id: _text(body, 'id'),
    savedSearchId: _text(body, 'savedSearchId'),
    quantifierName: _text(body, 'quantifier'),
    count: _int(body, 'count', 0, maxEventRuleCount),
    scopeName: _text(body, 'scope'),
    nickname: nickname as String?,
    position: _int(body, 'position', 0, 1 << 31),
  );
}

String _text(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is! String || value.isEmpty || value.length > 200) {
    throw FormatException('event rule $key must be text of 1 to 200 units');
  }
  return value;
}

int _int(Map<String, Object?> body, String key, int min, int max) {
  final value = body[key];
  if (value is! int || value < min || value > max) {
    throw FormatException('event rule $key must be an integer $min to $max');
  }
  return value;
}
