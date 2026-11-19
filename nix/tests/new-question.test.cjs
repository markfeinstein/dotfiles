// QuickAdd question script tests with mocked Obsidian editor/vault APIs.
// Shares question-log-cases.json with the Neovim obsidian-capture check.
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { test } = require("node:test");

const script = require(process.env.QUESTION_SCRIPT || resolve(__dirname, "../../obsidian/quickadd/new-question.js"));
const casesPath = process.env.DOTFILES_OBSIDIAN_LOG_CASES || resolve(__dirname, "question-log-cases.json");
const cases = JSON.parse(readFileSync(casesPath, "utf8"));

let clock = [2026, 10, 12, 10, 30];
const RealDate = Date;
global.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : clock)); }
};
function at(time) {
  const [hour, minute] = time.split(":").map(Number);
  clock = [2026, 10, 12, hour, minute];
}

function editorFor(lines) {
  let value = lines.join("\n");
  let cursor = { line: lines.length - 1, ch: 0 };
  return {
    getValue: () => value,
    getCursor: () => cursor,
    getLine: (line) => value.split("\n")[line],
    setCursor: (pos) => { cursor = pos; },
    replaceRange(text, from, to = from) {
      const current = value.split("\n");
      const offset = ({ line, ch }) => {
        assert.ok(line >= 0 && line < current.length, "valid editor line");
        assert.ok(ch >= 0 && ch <= current[line].length, "valid editor column");
        return current.slice(0, line).reduce((n, s) => n + s.length + 1, 0) + ch;
      };
      const start = offset(from), end = offset(to);
      value = value.slice(0, start) + text + value.slice(end);
    },
  };
}

function fixture(lines, options = {}) {
  const config = script.configure(options.settings);
  const editor = editorFor(lines);
  const sourcePath = options.sourcePath || `${config.dailyDir}/2026/11-November/2026-11-11-Wednesday.md`;
  const question = options.question || "Why";
  const questionPath = `${config.questionsDir}/${question}.md`;
  const files = new Map([
    [config.template, { content: "---\ntype: question\ndate: {{date}}\nasked_in:\n---\n# {{title}}\n" }],
    [config.questionsDir, {}],
  ]);
  if (options.existing) files.set(questionPath, { path: questionPath, content: "Preserve existing answer" });
  if (options.noTemplate) files.delete(config.template);
  let opened;
  const params = {
    app: {
      workspace: {
        getActiveFile: () => ({ path: sourcePath, extension: "md", basename: sourcePath.split("/").at(-1).slice(0, -3) }),
        activeEditor: options.noEditor ? null : { editor },
        getLeaf: () => ({ openFile: async (file) => { opened = file.path; } }),
      },
      vault: {
        getAbstractFileByPath: (path) => files.get(path),
        read: async (file) => file.content,
        createFolder: async (path) => files.set(path, {}),
        create: async (path, content) => {
          assert.equal(files.has(path), false);
          const file = { path, content };
          files.set(path, file);
          return file;
        },
      },
    },
    quickAddApi: { inputPrompt: async () => options.cancel ? null : `${question}?` },
    obsidian: { Notice: class {} },
  };
  const run = () => script.entry(params, options.settings);
  return { run, files, editor, questionPath, opened: () => opened };
}

function applyChange(input, change) {
  const actual = [...input];
  actual.splice(change.from, change.to - change.from, ...change.lines);
  return actual;
}

