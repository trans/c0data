import * as vscode from "vscode";

// Unicode Control Pictures for C0DATA (the canonical characters, always in the file)
const CONTROL_PICTURES = [
  "\u241C", // FS — file separator
  "\u241D", // GS — group separator
  "\u241E", // RS — record separator
  "\u241F", // US — unit separator
  "\u2401", // SOH — header
  "\u2402", // STX — start of text
  "\u2403", // ETX — end of text
  "\u2404", // EOT — end of transmission
  "\u2405", // ENQ — reference
  "\u2410", // DLE — escape
  "\u241A", // SUB — substitution
];

// Built-in glyph sets for display. Each maps the 11 control pictures to
// presentation characters. The file always contains Control Pictures;
// these are CSS-only overlays.
const GLYPH_SETS: Record<string, string[]> = {
  moon: [
    "◆", // FS — solid diamond
    "◇", // GS — open diamond
    "▸", // RS — small triangle
    "·", // US — middle dot
    "‡", // SOH — double dagger
    "◖", // STX — left half circle (alt: ⟬ U+27EC)
    "◗", // ETX — right half circle (alt: ⟭ U+27ED)
    "■", // EOT — black square
    "§", // ENQ — section sign
    "⧵", // DLE — reverse solidus
    "⇄", // SUB — swap arrows
  ],
};

// Order of the 11 codes in a glyph set array
const CODE_KEYS = ["FS", "GS", "RS", "US", "SOH", "STX", "ETX", "EOT", "ENQ", "DLE", "SUB"];

let activeGlyphSet: string | null = null; // null = standard (no decorations)

type FormatMode = "spaced" | "aligned" | "compact";
let formatMode: FormatMode = "spaced";

/**
 * Load custom glyph sets from user settings and merge with built-ins.
 */
function loadGlyphSets(): void {
  const config = vscode.workspace.getConfiguration("c0data");
  const custom = config.get<Record<string, Record<string, string>>>("glyphSets", {});

  for (const [name, mapping] of Object.entries(custom)) {
    const glyphs = CODE_KEYS.map((key, i) => mapping[key] ?? CONTROL_PICTURES[i]);
    GLYPH_SETS[name] = glyphs;
  }
}

// --- Glyph decorations (CSS presentation layer) ---

// One decoration type per control picture → display glyph mapping.
// The decoration hides the original character and shows the replacement.
let glyphDecorationTypes: vscode.TextEditorDecorationType[] = [];

function createGlyphDecorations(glyphs: string[]): vscode.TextEditorDecorationType[] {
  return glyphs.map((glyph) =>
    vscode.window.createTextEditorDecorationType({
      opacity: "0",
      letterSpacing: "-1ch",
      before: {
        contentText: glyph,
      },
    })
  );
}

function disposeGlyphDecorations(): void {
  for (const dec of glyphDecorationTypes) {
    dec.dispose();
  }
  glyphDecorationTypes = [];
}

function updateGlyphDecorations(editor: vscode.TextEditor | undefined): void {
  if (!editor || editor.document.languageId !== "c0data") return;

  // If no glyph set active, clear all decorations
  if (!activeGlyphSet) {
    for (const dec of glyphDecorationTypes) {
      editor.setDecorations(dec, []);
    }
    return;
  }

  const text = editor.document.getText();

  for (let idx = 0; idx < CONTROL_PICTURES.length; idx++) {
    if (idx >= glyphDecorationTypes.length) break;

    const cp = CONTROL_PICTURES[idx];
    const ranges: vscode.Range[] = [];

    for (let i = 0; i < text.length; i++) {
      if (text[i] === cp) {
        const pos = editor.document.positionAt(i);
        ranges.push(new vscode.Range(pos, pos.translate(0, 1)));
      }
    }

    editor.setDecorations(glyphDecorationTypes[idx], ranges);
  }
}

// --- Formatter (always operates on standard Control Pictures) ---

const US = "\u241F";
const RS = "\u241E";
const GS = "\u241D";
const FS = "\u241C";
const SOH = "\u2401";
const EOT = "\u2404";
const DLE = "\u2410";

const PREFIXES = new Set([FS, GS, RS, SOH, US]);

interface TableGroup {
  lines: TableLine[];
}

interface TableLine {
  lineIndex: number;
  prefix: string;
  fields: string[];
}

