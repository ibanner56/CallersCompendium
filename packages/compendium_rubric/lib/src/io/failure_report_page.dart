/// The files the harness writes for `--report` (see
/// `bin/callersbox_harness.dart`), and [writeFailureReport], which writes them.
///
/// The page is two files: [failureReportPage] is static HTML, and [failureReportScript]
/// renders the data as `report.js`, which the page loads with a plain
/// `<script src>`. A script rather than `fetch` of JSON so the page also opens
/// straight from disk (`file://`), where `fetch` is refused.
library;

import 'dart:convert';
import 'dart:io';

import 'failure_report.dart';

/// `report.js`: the diagnoses as one global, `window.RUBRIC_REPORT`.
///
/// [headline] is free-form context shown at the top of the page (the
/// harness's in-scope line, in practice).
String failureReportScript(
  List<FailureDiagnosis> diagnoses, {
  Set<String> coreIds = const {},
  String headline = '',
}) {
  final data = {
    'headline': headline,
    'hasCore': coreIds.isNotEmpty,
    'dances': [
      for (final d in diagnoses)
        d.toJson(core: coreIds.contains(d.run.sourceId)),
    ],
  };
  return 'window.RUBRIC_REPORT = ${jsonEncode(data)};\n';
}

/// Writes the whole report into [dir], creating it if need be:
/// `failures.jsonl`, `summary.md`, `report.js` and `index.html`.
///
/// Returns `null` on success and the reason on failure. It never throws a
/// [FileSystemException], so a report that cannot be written can never end a
/// harness run or change its exit code.
String? writeFailureReport(
  String dir,
  List<FailureDiagnosis> diagnoses, {
  Set<String> coreIds = const {},
  String headline = '',
}) {
  try {
    final directory = Directory(dir)..createSync(recursive: true);
    String at(String name) => '${directory.path}${Platform.pathSeparator}$name';
    File(at('failures.jsonl')).writeAsStringSync(
      diagnoses
          .map(
            (d) =>
                '${jsonEncode(d.toJson(core: coreIds.contains(d.run.sourceId)))}\n',
          )
          .join(),
    );
    File(at('summary.md')).writeAsStringSync(
      '${headline.isEmpty ? '' : '$headline.\n\n'}'
      '${summarizeFailures(diagnoses, coreIds: coreIds)}',
    );
    File(at('report.js')).writeAsStringSync(
      failureReportScript(diagnoses, coreIds: coreIds, headline: headline),
    );
    File(at('index.html')).writeAsStringSync(
      '<!doctype html>\n<meta charset="utf-8">\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1, '
      'viewport-fit=cover">\n$failureReportPage',
    );
    return null;
  } on FileSystemException catch (error) {
    return error.path == null
        ? error.message
        : '${error.path}: ${error.message}';
  }
}

