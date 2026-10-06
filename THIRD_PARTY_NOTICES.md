# Third-party notices

Caller's Compendium is licensed under AGPL-3.0 (see [`LICENSE`](LICENSE) and
[`LICENSE-EXCEPTION.md`](LICENSE-EXCEPTION.md)). This file carries the notices
that other projects' licenses require to travel with code or data we took from
them, and the attribution we promised where the licence leaves it optional. The
same texts ship in the app under **Settings ▸ About ▸ View licenses**.

Fonts bundled with the app are covered separately: their SIL Open Font License
texts live beside them in [`app/assets/fonts/`](app/assets/fonts/) and appear on
the same in-app license page. Third-party Dart packages the app depends on
carry their own licenses, which Flutter lists on that page automatically.
Native libraries that do not come through pub are not listed automatically;
their notices are bundled and registered by hand (see [pdfium](#pdfium) below).

If you port code from another project, add its notice here, to the head of the
ported file, and to the in-app license page (`app/lib/src/licenses.dart`).
The bundled asset under `app/assets/licenses/` is the reference copy;
`app/test/licenses_notice_test.dart` compares every other copy against it, and
fails when a source file that calls itself an MIT-licensed port carries no
notice.

## pdfium

The Linux and Windows builds ship a prebuilt
[pdfium](https://pdfium.googlesource.com/pdfium/) (PDFium 106.0.5200.0, from
the [`bblanchon/pdfium-binaries`](https://github.com/bblanchon/pdfium-binaries)
release `chromium/5200`), which the `printing` plugin uses to render PDF pages
on those platforms. It is pinned and hash-checked by
[`packaging/pdfium/pdfium.cmake`](packaging/pdfium/pdfium.cmake). The Android,
iOS and macOS builds do not contain it.

PDFium's own licence section carries BSD-3-Clause and Apache-2.0 texts, and the
binary includes code from FreeType, libjpeg-turbo, the IJG JPEG library, lcms,
OpenJPEG, zlib, libpng, LibTIFF, Anti-Grain Geometry and ICU, among others,
each with its own notice. The release archive's `LICENSE` file carries all of
them; we ship it verbatim (one Latin-1 byte re-encoded as UTF-8) as
[`app/assets/licenses/pdfium-LICENSE.txt`](app/assets/licenses/pdfium-LICENSE.txt),
and the Linux and Windows apps show it under **Settings ▸ About ▸ View
licenses**. At about 1,300 lines it is not repeated here.

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

## EFF Long Wordlist

Device Sync identifies an account by a generated four-word ID drawn from the
Electronic Frontier Foundation's long wordlist (7,776 words, published 2016).
The list is compiled unmodified into
[`packages/compendium_core/lib/src/sync/eff_long_wordlist.dart`](packages/compendium_core/lib/src/sync/eff_long_wordlist.dart)
and used by `sync_id.dart` to generate and score IDs.

The wordlist is licensed under [Creative Commons Attribution 3.0 United
States](https://creativecommons.org/licenses/by/3.0/us/) (CC BY 3.0 US), the
licence EFF's copyright notice pointed to when the list was copied (the
wordlist pages themselves state no licence; the header we recorded says
CC BY 3.0, and EFF's 3.0 licence badge links the US port). EFF's
[copyright page](https://www.eff.org/copyright) now states CC BY 4.0
International for the site's content unless otherwise noted; we cite the
licence under which the file was obtained. Either version asks for the author,
the licence and the source to be named. The notice, verbatim:

```text
EFF Long Wordlist
Copyright (c) 2016 Electronic Frontier Foundation (EFF)

The 7,776-word EFF long wordlist is licensed by EFF under the Creative Commons
Attribution 3.0 United States license (CC BY 3.0 US),
https://creativecommons.org/licenses/by/3.0/us/ - the license EFF's copyright
notice pointed to when the list was copied. EFF's copyright page
(https://www.eff.org/copyright) now states CC BY 4.0 International for the
site's content unless otherwise noted.

Source: https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt

Caller's Compendium compiles the wordlist in unmodified form and uses it to
generate the four-word IDs that identify a device-sync account.
```

## ContraDB

[ContraDB](https://github.com/contradb/contra) by David Morse is licensed under
AGPL-3.0, the same licence as Caller's Compendium.
[`docs/research/contradb.md`](docs/research/contradb.md) records the decision
to reuse its design with attribution. No ContraDB source code is transcribed,
but the figure sentence structure and modifier phrasing produced by
[`packages/compendium_core/lib/src/dialect/renderer.dart`](packages/compendium_core/lib/src/dialect/renderer.dart)
follow ContraDB's `libfigure` (`app/javascript/libfigure/` upstream): a
handful of moves adopt its `words()` sentence structure verbatim, and the
modifier clauses follow `upOrDownTheHallWords`, `zigZagWords`,
`longLinesWords`, `heyWords` and `gyreWords`, which the renderer's comments name
at each site. The notice, verbatim:

```text
ContraDB
Copyright (c) David Morse and ContraDB contributors
Licensed under the GNU Affero General Public License, version 3 (AGPL-3.0).

Source: https://github.com/contradb/contra

Figure sentence structure and modifier phrasing in Caller's Compendium's
dialect renderer follow ContraDB's libfigure (its words() functions, among them
upOrDownTheHallWords, zigZagWords, longLinesWords, heyWords and gyreWords). No
ContraDB source code is transcribed; the renderer's comments name the libfigure
function each rendering follows.
```
