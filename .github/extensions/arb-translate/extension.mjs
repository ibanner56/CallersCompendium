// Extension: arb-translate
//
// Assisted ARB localization for Caller's Compendium. These tools let the
// Copilot session model (Claude) act as the translation engine while the
// deterministic, security-critical halves run in tools/ci/arb_translate.py:
//
//   arb_translate_plan     -> extract the untranslated batch for a locale
//                             (English source + description + placeholders +
//                             dance-domain glossary hints) for the model to
//                             translate.
//   arb_translate_apply    -> merge the model's translations into
//                             app_<locale>.arb (values only) and immediately
//                             validate them (placeholder/ICU parity + OWASP
//                             content safety). Reports errors to fix.
//   arb_translate_validate -> validate a locale (or --all) against the template.
//
// This realizes "translate with Claude via Copilot" without any third-party
// translation API or extra billing: the model does the words; Python guards the
// contract. After a successful apply, regenerate Dart with `fvm flutter gen-l10n`.

import { joinSession } from "@github/copilot-sdk/extension";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";

const execFileAsync = promisify(execFile);

// .github/extensions/arb-translate/extension.mjs -> repo root is three up.
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const CLI = "tools/ci/arb_translate.py";

/** Run the ARB CLI from the repo root. Returns {code, stdout, stderr}. */
async function runCli(args) {
    try {
        const { stdout, stderr } = await execFileAsync("python3", [CLI, ...args], {
            cwd: REPO_ROOT,
            maxBuffer: 16 * 1024 * 1024,
        });
        return { code: 0, stdout, stderr };
    } catch (err) {
        return {
            code: typeof err.code === "number" ? err.code : 1,
            stdout: err.stdout ?? "",
            stderr: err.stderr ?? String(err),
        };
    }
}

const failure = (text) => ({ textResultForLlm: text, resultType: "failure" });

const PLAN_GUIDANCE = [
    "Translate each item's `source` into the requested locale and return the result to arb_translate_apply.",
    "Rules:",
    "- Preserve EVERY placeholder exactly: `{name}` tokens and ICU `{n, plural, ...}` / `{n, select, ...}` argument names must appear unchanged. You MAY change plural branch categories to fit the target language (e.g. add `zero`/`few`/`many`); always keep an `other` branch.",
    "- Do not add, drop, or rename any placeholder — the validator will reject it.",
    "- Copy items in `doNotTranslate` verbatim (brand/proper nouns).",
    "- Honor each item's `glossary` hints so dance jargon takes its dance meaning (e.g. `caller`, `set`, `figure`, `program`), not an everyday homograph.",
    "- Use the item `description` for tone/length/context; keep UI strings concise.",
    "- Output plain translated text only — never HTML, scripts, or URIs, and no control/bidirectional-override characters.",
].join("\n");

