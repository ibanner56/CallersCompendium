import 'package:meta/meta.dart';

/// A success-or-failure value threaded through the compilation fold.
///
/// `docs/architecture.md` §8.3 requires that the engine use **no exceptions for
/// control flow**: a failed precondition is an ordinary, expected outcome of
/// compiling a dance, not a defect. Modelling it as a value keeps every exit
/// path visible in the type signature and lets the fold short-circuit without
/// unwinding the stack.
///
/// Exceptions are still used for genuine *compiler* defects — a
/// `FormationProjectionError` means a figure produced an impossible state, and
/// that should crash loudly rather than be reported as a dance error.
@immutable
sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;

  bool get isErr => this is Err<T, E>;

  /// The success value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok<T, E>(:final value) => value,
    Err<T, E>() => null,
  };

  /// The failure value, or `null` when this is an [Ok].
  E? get errorOrNull => switch (this) {
    Ok<T, E>() => null,
    Err<T, E>(:final error) => error,
  };

  /// Collapses both cases to a single value.
  R fold<R>(R Function(T value) onOk, R Function(E error) onErr) =>
      switch (this) {
        Ok<T, E>(:final value) => onOk(value),
        Err<T, E>(:final error) => onErr(error),
      };

  /// Transforms the success value, leaving a failure untouched.
  Result<U, E> map<U>(U Function(T value) transform) => switch (this) {
    Ok<T, E>(:final value) => Ok<U, E>(transform(value)),
    Err<T, E>(:final error) => Err<U, E>(error),
  };

  /// Chains another fallible step onto a success.
  ///
  /// This is the operator the execution fold is built from: each operation
  /// consumes the previous formation and may fail, and the first failure wins.
  Result<U, E> flatMap<U>(Result<U, E> Function(T value) transform) =>
      switch (this) {
        Ok<T, E>(:final value) => transform(value),
        Err<T, E>(:final error) => Err<U, E>(error),
      };
}

/// A successful [Result] carrying its [value].
final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, E> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok<T, E>, value);

  @override
  String toString() => 'Ok($value)';
}

/// A failed [Result] carrying its [error].
final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  final E error;

  @override
  bool operator ==(Object other) => other is Err<T, E> && other.error == error;

  @override
  int get hashCode => Object.hash(Err<T, E>, error);

  @override
  String toString() => 'Err($error)';
}
