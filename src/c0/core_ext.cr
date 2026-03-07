class Array(T)
  def to_c0(group_name : String? = nil) : Bytes
    raise C0::Error.new("Cannot serialize empty array") if empty?
    io = IO::Memory.new
    first.to_c0(io, group_name)
    each_with_index do |item, idx|
      next if idx == 0
      item._c0_write_record(io)
    end
    io.to_slice.dup
  end

  def to_c0_pretty(group_name : String? = nil) : String
    C0::Pretty.format(to_c0(group_name))
  end
end

struct NamedTuple
  def to_c0(group_name : String = "data") : Bytes
    io = IO::Memory.new
    io.write_byte(C0::GS)
    io << group_name
    {% for key in T.keys %}
      io.write_byte(C0::RS)
      io << {{ key.stringify }}
      io.write_byte(C0::US)
      C0::Serializable._serialize_field(self[{{ key.symbolize }}], io)
    {% end %}
    io.to_slice.dup
  end

  def to_c0_pretty(group_name : String = "data") : String
    C0::Pretty.format(to_c0(group_name))
  end
end

class Hash(K, V)
  def to_c0(group_name : String = "data") : Bytes
    io = IO::Memory.new
    io.write_byte(C0::GS)
    io << group_name
    each do |k, v|
      io.write_byte(C0::RS)
      C0::Serializable._serialize_field(k, io)
      io.write_byte(C0::US)
      C0::Serializable._serialize_field(v, io)
    end
    io.to_slice.dup
  end

  def to_c0_pretty(group_name : String = "data") : String
    C0::Pretty.format(to_c0(group_name))
  end
end
