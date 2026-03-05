require "csv"

module C0data
  module CSV
    # Convert CSV text to C0DATA compact bytes.
    #
    # The first row is treated as headers, remaining rows as records.
    # The result is a single group (GS + name + SOH headers + RS records).
    def self.from_csv(input : String, group_name : String = "data") : Bytes
      rows = ::CSV.parse(input)
      return Bytes.empty if rows.empty?

      Builder.build do |b|
        headers = rows[0]
        b.group(group_name, headers: headers) do
          rows[1..].each do |row|
            b.record(row)
          end
        end
      end
    end

    # Convert C0DATA compact bytes to CSV text.
    #
    # Expects a buffer containing at least one group with tabular data.
    # Outputs headers (if present) as the first row, then each record.
    def self.to_csv(buf : Bytes) : String
      table = find_table(buf)
      ::CSV.build do |csv|
        if table.header_count > 0
          csv.row do |row|
            table.header_count.times do |i|
              row << String.new(table.header(i))
            end
          end
        end
        table.each_record do |rec|
          csv.row do |row|
            rec.field_count.times do |i|
              row << unescape(rec.field(i))
            end
          end
        end
      end
    end

    # Find the first table in the buffer. Tries Document parsing first
    # (for FS-prefixed data), falls back to bare Table.
    private def self.find_table(buf : Bytes) : Table
      if buf.size > 0 && buf[0] == FS
        doc = Document.new(buf)
        if doc.group_count > 0
          return doc.group(0).table
        end
      end
      Table.new(buf)
    end

    # Unescape DLE sequences in a field value, returning a String.
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
