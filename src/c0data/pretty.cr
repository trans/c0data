module C0data
  # Unicode Control Pictures (U+2400 block) for pretty-printing.
  # Each C0 code at position N maps to U+2400+N.
  module Pretty
    # Convert a C0 control byte to its Unicode Control Picture character.
    @[AlwaysInline]
    def self.glyph(byte : UInt8) : Char
      (0x2400 + byte).chr
    end

    # Format a compact C0DATA buffer as a human-readable Unicode string
    # with newlines and indentation.
    def self.format(buf : Bytes, indent : String = "  ") : String
      String.build do |io|
        format(buf, io, indent)
      end
    end

    # Format to an IO.
    def self.format(buf : Bytes, io : IO, indent : String = "  ") : Nil
      pos = 0
      len = buf.size
      ptr = buf.to_unsafe
      depth = 0
      line_start = true
      gs_run = 0

      while pos < len
        byte = ptr[pos]

        if byte < 0x20_u8
          case byte
          when FS
            depth = 0
            io << '\n' unless line_start
            io << glyph(byte)
            pos += 1
            depth = 1
            gs_run = 0
            write_data_until_control(buf, pos, io) { |new_pos| pos = new_pos }
            io << '\n'
            line_start = true
          when GS
            # Count consecutive GS for depth
            gs_run = 0
            while pos < len && ptr[pos] == GS
              gs_run += 1
              pos += 1
            end
            io << '\n' unless line_start
            write_indent(io, indent, depth)
            gs_run.times { io << glyph(GS) }
            write_data_until_control(buf, pos, io) { |new_pos| pos = new_pos }
            io << '\n'
            line_start = true
          when SOH
            write_indent(io, indent, depth + 1)
            io << glyph(byte)
            pos += 1
            # Write header fields on same line
            write_fields_line(buf, pos, io) { |new_pos| pos = new_pos }
            io << '\n'
            line_start = true
          when RS
            write_indent(io, indent, depth + 1)
            io << glyph(byte)
            pos += 1
            # Write record fields on same line
            write_fields_line(buf, pos, io) { |new_pos| pos = new_pos }
            io << '\n'
            line_start = true
          when STX
            io << glyph(byte)
            pos += 1
            depth += 1
            io << '\n'
            line_start = true
          when ETX
            depth -= 1 if depth > 0
            write_indent(io, indent, depth + 1)
            io << glyph(byte)
            pos += 1
            # Don't add newline here — let the next token handle it
          when EOT
            io << '\n' unless line_start
            io << glyph(byte)
            io << '\n'
            pos += 1
            line_start = true
          when ENQ
            io << glyph(byte)
            pos += 1
          when DLE
            io << glyph(byte)
            pos += 1
            if pos < len
              io << glyph(ptr[pos]) if ptr[pos] < 0x20_u8
              io.write_byte(ptr[pos]) if ptr[pos] >= 0x20_u8
              pos += 1
            end
          when SUB
            io << glyph(byte)
            pos += 1
          when US
            io << glyph(byte)
            pos += 1
          else
            # Unassigned — show glyph
            io << glyph(byte)
            pos += 1
          end
        else
          # Data byte
          io.write_byte(byte)
          pos += 1
          line_start = false
        end
      end
      io << '\n' unless line_start
    end

    # Parse pretty-form back to compact form.
    #
    # Rules:
    # - Unicode Control Pictures (U+2400-U+241F) → C0 bytes
    # - LF/CR are ignored (formatting only)
    # - Whitespace (space/tab) adjacent to control codes is trimmed
    # - Inside STX/ETX (␂...␃), everything is preserved verbatim
    #   (no trimming). This allows STX/ETX to serve as quoting for
    #   values with significant whitespace.
    def self.parse(str : String) : Bytes
      io = IO::Memory.new
      iter = str.each_char
      whitespace_buf = IO::Memory.new
      trim_after = true # trim leading whitespace at start of input

      while true
        c = iter.next
        break if c.is_a?(Iterator::Stop)
        char = c.as(Char)

        if char.ord >= 0x2400 && char.ord <= 0x241F
          code = (char.ord - 0x2400).to_u8
          # Discard buffered whitespace (trim before control code)
          whitespace_buf.clear

          if code == STX
            io.write_byte(code)
            # Inside STX/ETX: preserve everything verbatim
            parse_quoted(iter, io)
          else
            io.write_byte(code)
          end
          # Trim whitespace after control code too
          trim_after = true
        elsif char == '\n' || char == '\r'
          # Ignored — also discard buffered whitespace
          whitespace_buf.clear
          trim_after = true
        elsif char == ' ' || char == '\t'
          if trim_after
            # Skip whitespace immediately after a control code or newline
            next
          end
          # Buffer whitespace — only flush if followed by data
          whitespace_buf << char
        else
          trim_after = false
          # Data character: flush buffered whitespace first
          if whitespace_buf.size > 0
            io.write(whitespace_buf.to_slice)
            whitespace_buf.clear
          end
          char.each_byte { |b| io.write_byte(b) }
        end
      end

      io.to_slice
    end

    # Parse inside STX/ETX — preserve everything verbatim until
    # matching ETX glyph (␃). Handles nested STX/ETX.
    private def self.parse_quoted(iter : Iterator(Char), io : IO) : Nil
      depth = 1

      while true
        c = iter.next
        break if c.is_a?(Iterator::Stop)
        char = c.as(Char)

        if char.ord >= 0x2400 && char.ord <= 0x241F
          code = (char.ord - 0x2400).to_u8
          io.write_byte(code)

          if code == STX
            depth += 1
          elsif code == ETX
            depth -= 1
            break if depth == 0
          end
        else
          # Preserve everything — newlines, spaces, all of it
          char.each_byte { |b| io.write_byte(b) }
        end
      end
    end

    # Write data bytes from buf[pos] until the next control code.
    private def self.write_data_until_control(buf : Bytes, pos : Int32, io : IO, & : Int32 ->) : Nil
      ptr = buf.to_unsafe
      len = buf.size
      while pos < len && ptr[pos] >= 0x20_u8
        io.write_byte(ptr[pos])
        pos += 1
      end
      yield pos
    end

    # Write fields (data separated by US) on a single line until the next
    # structural control code (RS, GS, FS, EOT, ETX, SOH, STX).
    private def self.write_fields_line(buf : Bytes, pos : Int32, io : IO, & : Int32 ->) : Nil
      ptr = buf.to_unsafe
      len = buf.size
      while pos < len
        byte = ptr[pos]
        if byte == US
          io << glyph(US)
          pos += 1
        elsif byte == DLE
          io << glyph(DLE)
          pos += 1
          if pos < len
            if ptr[pos] < 0x20_u8
              io << glyph(ptr[pos])
            else
              io.write_byte(ptr[pos])
            end
            pos += 1
          end
        elsif byte == ENQ
          io << glyph(ENQ)
          pos += 1
        elsif byte == STX
          io << glyph(STX)
          pos += 1
          # Write until ETX on same line
          while pos < len
            b = ptr[pos]
            if b == ETX
              io << glyph(ETX)
              pos += 1
              break
            elsif b == US
              io << glyph(US)
              pos += 1
            elsif b < 0x20_u8
              io << glyph(b)
              pos += 1
            else
              io.write_byte(b)
              pos += 1
            end
          end
        elsif byte < 0x20_u8
          # Next structural code — stop
          break
        else
          io.write_byte(byte)
          pos += 1
        end
      end
      yield pos
    end

    private def self.write_indent(io : IO, indent : String, depth : Int32) : Nil
      depth.times { io << indent }
    end
  end
end
