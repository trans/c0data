module C0data
  # Zero-copy accessor for a tabular C0DATA group.
  #
  # Scans the buffer once to index record positions, then provides
  # O(1) access to records and fields as slices into the original buffer.
  struct Table
    @buf : Bytes
    @name_start : Int32
    @name_end : Int32
    @headers : Array(Int32)     # pairs of [start, end] for each header field
    @records : Array(Int32)     # start offset of each record
    @record_ends : Array(Int32) # end offset of each record

    def initialize(@buf : Bytes, offset : Int32 = 0)
      @name_start = 0
      @name_end = 0
      @headers = Array(Int32).new
      @records = Array(Int32).new
      @record_ends = Array(Int32).new
      index(offset)
    end

    # Group/table name as a slice into the buffer.
    @[AlwaysInline]
    def name : Bytes
      @buf[@name_start...@name_end]
    end

    # Number of header fields.
    @[AlwaysInline]
    def header_count : Int32
      @headers.size // 2
    end

    # Header field name by index.
    @[AlwaysInline]
    def header(i : Int32) : Bytes
      @buf[@headers[i * 2]...@headers[i * 2 + 1]]
    end

    # All header names.
    def headers : Array(Bytes)
      (0...header_count).map { |i| header(i) }
    end

    # Number of records.
    @[AlwaysInline]
    def record_count : Int32
      @records.size
    end

    # Access a record by index. Returns a Record accessor.
    @[AlwaysInline]
    def record(i : Int32) : Record
      Record.new(@buf, @records[i], @record_ends[i])
    end

    # Iterate all records.
    def each_record(& : Record ->) : Nil
      @records.size.times do |i|
        yield record(i)
      end
    end

    # Scan the buffer and build the index.
    private def index(offset : Int32) : Nil
      pos = offset
      len = @buf.size.to_i32
      ptr = @buf.to_unsafe

      # Expect GS to start the group
      return if pos >= len
      if ptr[pos] == GS
        pos += 1
        # Read group name
        @name_start = pos
        while pos < len && ptr[pos] >= 0x20_u8
          pos += 1
        end
        @name_end = pos
      end

      # Read SOH header if present
      if pos < len && ptr[pos] == SOH
        pos += 1
        field_start = pos
        while pos < len
          byte = ptr[pos]
          if byte == US
            @headers << field_start
            @headers << pos
            pos += 1
            field_start = pos
          elsif byte < 0x20_u8
            # End of header — save last field
            @headers << field_start
            @headers << pos
            break
          else
            pos += 1
          end
        end
      end

      # Read records
      while pos < len
        byte = ptr[pos]
        break if byte == GS || byte == FS || byte == EOT || byte == ETX

        if byte == RS
          pos += 1
          rec_start = pos
          # Scan to end of record
          while pos < len
            b = ptr[pos]
            break if b == RS || b == GS || b == FS || b == EOT || b == ETX
            if b == DLE
              pos += 2 # skip escaped byte
            else
              pos += 1
            end
          end
          @records << rec_start
          @record_ends << pos
        else
          pos += 1
        end
      end
    end
  end

  # Zero-copy accessor for a single record within a table.
  # Fields are accessed by index, returning slices into the original buffer.
  struct Record
    @buf : Bytes
    @start : Int32
    @end : Int32

    def initialize(@buf : Bytes, @start : Int32, @end : Int32)
    end

    # Access field by index. Scans for the Nth US separator.
    def field(n : Int32) : Bytes
      pos = @start
      ptr = @buf.to_unsafe
      field_idx = 0
      field_start = pos

      while pos < @end
        byte = ptr[pos]
        if byte == US
          return @buf[field_start...pos] if field_idx == n
          field_idx += 1
          pos += 1
          field_start = pos
        elsif byte == DLE
          pos += 2
        else
          pos += 1
        end
      end

      # Last field (no trailing US)
      return @buf[field_start...pos] if field_idx == n
      Bytes.empty
    end

    # Number of fields in this record.
    def field_count : Int32
      count = 1
      pos = @start
      ptr = @buf.to_unsafe

      while pos < @end
        byte = ptr[pos]
        if byte == US
          count += 1
          pos += 1
        elsif byte == DLE
          pos += 2
        else
          pos += 1
        end
      end
      count
    end

    # All fields as slices.
    def fields : Array(Bytes)
      (0...field_count).map { |i| field(i) }
    end

    # Raw bytes of the entire record.
    @[AlwaysInline]
    def raw : Bytes
      @buf[@start...@end]
    end
  end
end
