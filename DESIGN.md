# C0DATA Specification (Draft)

C0DATA is a data system built on ASCII C0 control codes. It provides concise,
structured representation for common data forms — tabular data, hierarchical
documents, diffs, configuration — using single-byte control codes as delimiters
and UTF-8 text for values.

It sits between human-readable text formats (JSON, YAML, TOML) and opaque
binary formats (protobuf, msgpack). Values remain plain text. Structure is
expressed through control bytes — compact, zero-copy friendly, and inspectable
with minimal tooling.


## Design Principles

- Preserve the original semantics of C0 control codes where possible.
- Only assign codes that genuinely earn their place — leave the rest reserved.
- Support both self-describing (schemaless) and positional (schema-based) usage.
- One control code vocabulary, multiple data shapes (table, document, diff, etc.).


## Assigned Control Codes

| Byte | Hex  | Abbr | C0DATA Role                                  |
|------|------|------|----------------------------------------------|
| 0x01 | 0x01 | SOH  | Header (declares field names for a group)     |
| 0x02 | 0x02 | STX  | Open nested sub-structure / reference scope   |
| 0x03 | 0x03 | ETX  | Close nested sub-structure / reference scope  |
| 0x04 | 0x04 | EOT  | End of document / message                     |
| 0x05 | 0x05 | ENQ  | Reference (enquiry — look up named data)      |
| 0x10 | 0x10 | DLE  | Escape (next byte is literal, not control)    |
| 0x1A | 0x1A | SUB  | Substitution (old → new, used in C0-DIFF)     |
| 0x1C | 0x1C | FS   | File / Database separator                     |
| 0x1D | 0x1D | GS   | Group / Table / Section separator             |
| 0x1E | 0x1E | RS   | Record / Row separator                        |
| 0x1F | 0x1F | US   | Unit / Field separator                        |

All other C0 codes (0x00–0x1F) are currently **reserved**.


## Structural Hierarchy

The four separator codes form a fixed semantic hierarchy:

    FS  >  GS  >  RS  >  US
    file   group  record  field

- **FS (0x1C)** — Top-level container. A database, a file, a document.
- **GS (0x1D)** — A group within a file. A table, a collection, a section.
- **RS (0x1E)** — A record within a group. A row, an entry, a block.
- **US (0x1F)** — A unit within a record. A field, a property, an element.

Text immediately following FS or GS is the **label** (name) for that scope.


## Two Forms: Compact and Pretty

C0DATA has two representations of the same data.

### Compact Form (Canonical)

The wire/storage format. A continuous byte stream. Every byte between control
codes is literal data — including LF, CR, HT, and spaces. No whitespace is
ignored. This is the canonical form.

    [FS]mydb[GS]users[SOH]name[US]amount[RS]Alice Smith[US]1502.30[RS]Bob[US]340.00

### Pretty Form (Human-Readable)

For human inspection and documentation. Uses Unicode Control Pictures
(U+2400 block) for visible glyphs. Whitespace rules:

- LF and CR are ignored (formatting only).
- Whitespace (spaces, tabs) adjacent to control codes is trimmed.
  This allows indentation and spacing for readability.
- Spaces between non-whitespace data characters are preserved
  (e.g., "Alice Smith" keeps its space).
- Inside STX/ETX (␂...␃), all content is preserved verbatim —
  no trimming. This allows STX/ETX to serve as quoting for values
  with significant leading/trailing whitespace.

Example:

    ␜mydb
      ␝users
        ␁name␟amount
        ␞Alice Smith␟1502.30
        ␞Bob␟340.00

To include a literal LF or CR in a value, DLE-escape it: `[DLE][LF]`.

Quoting with STX/ETX:

    ␞␂  leading spaces  ␃␟normal value

A `c0fmt` tool can convert between compact and pretty forms.


## Self-Describing Data (SOH Headers)

When SOH (0x01) appears at the start of a group, it declares field names.
Records that follow are positional against those names — like a CSV header row.

    [GS]users
    [SOH]name[US]amount[US]type
    [RS]Alice[US]1502.30[US]DEPOSIT
    [RS]Bob[US]340.00[US]WITHDRAWAL

