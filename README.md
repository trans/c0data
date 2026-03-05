# C0DATA

A data system built on ASCII C0 control codes. One vocabulary, multiple shapes
-- tabular data, hierarchical documents, key-value config, diffs, and more.

C0DATA sits between human-readable text formats (JSON, YAML, TOML) and opaque
binary formats (protobuf, msgpack). Values are plain UTF-8 text. Structure is
expressed through single-byte control codes -- compact, zero-copy friendly,
and inspectable with minimal tooling.

## The Idea

ASCII has 32 control codes (0x00-0x1F) that were designed in the 1960s for
structuring data transmissions. Four of them -- FS, GS, RS, US -- are literal
**data separators** at four hierarchical levels. C0DATA modernizes these codes
as a universal grammar for structured data.

```
␜mydb
  ␝users
    ␁name␟amount␟type
    ␞Alice␟1502.30␟DEPOSIT
    ␞Bob␟340.00␟WITHDRAWAL
  ␝products
    ␁id␟product␟qty
    ␞01␟Widget␟100
    ␞02␟Gadget␟250
␄
```

That's a complete database with two tables, headers, and typed rows. Each
glyph (␜ ␝ ␞ ␟ ␁ ␄) is a single-byte control code. No braces, no quotes,
no escaping. Whitespace around control codes is trimmed -- the indentation
is just for readability.

## Control Codes

| Byte | Abbr | Role |
|------|------|------|
| 0x01 | SOH | Header (declares field names) |
| 0x02 | STX | Open nested sub-structure |
| 0x03 | ETX | Close nested sub-structure |
| 0x04 | EOT | End of document |
| 0x05 | ENQ | Reference (look up named data) |
| 0x10 | DLE | Escape (next byte is literal) |
| 0x1A | SUB | Substitution (C0DIFF) |
| 0x1C | FS  | File / Database separator |
| 0x1D | GS  | Group / Table / Section separator |
| 0x1E | RS  | Record / Row separator |
| 0x1F | US  | Unit / Field separator |

## Data Shapes

The same codes express multiple common data shapes:

### Tabular (CSV, SQL)

```
␝users
  ␁name␟amount␟type
  ␞Alice␟1502.30␟DEPOSIT
  ␞Bob␟340.00␟WITHDRAWAL
```

### Key-Value (TOML, INI)

```
␝database
  ␞host␟localhost
  ␞port␟5432
␝server
  ␞host␟0.0.0.0
  ␞port␟8080
```

### Document (Markdown)

GS repeated indicates depth level (like # in Markdown):

```
␜My Document
  ␝Chapter 1
    ␞First paragraph.
    ␞A list:
      ␟Item one
      ␟Item two
    ␝␝Section 1.1
      ␞Nested content.
  ␝Chapter 2
    ␞And so on.
```

### Diff (Atomic Multi-File Edits)

C0DIFF uses anchored patterns for safe search-and-replace:

```
␜foo.txt
  ␝Hello ␟world␚universe␟!
```

Means: in `foo.txt`, find `Hello world!`, replace `world` with `universe`.

### Whitespace and Quoting

In pretty form, whitespace around control codes is trimmed. To preserve
significant whitespace, use STX/ETX as quotes:

```
␞␂  leading spaces  ␃␟normal value
```

## Performance

The scanner's hot loop is a single comparison: `byte < 0x20`. This makes
C0DATA inherently fast to parse -- single-byte delimiters, zero-copy
friendly, and SIMD-acceleratable.

Benchmark on 10 MB document (Crystal, --release):

```
  avg         4.88 ms       2048.0 MB/s
  best        4.09 ms       2447.7 MB/s
```

For comparison, a fast YAML scanner in C achieves ~420 MB/s on equivalent data.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  c0data:
    github: transfire/c0data
```

Then run `shards install`.

## Usage

```crystal
require "c0data"
```

### Building

```crystal
buf = C0data::Builder.build do |b|
  b.file("mydb") do
    b.group("users", headers: ["name", "amount", "type"]) do
      b.record("Alice", "1502.30", "DEPOSIT")
      b.record("Bob", "340.00", "WITHDRAWAL")
    end
  end
  b.eot
end
```

### Reading

```crystal
doc = C0data::Document.new(buf)
doc.name                                # => "mydb"
doc["users"].table.record(0).field(0)   # => "Alice" (zero-copy slice)
doc["users"].table.record(0).field(1)   # => "1502.30"
```

### Pretty-Printing

```crystal
puts C0data::Pretty.format(buf)
# ␜mydb
#   ␝users
#     ␁name␟amount␟type
#     ␞Alice␟1502.30␟DEPOSIT
#     ␞Bob␟340.00␟WITHDRAWAL
#   ␄
```

### Round-Trip

```crystal
pretty = C0data::Pretty.format(buf)
compact = C0data::Pretty.parse(pretty)
# compact is identical to the original buf
```

### CSV Conversion

```crystal
# CSV → C0DATA
buf = C0data::CSV.from_csv(csv_string, group_name: "users")

# C0DATA → CSV
csv = C0data::CSV.to_csv(buf)
```

### C0DIFF

```crystal
diff = C0data::Diff.build do |b|
  b.file("src/app.cr") do
    b.section do |s|
      s.anchor("class App\n  def ")
      s.sub("run", "start")
    end
  end
end

files = {"src/app.cr" => source_code}
result = C0data::Diff.apply(diff, files)
```

## Two Forms

C0DATA has two representations:

- **Compact** -- canonical wire/storage format. Every byte is literal.
  No whitespace is ignored.
- **Pretty** -- human-readable. Uses Unicode Control Pictures (U+2400 block)
  for visible glyphs. Newlines and indentation are ignored by the parser.

The `c0fmt` command-line tool converts between them and more.

## c0fmt

`c0fmt` is a CLI tool for working with C0DATA from the command line.

```
c0fmt [command] [options] [file]

Commands:
  pretty       Compact → pretty (default)
  compact      Pretty → compact
  csv-import   CSV → C0DATA
  csv-export   C0DATA → CSV
  validate     Check well-formedness

Options:
  -o, --output FILE    Write to file (default: stdout)
  -g, --group NAME     Group name for csv-import (default: filename stem)
  -h, --help           Show help
```

Reads from a file argument or stdin.

### Examples

Convert a CSV file to pretty-printed C0DATA:

```sh
c0fmt csv-import data.csv | c0fmt pretty
```

```
␝data
  ␁name␟amount
  ␞Alice␟100
  ␞Bob␟200
```

Round-trip through C0DATA and back to CSV:

```sh
c0fmt csv-import users.csv | c0fmt csv-export
```

Validate a C0DATA file:

```sh
c0fmt validate data.c0
```

Convert between pretty and compact forms:

```sh
c0fmt compact pretty.c0 -o data.c0    # pretty → compact
c0fmt pretty data.c0                   # compact → pretty
```

### Building c0fmt

```sh
crystal build src/c0fmt.cr -o bin/c0fmt --release
```

## Design

See [DESIGN.md](DESIGN.md) for the full specification, including open
questions and future directions.

## Development

```
crystal spec        # run tests (83 specs)
crystal build bench/bench_tokenizer.cr -o bench/bench_tokenizer --release
./bench/bench_tokenizer 10   # benchmark with 10 MB document
```

## License

MIT