for (const example of cases) {
  const body = example.question ? `? [[${example.question}]]` : example.text;
  const entry = `- **${example.time}** - ${body}`;
  test(`line edit: ${example.name}`, () => {
    const change = example.question
      ? script.questionLogEdit(example.input, example.question, example.time, example.heading)
      : script.logEdit(example.input, example.text, example.time, example.heading);
    const actual = applyChange(example.input, change);
    assert.deepEqual(actual, example.expected);
    assert.equal(actual[change.row], entry);
  });
  if (!example.question) continue;
  test(`QuickAdd entry point (mocked editor/vault): ${example.name}`, async () => {
    at(example.time);
    const f = fixture(example.input, { question: example.question, settings: { "Log heading": example.heading } });
    await f.run();
    assert.deepEqual(f.editor.getValue().split("\n"), example.expected);
    assert.equal(f.editor.getLine(f.editor.getCursor().line), entry);
    assert.equal(f.editor.getCursor().ch, entry.length);
    assert.match(f.files.get(f.questionPath).content, /date: 2026-11-11/);
    assert.match(f.files.get(f.questionPath).content, /asked_in: "\[\[2026-11-11-Wednesday\]\]"/);
    assert.equal(f.opened(), undefined);
  });
}

test("defaults match the shared Neovim capture layout and blank settings fall back", () => {
  const expected = {
    questionsDir: "2 - Notes/Knowledge/Questions",
    template: "8 - Resources/Templates/Question.md",
    dailyDir: "1 - Journals",
    logHeading: "## Log",
  };
  assert.deepEqual(script.configure(), expected);
  assert.deepEqual(script.configure({ "Questions folder": "  ", "Log heading": "" }), expected);
  assert.deepEqual(Object.keys(script.settings.options), ["Questions folder", "Question template", "Daily notes folder", "Log heading"]);
});

test("configured folders, template, and heading are used", async () => {
  at("10:30");
  const settings = {
    "Questions folder": "/Questions/",
    "Question template": "Templates/Q.md",
    "Daily notes folder": "Daily",
    "Log heading": "## Activity",
  };
  const f = fixture(["## Activity", "", "- "], { settings, sourcePath: "Daily/2026-11-11.md" });
  await f.run();
  assert.equal(f.questionPath, "Questions/Why.md");
  assert.equal(f.editor.getValue(), "## Activity\n\n- **10:30** - ? [[Why]]");
  assert.match(f.files.get(f.questionPath).content, /date: 2026-11-11/);
});

test("existing questions are linked without overwriting their answers", async () => {
  at("10:30");
  const f = fixture(["## Log", "", "- "], { existing: true });
  await f.run();
  assert.equal(f.files.get(f.questionPath).content, "Preserve existing answer");
  assert.match(f.editor.getValue(), /- \*\*10:30\*\* - \? \[\[Why\]\]/);
});
test("non-daily notes keep cursor-local links", async () => {
  const f = fixture(["# Meeting", "  - "], { sourcePath: "2 - Notes/Meeting.md" });
  await f.run();
  assert.equal(f.editor.getValue(), "# Meeting\n  - ? [[Why]]");
});
for (const sourcePath of [
  "1 - Journals/Daily/2000-01-01-Saturday.md",
  "1 - Journals/Daily/2000-01-01.md",
]) {
  test(`legacy daily note keeps its date and log placement: ${sourcePath}`, async () => {
    at("10:30");
    const f = fixture(["## Log", "", "- "], { sourcePath });
    await f.run();
    assert.equal(f.editor.getValue(), "## Log\n\n- **10:30** - ? [[Why]]");
    assert.match(f.files.get(f.questionPath).content, /date: 2000-01-01/);
  });
}
test("non-daily journals keep cursor-local links and use today", async () => {
  const f = fixture(["# Weekly journal", "  - "], { sourcePath: "1 - Journals/2026/11-November/2026-W46.md" });
  await f.run();
  assert.equal(f.editor.getValue(), "# Weekly journal\n  - ? [[Why]]");
  assert.match(f.files.get(f.questionPath).content, /date: 2026-11-12/);
});
test("no editor still opens the question", async () => {
  const f = fixture(["## Log", "", "- "], { noEditor: true });
  await f.run();
  assert.equal(f.opened(), f.questionPath);
});
for (const option of ["cancel", "noTemplate"]) {
  test(`${option} leaves the source unchanged`, async () => {
    const f = fixture(["## Log", "", "- "], { [option]: true });
    await f.run();
    assert.equal(f.editor.getValue(), "## Log\n\n- ");
    assert.equal(f.files.has(f.questionPath), false);
  });
}
