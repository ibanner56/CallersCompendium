import 'package:flutter/material.dart';

/// A `MaterialApp.builder` that applies [scale] as the system text scale, as a
/// phone with a larger font-size setting does. Null (the default scale) leaves
/// the app untouched.
TransitionBuilder? textScaleBuilder(double scale) {
  if (scale == 1) return null;
  return (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  );
}