const session = await joinSession({
    tools: [
        {
            name: "arb_translate_plan",
            description:
                "Extract the strings still needing translation for a locale as a JSON batch " +
                "(English source, description, declared placeholders, and dance-domain glossary " +
                "hints). Step 1 of the assisted-translation workflow: call this, translate the " +
                "returned items yourself, then pass them to arb_translate_apply.",
            parameters: {
                type: "object",
                properties: {
                    locale: {
                        type: "string",
                        description:
                            "Target locale in gen-l10n underscore form (e.g. 'fr', 'pt_BR', 'zh_Hant').",
                    },
                    limit: {
                        type: "number",
                        description: "Optional cap on the number of items returned (0 = all).",
                    },
                },
                required: ["locale"],
            },
            skipPermission: true, // read-only
            handler: async (args) => {
                const cliArgs = ["extract", "--locale", String(args.locale)];
                if (args.limit) cliArgs.push("--limit", String(args.limit));
                const { code, stdout, stderr } = await runCli(cliArgs);
                if (code !== 0) return failure(`arb_translate extract failed:\n${stderr}`);
                return `${PLAN_GUIDANCE}\n\nBatch:\n${stdout}`;
            },
        },
        {
            name: "arb_translate_apply",
            description:
                "Merge translated strings into app_<locale>.arb (values only; keys and @key " +
                "metadata come from the template) and validate them against the English template " +
                "(placeholder/ICU parity, @@locale, content safety). Step 2 of the workflow. " +
                "On success, run `fvm flutter gen-l10n` (from app/) and commit the ARB plus the " +
                "regenerated app_localizations*.dart.",
            parameters: {
                type: "object",
                properties: {
                    locale: {
                        type: "string",
                        description: "Target locale in underscore form (e.g. 'fr', 'pt_BR').",
                    },
                    translations: {
                        type: "object",
                        description:
                            "Map of ARB key -> translated string. Provide this OR `items`.",
                        additionalProperties: { type: "string" },
                    },
                    items: {
                        type: "array",
                        description:
                            "Alternative to `translations`: array of {key, translation} objects.",
                        items: {
                            type: "object",
                            properties: {
                                key: { type: "string" },
                                translation: { type: "string" },
                            },
                            required: ["key", "translation"],
                        },
                    },
                },
                required: ["locale"],
            },
            handler: async (args) => {
                const payload =
                    args.translations && Object.keys(args.translations).length
                        ? args.translations
                        : args.items
                          ? { items: args.items }
                          : null;
                if (!payload) {
                    return failure(
                        "Provide `translations` (key->string) or `items` ([{key,translation}]).",
                    );
                }
                let dir;
                try {
                    dir = await mkdtemp(join(tmpdir(), "arb-apply-"));
                    const input = join(dir, "batch.json");
                    await writeFile(input, JSON.stringify(payload), "utf-8");
                    const apply = await runCli([
                        "apply",
                        "--locale",
                        String(args.locale),
                        "--input",
                        input,
                    ]);
                    if (apply.code !== 0) {
                        return failure(
                            `apply failed (no file written):\n${apply.stderr || apply.stdout}`,
                        );
                    }
                    const check = await runCli(["validate", "--locale", String(args.locale)]);
                    const report = `${apply.stdout.trim()}\n\n${check.stdout.trim()}`;
                    if (check.code !== 0) {
                        return failure(
                            "Translations were written but FAILED validation — fix these and " +
                                `call arb_translate_apply again:\n${report}`,
                        );
                    }
                    return (
                        `${report}\n\nNext: from app/, run \`fvm flutter gen-l10n\`, then ` +
                        `\`fvm dart format .\`, and commit app_${args.locale}.arb with the ` +
                        `regenerated app_localizations*.dart.`
                    );
                } finally {
                    if (dir) await rm(dir, { recursive: true, force: true });
                }
            },
        },
        {
            name: "arb_translate_validate",
            description:
                "Validate one locale's ARB (or every app_*.arb with `all: true`) against the " +
                "English template: key subset, ICU/placeholder parity (locale-specific plural " +
                "categories allowed), @@locale agreement, metadata integrity, and OWASP content " +
                "safety. Use before committing or when reviewing a contributed translation.",
            parameters: {
                type: "object",
                properties: {
                    locale: { type: "string", description: "Locale to validate (e.g. 'fr')." },
                    all: {
                        type: "boolean",
                        description: "Validate every app_*.arb instead of a single locale.",
                    },
                },
            },
            skipPermission: true, // read-only
            handler: async (args) => {
                const cliArgs = ["validate"];
                if (args.all) cliArgs.push("--all");
                else if (args.locale) cliArgs.push("--locale", String(args.locale));
                else return failure("Pass `locale` or `all: true`.");
                const { code, stdout, stderr } = await runCli(cliArgs);
                const out = `${stdout}${stderr}`.trim();
                return code === 0 ? out : failure(out);
            },
        },
    ],
});

await session.log("arb-translate extension ready (plan / apply / validate).");
