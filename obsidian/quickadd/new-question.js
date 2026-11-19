// QuickAdd user script: create a Question note from the Question template.
//
// Run by a QuickAdd macro such as "New question". Type the question naturally,
// including the "?": the heading keeps it exactly, and the filename drops
// characters filenames can't hold. Same rules as Neovim's <leader>mq.
//
// It also sets `date` (the daily note's date when run from one, otherwise
// today) and `asked_in` (the note you ran it from). In daily notes it inserts
// "- **HH:mm** - ? [[Question]]" chronologically under the log heading, above
// callouts. Elsewhere it inserts "- ? [[Question]]" at the cursor. Existing
// questions are linked, never overwritten.
//
// Folder, template, and heading defaults match the shared Neovim capture
// defaults; change them in the script's QuickAdd settings for another layout.

const OPTIONS = {
  "Questions folder": {
    type: "text",
    defaultValue: "2 - Notes/Knowledge/Questions",
    description: "Vault-relative folder for question notes",
  },
  "Question template": {
    type: "text",
    defaultValue: "8 - Resources/Templates/Question.md",
    description: "Vault-relative path of the question template",
  },
  "Daily notes folder": {
    type: "text",
    defaultValue: "1 - Journals",
    description: "Vault-relative folder containing daily notes",
  },
  "Log heading": {
    type: "text",
    defaultValue: "## Log",
    description: "Heading under which daily-note links are inserted",
  },
};

// Blank or missing QuickAdd values fall back to the defaults above.
function configure(settings = {}) {
  const value = (name) => {
    const configured = typeof settings[name] === "string" ? settings[name].trim() : "";
    return configured || OPTIONS[name].defaultValue;
  };
  const folder = (name) => value(name).replace(/^\/+|\/+$/g, "");
  return {
    questionsDir: folder("Questions folder"),
    template: folder("Question template"),
    dailyDir: folder("Daily notes folder"),
    logHeading: value("Log heading"),
  };
}

