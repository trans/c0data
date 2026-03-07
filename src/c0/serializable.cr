module C0
  annotation Field
  end

  module Serializable
    macro included
      def self.from_c0(buf : Bytes) : self
        arr = array_from_c0(buf)
        arr.first? || raise C0::Error.new("No records found")
      end

      def self.from_c0(str : String) : self
        from_c0(C0::Pretty.parse(str))
      end

      def self.array_from_c0(buf : Bytes) : Array(self)
        offset = 0
        if buf.size > 0 && buf[0] == C0::FS
          offset += 1
          while offset < buf.size && buf[offset] >= 0x20_u8
            offset += 1
          end
        end

        table = C0::Table.new(buf, offset)
        headers = (0...table.header_count).map { |i| String.new(table.header(i)) }

        results = Array(self).new(table.record_count)
        table.each_record do |rec|
          instance = allocate
          instance.initialize(__c0_headers: headers, __c0_record: rec)
          ::GC.add_finalizer(instance) if instance.responds_to?(:finalize)
          results << instance
        end
        results
      end

      def self.array_from_c0(str : String) : Array(self)
        array_from_c0(C0::Pretty.parse(str))
      end
    end

    def initialize(*, __c0_headers headers : Array(String), __c0_record rec : C0::Record)
      {% verbatim do %}
        {% begin %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(C0::Field) %}
            {% unless ann && ann[:ignore] %}
              {% key = (ann && ann[:key]) || ivar.name.stringify %}
              %idx{ivar.id} = headers.index({{ key }})
              if %idx{ivar.id}
                %raw{ivar.id} = rec.field(%idx{ivar.id}.not_nil!)
                {% if ivar.type == String %}
                  @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id})
                {% elsif ivar.type == Int32 %}
                  @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_i32
                {% elsif ivar.type == Int64 %}
                  @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_i64
                {% elsif ivar.type == Float32 %}
                  @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_f32
                {% elsif ivar.type == Float64 %}
                  @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_f64
                {% elsif ivar.type == Bool %}
                  @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}) == "true"
                {% elsif ivar.type == Array(String) %}
                  @{{ ivar.id }} = C0::Serializable._deserialize_string_array(%raw{ivar.id})
                {% elsif ivar.type.nilable? %}
                  if %raw{ivar.id}.empty?
                    @{{ ivar.id }} = nil
                  else
                    {% inner = ivar.type.union_types.reject { |t| t == Nil }.first %}
                    {% if inner == String %}
                      @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id})
                    {% elsif inner == Int32 %}
                      @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_i32
                    {% elsif inner == Int64 %}
                      @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_i64
                    {% elsif inner == Float32 %}
                      @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_f32
                    {% elsif inner == Float64 %}
                      @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}).to_f64
                    {% elsif inner == Bool %}
                      @{{ ivar.id }} = C0::Serializable._unescape(%raw{ivar.id}) == "true"
                    {% end %}
                  end
                {% end %}
              {% if !ivar.has_default_value? && !ivar.type.nilable? %}
              else
                raise C0::Error.new("Missing required field '{{ key.id }}' for #{self.class}")
              {% end %}
              end
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    end

    def to_c0(group_name : String? = nil) : Bytes
      io = IO::Memory.new
      to_c0(io, group_name)
      io.to_slice.dup
    end

    def to_c0_pretty(group_name : String? = nil) : String
      C0::Pretty.format(to_c0(group_name))
    end

    def to_c0(io : IO, group_name : String? = nil) : Nil
      {% verbatim do %}
        {% begin %}
          %name = group_name || {{ @type.name.split("::").last.downcase }}
          io.write_byte(C0::GS)
          io << %name

          io.write_byte(C0::SOH)
          {% fields = @type.instance_vars.reject { |v| (ann = v.annotation(C0::Field)) && ann[:ignore] } %}
          {% for ivar, i in fields %}
            {% ann = ivar.annotation(C0::Field) %}
            {% key = (ann && ann[:key]) || ivar.name.stringify %}
            io.write_byte(C0::US) if {{ i }} > 0
            io << {{ key }}
          {% end %}

          io.write_byte(C0::RS)
          {% for ivar, i in fields %}
            io.write_byte(C0::US) if {{ i }} > 0
            C0::Serializable._serialize_field(@{{ ivar.id }}, io)
          {% end %}
        {% end %}
      {% end %}
    end

    # Write just the record portion (RS + fields), used by Array#to_c0.
    def _c0_write_record(io : IO) : Nil
      {% verbatim do %}
        {% begin %}
          {% fields = @type.instance_vars.reject { |v| (ann = v.annotation(C0::Field)) && ann[:ignore] } %}
          io.write_byte(C0::RS)
          {% for ivar, i in fields %}
            io.write_byte(C0::US) if {{ i }} > 0
            C0::Serializable._serialize_field(@{{ ivar.id }}, io)
          {% end %}
        {% end %}
      {% end %}
    end

    def self._serialize_field(value : String, io : IO) : Nil
      value.each_byte do |byte|
        io.write_byte(C0::DLE) if byte < 0x20_u8
        io.write_byte(byte)
      end
    end

    def self._serialize_field(value : Int | Float, io : IO) : Nil
      io << value
    end

    def self._serialize_field(value : Bool, io : IO) : Nil
      io << value
    end

    def self._serialize_field(value : Nil, io : IO) : Nil
    end

    def self._serialize_field(value : Array, io : IO) : Nil
      io.write_byte(C0::STX)
      value.each do |item|
        io.write_byte(C0::US)
        _serialize_field(item, io)
      end
      io.write_byte(C0::ETX)
    end

    def self._serialize_field(value : Hash, io : IO) : Nil
      io.write_byte(C0::STX)
      value.each do |k, v|
        io.write_byte(C0::RS)
        _serialize_field(k, io)
        io.write_byte(C0::US)
        _serialize_field(v, io)
      end
      io.write_byte(C0::ETX)
    end

    def self._serialize_field(value : C0::Serializable, io : IO) : Nil
      io.write_byte(C0::STX)
      value.to_c0(io)
      io.write_byte(C0::ETX)
    end

    def self._unescape(field : Bytes) : String
      io = IO::Memory.new(field.size)
      pos = 0
      while pos < field.size
        if field[pos] == C0::DLE && pos + 1 < field.size
          pos += 1
        end
        io.write_byte(field[pos])
        pos += 1
      end
      String.new(io.to_slice)
    end

    def self._deserialize_string_array(raw : Bytes) : Array(String)
      return Array(String).new if raw.empty?
      stop = raw.size
      stop -= 1 if stop > 0 && raw[stop - 1] == C0::ETX
      pos = (raw.size > 0 && raw[0] == C0::STX) ? 1 : 0
      items = Array(String).new
      while pos < stop
        if raw[pos] == C0::US
          pos += 1
          start = pos
          while pos < stop && raw[pos] != C0::US
            pos += (raw[pos] == C0::DLE) ? 2 : 1
          end
          items << _unescape(raw[start...pos])
        else
          pos += 1
        end
      end
      items
    end
  end
end