Without SOH, data is purely positional (schema known by both sides):

    [GS]
    [RS]Alice[US]1502.30[US]DEPOSIT
    [RS]Bob[US]340.00[US]WITHDRAWAL

**Convention:** When no schema is provided, the first field of a record is
assumed to be its `id`.


## Nested Structures (STX/ETX)

When a field value is itself structured, wrap it in STX/ETX. Inside the
brackets, the separator hierarchy resets — codes are scoped to the
sub-structure.

    [GS]
    [SOH]name[US]amount[US]address
    [RS]Alice[US]1502.30[US][STX]
      [SOH]street[US]city
      [RS]123 Main[US]Springfield
    [ETX]
    [RS]Bob[US]340.00[US][STX]
      [SOH]street[US]city
      [RS]456 Elm[US]Shelbyville
    [ETX]

STX/ETX can nest within themselves for arbitrary depth.

Arrays are simply US-separated values inside STX/ETX:

    [RS]Alice[US][STX]Admin[US]Editor[US]User[ETX][US]1502.30


## References (ENQ)

ENQ (0x05) marks a field value as a reference to data defined elsewhere.
Referenced material must be defined **before** any reference to it (enabling
single-pass parsing with no backtracking).

**Simple reference** (entire group):

    [ENQ]tags

Terminated by the next control code. Looks up the group labeled `tags`.

**Path reference** (record or field within a group):

    [ENQ][STX]tags[US]001[US]label[ETX]

STX/ETX scopes the reference. US separates path segments:
group → record id → field name.

### Example

    [GS]tags
    [SOH]id[US]label
    [RS]001[US]Admin
    [RS]002[US]Editor
    [RS]003[US]User

    [GS]articles
    [SOH]title[US]tags[US]body
    [RS]My Post[US][ENQ]tags[US][ENQ][STX]article[US]001[ETX]


## Document Mode (Depth via GS Repetition)

