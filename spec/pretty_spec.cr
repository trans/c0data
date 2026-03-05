require "./spec_helper"

describe C0data::Pretty do
  describe ".format" do
    it "formats a simple table" do
      buf = C0data::Builder.build do |b|
        b.group("users", headers: ["name", "amount", "type"]) do
          b.record("Alice", "1502.30", "DEPOSIT")
          b.record("Bob", "340.00", "WITHDRAWAL")
        end
      end

      out = C0data::Pretty.format(buf)
      out.should contain("␝users")
      out.should contain("␁name␟amount␟type")
      out.should contain("␞Alice␟1502.30␟DEPOSIT")
      out.should contain("␞Bob␟340.00␟WITHDRAWAL")
    end

    it "formats a database with file and groups" do
      buf = C0data::Builder.build do |b|
        b.file("mydb") do
          b.group("users", headers: ["name", "amount"]) do
            b.record("Alice", "1502.30")
          end
        end
        b.eot
      end

      out = C0data::Pretty.format(buf)
      out.should contain("␜mydb")
      out.should contain("␝users")
      out.should contain("␁name␟amount")
      out.should contain("␞Alice␟1502.30")
      out.should contain("␄")
    end

    it "formats document-mode sections with depth" do
      buf = C0data::Builder.build do |b|
        b.file("doc") do
          b.section("Chapter 1") do
            b.block("Content here.")
            b.section("Section 1.1", depth: 2) do
              b.block("Nested.")
            end
          end
        end
      end

      out = C0data::Pretty.format(buf)
      out.should contain("␜doc")
      out.should contain("␝Chapter 1")
      out.should contain("␞Content here.")
      out.should contain("␝␝Section 1.1")
      out.should contain("␞Nested.")
    end

    it "formats key-value config" do
      buf = C0data::Builder.build do |b|
        b.group("database") do
          b.record("host", "localhost")
          b.record("port", "5432")
        end
      end

      out = C0data::Pretty.format(buf)
      out.should contain("␝database")
      out.should contain("␞host␟localhost")
      out.should contain("␞port␟5432")
    end
  end

  describe ".parse" do
    it "round-trips a table through format and parse" do
      original = C0data::Builder.build do |b|
        b.group("users", headers: ["name", "amount"]) do
          b.record("Alice", "1502.30")
          b.record("Bob", "340.00")
        end
      end

      pretty = C0data::Pretty.format(original)
      reparsed = C0data::Pretty.parse(pretty)

      # Should produce identical compact bytes
      t = C0data::Table.new(reparsed)
      String.new(t.name).should eq("users")
      t.header_count.should eq(2)
      t.record_count.should eq(2)
      String.new(t.record(0).field(0)).should eq("Alice")
      String.new(t.record(1).field(1)).should eq("340.00")
    end

    it "strips indentation whitespace" do
      pretty = "␜mydb\n  ␝users\n    ␁name␟amount\n    ␞Alice␟100\n"
      buf = C0data::Pretty.parse(pretty)

      tokens = C0data::Tokenizer.new(buf).to_a
      data = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data.map { |t| String.new(t.value(buf)) }
      values.should eq(["mydb", "users", "name", "amount", "Alice", "100"])
    end

    it "trims whitespace adjacent to control codes" do
      pretty = "␞  Alice  ␟  1502.30  "
      buf = C0data::Pretty.parse(pretty)

      tokens = C0data::Tokenizer.new(buf).to_a
      data = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data.map { |t| String.new(t.value(buf)) }
      values.should eq(["Alice", "1502.30"])
    end

    it "preserves whitespace inside STX/ETX (quoting)" do
      pretty = "␞␂  Alice  ␃␟␂  1502.30  ␃"
      buf = C0data::Pretty.parse(pretty)

      tokens = C0data::Tokenizer.new(buf).to_a
      data = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data.map { |t| String.new(t.value(buf)) }
      values.should eq(["  Alice  ", "  1502.30  "])
    end

    it "preserves whitespace inside nested STX/ETX" do
      pretty = "␞␂ outer ␂ inner ␃ still outer ␃"
      buf = C0data::Pretty.parse(pretty)

      # STX, " outer ", STX, " inner ", ETX, " still outer ", ETX
      tokens = C0data::Tokenizer.new(buf).to_a
      stx_count = tokens.count { |t| t.type == C0data::TokenType::STX }
      etx_count = tokens.count { |t| t.type == C0data::TokenType::ETX }
      stx_count.should eq(2)
      etx_count.should eq(2)
    end

    it "preserves spaces between words without trimming" do
      pretty = "␞Alice Smith␟New York"
      buf = C0data::Pretty.parse(pretty)

      tokens = C0data::Tokenizer.new(buf).to_a
      data = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data.map { |t| String.new(t.value(buf)) }
      values.should eq(["Alice Smith", "New York"])
    end
  end

  describe "glyph mapping" do
    it "maps all assigned codes to correct Unicode Control Pictures" do
      C0data::Pretty.glyph(C0data::SOH).should eq('␁')
      C0data::Pretty.glyph(C0data::STX).should eq('␂')
      C0data::Pretty.glyph(C0data::ETX).should eq('␃')
      C0data::Pretty.glyph(C0data::EOT).should eq('␄')
      C0data::Pretty.glyph(C0data::ENQ).should eq('␅')
      C0data::Pretty.glyph(C0data::DLE).should eq('␐')
      C0data::Pretty.glyph(C0data::SUB).should eq('␚')
      C0data::Pretty.glyph(C0data::FS).should eq('␜')
      C0data::Pretty.glyph(C0data::GS).should eq('␝')
      C0data::Pretty.glyph(C0data::RS).should eq('␞')
      C0data::Pretty.glyph(C0data::US).should eq('␟')
    end
  end
end
