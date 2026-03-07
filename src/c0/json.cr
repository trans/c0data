require "json"
require "yaml"

module C0
  module JSON
    # Recursive value type for intermediate data structures.
    alias Value = String | Array(Value) | Hash(String, Value)

    # --- Export: C0DATA → JSON/YAML ---

    # Convert C0DATA compact bytes to JSON string.
    def self.to_json(buf : Bytes) : String
      export(buf).to_pretty_json
    end

    # Convert C0DATA compact bytes to YAML string.
    def self.to_yaml(buf : Bytes) : String
      export(buf).to_yaml
    end

    # Build an intermediate data structure from C0DATA bytes.
    private def self.export(buf : Bytes) : Value
      if buf.size > 0 && buf[0] == FS
        doc = Document.new(buf)
        export_document(doc)
      elsif buf.size > 0 && buf[0] == GS
        table = Table.new(buf)
        {String.new(table.name) => export_group_data(table)} of String => Value
      else
        Hash(String, Value).new
      end
    end

    private def self.export_document(doc : Document) : Value
      name = String.new(doc.name)
      groups = Hash(String, Value).new
      doc.each_group do |group|
        groups[String.new(group.name)] = export_group_data(group.table)
      end

      if name.empty?
        groups.as(Value)
      else
        {name => groups.as(Value)} of String => Value
      end
    end

    private def self.export_group_data(table : Table) : Value
      if table.header_count > 0
        export_table(table)
      elsif table.record_count > 0 && table.record(0).field_count == 2
        export_kv(table)
      elsif table.record_count > 0
        export_records(table)
      else
        Array(Value).new
      end
    end

    # Tabular: array of objects with header keys.
    private def self.export_table(table : Table) : Value
      headers = (0...table.header_count).map { |i| String.new(table.header(i)) }
      rows = Array(Value).new
      table.each_record do |rec|
        row = Hash(String, Value).new
        headers.each_with_index do |h, i|
          row[h] = field_to_value(rec.field(i))
        end
        rows << row.as(Value)
      end
      rows.as(Value)
    end

    # Key-value: flat object.
    private def self.export_kv(table : Table) : Value
      obj = Hash(String, Value).new
      table.each_record do |rec|
        obj[unescape(rec.field(0))] = field_to_value(rec.field(1))
      end
      obj.as(Value)
    end

    # Raw records: array of arrays.
    private def self.export_records(table : Table) : Value
      rows = Array(Value).new
      table.each_record do |rec|
        fields = Array(Value).new
        rec.field_count.times do |i|
          fields << field_to_value(rec.field(i))
        end
        rows << fields.as(Value)
      end
      rows.as(Value)
    end

    # Convert a field's raw bytes to a Value.
    # If the field starts with STX, parse the nested structure recursively.
    private def self.field_to_value(field : Bytes) : Value
      if field.size > 0 && field[0] == STX
        parse_nested_field(field)
      else
        unescape(field).as(Value)
      end
    end

    # Parse a nested field (STX ... ETX) into a Value.
    # Inside the scope: RS-separated records → Hash, US-separated items → Array.
    private def self.parse_nested_field(field : Bytes) : Value
      # Strip outer STX/ETX
      stop = field.size
      stop -= 1 if stop > 0 && field[stop - 1] == ETX
      pos = 1 # skip STX

      # Detect structure: scan for RS or US at top level
      has_rs = false
      scan = pos
      while scan < stop
        byte = field[scan]
        if byte == RS
          has_rs = true
          break
        elsif byte == STX
          scan = skip_nested_bytes(field, scan, stop)
        elsif byte == DLE
          scan += 2
        else
          scan += 1
        end
      end

      if has_rs
        # RS-separated records → parse as key-value Hash
        parse_nested_kv(field, pos, stop)
      else
        # US-separated items → Array
        parse_nested_array(field, pos, stop)
      end
    end

    # Parse RS-separated key-value records inside a nested scope.
    private def self.parse_nested_kv(field : Bytes, pos : Int32, stop : Int32) : Value
      obj = Hash(String, Value).new
      while pos < stop
        if field[pos] == RS
          pos += 1
          # Read key (until US)
          key_start = pos
          while pos < stop && field[pos] != US
            if field[pos] == DLE
              pos += 2
            else
              pos += 1
            end
          end
          key = unescape(field[key_start...pos])
          # Read value (until next RS or end)
          if pos < stop && field[pos] == US
            pos += 1
            val_start = pos
            while pos < stop && field[pos] != RS
              if field[pos] == STX
                pos = skip_nested_bytes(field, pos, stop)
              elsif field[pos] == DLE
                pos += 2
              else
                pos += 1
              end
            end
            obj[key] = field_to_value(field[val_start...pos])
          else
            obj[key] = "".as(Value)
          end
        else
          pos += 1
        end
      end
      obj.as(Value)
    end

    # Parse US-separated items inside a nested scope.
    private def self.parse_nested_array(field : Bytes, pos : Int32, stop : Int32) : Value
      items = Array(Value).new
      # Skip leading US if present
      while pos < stop
        if field[pos] == US
          pos += 1
          item_start = pos
          while pos < stop && field[pos] != US
            if field[pos] == STX
              pos = skip_nested_bytes(field, pos, stop)
            elsif field[pos] == DLE
              pos += 2
            else
              pos += 1
            end
          end
          items << field_to_value(field[item_start...pos])
        else
          pos += 1
        end
      end
      items.as(Value)
    end

    # Skip over STX/ETX nested scope in raw bytes.
    private def self.skip_nested_bytes(buf : Bytes, pos : Int32, stop : Int32) : Int32
      pos += 1 # skip STX
      depth = 1
      while pos < stop && depth > 0
        byte = buf[pos]
        if byte == STX
          depth += 1
        elsif byte == ETX
          depth -= 1
        elsif byte == DLE
          pos += 1
        end
        pos += 1
      end
      pos
    end

    # --- Import: JSON/YAML → C0DATA ---

    # Convert JSON string to C0DATA compact bytes.
    def self.from_json(input : String, group_name : String = "data") : Bytes
      value = json_to_value(::JSON.parse(input))
      io = IO::Memory.new
      emit_root(value, group_name, io)
      io.to_slice.dup
    end

    # Convert YAML string to C0DATA compact bytes.
    def self.from_yaml(input : String, group_name : String = "data") : Bytes
      value = yaml_to_value(::YAML.parse(input))
      io = IO::Memory.new
      emit_root(value, group_name, io)
      io.to_slice.dup
    end

    # Convert JSON::Any to Value.
    private def self.json_to_value(any : ::JSON::Any) : Value
      raw = any.raw
      case raw
      when Hash
        result = Hash(String, Value).new
        raw.each { |k, v| result[k] = json_to_value(v) }
        result.as(Value)
      when Array
        raw.map { |v| json_to_value(v).as(Value) }.as(Value)
      when String
        raw.as(Value)
      when Nil
        "".as(Value)
      else
        raw.to_s.as(Value)
      end
    end

    # Convert YAML::Any to Value.
    private def self.yaml_to_value(any : ::YAML::Any) : Value
      raw = any.raw
      case raw
      when Hash
        result = Hash(String, Value).new
        raw.each { |k, v| result[k.to_s] = yaml_to_value(v) }
        result.as(Value)
      when Array
        raw.map { |v| yaml_to_value(v).as(Value) }.as(Value)
      when String
        raw.as(Value)
      when Nil
        "".as(Value)
      else
        raw.to_s.as(Value)
      end
    end

    # Emit a top-level Value as C0DATA.
    private def self.emit_root(value : Value, group_name : String, io : IO) : Nil
      case value
      when Hash(String, Value)
        if all_scalar?(value)
          # Flat key-value → single group
          write_group(group_name, io)
          value.each do |k, v|
            io.write_byte(RS)
            write_escaped(k, io)
            io.write_byte(US)
            write_escaped(v.as(String), io)
          end
        elsif value.size == 1
          key, inner = value.first_key, value.first_value
          if inner.is_a?(Hash) && all_groupable?(inner)
            # Wrapped document: {"mydb": {"users": [...], "config": {...}}}
            io.write_byte(FS)
            io << key
            emit_hash_as_groups(inner, io)
          else
            emit_hash_as_groups(value, io)
          end
        else
          emit_hash_as_groups(value, io)
        end
      when Array(Value)
        emit_array_as_group(value, group_name, io)
      when String
        write_group(group_name, io)
        io.write_byte(RS)
        write_escaped(value, io)
      end
    end

    # Emit a Hash as multiple groups.
    private def self.emit_hash_as_groups(hash : Hash(String, Value), io : IO) : Nil
      hash.each do |name, value|
        case value
        when Hash(String, Value)
          if all_scalar?(value)
            # Flat KV group
            write_group(name, io)
            value.each do |k, v|
              io.write_byte(RS)
              write_escaped(k, io)
              io.write_byte(US)
              write_escaped(v.as(String), io)
            end
          else
            # Mixed group — emit records with nested values
            write_group(name, io)
            value.each do |k, v|
              io.write_byte(RS)
              write_escaped(k, io)
              io.write_byte(US)
              emit_field_value(v, io)
            end
          end
        when Array(Value)
          emit_array_as_group(value, name, io)
        when String
          write_group(name, io)
          io.write_byte(RS)
          write_escaped(value, io)
        end
      end
    end

    # Emit an Array as a named group.
    private def self.emit_array_as_group(arr : Array(Value), name : String, io : IO) : Nil
      if tabular?(arr)
        headers = arr[0].as(Hash(String, Value)).keys
        write_group(name, io)
        # SOH headers
        io.write_byte(SOH)
        headers.each_with_index do |h, i|
          io.write_byte(US) if i > 0
          io << h
        end
        # Records
        arr.each do |row|
          h = row.as(Hash(String, Value))
          io.write_byte(RS)
          headers.each_with_index do |key, i|
            io.write_byte(US) if i > 0
            emit_field_value(h.fetch(key, "".as(Value)), io)
          end
        end
      else
        write_group(name, io)
        arr.each do |item|
          case item
          when String
            io.write_byte(RS)
            write_escaped(item, io)
          when Array(Value)
            io.write_byte(RS)
            item.each_with_index do |v, i|
              io.write_byte(US) if i > 0
              emit_field_value(v, io)
            end
          when Hash(String, Value)
            item.each do |k, v|
              io.write_byte(RS)
              write_escaped(k, io)
              io.write_byte(US)
              emit_field_value(v, io)
            end
          end
        end
      end
    end

    # Emit a value as a record field. Scalars are written directly;
    # nested structures are wrapped in STX/ETX.
    private def self.emit_field_value(value : Value, io : IO) : Nil
      case value
      when String
        write_escaped(value, io)
      when Hash(String, Value)
        io.write_byte(STX)
        value.each do |k, v|
          io.write_byte(RS)
          write_escaped(k, io)
          io.write_byte(US)
          emit_field_value(v, io)
        end
        io.write_byte(ETX)
      when Array(Value)
        io.write_byte(STX)
        value.each do |item|
          io.write_byte(US)
          emit_field_value(item, io)
        end
        io.write_byte(ETX)
      end
    end

    # --- Helpers ---

    private def self.write_group(name : String, io : IO) : Nil
      io.write_byte(GS)
      io << name
    end

    private def self.write_escaped(str : String, io : IO) : Nil
      str.each_byte do |byte|
        io.write_byte(DLE) if byte < 0x20_u8
        io.write_byte(byte)
      end
    end

    private def self.all_scalar?(hash : Hash(String, Value)) : Bool
      hash.all? { |_, v| v.is_a?(String) }
    end

    # Check if all values in a hash are groups (arrays or hashes, not scalars).
    # Used to decide if a single-key wrapper should become FS document.
    private def self.all_groupable?(hash : Hash(String, Value)) : Bool
      hash.all? { |_, v| v.is_a?(Hash) || v.is_a?(Array) }
    end

    private def self.tabular?(arr : Array(Value)) : Bool
      return false if arr.empty?
      return false unless arr.all? { |item| item.is_a?(Hash) }
      keys = arr[0].as(Hash(String, Value)).keys
      arr.all? { |item| item.as(Hash(String, Value)).keys == keys }
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