// Filenames can't contain these in Obsidian; the heading keeps the original text.
function toFilename(question) {
  return question
    .replace(/[\\/:*?"<>|#^[\]]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[.\s]+$/, "");
}

function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// Nested and legacy daily notes share an ISO date prefix in the filename.
// Other journals (weekly/monthly) must retain cursor-local question links.
function dailyDate(sourcePath, dailyDir = configure().dailyDir) {
  if (sourcePath && sourcePath.startsWith(dailyDir + "/")) {
    return sourcePath.match(/\/(\d{4}-\d{2}-\d{2})[^/]*\.md$/)?.[1];
  }
}

// The daily note's own date when run from one, otherwise today.
function noteDate(sourcePath, dailyDir) {
  return dailyDate(sourcePath, dailyDir) || today();
}

function yamlQuote(s) {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function render(template, question, date, askedIn) {
  return template
    .split("\n")
    .map((line) => {
      line = line.split("{{date}}").join(date).split("{{title}}").join(question);
      if (askedIn && line === "asked_in:") line = `asked_in: ${yamlQuote(askedIn)}`;
      return line;
    })
    .join("\n");
}

// Match top-level timestamps (bold with dash, or legacy plain/bold/bracketed)
// without mistaking nested notes for log entries.
function logTime(line) {
  const match = line.match(/^[-*]\s+(?:\*\*|\[)?(\d{1,2}):(\d{2})(?:\*\*|\])?(?:\s|$)/);
  if (!match || +match[1] > 23 || +match[2] > 59) return null;
  return +match[1] * 60 + +match[2];
}

function fenceMarker(line) {
  return line.match(/^\s*(`{3,}|~{3,})/)?.[1];
}

function closesFence(line, fence) {
  const close = line.match(/^\s*([`~]+)\s*$/)?.[1];
  return close && close.length >= fence.length && [...close].every((c) => c === fence[0]);
}

// Headings match after trimming and dropping closing hashes, as in Neovim.
function normalizedHeading(line) {
  return line.trim().replace(/\s+#+\s*$/, "");
}

// A zero-based, end-exclusive line edit. Preserve existing blocks and untimed
// history instead of sorting or rewriting the rest of the daily note. Mirrors
// Neovim's mark.obsidian_capture.log_edit; both run the shared log cases.
function logEdit(lines, text, time, heading = configure().logHeading) {
  const entry = `- **${time}** - ${text}`;
  const wanted = normalizedHeading(heading);
  let first, finish = lines.length, fence;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const marker = fenceMarker(line);
    if (fence) {
      if (closesFence(line, fence)) fence = null;
    } else if (marker) {
      fence = marker;
    } else if (first === undefined && normalizedHeading(line) === wanted) {
      first = i + 1;
    } else if (first !== undefined && (/^#+\s/.test(line) || /^>\s*\[!/.test(line))) {
      finish = i;
      break;
    }
  }
  if (first === undefined) {
    const added = lines.length && lines.at(-1) !== "" ? [""] : [];
    added.push(heading, "", entry);
    return { from: lines.length, to: lines.length, lines: added, row: lines.length + added.length - 1 };
  }
  let placeholder, empty = true;
  for (let i = first; i < finish; i++) {
    if (/^[-*]\s*\??\s*$/.test(lines[i])) placeholder ??= i;
    else if (!/^\s*$/.test(lines[i])) empty = false;
  }
  if (empty && placeholder !== undefined) {
    return { from: placeholder, to: placeholder + 1, lines: [entry], row: placeholder };
  }
  let at = finish;
  const now = logTime(entry);
  fence = null;
  for (let i = first; i < finish; i++) {
    const marker = fenceMarker(lines[i]);
    if (fence) {
      if (closesFence(lines[i], fence)) fence = null;
    } else if (marker) {
      fence = marker;
    } else {
      const existing = logTime(lines[i]);
      if (existing !== null && existing > now) {
        at = i;
        break;
      }
    }
  }
  if (at === finish) {
    while (at > first && /^\s*$/.test(lines[at - 1])) at--;
  }
  if (at > first && /^[-*]\s*\??\s*$/.test(lines[at - 1])) {
    return { from: at - 1, to: at, lines: [entry], row: at - 1 };
  }
  const added = [entry];
  let row = at;
  if (empty) {
    added.unshift("");
    row++;
  }
  if (at === finish && finish < lines.length) added.push("");
  return { from: at, to: at, lines: added, row };
}

function questionLogEdit(lines, name, time, heading) {
  return logEdit(lines, `? [[${name}]]`, time, heading);
}

function insertLogLink(editor, name, heading) {
  const lines = editor.getValue().split("\n");
  const now = new Date();
  const time = [now.getHours(), now.getMinutes()].map((n) => String(n).padStart(2, "0")).join(":");
  const change = questionLogEdit(lines, name, time, heading);
  const eof = { line: lines.length - 1, ch: lines.at(-1).length };
  const start = change.from === lines.length ? eof : { line: change.from, ch: 0 };
  const end = change.to === lines.length ? eof : { line: change.to, ch: 0 };
  const replacement = (change.from === lines.length ? "\n" : "") + change.lines.join("\n")
    + (change.to < lines.length ? "\n" : "");
  editor.replaceRange(replacement, start, end);
  editor.setCursor({ line: change.row, ch: editor.getLine(change.row).length });
}

async function run(params, settings) {
  const { app, quickAddApi, obsidian } = params;
  const config = configure(settings);
  const notice = (msg) => new obsidian.Notice(msg);

  const question = (await quickAddApi.inputPrompt("Question", "Why mono-repo?"))?.trim();
  if (!question) return;
  const name = toFilename(question);
  if (!name) {
    notice("New question: that question has no usable filename characters.");
    return;
  }

  const source = app.workspace.getActiveFile();
  const path = `${config.questionsDir}/${name}.md`;
  let file = app.vault.getAbstractFileByPath(path);
  const existed = !!file;

  if (!existed) {
    const template = app.vault.getAbstractFileByPath(config.template);
    if (!template) {
      notice(`New question: template not found: ${config.template}`);
      return;
    }
    const askedIn = source?.extension === "md" ? `[[${source.basename}]]` : null;
    const date = noteDate(source?.path, config.dailyDir);
    const content = render(await app.vault.read(template), question, date, askedIn);
    if (!app.vault.getAbstractFileByPath(config.questionsDir)) {
      await app.vault.createFolder(config.questionsDir);
    }
    file = await app.vault.create(path, content);
  }

  // Daily log placement is independent of the cursor; other notes stay inline.
  const editor = app.workspace.activeEditor?.editor;
  if (editor && source?.extension === "md") {
    if (dailyDate(source.path, config.dailyDir)) {
      insertLogLink(editor, name, config.logHeading);
    } else {
      const { line } = editor.getCursor();
      const text = editor.getLine(line);
      const indent = text.match(/^\s*/)[0];
      const entry = `${indent}- ? [[${name}]]`;
      if (/^\s*[-*]?\s*\??\s*$/.test(text)) {
        editor.replaceRange(entry, { line, ch: 0 }, { line, ch: text.length });
        editor.setCursor({ line, ch: entry.length });
      } else {
        editor.replaceRange(`\n${entry}`, { line, ch: text.length });
        editor.setCursor({ line: line + 1, ch: entry.length });
      }
    }
  } else {
    await app.workspace.getLeaf(false).openFile(file);
  }

  notice(`${existed ? "Linked existing question" : "Created question"}: ${name}`);
}

module.exports = {
  entry: run,
  settings: { name: "New question", author: "dotfiles", options: OPTIONS },
  // Exposed for tests; QuickAdd only calls `entry`.
  configure,
  toFilename,
  noteDate,
  render,
  logEdit,
  questionLogEdit,
};