/// `index.html`. Reads `report.js` from beside itself.
const String failureReportPage = r'''<title>Rubric Failures</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
/* Layout: a filter bar, then three panes (causes | dances | one dance) that stack on a phone. */
:root {
  --bg: #f6f7f9; --panel: #ffffff; --fg: #1b2230; --muted: #5d6779;
  --line: #dde1e8; --accent: #2a5bd7; --accent-soft: #e6edfc;
  --lark: #1f6f8b; --robin: #a8432a; --bad: #b4232c; --bad-soft: #fbe9ea;
  --good: #1d7a46; --good-soft: #e4f4ea;
  --sans: "IBM Plex Sans", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, Menlo, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #12161d; --panel: #1a1f29; --fg: #e3e7ee; --muted: #9aa4b5;
  --line: #2c3340; --accent: #7aa2ff; --accent-soft: #23304d;
  --lark: #6cc3e0; --robin: #f0937a; --bad: #ff7b84; --bad-soft: #3a1d22;
  --good: #6fd39b; --good-soft: #17301f; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #12161d; --panel: #1a1f29; --fg: #e3e7ee; --muted: #9aa4b5;
  --line: #2c3340; --accent: #7aa2ff; --accent-soft: #23304d;
  --lark: #6cc3e0; --robin: #f0937a; --bad: #ff7b84; --bad-soft: #3a1d22;
  --good: #6fd39b; --good-soft: #17301f; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font-family: var(--sans); font-size: 14px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 16px; }
h1 { font-size: 20px; margin: 0; font-weight: 600; text-wrap: balance; }
h2 { font-size: 15px; margin: 0; font-weight: 600; text-wrap: balance; }
h3 { font-size: 12px; margin: 0; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); font-weight: 600; }
header { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: baseline; margin-bottom: 12px; }
header .headline { color: var(--muted); font-variant-numeric: tabular-nums; }
.filters { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; margin-bottom: 12px; }
.filters label { display: inline-flex; gap: 6px; align-items: center; color: var(--muted); }
select, input[type=search] { font: inherit; color: var(--fg); background: var(--panel); border: 1px solid var(--line); border-radius: 6px; padding: 4px 8px; }
input[type=search] { min-width: 0; width: 14em; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.panes { display: grid; grid-template-columns: minmax(0, 22fr) minmax(0, 18fr) minmax(0, 60fr); gap: 12px; align-items: start; }
@media (max-width: 1000px) { .panes { grid-template-columns: minmax(0, 1fr); } }
.pane { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; min-width: 0; }
.pane > h3 { padding: 10px 12px 6px; }
.list { max-height: 78vh; overflow: auto; }
@media (max-width: 1000px) { .list { max-height: 40vh; } }
.item { display: grid; grid-template-columns: 4.5em minmax(0, 1fr); gap: 8px; width: 100%; text-align: left; background: none; border: 0; border-top: 1px solid var(--line); padding: 7px 12px; font: inherit; color: inherit; cursor: pointer; }
.item:hover { background: var(--accent-soft); }
.item[aria-current="true"] { background: var(--accent-soft); box-shadow: inset 3px 0 0 var(--accent); }
.count { font-variant-numeric: tabular-nums; text-align: right; color: var(--muted); }
.count b { color: var(--fg); font-weight: 600; }
.cause { overflow-wrap: anywhere; }
.dance-item { grid-template-columns: minmax(0, 1fr) auto; }
.tag { display: inline-block; font-size: 11px; padding: 1px 6px; border-radius: 99px; background: var(--accent-soft); color: var(--accent); white-space: nowrap; }
.tag.core { background: var(--good-soft); color: var(--good); }
.tag.bad { background: var(--bad-soft); color: var(--bad); }
.detail { padding: 14px; display: grid; grid-template-columns: minmax(0, 1fr); gap: 16px; }
.detail > *, .cols > * { min-width: 0; }
.detail .meta { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; color: var(--muted); }
.detail a { color: var(--accent); }
.why { font-family: var(--mono); font-size: 12.5px; background: var(--bad-soft); color: var(--fg); padding: 8px 10px; border-radius: 6px; overflow-wrap: anywhere; }
.cols { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 16px; }
@media (max-width: 640px) { .cols { grid-template-columns: minmax(0, 1fr); } }
.phrase { display: grid; grid-template-columns: 2.4em minmax(0, 1fr); gap: 2px 8px; }
.phrase .name { color: var(--muted); font-weight: 600; }
ol.figs { margin: 0; padding-left: 2.2em; font-family: var(--mono); font-size: 12px; display: grid; gap: 3px; }
ol.figs li { overflow-wrap: anywhere; }
ol.figs li.failed { color: var(--bad); font-weight: 600; }
ol.figs li.assumed::after { content: "  ← progression assumed"; color: var(--accent); font-family: var(--sans); }
ol.figs li.hint::after { content: "  ← compiles with progression here"; color: var(--good); font-family: var(--sans); }
.trace { display: flex; gap: 10px; overflow-x: auto; padding-bottom: 6px; }
.step { flex: 0 0 auto; border: 1px solid var(--line); border-radius: 6px; padding: 6px 8px; }
.step.failed { border-color: var(--bad); background: var(--bad-soft); }
.step .cap { font-size: 11px; color: var(--muted); max-width: 22em; overflow-wrap: anywhere; margin-bottom: 4px; }
.grid { font-family: var(--mono); font-size: 11.5px; line-height: 1.45; white-space: pre; }
.grid .L { color: var(--lark); }
.grid .R { color: var(--robin); }
.grid .mv { font-weight: 600; text-decoration: underline; }
.grid .off { background: var(--bad-soft); }
ul.plain { margin: 0; padding-left: 1.2em; font-family: var(--mono); font-size: 12px; }
.empty { padding: 16px; color: var(--muted); }
.legend { color: var(--muted); font-size: 12px; }
</style>

<header>
  <h1>Rubric failures</h1>
  <span class="headline" id="headline"></span>
</header>
<div class="filters">
  <label for="scope">Scope <select id="scope">
    <option value="in">In scope</option><option value="deferred">Deferred</option><option value="all">All</option>
  </select></label>
  <label for="outcome">Outcome <select id="outcome"><option value="">Any</option></select></label>
  <label for="coreOnly" id="coreLabel"><input type="checkbox" id="coreOnly"> Core set only</label>
  <label for="hintOnly"><input type="checkbox" id="hintOnly"> Compiles with progression moved</label>
  <label for="q">Find <input type="search" id="q" placeholder="title or id"></label>
</div>
<div class="panes">
  <section class="pane"><h3>Causes</h3><div class="list" id="causes"></div></section>
  <section class="pane"><h3 id="dancesHead">Dances</h3><div class="list" id="dances"></div></section>
  <section class="pane" id="detail"><div class="empty">Pick a dance to see its figures, the set after each one, and where it failed.</div></section>
</div>

<script src="report.js"></script>
<script>
(function () {
  const data = window.RUBRIC_REPORT;
  const $ = (id) => document.getElementById(id);
  if (!data) { $('detail').innerHTML = '<div class="empty">report.js did not load. Keep it beside this page.</div>'; return; }
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const dances = data.dances;
  // A dance's route: its Caller's Box id, or its position when it has none.
  dances.forEach((d, i) => { d.key = d.id == null ? 'n' + i : String(d.id); });
  $('headline').textContent = data.headline || '';
  if (!data.hasCore) $('coreLabel').hidden = true;
  [...new Set(dances.map((d) => d.outcome))].sort().forEach((o) => {
    const opt = document.createElement('option'); opt.value = o; opt.textContent = o; $('outcome').appendChild(opt);
  });
  let cause = null, current = null;

  function filtered() {
    const scope = $('scope').value, outcome = $('outcome').value, q = $('q').value.trim().toLowerCase();
    return dances.filter((d) =>
      (scope === 'all' || (scope === 'in') === d.inScope) &&
      (!outcome || d.outcome === outcome) &&
      (!$('coreOnly').checked || d.core) &&
      (!$('hintOnly').checked || (d.placementHint && d.placementHint.length)) &&
      (!q || (d.title || '').toLowerCase().includes(q) || String(d.id) === q));
  }

  function renderCauses() {
    const groups = new Map();
    for (const d of filtered()) {
      const g = groups.get(d.signature) || { n: 0, core: 0 };
      g.n++; if (d.core) g.core++; groups.set(d.signature, g);
    }
    const rows = [...groups.entries()].sort((a, b) => b[1].n - a[1].n || a[0].localeCompare(b[0]));
    if (cause !== null && !groups.has(cause)) cause = null;
    const total = rows.reduce((t, r) => t + r[1].n, 0);
    const item = (key, label, g) => `<button class="item" data-cause="${esc(key)}" aria-current="${cause === key}">
      <span class="count"><b>${g.n}</b>${data.hasCore && g.core ? `<br>${g.core} core` : ''}</span><span class="cause">${esc(label)}</span></button>`;
    $('causes').innerHTML = item('', 'All causes', { n: total, core: rows.reduce((t, r) => t + r[1].core, 0) }).replace(`aria-current="false"`, `aria-current="${cause === null}"`) +
      rows.map(([k, g]) => item(k, k, g)).join('');
    $('causes').querySelectorAll('.item').forEach((b) => b.onclick = () => { cause = b.dataset.cause || null; render(); });
  }

  function renderDances() {
    const list = filtered().filter((d) => cause === null || d.signature === cause);
    $('dancesHead').textContent = `Dances (${list.length})`;
    $('dances').innerHTML = list.length ? list.slice(0, 600).map((d) => `<button class="item dance-item" data-key="${esc(d.key)}" aria-current="${current === d}">
      <span>${esc(d.title)} <span class="legend">#${esc(d.id)}</span></span>
      <span>${d.core ? '<span class="tag core">core</span> ' : ''}${d.placementHint && d.placementHint.length ? '<span class="tag">placement</span>' : ''}</span></button>`).join('') +
      (list.length > 600 ? `<div class="empty">Showing 600 of ${list.length}. Narrow the filters to see the rest.</div>` : '')
      : '<div class="empty">No dances match these filters.</div>';
    $('dances').querySelectorAll('.item').forEach((b) => b.onclick = () => { location.hash = 'd' + encodeURIComponent(b.dataset.key); });
  }

  function gridHtml(rows, marks) {
    return rows.map((row) => row.split(' ').map((cell) => {
      if (cell === '.') return '  .   ';
      const label = cell.replace(/[\^v<>~*]+$/, '');
      const cls = [cell[0], marks.moved && marks.moved.has(label) ? 'mv' : '', marks.off && marks.off.has(label.replace(/[12]-/, '-')) ? 'off' : ''].join(' ');
      return `<span class="${cls}">${esc(cell.padEnd(6))}</span>`;
    }).join(' ')).join('\n');
  }

  function renderDetail(d) {
    if (!d) { $('detail').innerHTML = '<div class="empty">Pick a dance to see its figures, the set after each one, and where it failed.</div>'; return; }
    const hint = new Set(d.placementHint || []);
    const phrases = d.phrases.length ? d.phrases.map((p) => p.lines.map((l, i) =>
      `<span class="name">${i ? '' : esc(p.name)}</span><span>${esc(l)}</span>`).join('')).join('') : '<span></span><span class="legend">The source carried no figure lines.</span>';
    const figs = d.figures.map((f, i) => `<li class="${[i === d.failedAt ? 'failed' : '', i === d.assumedProgressionAt ? 'assumed' : '', hint.has(i) ? 'hint' : ''].join(' ')}">${esc(f)}</li>`).join('');
    const off = new Set((d.offDancers || []).map((s) => s.split(':')[0]));
    const steps = d.trace.map((s) => `<div class="step"><div class="cap">${s.index === null ? 'Start' : `After ${s.index + 1}. ${esc((d.figures[s.index] || '').split('(')[0])}`}</div>
      <div class="grid">${gridHtml(s.grid, { moved: new Set(s.moved || []) })}</div></div>`);
    if (d.failedAt !== null && d.failedAt !== undefined) {
      steps.push(`<div class="step failed"><div class="cap">${d.failedAt + 1}. ${esc((d.figures[d.failedAt] || '').split('(')[0])} ${d.outcome === 'crashed' ? 'threw' : 'refused'}</div><div class="grid legend">${esc(d.signature)}</div></div>`);
    }
    const mismatch = d.expected ? `<div><h3>End state</h3><div class="trace">
      <div class="step"><div class="cap">Expected</div><div class="grid">${gridHtml(d.expected, { off })}</div></div>
      <div class="step failed"><div class="cap">Actual (${esc(d.mismatchClass)})</div><div class="grid">${gridHtml(d.actual, { off })}</div></div></div>
      ${d.offDancers ? `<ul class="plain">${d.offDancers.map((s) => `<li>${esc(s)}</li>`).join('')}</ul>` : ''}</div>` : '';
    const warnings = d.warnings.length ? `<div><h3>Warnings</h3><ul class="plain">${d.warnings.map((w) => `<li>${w.at === null ? '' : `figure ${w.at + 1}: `}${esc(w.message)}</li>`).join('')}</ul></div>` : '';
    $('detail').innerHTML = `<div class="detail">
      <div><h2>${esc(d.title)}</h2><div class="meta">
        <a href="https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=${encodeURIComponent(d.id)}" target="_blank" rel="noopener">Caller's Box #${esc(d.id)}</a>
        <span class="tag bad">${esc(d.outcome)}</span>${d.core ? '<span class="tag core">core</span>' : ''}${d.inScope ? '' : '<span class="tag">deferred</span>'}
        ${hint.size ? `<span class="tag">compiles with progression on ${[...hint].map((i) => i + 1).join(', ')}</span>` : (d.placementHint ? '<span class="legend">No other progression placement compiles.</span>' : '')}
      </div></div>
      ${d.detail ? `<div class="why">${esc(d.detail)}</div>` : ''}
      ${d.diagnosisError ? `<div class="why">Re-running this dance for the report failed: ${esc(d.diagnosisError)}</div>` : ''}
      <div class="cols"><div><h3>Caller's Box lines</h3><div class="phrase">${phrases}</div></div>
        <div><h3>Danced as</h3><ol class="figs">${figs}</ol></div></div>
      ${steps.length ? `<div><h3>The set after each figure</h3><p class="legend">Top of the set is row 0. L = lark, R = robin, then couple number and couple letter; the arrow is facing, * is standing out. Underlined dancers moved in that figure.</p><div class="trace">${steps.join('')}</div></div>` : ''}
      ${mismatch}${warnings}</div>`;
  }

  function render() {
    let key = null;
    try { key = location.hash.startsWith('#d') ? decodeURIComponent(location.hash.slice(2)) : null; } catch (_) {}
    current = key ? dances.find((d) => d.key === key) || null : null;
    renderCauses(); renderDances(); renderDetail(current);
  }
  ['scope', 'outcome', 'coreOnly', 'hintOnly'].forEach((id) => $(id).onchange = () => { cause = null; render(); });
  $('q').oninput = render;
  window.addEventListener('hashchange', () => {
    render();
    // Stacked on a narrow screen, the dance opens below both lists.
    if (current && window.matchMedia('(max-width: 1000px)').matches) $('detail').scrollIntoView();
  });
  render();
})();
</script>
''';