function parseTableGroups(document: vscode.TextDocument): TableGroup[] {
  const groups: TableGroup[] = [];
  let current: TableGroup | null = null;
  let expectedCols = -1;

  for (let i = 0; i < document.lineCount; i++) {
    const text = document.lineAt(i).text;
    const trimmed = text.trim();

    if (
      trimmed === "" ||
      trimmed.startsWith(GS) ||
      trimmed.startsWith(FS) ||
      trimmed.startsWith(EOT)
    ) {
      if (current && current.lines.length > 0) groups.push(current);
      current = null;
      expectedCols = -1;
      continue;
    }

    if (trimmed.startsWith(SOH) || trimmed.startsWith(RS)) {
      const parsed = parseTableLine(i, text);
      if (!parsed || parsed.fields.length < 2) {
        if (current && current.lines.length > 0) groups.push(current);
        current = null;
        expectedCols = -1;
        continue;
      }

      const colCount = parsed.fields.length;

      if (current === null || (expectedCols !== -1 && colCount !== expectedCols)) {
        if (current && current.lines.length > 0) groups.push(current);
        current = { lines: [] };
        expectedCols = colCount;
      }

      current.lines.push(parsed);
    } else {
      if (current && current.lines.length > 0) groups.push(current);
      current = null;
      expectedCols = -1;
    }
  }

  if (current && current.lines.length > 0) groups.push(current);
  return groups;
}

function parseTableLine(lineIndex: number, text: string): TableLine | null {
  let markerPos = -1;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === " " || text[i] === "\t") continue;
    if (text[i] === SOH || text[i] === RS) {
      markerPos = i;
      break;
    }
    return null;
  }
  if (markerPos === -1) return null;

  const prefix = text.slice(0, markerPos + 1);
  const rest = text.slice(markerPos + 1);

  const fields: string[] = [];
  let field = "";
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === DLE && i + 1 < rest.length) {
      field += rest[i] + rest[i + 1];
      i++;
    } else if (rest[i] === US) {
      fields.push(field.trim());
      field = "";
    } else {
      field += rest[i];
    }
  }
  fields.push(field.trim());

  if (fields.length < 2) return null;

  return { lineIndex, prefix, fields };
}

function formatSpacing(
  document: vscode.TextDocument,
  spaced: boolean,
  tableLineIndices: Set<number>
): vscode.TextEdit[] {
  const edits: vscode.TextEdit[] = [];

  for (let i = 0; i < document.lineCount; i++) {
    if (tableLineIndices.has(i)) continue;

    const line = document.lineAt(i);
    const text = line.text;
    if (text.trim() === "") continue;

    let wsEnd = 0;
    while (wsEnd < text.length && (text[wsEnd] === " " || text[wsEnd] === "\t")) {
      wsEnd++;
    }
    const indent = text.slice(0, wsEnd);

    let glyphEnd = wsEnd;
    while (glyphEnd < text.length && PREFIXES.has(text[glyphEnd])) {
      glyphEnd++;
    }
    if (glyphEnd > wsEnd && glyphEnd < text.length && text[glyphEnd] === SOH) {
      glyphEnd++;
    }

    if (glyphEnd === wsEnd) continue;
    if (glyphEnd === text.length) continue;

    const glyphs = text.slice(wsEnd, glyphEnd);
    const rest = text.slice(glyphEnd);

    let newText: string;
    if (spaced) {
      newText = indent + glyphs + " " + rest.trimStart();
    } else {
      newText = indent + glyphs + rest.trimStart();
    }

    if (text !== newText) {
      edits.push(vscode.TextEdit.replace(line.range, newText));
    }
  }

  return edits;
}

function formatAligned(document: vscode.TextDocument, spaced: boolean): vscode.TextEdit[] {
  const groups = parseTableGroups(document);
  const edits: vscode.TextEdit[] = [];
  const tableLineIndices = new Set<number>();
  const sp = spaced ? " " : "";

  for (const group of groups) {
    if (group.lines.length < 1) continue;

    const colCount = group.lines[0].fields.length;

    const maxWidths: number[] = new Array(colCount).fill(0);
    for (const line of group.lines) {
      for (let col = 0; col < line.fields.length; col++) {
        maxWidths[col] = Math.max(maxWidths[col], line.fields[col].length);
      }
    }

    for (const line of group.lines) {
      tableLineIndices.add(line.lineIndex);
      let newText = line.prefix + sp;
      for (let col = 0; col < line.fields.length; col++) {
        const field = line.fields[col];
        if (col < line.fields.length - 1) {
          newText += field.padEnd(maxWidths[col]) + sp + US + sp;
        } else {
          newText += field;
        }
      }

      const lineObj = document.lineAt(line.lineIndex);
      if (lineObj.text !== newText) {
        edits.push(vscode.TextEdit.replace(lineObj.range, newText));
      }
    }
  }

  if (spaced) {
    edits.push(...formatSpacing(document, true, tableLineIndices));
  }

  return edits;
}

