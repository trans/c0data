require "./spec_helper"

describe C0::Builder do
  it "builds a simple table" do
    buf = C0::Builder.build do |b|
      b.group("users", headers: ["name", "amount"]) do
        b.record("Alice", "1502.30")
        b.record("Bob", "340.00")
      end
    end

    # Parse it back with Table
    t = C0::Table.new(buf)
    String.new(t.name).should eq("users")
    t.header_count.should eq(2)
    String.new(t.header(0)).should eq("name")
    String.new(t.header(1)).should eq("amount")
    t.record_count.should eq(2)
    String.new(t.record(0).field(0)).should eq("Alice")
    String.new(t.record(0).field(1)).should eq("1502.30")
    String.new(t.record(1).field(0)).should eq("Bob")
    String.new(t.record(1).field(1)).should eq("340.00")
  end

  it "builds a full database with multiple tables" do
    buf = C0::Builder.build do |b|
      b.file("mydb") do
        b.group("users", headers: ["name", "type"]) do
          b.record("Alice", "ADMIN")
        end
        b.group("products", headers: ["id", "name"]) do
          b.record("01", "Widget")
        end
      end
      b.eot
    end

    # Verify tokenizer sees the structure
    tokens = C0::Tokenizer.new(buf).to_a
    types = tokens.map(&.type)
    types.should eq([
      C0::TokenType::FS, C0::TokenType::Data,    # file "mydb"
      C0::TokenType::GS, C0::TokenType::Data,    # group "users"
      C0::TokenType::SOH, C0::TokenType::Data,   # header "name"
      C0::TokenType::US, C0::TokenType::Data,    # header "type"
      C0::TokenType::RS, C0::TokenType::Data,    # "Alice"
      C0::TokenType::US, C0::TokenType::Data,    # "ADMIN"
      C0::TokenType::GS, C0::TokenType::Data,    # group "products"
      C0::TokenType::SOH, C0::TokenType::Data,   # header "id"
      C0::TokenType::US, C0::TokenType::Data,    # header "name"
      C0::TokenType::RS, C0::TokenType::Data,    # "01"
      C0::TokenType::US, C0::TokenType::Data,    # "Widget"
      C0::TokenType::EOT,                            # end
    ])
  end

  it "escapes control codes in field values" do
    buf = C0::Builder.build do |b|
      b.group("t") do
        b.record("hello\x1eworld") # contains a literal RS
      end
    end

    # Tokenizer should see DLE-escaped data, not an RS
    tokens = C0::Tokenizer.new(buf).to_a
    types = tokens.map(&.type)
    # GS, Data("t"), RS, Data("hello"), Data(0x1e), Data("world")
    types.count(C0::TokenType::RS).should eq(1) # only the record RS, not the escaped one
  end

  it "builds document-mode sections" do
    buf = C0::Builder.build do |b|
      b.file("doc") do
        b.section("Chapter 1") do
          b.block("First paragraph.")
          b.block("A list:")
          b.item("Item one")
          b.item("Item two")
          b.section("Section 1.1", depth: 2) do
            b.block("Nested content.")
          end
        end
      end
    end

    tokens = C0::Tokenizer.new(buf).to_a
    types = tokens.map(&.type)

    # FS, Data, GS, Data, RS, Data, RS, Data, US, Data, US, Data,
    # GS, GS, Data, RS, Data
    types[0].should eq(C0::TokenType::FS)
    types[2].should eq(C0::TokenType::GS)    # Chapter 1
    types[4].should eq(C0::TokenType::RS)     # First paragraph
    types[6].should eq(C0::TokenType::RS)     # A list
    types[8].should eq(C0::TokenType::US)     # Item one
    types[10].should eq(C0::TokenType::US)    # Item two
    types[12].should eq(C0::TokenType::GS)    # GS×2 = Section 1.1
    types[13].should eq(C0::TokenType::GS)
  end

  it "builds key-value config" do
    buf = C0::Builder.build do |b|
      b.group("database") do
        b.record("host", "localhost")
        b.record("port", "5432")
      end
      b.group("server") do
        b.record("host", "0.0.0.0")
        b.record("port", "8080")
      end
    end

    # Read first group as table
    t = C0::Table.new(buf)
    String.new(t.name).should eq("database")
    String.new(t.record(0).field(0)).should eq("host")
    String.new(t.record(0).field(1)).should eq("localhost")
    String.new(t.record(1).field(0)).should eq("port")
    String.new(t.record(1).field(1)).should eq("5432")
  end

  it "builds simple references" do
    buf = C0::Builder.build do |b|
      b.group("tags") do
        b.record("001", "Admin")
      end
    end

    tokens = C0::Tokenizer.new(buf).to_a
    tokens.size.should be > 0
  end

  it "round-trips with tokenizer" do
    buf = C0::Builder.build do |b|
      b.file("test") do
        b.group("g", headers: ["a", "b", "c"]) do
          b.record("1", "2", "3")
          b.record("4", "5", "6")
        end
      end
    end

    t = C0::Table.new(buf, offset: 5) # skip FS + "test"
    String.new(t.name).should eq("g")
    t.record_count.should eq(2)
    String.new(t.record(0).field(0)).should eq("1")
    String.new(t.record(0).field(2)).should eq("3")
    String.new(t.record(1).field(1)).should eq("5")
  end
end
