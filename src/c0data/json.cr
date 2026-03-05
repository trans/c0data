require "json"
require "yaml"

module C0data
  module JSON
    # Recursive value type for building intermediate data structures.
    alias Value = String | Array(Value) | Hash(String, Value)

    # Convert C0DATA compact bytes to JSON string.
    def self.to_json(buf : Bytes) : String
      build(buf).to_pretty_json
    end

    # Convert C0DATA compact bytes to YAML string.
    def self.to_yaml(buf : Bytes) : String
      build(buf).to_yaml
    end

    # Build an intermediate data structure from C0DATA bytes.
    private def self.build(buf : Bytes) : Value
      if buf.size > 0 && buf[0] == FS
        doc = Document.new(buf)
        build_document(doc)
      elsif buf.size > 0 && buf[0] == GS
        table = Table.new(buf)
        {String.new(table.name) => build_group_data(table)} of String => Value
      else
        Hash(String, Value).new
      end
    end

    # Build a full document: {file_name: {group1: ..., group2: ...}}
    private def self.build_document(doc : Document) : Value
      name = String.new(doc.name)
      groups = Hash(String, Value).new
      doc.each_group do |group|
        groups[String.new(group.name)] = build_group_data(group.table)
      end

      if name.empty?
        groups.as(Value)
      else
        {name => groups.as(Value)} of String => Value
      end
    end

    # Detect shape and build appropriate structure for a group's data.
    private def self.build_group_data(table : Table) : Value
      if table.header_count > 0
        build_table(table)
      elsif table.record_count > 0 && table.record(0).field_count == 2
        build_kv(table)
      elsif table.record_count > 0
        build_records(table)
      else
        Array(Value).new
      end
    end

    # Tabular: array of objects with header keys.
    private def self.build_table(table : Table) : Value
      headers = (0...table.header_count).map { |i| String.new(table.header(i)) }
      rows = Array(Value).new
      table.each_record do |rec|
        row = Hash(String, Value).new
        headers.each_with_index do |h, i|
          row[h] = unescape(rec.field(i)).as(Value)
        end
        rows << row.as(Value)
      end
      rows.as(Value)
    end

    # Key-value: flat object.
    private def self.build_kv(table : Table) : Value
      obj = Hash(String, Value).new
      table.each_record do |rec|
        obj[unescape(rec.field(0))] = unescape(rec.field(1)).as(Value)
      end
      obj.as(Value)
    end

    # Raw records: array of arrays.
    private def self.build_records(table : Table) : Value
      rows = Array(Value).new
      table.each_record do |rec|
        fields = Array(Value).new
        rec.field_count.times do |i|
          fields << unescape(rec.field(i)).as(Value)
        end
        rows << fields.as(Value)
      end
      rows.as(Value)
    end

    # Unescape DLE sequences in a field value.
    private def self.unescape(field : Bytes) : String
      io = IO::Memory.new(field.size)
      pos = 0
      while pos < field.size
        if field[pos] == DLE && pos + 1 < field.size
          pos += 1
          io.write_byte(field[pos])
        else
          io.write_byte(field[pos])
        end
        pos += 1
      end
      String.new(io.to_slice)
    end
  end
end