function formatCompact(document: vscode.TextDocument): vscode.TextEdit[] {
  const groups = parseTableGroups(document);
  const edits: vscode.TextEdit[] = [];
  const tableLineIndices = new Set<number>();

  for (const group of groups) {
    for (const line of group.lines) {
      tableLineIndices.add(line.lineIndex);
      let newText = line.prefix;
      for (let col = 0; col < line.fields.length; col++) {
        newText += line.fields[col];
        if (col < line.fields.length - 1) newText += US;
      }

      const lineObj = document.lineAt(line.lineIndex);
      if (lineObj.text !== newText) {
        edits.push(vscode.TextEdit.replace(lineObj.range, newText));
      }
    }
  }

  edits.push(...formatSpacing(document, false, tableLineIndices));

  return edits;
}

// --- Input method: \gs expansion ---

// Backslash code names → Control Pictures
const BACKSLASH_CODES: Record<string, string> = {
  fs:  "\u241C",
  gs:  "\u241D",
  rs:  "\u241E",
  us:  "\u241F",
  soh: "\u2401",
  stx: "\u2402",
  etx: "\u2403",
  eot: "\u2404",
  enq: "\u2405",
  dle: "\u2410",
  sub: "\u241A",
};

// Sorted longest-first so we match "stx" before "s"
const CODE_NAMES_PATTERN = Object.keys(BACKSLASH_CODES)
  .sort((a, b) => b.length - a.length)
  .join("|");

// Matches \code at end of a region, preceded by non-backslash (or start of line)
const EXPANSION_RE = new RegExp(`(?:^|[^\\\\])\\\\(${CODE_NAMES_PATTERN})$`);

// Matches \\code (escaped — should become literal \code)
const ESCAPE_RE = new RegExp(`\\\\\\\\(${CODE_NAMES_PATTERN})$`);

/**
 * Check for \code sequences and expand them when a trigger character
 * (space, tab, enter, or another \) is typed.
 */
function handleExpansion(event: vscode.TextDocumentChangeEvent): void {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document !== event.document) return;
  if (event.document.languageId !== "c0data") return;
  if (event.contentChanges.length === 0) return;

  // Only act on single-character insertions (typing)
  const change = event.contentChanges[0];
  if (change.text.length !== 1) return;

  const trigger = change.text;
  const isTrigger = trigger === " " || trigger === "\t" || trigger === "\n" ||
                    trigger === "\\" || trigger === "\u241C" || trigger === "\u241D" ||
                    trigger === "\u241E" || trigger === "\u241F";

  if (!isTrigger) return;

  // Get text before the trigger (the line up to the insertion point)
  const pos = change.range.start;
  const line = event.document.lineAt(pos.line).text;
  // Text before the just-typed trigger character
  const before = line.slice(0, pos.character);

  // Check for \\code (escaped) first
  const escMatch = ESCAPE_RE.exec(before);
  if (escMatch) {
    const codeName = escMatch[1];
    const startCol = pos.character - codeName.length - 2; // \\code
    const range = new vscode.Range(pos.line, startCol, pos.line, pos.character);
    // Replace \\code with \code (literal)
    editor.edit((edit) => {
      edit.replace(range, "\\" + codeName);
    }, { undoStopBefore: false, undoStopAfter: true });
    return;
  }

  // Check for \code (expansion)
  const expMatch = EXPANSION_RE.exec(before);
  if (expMatch) {
    const codeName = expMatch[1];
    const glyph = BACKSLASH_CODES[codeName];
    if (!glyph) return;

    const startCol = pos.character - codeName.length - 1; // \code
    const range = new vscode.Range(pos.line, startCol, pos.line, pos.character);
    // Replace \code with the glyph (trigger char stays)
    editor.edit((edit) => {
      edit.replace(range, glyph);
    }, { undoStopBefore: false, undoStopAfter: true });
  }
}

