# Third-party notices

Caller's Compendium is licensed under AGPL-3.0 (see [`LICENSE`](LICENSE) and
[`LICENSE-EXCEPTION.md`](LICENSE-EXCEPTION.md)). This file carries the notices
that other projects' licenses require to travel with code we ported from them.
The same texts ship in the app under **Settings ▸ About ▸ View licenses**.

Fonts bundled with the app are covered separately: their SIL Open Font License
texts live beside them in [`app/assets/fonts/`](app/assets/fonts/) and appear on
the same in-app license page. Third-party packages the app depends on carry
their own licenses, which Flutter lists on that page automatically.

If you port code from another project, add its notice here, to the head of the
ported file, and to the in-app license page (`app/lib/src/licenses.dart`).
`app/test/licenses_notice_test.dart` fails when a source file that calls itself
an MIT-licensed port carries no notice.

## fmptools

The Caller's Companion `.USR` importer reads the FileMaker Pro 12 container
format. Two files in `compendium_core` are ports of
[`fmptools`](https://github.com/evanmiller/fmptools) by Evan Miller, which is
MIT-licensed:

- [`packages/compendium_core/lib/src/imports/fmp/fmp_reader.dart`](packages/compendium_core/lib/src/imports/fmp/fmp_reader.dart)
  — the block/sector traversal, chunk byte-code decoder, path stack, and
  table/column/record reconstruction.
- [`packages/compendium_core/lib/src/imports/fmp/scsu.dart`](packages/compendium_core/lib/src/imports/fmp/scsu.dart)
  — a port of `src/scsu.c`.

The `fmptools` license, verbatim:

```text
Copyright (c) 2020 Evan Miller (except where otherwise noted)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
