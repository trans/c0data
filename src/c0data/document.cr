module C0data
  # Zero-copy navigator for a full C0DATA document.
  #
  # Walks an entire buffer containing FS/GS/RS/US structure and provides
  # access to files, groups, records, and fields as slices into the
  # original buffer.
  #
  # Example:
  #   doc = C0data::Document.new(buf)
  #   doc.name                     # => "mydb"
  #   doc.groups.size              # => 2
  #   doc.group("users")           # => Group
  #   doc.group("users").table     # => Table
  #   doc["users"]                 # => Group (shortcut)
  struct Document
    @buf : Bytes
    @name_start : Int32
    @name_end : Int32
    @group_offsets : Array(Int32) # start offset of each GS
    @group_names : Array({Int32, Int32})

    def initialize(@buf : Bytes)
      @name_start = 0
      @name_end = 0
      @group_offsets = Array(Int32).new
      @group_names = Array({Int32, Int32}).new
      index
    end

    # Document/file name (text after FS). Empty if no FS present.
    def name : Bytes
      @buf[@name_start...@name_end]
    end

    # Number of top-level groups.
    def group_count : Int32
      @group_offsets.size
    end

    # Access a group by index.
    def group(i : Int32) : Group
      gs_start = @group_offsets[i]
      gs_end = if i + 1 < @group_offsets.size
                 @group_offsets[i + 1]
               else
                 find_end(gs_start)
               end
      Group.new(@buf, gs_start, gs_end)
    end

    # Access a group by name.
    def group(name : String) : Group
      @group_names.each_with_index do |(ns, ne), i|
        if @buf[ns...ne] == name.to_slice
          return group(i)
        end
      end
      raise KeyError.new("No group named '#{name}'")
    end

    # Shortcut for group by name.
    def [](name : String) : Group
      group(name)
    end

    # Shortcut for group by index.
    def [](i : Int32) : Group
      group(i)
    end

    # Iterate all groups.
    def each_group(& : Group ->) : Nil
      group_count.times { |i| yield group(i) }
    end

    # All group names.
    def group_names : Array(Bytes)
      @group_names.map { |(ns, ne)| @buf[ns...ne] }
    end

    private def index : Nil
      pos = 0
      len = @buf.size.to_i32
      ptr = @buf.to_unsafe

      # Skip FS + file name if present
      if pos < len && ptr[pos] == FS
        pos += 1
        @name_start = pos
        while pos < len && ptr[pos] >= 0x20_u8
          pos += 1
        end
        @name_end = pos
      end

      # Find all top-level GS groups
      while pos < len
        byte = ptr[pos]
        break if byte == EOT

        if byte == GS
          # Check if this is a top-level GS (single, not GS×N continuation)
          gs_pos = pos
          gs_count = 0
          while pos < len && ptr[pos] == GS
            gs_count += 1
            pos += 1
          end

          if gs_count == 1
            # Top-level group
            @group_offsets << gs_pos
            name_start = pos
            while pos < len && ptr[pos] >= 0x20_u8
              pos += 1
            end
            @group_names << {name_start, pos}
          else
            # Deeper section (GS×N) — skip past its name
            while pos < len && ptr[pos] >= 0x20_u8
              pos += 1
            end
          end
        else
          pos += 1
        end
      end
    end

    # Find the end of a group starting at gs_start.
    private def find_end(gs_start : Int32) : Int32
      pos = gs_start
      len = @buf.size.to_i32
      ptr = @buf.to_unsafe

      # Skip past the initial GS + name
      pos += 1
      while pos < len && ptr[pos] >= 0x20_u8
        pos += 1
      end

      # Scan until next top-level GS, FS, or EOT
      while pos < len
        byte = ptr[pos]
        break if byte == FS || byte == EOT

        if byte == GS
          # Check if it's a single GS (top-level) or GS×N (nested)
          count = 0
          peek = pos
          while peek < len && ptr[peek] == GS
            count += 1
            peek += 1
          end
          break if count == 1 # next top-level group
          pos = peek          # skip deeper section
          # Skip name
          while pos < len && ptr[pos] >= 0x20_u8
            pos += 1
          end
        elsif byte == DLE
          pos += 2
        else
          pos += 1
        end
      end
      pos
    end
  end

  # A group within a document. Can be accessed as a Table or iterated
  # for document-mode content.
  struct Group
    @buf : Bytes
    @start : Int32 # offset of the GS byte
    @end : Int32   # offset past the last byte of this group

    def initialize(@buf : Bytes, @start : Int32, @end : Int32)
    end

    # Group name.
    def name : Bytes
      pos = @start + 1 # skip GS
      ptr = @buf.to_unsafe
      name_start = pos
      while pos < @end && ptr[pos] >= 0x20_u8
        pos += 1
      end
      @buf[name_start...pos]
    end

    # Access as a Table (for tabular/key-value data).
    def table : Table
      Table.new(@buf, @start)
    end

    # Check if this group has an SOH header.
    def has_header? : Bool
      pos = @start + 1
      ptr = @buf.to_unsafe
      # Skip name
      while pos < @end && ptr[pos] >= 0x20_u8
        pos += 1
      end
      pos < @end && ptr[pos] == SOH
    end

    # Iterate records directly (convenience for key-value groups).
    def each_record(& : Record ->) : Nil
      table.each_record { |r| yield r }
    end

    # Access record by index.
    def record(i : Int32) : Record
      table.record(i)
    end

    # Number of records.
    def record_count : Int32
      table.record_count
    end

    # Raw bytes of this group.
    def raw : Bytes
      @buf[@start...@end]
    end
  end
end