// --- Activation ---

export function activate(context: vscode.ExtensionContext) {
  loadGlyphSets();

  // Document formatter (Shift+Alt+F)
  context.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider("c0data", {
      provideDocumentFormattingEdits(document): vscode.TextEdit[] {
        switch (formatMode) {
          case "spaced":
            return formatAligned(document, true);
          case "aligned":
            return formatAligned(document, false);
          case "compact":
            return formatCompact(document);
        }
      },
    })
  );

  // Cycle format mode
  context.subscriptions.push(
    vscode.commands.registerCommand("c0data.toggleAlignment", () => {
      const modes: FormatMode[] = ["spaced", "aligned", "compact"];
      const idx = modes.indexOf(formatMode);
      formatMode = modes[(idx + 1) % modes.length];
      const labels = { spaced: "Spaced", aligned: "Aligned", compact: "Compact" };
      vscode.window.showInformationMessage(`C0DATA format mode: ${labels[formatMode]}`);
    })
  );

  // Explicit format commands
  const applyEdits = (edits: vscode.TextEdit[]) => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== "c0data" || edits.length === 0) return;
    const wsEdit = new vscode.WorkspaceEdit();
    for (const edit of edits) {
      wsEdit.replace(editor.document.uri, edit.range, edit.newText);
    }
    vscode.workspace.applyEdit(wsEdit);
  };

  context.subscriptions.push(
    vscode.commands.registerCommand("c0data.alignColumns", () => {
      const editor = vscode.window.activeTextEditor;
      if (editor) applyEdits(formatAligned(editor.document, true));
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("c0data.compactColumns", () => {
      const editor = vscode.window.activeTextEditor;
      if (editor) applyEdits(formatCompact(editor.document));
    })
  );

  // Glyph set switching — pure CSS decoration overlay
  context.subscriptions.push(
    vscode.commands.registerCommand("c0data.switchGlyphs", async () => {
      const sets = ["standard", ...Object.keys(GLYPH_SETS)];
      const current = activeGlyphSet ?? "standard";
      const pick = await vscode.window.showQuickPick(sets, {
        placeHolder: `Current: ${current}`,
        title: "Select glyph set",
      });
      if (!pick || pick === current) return;

      // Dispose old decorations
      disposeGlyphDecorations();

      if (pick === "standard") {
        activeGlyphSet = null;
      } else {
        activeGlyphSet = pick;
        glyphDecorationTypes = createGlyphDecorations(GLYPH_SETS[pick]);
      }

      // Apply to all visible editors
      for (const editor of vscode.window.visibleTextEditors) {
        updateGlyphDecorations(editor);
      }

      vscode.window.showInformationMessage(`C0DATA glyphs: ${pick}`);
    })
  );

  // --- Input method ---

  // \code expansion on trigger characters
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((event) => {
      handleExpansion(event);
    })
  );

  // Completion provider: type \ and see all codes
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider("c0data", {
      provideCompletionItems(document, position) {
        const lineText = document.lineAt(position.line).text;
        const before = lineText.slice(0, position.character);
        if (!before.endsWith("\\")) return [];

        return Object.entries(BACKSLASH_CODES).map(([name, glyph]) => {
          const item = new vscode.CompletionItem(
            `\\${name}`,
            vscode.CompletionItemKind.Text
          );
          item.detail = `${glyph} (${CODE_KEYS[CONTROL_PICTURES.indexOf(glyph)]})`;
          item.insertText = name;
          // Replace the \ that triggered completion + insert the code name,
          // then the filterText matches what the user is typing
          item.range = new vscode.Range(
            position.line, position.character - 1,
            position.line, position.character
          );
          item.insertText = glyph;
          return item;
        });
      },
    }, "\\")
  );

  // Keep decorations updated
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor((editor) => {
      updateGlyphDecorations(editor);
    })
  );

  let decorTimeout: ReturnType<typeof setTimeout> | undefined;
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((event) => {
      if (!activeGlyphSet) return;
      const editor = vscode.window.activeTextEditor;
      if (editor && event.document === editor.document) {
        if (decorTimeout) clearTimeout(decorTimeout);
        decorTimeout = setTimeout(() => updateGlyphDecorations(editor), 50);
      }
    })
  );
}

export function deactivate(): void {
  disposeGlyphDecorations();
}
