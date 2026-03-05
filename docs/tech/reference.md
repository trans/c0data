---
title: C0DATA Technical Reference
---

# C0DATA Technical Reference

## Format Overview

C0DATA uses ASCII C0 control codes (0x00--0x1F) as structural delimiters
with UTF-8 text values. It has two representations:

- **Compact** -- canonical wire/storage form. Every byte is literal.
- **Pretty** -- human-readable. Uses Unicode Control Pictures (U+2400 block).
  Whitespace adjacent to control codes is trimmed.

See [DESIGN.md](https://github.com/trans/c0data/blob/main/DESIGN.md) for the
full specification.

### Assigned Control Codes

| Byte | Abbr | Glyph | Role |
|------|------|-------|------|
| 0x01 | SOH | ␁ | Header (declares field names) |
| 0x02 | STX | ␂ | Open nested sub-structure |
| 0x03 | ETX | ␃ | Close nested sub-structure |
| 0x04 | EOT | ␄ | End of document / message |
| 0x05 | ENQ | ␅ | Reference (look up named data) |
| 0x10 | DLE | ␐ | Escape (next byte is literal) |
| 0x1A | SUB | ␚ | Substitution (C0DIFF) |
| 0x1C | FS  | ␜ | File / Database separator |
| 0x1D | GS  | ␝ | Group / Table / Section separator |
| 0x1E | RS  | ␞ | Record / Row separator |
| 0x1F | US  | ␟ | Unit / Field separator |

### Structural Hierarchy

```
FS  >  GS  >  RS  >  US
file   group  record  field
```

Text immediately following FS or GS is the **label** (name) for that scope.


---

## Crystal API

### Installation

Add to your `shard.yml`:

```yaml
dependencies:
  c0data:
    github: trans/c0data
```

```crystal
require "c0data"
```

---

### Builder

Builds C0DATA documents in compact form.

```crystal
buf = C0data::Builder.build do |b|
  b.file("mydb") do
    b.group("users", headers: ["name", "amount"]) do
      b.record("Alice", "1502.30")
      b.record("Bob", "340.00")
    end
  end
  b.eot
end
```

#### Methods

**`Builder.build(&) : Bytes`**
:   Yields a Builder instance to the block and returns the compiled bytes.

**`file(name : String, &)`**
:   Write a FS separator followed by the name. Block scopes the file content.

**`group(name : String, headers : Indexable(String)? = nil, &)`**
:   Write a GS separator, name, and optional SOH header row.
    Block scopes the group content.

**`record(*fields : String)`**
:   Write an RS separator followed by US-delimited fields.
    Also accepts `record(fields : Indexable(String))`.

**`field(value : String)`**
:   Write a single US-delimited field value. Use within records
    when building fields incrementally.

**`nested(&)`**
:   Write an STX/ETX pair. Block contents are scoped inside the nesting.

**`ref(name : String)`**
:   Write an ENQ reference to a named group.

**`ref(*path : String)`**
:   Write a path reference: `ENQ STX group US record_id US field ETX`.

**`section(name : String, depth : Int32 = 1, &)`**
:   Write GS repeated `depth` times for document-mode depth levels.

**`block(text : String)`**
:   Write RS + text (a content block in document mode).

**`item(text : String)`**
:   Write US + text (a list item in document mode).

**`eot`**
:   Write an EOT marker.

**`to_slice : Bytes`**
:   Return the compiled bytes.

---

### Document

Zero-copy navigator for a complete C0DATA document (FS + groups).

```crystal
doc = C0data::Document.new(buf)
doc.name                        # => "mydb" (Bytes)
doc.group_count                 # => 2
doc["users"].table.headers      # => [Bytes("name"), Bytes("amount")]
```

#### Methods

**`Document.new(buf : Bytes)`**
:   Create a Document accessor from a compact buffer.

**`name : Bytes`**
:   Document name (text after FS). Empty if no FS present.

**`group_count : Int32`**
:   Number of top-level groups.

**`group(i : Int32) : Group`**
:   Get group by index.

**`group(name : String) : Group`**
:   Get group by name. Raises `KeyError` if not found.

**`[](name : String) : Group`** / **`[](i : Int32) : Group`**
:   Shorthand for `group(...)`.

**`each_group(& : Group ->)`**
:   Iterate over all groups.

**`group_names : Array(Bytes)`**
:   Get all group names.

---

### Group

A group within a document.

#### Methods

**`name : Bytes`**
:   Group name.

**`has_header? : Bool`**
:   Whether this group has an SOH header row.

**`table : Table`**
:   Access the group as a Table.

**`record(i : Int32) : Record`**
:   Get record by index.

**`record_count : Int32`**
:   Number of records.

**`each_record(& : Record ->)`**
:   Iterate records.

**`raw : Bytes`**
:   Raw bytes of this group.

---

### Table

Zero-copy accessor for tabular C0DATA data.

```crystal
table = C0data::Table.new(buf)
table.name                  # => "users" (Bytes)
table.headers               # => [Bytes("name"), Bytes("amount")]
table.record(0).field(0)    # => "Alice" (Bytes, zero-copy slice)
```

#### Methods

**`Table.new(buf : Bytes, offset : Int32 = 0)`**
:   Create a Table accessor.

**`name : Bytes`**
:   Table/group name.

**`header_count : Int32`**
:   Number of header fields.

**`header(i : Int32) : Bytes`**
:   Get header name by index.

**`headers : Array(Bytes)`**
:   All header names.

**`record_count : Int32`**
:   Number of records.

**`record(i : Int32) : Record`**
:   Get record by index.

**`each_record(& : Record ->)`**
:   Iterate over all records.

---

### Record

Zero-copy accessor for a single record.

#### Methods

**`field(n : Int32) : Bytes`**
:   Get field by index. Skips STX/ETX nested scopes when counting US
    boundaries.

**`field_count : Int32`**
:   Number of fields. Respects STX/ETX nesting.

**`fields : Array(Bytes)`**
:   All fields as byte slices.

**`raw : Bytes`**
:   Raw bytes of the entire record.

---

### Tokenizer

High-performance zero-copy tokenizer. Hot loop is a single comparison:
`byte < 0x20`.

```crystal
C0data::Tokenizer.new(buf).each do |token|
  case token.type
  when .gs? then puts "Group: #{String.new(token.value(buf))}"
  when .rs? then puts "Record start"
  when .data? then puts "Data: #{String.new(token.value(buf))}"
  end
end
```

#### Methods

**`Tokenizer.new(buf : Bytes)`**
:   Create a tokenizer.

**`each(& : Token ->)`**
:   Yield each token. Primary streaming interface.

**`to_a : Array(Token)`**
:   Collect all tokens.

#### Token Struct

| Field | Type | Description |
|-------|------|-------------|
| `type` | `TokenType` | Token type (see below) |
| `start` | `Int32` | Start offset in buffer |
| `end` | `Int32` | End offset in buffer |

**`size : Int32`** -- byte length.
**`value(buf : Bytes) : Bytes`** -- zero-copy slice into the buffer.

#### TokenType Enum

`Data`, `SOH`, `STX`, `ETX`, `EOT`, `ENQ`, `DLE`, `SUB`, `FS`, `GS`, `RS`, `US`

#### Exceptions

**`C0data::UnassignedCodeError`**
:   Raised on unassigned control codes. Properties: `byte : UInt8`,
    `position : Int32`.

**`C0data::UnexpectedEndError`**
:   Raised when DLE escape reaches end of input.

---

### Pretty

Convert between compact and pretty (Unicode Control Pictures) forms.

```crystal
pretty = C0data::Pretty.format(buf)
compact = C0data::Pretty.parse(pretty)
```

#### Methods

**`Pretty.format(buf : Bytes, indent : String = "  ") : String`**
:   Format compact buffer as human-readable Unicode string.

**`Pretty.format(buf : Bytes, io : IO, indent : String = "  ")`**
:   Format to an IO stream.

**`Pretty.parse(str : String) : Bytes`**
:   Parse pretty-form back to compact bytes.
    LF/CR are ignored. Whitespace adjacent to control codes is trimmed.
    Inside STX/ETX, content is preserved verbatim.

**`Pretty.glyph(byte : UInt8) : Char`**
:   Convert a C0 byte to its Unicode Control Picture character.

---

### CSV

Convert between CSV text and C0DATA compact bytes.

```crystal
buf = C0data::CSV.from_csv(csv_string, group_name: "users")
csv = C0data::CSV.to_csv(buf)
```

#### Methods

**`CSV.from_csv(input : String, group_name : String = "data") : Bytes`**
:   First CSV row becomes SOH headers, remaining rows become records.

**`CSV.to_csv(buf : Bytes) : String`**
:   Export the first group as CSV. Headers become the first row.

---

### JSON

Convert between JSON/YAML and C0DATA compact bytes. Handles nested
structures using STX/ETX scoping.

```crystal
# Import
buf = C0data::JSON.from_json(json_string)
buf = C0data::JSON.from_yaml(yaml_string, group_name: "config")

# Export
json = C0data::JSON.to_json(buf)
yaml = C0data::JSON.to_yaml(buf)
```

#### Type Alias

```crystal
alias C0data::JSON::Value = String | Array(Value) | Hash(String, Value)
```

Intermediate recursive type used during conversion.

#### Methods

**`JSON.from_json(input : String, group_name : String = "data") : Bytes`**
:   Convert JSON to C0DATA. Shape detection:
    - Object with array-of-objects values → tabular groups with FS wrapper
    - Object with scalar values → key-value group
    - Array of objects → tabular group
    - Nested Hash/Array values → STX/ETX sub-structures

**`JSON.from_yaml(input : String, group_name : String = "data") : Bytes`**
:   Same as `from_json` but parses YAML input.

**`JSON.to_json(buf : Bytes) : String`**
:   Convert C0DATA to pretty-printed JSON. Shape detection:
    - SOH headers → array of objects
    - 2-field records without header → flat key-value object
    - N-field records without header → array of arrays
    - STX/ETX fields → nested JSON objects/arrays

**`JSON.to_yaml(buf : Bytes) : String`**
:   Same structure as `to_json` but outputs YAML.

---

### Diff

C0DIFF: atomic multi-file edits using anchored patterns.

```crystal
# Build
diff = C0data::Diff.build do |b|
  b.file("src/app.cr") do
    b.section do |s|
      s.anchor("class App\n  def ")
      s.sub("run", "start")
    end
  end
end

# Apply to in-memory files
files = {"src/app.cr" => source_code}
result = C0data::Diff.apply(diff, files)

# Apply to files on disk
C0data::Diff.apply_files(diff, base_dir: ".")
```

#### Module Methods

**`Diff.build(& : DiffBuilder ->) : Bytes`**
:   Build a C0DIFF document.

**`Diff.parse(buf : Bytes) : Array(FileEdit)`**
:   Parse a C0DIFF buffer into file edits.

**`Diff.apply(diff_buf : Bytes, files : Hash(String, String)) : Hash(String, String)`**
:   Apply diff to a hash of file contents. Atomic: validates all patterns
    match before modifying any file.

**`Diff.apply_files(diff_buf : Bytes, base_dir : String = ".")`**
:   Apply diff to files on disk. Atomic: validates all before writing.

#### DiffBuilder

**`file(path : String, &)`**
:   Add a file edit block.

**`section(& : SectionBuilder ->)`**
:   Add a pattern section.

**`replace(context_before, old_text, new_text, context_after = "")`**
:   Convenience: add a simple find/replace.

#### SectionBuilder

**`anchor(text : String)`**
:   Add literal anchor text.

**`sub(old_text : String, new_text : String)`**
:   Add a substitution.

#### Data Types

**`FileEdit`** -- `path : Bytes`, `sections : Array(Section)`

**`Section`** -- `units : Array(Unit)`
:   `search_pattern : Bytes` -- concatenated old text.
    `replacement : Bytes` -- concatenated new text.

**`Sub`** -- `old : Bytes`, `new : Bytes`

**`Unit`** -- `Bytes | Sub` (literal anchor or substitution)


---

## c0fmt CLI

Command-line tool for converting and inspecting C0DATA.

### Build

```sh
crystal build src/c0fmt.cr -o bin/c0fmt --release
```

### Commands

#### import

```
c0fmt import [format] [file]
```

Import CSV, JSON, or YAML into C0DATA compact format.

- **format** -- `csv`, `json`, or `yaml`. Optional: auto-detected from file
  extension (`.csv`, `.json`, `.yaml`, `.yml`) or content sniffing.
- **file** -- input file. Reads stdin if omitted.
- **-o FILE** -- write output to file instead of stdout.
- **-g NAME** -- group name (defaults to filename stem or `data`).

```sh
c0fmt import data.csv                      # auto-detect from extension
c0fmt import csv data.csv                  # explicit format
echo '{"a":1}' | c0fmt import              # sniff stdin (detects JSON)
cat data.csv | c0fmt import csv            # explicit format, stdin
c0fmt import data.json -g mydata           # custom group name
```

#### export

```
c0fmt export <format> [file]
```

Export C0DATA to CSV, JSON, or YAML.

- **format** -- `csv`, `json`, or `yaml`. Required.
- **file** -- input C0DATA file. Reads stdin if omitted.
- **-o FILE** -- write output to file.

```sh
c0fmt import data.csv | c0fmt export json
c0fmt export yaml data.c0
c0fmt export csv data.c0 -o data.csv
```

#### pretty

```
c0fmt pretty [file]
```

Convert C0DATA to pretty-printed Unicode form. Auto-detects whether
input is already pretty or compact.

- **-o FILE** -- write output to file.

```sh
c0fmt pretty data.c0
cat data.c0 | c0fmt pretty
```

#### compact

```
c0fmt compact [file]
```

Convert C0DATA to compact binary form.

- **-o FILE** -- write output to file.

```sh
c0fmt compact pretty.c0 -o data.c0
```

#### validate

```
c0fmt validate [file]
```

Check well-formedness of a C0DATA document. Prints `valid` to stderr
and exits 0, or prints the error and exits 1.

```sh
c0fmt validate data.c0
```

### Pipelines

Commands compose via stdin/stdout:

```sh
# CSV to JSON
c0fmt import data.csv | c0fmt export json

# JSON to pretty C0DATA
c0fmt import config.json | c0fmt pretty

# YAML to compact C0DATA file
c0fmt import settings.yml | c0fmt compact -o data.c0

# Round-trip: CSV → C0DATA → CSV
c0fmt import csv users.csv | c0fmt export csv
```


---

## Data Shape Mapping

How C0DATA maps to and from JSON/YAML/CSV.

### Tabular (SOH header present)

```
␝users
  ␁name␟amount
  ␞Alice␟100
  ␞Bob␟200
```

```json
{"users": [{"name": "Alice", "amount": "100"}, {"name": "Bob", "amount": "200"}]}
```

```csv
name,amount
Alice,100
Bob,200
```

### Key-Value (no header, 2-field records)

```
␝database
  ␞host␟localhost
  ␞port␟5432
```

```json
{"database": {"host": "localhost", "port": "5432"}}
```

### Multi-field records (no header, N fields)

```
␝data
  ␞a␟b␟c
  ␞d␟e␟f
```

```json
{"data": [["a", "b", "c"], ["d", "e", "f"]]}
```

### Nested values (STX/ETX)

```
␝users
  ␁name␟address
  ␞Alice␟␂␁street␟city␞123 Main␟Springfield␃
```

```json
{"users": [{"name": "Alice", "address": {"street": "123 Main", "city": "Springfield"}}]}
```

### Document (FS wrapper)

```
␜mydb
  ␝users
    ␁name
    ␞Alice
  ␝products
    ␁id
    ␞01
```

```json
{"mydb": {"users": [{"name": "Alice"}], "products": [{"id": "01"}]}}
```
