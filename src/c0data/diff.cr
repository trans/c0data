module C0data
  # C0DIFF parser and applier for atomic multi-file edits.
  #
  # Format:
  #   [FS]<filepath>[GS]<literal>[US]<old>[SUB]<new>[US]<literal>
  #
  # - FS starts a new file block
  # - GS starts a new pattern section within a file
  # - US separates pattern units (anchor text ↔ replacement regions)
  # - SUB separates old text from new text within a replacement
  # - DLE escapes literal control codes
  #
  # TODO: Consider a "replace-all within bounded scope" mode.
  #   Two unique sentinel anchors would define a region, and all
  #   occurrences within that region would be replaced. Candidate
  #   codes: SO/SI (0x0E/0x0F) — "Shift Out/In" to switch into
  #   replace-all mode:
  #     [GS]<start anchor>[SO]<old>[SUB]<new>[SI]<end anchor>
  #   Open questions:
  #   - Is this too liberal? Should there be a max replacement count?
  #   - Or is it better to generate one section per occurrence at
  #     a higher tool level, keeping the format strictly exact-match?
  #   - Could also be useful for batch renames (variable/method renaming
  #     within a function scope).
  module Diff
    # A single substitution: old text → new text.
    record Sub, old : Bytes, new : Bytes

    # A pattern unit: either literal anchor text or a substitution.
    alias Unit = Bytes | Sub

    # A section is a sequential pattern of units (anchors + substitutions).
    struct Section
      getter units : Array(Unit)

      def initialize(@units)
      end

      # Build the search pattern (old text concatenated).
      def search_pattern : Bytes
        io = IO::Memory.new
        @units.each do |unit|
          case unit
          when Bytes then io.write(unit)
          when Sub   then io.write(unit.old)
          end
        end
        io.to_slice
      end

      # Build the replacement (new text concatenated).
      def replacement : Bytes
        io = IO::Memory.new
        @units.each do |unit|
          case unit
          when Bytes then io.write(unit)
          when Sub   then io.write(unit.new)
          end
        end
        io.to_slice
      end
    end

    # A file edit: a file path and its sections.
    struct FileEdit
      getter path : Bytes
      getter sections : Array(Section)

      def initialize(@path, @sections)
      end
    end

    # Parse a C0DIFF buffer into a list of file edits.
    def self.parse(buf : Bytes) : Array(FileEdit)
      edits = Array(FileEdit).new
      pos = 0
      len = buf.size.to_i32
      ptr = buf.to_unsafe

      while pos < len
        byte = ptr[pos]
        break if byte == EOT

        if byte == FS
          pos += 1
          edit = parse_file(buf, pos) { |new_pos| pos = new_pos }
          edits << edit
        else
          pos += 1
        end
      end

      edits
    end

    # Parse a C0DIFF buffer into a list of file edits.
    def self.parse(buf : Bytes) : Array(FileEdit)
      edits = Array(FileEdit).new
      pos = 0
      len = buf.size.to_i32
      ptr = buf.to_unsafe

      while pos < len
        byte = ptr[pos]
        break if byte == EOT

        if byte == FS
          pos += 1
          edit, pos = parse_file_at(buf, pos)
          edits << edit
        else
          pos += 1
        end
      end

      edits
    end

    # Apply a C0DIFF buffer to a hash of file contents.
    # Returns the modified file contents. Raises on validation failure.
    # All files are validated before any modifications (atomic semantics).
    def self.apply(diff_buf : Bytes, files : Hash(String, String)) : Hash(String, String)
      edits = parse(diff_buf)
      results = Hash(String, String).new

      # Validate all edits first
      edits.each do |edit|
        path = String.new(edit.path)
        content = files[path]? || raise Error.new("File not found: #{path}")

        # Validate each section's search pattern exists exactly once
        edit.sections.each_with_index do |section, i|
          pattern = String.new(section.search_pattern)
          count = count_occurrences(content, pattern)
          if count == 0
            raise Error.new("Pattern not found in #{path} (section #{i}): #{pattern.inspect}")
          elsif count > 1
            raise Error.new("Pattern found #{count} times in #{path} (section #{i}), expected exactly 1: #{pattern.inspect}")
          end
        end
      end

      # Apply all edits
      edits.each do |edit|
        path = String.new(edit.path)
        content = files[path]

        edit.sections.each do |section|
          pattern = String.new(section.search_pattern)
          replacement = String.new(section.replacement)
          content = content.sub(pattern, replacement)
        end

        results[path] = content
      end

      # Include unmodified files
      files.each do |path, content|
        results[path] = content unless results.has_key?(path)
      end

      results
    end

    # Apply a C0DIFF buffer to files on disk.
    # Validates all files before writing any (atomic semantics).
    def self.apply_files(diff_buf : Bytes, base_dir : String = ".") : Nil
      edits = parse(diff_buf)

      # Read all files and validate
      files = Hash(String, String).new
      edits.each do |edit|
        path = File.join(base_dir, String.new(edit.path))
        unless File.exists?(path)
          raise Error.new("File not found: #{path}")
        end
        files[String.new(edit.path)] = File.read(path)
      end

      results = apply(diff_buf, files)

      # Write all modified files
      edits.each do |edit|
        path = File.join(base_dir, String.new(edit.path))
        File.write(path, results[String.new(edit.path)])
      end
    end

    # Build a C0DIFF document.
    def self.build(& : DiffBuilder ->) : Bytes
      builder = DiffBuilder.new
      yield builder
      builder.to_slice
    end

    private def self.count_occurrences(haystack : String, needle : String) : Int32
      count = 0
      pos = 0
      while (idx = haystack.index(needle, pos))
        count += 1
        pos = idx + needle.size
      end
      count
    end

    # Parse a file edit starting at pos (after FS).
    protected def self.parse_file_at(buf : Bytes, pos : Int32) : {FileEdit, Int32}
      len = buf.size.to_i32
      ptr = buf.to_unsafe

      # Read file path
      path_start = pos
      while pos < len && ptr[pos] >= 0x20_u8
        pos += 1
      end
      path = buf[path_start...pos]

      # Read sections
      sections = Array(Section).new

      while pos < len
        byte = ptr[pos]
        break if byte == FS || byte == EOT

        if byte == GS
          pos += 1
          units, pos = parse_section_at(buf, pos)
          sections << Section.new(units)
        else
          pos += 1
        end
      end

      {FileEdit.new(path, sections), pos}
    end

    # Parse a section's units starting at pos (after GS).
    protected def self.parse_section_at(buf : Bytes, pos : Int32) : {Array(Unit), Int32}
      units = Array(Unit).new
      len = buf.size.to_i32
      ptr = buf.to_unsafe
      in_sub = false
      data_start = pos

      while pos < len
        byte = ptr[pos]
        break if byte == GS || byte == FS || byte == EOT

        case byte
        when US
          # End current data span
          if pos > data_start
            span = collect_data(buf, data_start, pos)
            if in_sub
              # This is the "new" part — complete the Sub
              old = units.pop.as(Bytes)
              units << Sub.new(old, span)
              in_sub = false
            else
              units << span
            end
          end
          pos += 1
          data_start = pos
        when SUB
          # End current data span (this is the "old" part)
          if pos > data_start
            span = collect_data(buf, data_start, pos)
            units << span # temporarily store as old
            in_sub = true
          end
          pos += 1
          data_start = pos
        when DLE
          pos += 2 # skip DLE + escaped byte
        else
          pos += 1
        end
      end

      # Handle trailing data
      if pos > data_start
        span = collect_data(buf, data_start, pos)
        if in_sub
          old = units.pop.as(Bytes)
          units << Sub.new(old, span)
        else
          units << span
        end
      end

      {units, pos}
    end

    # Collect data bytes from a span, handling DLE escapes.
    private def self.collect_data(buf : Bytes, start : Int32, stop : Int32) : Bytes
      ptr = buf.to_unsafe
      # Fast path: no DLE in span
      has_dle = false
      pos = start
      while pos < stop
        if ptr[pos] == DLE
          has_dle = true
          break
        end
        pos += 1
      end

      return buf[start...stop] unless has_dle

      # Slow path: copy with DLE removal
      io = IO::Memory.new(stop - start)
      pos = start
      while pos < stop
        if ptr[pos] == DLE
          pos += 1
          io.write_byte(ptr[pos]) if pos < stop
          pos += 1
        else
          io.write_byte(ptr[pos])
          pos += 1
        end
      end
      io.to_slice
    end

  end

  # Builder for C0DIFF documents.
  class DiffBuilder
    @io : IO::Memory

    def initialize
      @io = IO::Memory.new
    end

    # Add a file edit.
    def file(path : String, & : ->) : Nil
      @io.write_byte(FS)
      @io << path
      yield
    end

    # Add a section (pattern) within the current file.
    def section(& : SectionBuilder ->) : Nil
      @io.write_byte(GS)
      sb = SectionBuilder.new(@io)
      yield sb
    end

    # Convenience: add a simple find/replace section.
    def replace(context_before : String, old_text : String, new_text : String, context_after : String = "") : Nil
      @io.write_byte(GS)
      write_escaped(context_before) unless context_before.empty?
      @io.write_byte(US) unless context_before.empty?
      write_escaped(old_text)
      @io.write_byte(SUB)
      write_escaped(new_text)
      unless context_after.empty?
        @io.write_byte(US)
        write_escaped(context_after)
      end
    end

    def to_slice : Bytes
      @io.to_slice
    end

    private def write_escaped(str : String) : Nil
      str.each_byte do |byte|
        @io.write_byte(DLE) if byte < 0x20_u8
        @io.write_byte(byte)
      end
    end
  end

  # Builder for individual diff sections.
  class SectionBuilder
    def initialize(@io : IO::Memory)
      @first = true
    end

    # Add literal anchor text.
    def anchor(text : String) : Nil
      @io.write_byte(US) unless @first
      write_escaped(text)
      @first = false
    end

    # Add a substitution (old → new).
    def sub(old_text : String, new_text : String) : Nil
      @io.write_byte(US) unless @first
      write_escaped(old_text)
      @io.write_byte(SUB)
      write_escaped(new_text)
      @first = false
    end

    private def write_escaped(str : String) : Nil
      str.each_byte do |byte|
        @io.write_byte(DLE) if byte < 0x20_u8
        @io.write_byte(byte)
      end
    end
  end
end
