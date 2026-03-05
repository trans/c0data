require "./spec_helper"

# Helper to build byte buffers with control codes.
# Accepts strings and UInt8 values, concatenates them.
def buf(*parts : String | UInt8) : Bytes
  io = IO::Memory.new
  parts.each do |part|
    case part
    when String then io.write(part.to_slice)
    when UInt8  then io.write_byte(part)
    end
  end
  io.to_slice
end

describe C0data::Tokenizer do

  describe "data tokens" do
    it "emits a single data token for plain text" do
      b = buf("hello")
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::Data)
      String.new(tokens[0].value(b)).should eq("hello")
    end

    it "handles empty input" do
      b = Bytes.empty
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(0)
    end
  end

  describe "control codes" do
    it "emits FS token" do
      b = buf(C0data::FS)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::FS)
    end

    it "emits GS token" do
      b = buf(C0data::GS)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::GS)
    end

    it "emits RS token" do
      b = buf(C0data::RS)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::RS)
    end

    it "emits US token" do
      b = buf(C0data::US)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::US)
    end

    it "emits SOH token" do
      b = buf(C0data::SOH)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::SOH)
    end

    it "emits STX/ETX tokens" do
      b = buf(C0data::STX, C0data::ETX)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(2)
      tokens[0].type.should eq(C0data::TokenType::STX)
      tokens[1].type.should eq(C0data::TokenType::ETX)
    end

    it "emits EOT token" do
      b = buf(C0data::EOT)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::EOT)
    end

    it "emits ENQ token" do
      b = buf(C0data::ENQ)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::ENQ)
    end

    it "emits SUB token" do
      b = buf(C0data::SUB)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::SUB)
    end
  end

  describe "tabular data" do
    it "tokenizes a simple table" do
      # [FS]mydb[GS]users[SOH]name[US]amount[RS]Alice[US]1502.30
      b = buf(
        C0data::FS, "mydb",
        C0data::GS, "users",
        C0data::SOH, "name", C0data::US, "amount",
        C0data::RS, "Alice", C0data::US, "1502.30"
      )
      tokens = C0data::Tokenizer.new(b).to_a

      types = tokens.map(&.type)
      types.should eq([
        C0data::TokenType::FS, C0data::TokenType::Data,
        C0data::TokenType::GS, C0data::TokenType::Data,
        C0data::TokenType::SOH, C0data::TokenType::Data,
        C0data::TokenType::US, C0data::TokenType::Data,
        C0data::TokenType::RS, C0data::TokenType::Data,
        C0data::TokenType::US, C0data::TokenType::Data,
      ])

      data_tokens = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data_tokens.map { |t| String.new(t.value(b)) }
      values.should eq(["mydb", "users", "name", "amount", "Alice", "1502.30"])
    end
  end

  describe "DLE escaping" do
    it "escapes a control code as data" do
      # The value contains a literal RS (0x1E)
      b = buf("hello", C0data::DLE, C0data::RS, "world")
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(3)
      tokens[0].type.should eq(C0data::TokenType::Data)
      tokens[1].type.should eq(C0data::TokenType::Data) # escaped byte
      tokens[2].type.should eq(C0data::TokenType::Data)

      String.new(tokens[0].value(b)).should eq("hello")
      tokens[1].value(b)[0].should eq(C0data::RS) # literal 0x1E
      String.new(tokens[2].value(b)).should eq("world")
    end

    it "escapes DLE itself" do
      b = buf(C0data::DLE, C0data::DLE)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::Data)
      tokens[0].value(b)[0].should eq(C0data::DLE)
    end

    it "raises on DLE at end of input" do
      b = buf(C0data::DLE)
      expect_raises(C0data::UnexpectedEndError) do
        C0data::Tokenizer.new(b).to_a
      end
    end
  end

  describe "strict mode" do
    it "rejects unassigned control codes" do
      b = buf(0x07_u8) # BEL — unassigned
      expect_raises(C0data::UnassignedCodeError) do
        C0data::Tokenizer.new(b).to_a
      end
    end

    it "rejects NUL" do
      b = buf(0x00_u8)
      expect_raises(C0data::UnassignedCodeError) do
        C0data::Tokenizer.new(b).to_a
      end
    end

    it "allows DEL (0x7F) as data" do
      b = buf(0x7f_u8)
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(1)
      tokens[0].type.should eq(C0data::TokenType::Data)
    end
  end

  describe "edge cases" do
    it "handles consecutive delimiters (empty fields)" do
      b = buf(C0data::RS, C0data::US, C0data::US, C0data::RS)
      tokens = C0data::Tokenizer.new(b).to_a
      types = tokens.map(&.type)
      types.should eq([
        C0data::TokenType::RS,
        C0data::TokenType::US,
        C0data::TokenType::US,
        C0data::TokenType::RS,
      ])
    end

    it "handles data between every control code" do
      b = buf(C0data::FS, "a", C0data::GS, "b", C0data::RS, "c", C0data::US, "d")
      tokens = C0data::Tokenizer.new(b).to_a
      tokens.size.should eq(8)
      data_tokens = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data_tokens.map { |t| String.new(t.value(b)) }
      values.should eq(["a", "b", "c", "d"])
    end

    it "handles UTF-8 data" do
      b = buf(C0data::RS, "日本語", C0data::US, "emoji 🎉")
      tokens = C0data::Tokenizer.new(b).to_a
      data_tokens = tokens.select { |t| t.type == C0data::TokenType::Data }
      values = data_tokens.map { |t| String.new(t.value(b)) }
      values.should eq(["日本語", "emoji 🎉"])
    end

    it "handles multiple GS for depth" do
      b = buf(C0data::GS, C0data::GS, C0data::GS, "deep")
      tokens = C0data::Tokenizer.new(b).to_a
      types = tokens.map(&.type)
      types.should eq([
        C0data::TokenType::GS,
        C0data::TokenType::GS,
        C0data::TokenType::GS,
        C0data::TokenType::Data,
      ])
    end
  end
end