For hierarchical documents (like Markdown headings), GS can be repeated to
indicate depth level:

    [GS]         = level 1   (like #)
    [GS][GS]     = level 2   (like ##)
    [GS][GS][GS] = level 3   (like ###)
    ...

Within a section, RS marks a content block (paragraph) and US marks
sub-elements (list items) within that block.

Example:

    [FS]My Document
    [GS]Chapter 1
    [RS]First paragraph of chapter one.
    [RS]Second paragraph.
    [GS][GS]Section 1.1
    [RS]Some content here.
    [RS]A list of items:
    [US]First item
    [US]Second item
    [US]Third item
    [GS][GS]Section 1.2
    [GS][GS][GS]Subsection 1.2.1
    [RS]Deep content.
    [GS]Chapter 2
    [GS][GS]Section 2.1
    [RS]And so on.


## Key-Value Configuration

For configuration data (like TOML or INI), each RS is an entry with the
first field as the key and the second as the value. No SOH header needed.

    [GS]database
    [RS]host[US]localhost
    [RS]port[US]5432
    [GS]server
    [RS]host[US]0.0.0.0
    [RS]port[US]8080

Nested values use STX/ETX or ENQ references:

    [RS]allowed_origins[US][STX]localhost[US]example.com[US]api.example.com[ETX]


## Consistent Roles Across Shapes

The separator codes maintain consistent meaning across all data shapes:

| Shape      | RS means          | US means                  |
|------------|-------------------|---------------------------|
| Tabular    | row               | field / column            |
| Document   | paragraph / block | list item / element       |
| Key-Value  | entry             | key → value               |
| Diff       | —                 | anchor ↔ replacement unit |


## Escaping (DLE)

DLE (0x10) escapes the next byte as literal data, not a control code.

- A literal 0x1E in a value: `[DLE][0x1E]`
- A literal DLE in a value: `[DLE][DLE]`

DLE was chosen over ESC (0x1B) to avoid conflict with ANSI escape sequences.


## Document Termination (EOT)

EOT (0x04) marks the end of a complete C0DATA document or message. Optional
in file-at-rest scenarios (EOF is implicit). Useful for streaming, where
multiple documents may be sent over a single connection.


## C0-DIFF (Atomic Multi-File Edits)

C0-DIFF is a control-code markup format for atomic multi-file edits. It uses
sequential anchored patterns — literal text acts as anchors that must match
exactly once, and SUB-delimited regions mark the actual replacements.

### Diff Control Codes

| Code | Hex  | Name           | Purpose                                            |
|------|------|----------------|----------------------------------------------------|
| FS   | 0x1C | File Separator | Starts a new file block (followed by file path)    |
| GS   | 0x1D | Group Sep.     | Starts a new section/pattern within a file         |
| US   | 0x1F | Unit Separator | Separates pattern units (anchor ↔ replacement)     |
| SUB  | 0x1A | Substitute     | Separates old text from new text (old [SUB] new)   |
| DLE  | 0x10 | Data Link Esc  | Escapes literal control codes (next byte is literal)|

### Format

    [FS]<filepath>[GS]<literal>[US]<old>[SUB]<new>[US]<literal>

US separates the units of the pattern — anchor text from replacement regions.
SUB is the substitution operator within a replacement — old [SUB] new.

### Example

    [FS]foo.txt
    [GS]Hello [US]world[SUB]universe[US]!

This means: In file `foo.txt`, find the pattern `Hello world!` and replace
`world` with `universe`, yielding `Hello universe!`.

Sections within a file are sequential anchored patterns. Literal text between
replacement regions must match exactly once in the file and serves as context
anchors. Multiple files can be edited in a single C0-DIFF document. All files
are validated before any writes happen (atomic rollback semantics).

### Relationship to C0DATA

C0-DIFF shares the same control code vocabulary as C0DATA. FS and GS retain
their structural meanings (file boundary, section/group boundary). US retains
its role as a unit-level separator. DLE is the same escape mechanism used
throughout C0DATA. SUB takes on a diff-specific role that aligns with its
original C0 semantic — substitution.


## A Full Example (Database)

    [FS]mydb
    [GS]users
    [SOH]name[US]amount[US]type
    [RS]Alice[US]1502.30[US]DEPOSIT
    [RS]Bob[US]340.00[US]WITHDRAWAL
    [GS]products
    [SOH]id[US]product[US]qty
    [RS]01[US]Widget[US]100
    [RS]02[US]Gadget[US]250
    [EOT]


## Data Shapes

C0DATA is a system, not a single format. The same control code vocabulary
expresses multiple common data shapes:

| Shape      | Primary Codes Used          | Analogous To         |
|------------|-----------------------------|----------------------|
| Tabular    | FS, GS, SOH, RS, US        | CSV, SQL results     |
| Document   | FS, GS×N, RS, US           | Markdown, outlines   |
| Key-Value  | GS, SOH, RS, US            | TOML, INI            |
| Nested     | STX/ETX, any inner codes   | JSON objects         |
| Reference  | ENQ, STX/ETX for paths     | foreign keys, links  |
| Diff       | FS, GS, US, SUB, DLE       | unified diff, patches|
| Stream     | EOT between documents      | NDJSON, SSE          |


## Open Questions

- **Type encoding:** Are values always text, or can binary-encoded values
  be supported?
- **Unassigned codes:** Should a parser reject, ignore, or pass-through
  unassigned C0 bytes in compact form?
- **C0-DIFF integration:** SUB is used in diff mode but not in data mode.
  Any conflicts if both modes coexist in one document?
- **Reserved codes:** CAN, ETB, ESC, and others may find roles as the spec
  evolves.


## Speculations

The following ideas are not part of the spec. They explore how remaining
reserved codes might be used if these features are needed in the future.

### Checkpoint Hashes (Integrity Verification)

**ETB (0x17)** — "End Transmission Block" — could mark a block boundary
followed by a hash. The receiver verifies integrity at each checkpoint,
not just at the end. Useful for large documents or unreliable transports.

    [GS]users
    [SOH]name[US]amount
    [RS]Alice[US]1502.30
    [RS]Bob[US]340.00
    [ETB]<hash bytes>

**CAN (0x18)** — "Cancel" — could signal that the preceding data is invalid
and should be discarded. A natural response when a checkpoint hash fails.

### Binary Data (SO/SI)

Binary blobs can contain any byte, including control codes. DLE-escaping
works but could double the size in the worst case.

**SO (0x0E) / SI (0x0F)** — "Shift Out / Shift In" — originally switched
between character sets. Modernized: shift into binary mode with a length
prefix, then shift back.

    [RS]image-001[US][SO]<4-byte length><raw bytes>[SI]

Inside SO...SI, the parser reads exactly N bytes without scanning for
control codes. No escaping overhead.

### Type Discrimination (Numbers vs Text)

Currently all values are text. If type information is needed, several
approaches are possible:

**Schema-level typing** — SOH header declares types alongside names using
a separator convention:

    [SOH]name:s[US]amount:n[US]qty:i

Where `s` = string, `n` = number, `i` = integer, etc.

**Value-level prefix** — A reserved code before a value signals its type.
Candidates include the DC codes (DC1–DC4, 0x11–0x14) which were originally
"device control" — they could become "data class" indicators:

    [RS]Alice[US][DC1]1502.30[US][DC1]42

Where DC1 means "this value is numeric."

**Convention** — The application decides, like how JSON numbers are simply
unquoted text. The format stays type-agnostic.


## Original C0 Control Code Reference

| Dec | Hex  | Abbr | Name                 | Original Purpose                                    |
|-----|------|------|----------------------|-----------------------------------------------------|
| 0   | 0x00 | NUL  | Null                 | Filler / do nothing                                 |
| 1   | 0x01 | SOH  | Start of Heading     | Beginning of message header                         |
| 2   | 0x02 | STX  | Start of Text        | End of header, start of body                        |
| 3   | 0x03 | ETX  | End of Text          | End of message body                                 |
| 4   | 0x04 | EOT  | End of Transmission  | Transmission complete                               |
| 5   | 0x05 | ENQ  | Enquiry              | Request identification / status                     |
| 6   | 0x06 | ACK  | Acknowledge          | Confirm correct receipt                             |
| 7   | 0x07 | BEL  | Bell                 | Alert the operator                                  |
| 8   | 0x08 | BS   | Backspace            | Move cursor back one space                          |
| 9   | 0x09 | HT   | Horizontal Tab       | Move to next tab stop                               |
| 10  | 0x0A | LF   | Line Feed            | Advance to next line                                |
| 11  | 0x0B | VT   | Vertical Tab         | Move to next vertical tab stop                      |
| 12  | 0x0C | FF   | Form Feed            | Eject page / start new page                         |
| 13  | 0x0D | CR   | Carriage Return      | Return to beginning of line                         |
| 14  | 0x0E | SO   | Shift Out            | Switch to alternate character set                   |
| 15  | 0x0F | SI   | Shift In             | Switch back to standard character set               |
| 16  | 0x10 | DLE  | Data Link Escape     | Next character is data, not control                 |
| 17  | 0x11 | DC1  | Device Control 1     | XON (resume transmission)                           |
| 18  | 0x12 | DC2  | Device Control 2     | Device-specific                                     |
| 19  | 0x13 | DC3  | Device Control 3     | XOFF (pause transmission)                           |
| 20  | 0x14 | DC4  | Device Control 4     | Device-specific                                     |
| 21  | 0x15 | NAK  | Negative Acknowledge | Report receive error                                |
| 22  | 0x16 | SYN  | Synchronous Idle     | Maintain timing sync                                |
| 23  | 0x17 | ETB  | End Trans. Block     | End of data block                                   |
| 24  | 0x18 | CAN  | Cancel               | Preceding data invalid                              |
| 25  | 0x19 | EM   | End of Medium        | Physical end of storage                             |
| 26  | 0x1A | SUB  | Substitute           | Replacement for invalid character                   |
| 27  | 0x1B | ESC  | Escape               | Introduces escape sequence                          |
| 28  | 0x1C | FS   | File Separator       | Highest-level data separator                        |
| 29  | 0x1D | GS   | Group Separator      | Second-level data separator                         |
| 30  | 0x1E | RS   | Record Separator     | Third-level data separator                          |
| 31  | 0x1F | US   | Unit Separator       | Lowest-level data separator                         |
| 127 | 0x7F | DEL  | Delete               | Erase character (punch all holes)                   |
