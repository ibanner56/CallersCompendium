import 'package:flutter/material.dart';

/// Whether controls should take their compact, pointer-sized form.
///
/// The theme's `visualDensity` is `adaptivePlatformDensity`: compact on
/// desktop, where a mouse hits a small target, standard on touch platforms,
/// where a finger needs the full 48dp. Controls that would otherwise hard-code
/// `isDense: true` ask this instead, so a dense dropdown stays dense on a
/// desktop and is full height on a phone or tablet.
bool denseControls(BuildContext context) =>
    Theme.of(context).visualDensity.vertical < 0;
