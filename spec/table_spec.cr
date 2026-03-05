require "./spec_helper"

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

describe C0data::Table do
  it "reads group name" do
    b = buf(C0data::GS, "users", C0data::RS, "Alice")
    t = C0data::Table.new(b)
    String.new(t.name).should eq("users")
  end

  it "reads SOH headers" do
    b = buf(C0data::GS, "users", C0data::SOH, "name", C0data::US, "amount", C0data::RS, "Alice", C0data::US, "1502.30")
    t = C0data::Table.new(b)
    t.header_count.should eq(2)
    String.new(t.header(0)).should eq("name")
    String.new(t.header(1)).should eq("amount")
  end

  it "reads records and fields" do
    b = buf(
      C0data::GS, "users",
      C0data::SOH, "name", C0data::US, "amount", C0data::US, "type",
      C0data::RS, "Alice", C0data::US, "1502.30", C0data::US, "DEPOSIT",
      C0data::RS, "Bob", C0data::US, "340.00", C0data::US, "WITHDRAWAL"
    )
    t = C0data::Table.new(b)

    t.record_count.should eq(2)

    String.new(t.record(0).field(0)).should eq("Alice")
    String.new(t.record(0).field(1)).should eq("1502.30")
    String.new(t.record(0).field(2)).should eq("DEPOSIT")

    String.new(t.record(1).field(0)).should eq("Bob")
    String.new(t.record(1).field(1)).should eq("340.00")
    String.new(t.record(1).field(2)).should eq("WITHDRAWAL")
  end

  it "handles table without SOH header" do
    b = buf(
      C0data::GS, "data",
      C0data::RS, "a", C0data::US, "b",
      C0data::RS, "c", C0data::US, "d"
    )
    t = C0data::Table.new(b)
    t.header_count.should eq(0)
    t.record_count.should eq(2)
    String.new(t.record(0).field(0)).should eq("a")
    String.new(t.record(1).field(1)).should eq("d")
  end

  it "stops at next GS boundary" do
    b = buf(
      C0data::GS, "t1",
      C0data::RS, "a", C0data::US, "b",
      C0data::GS, "t2",
      C0data::RS, "c", C0data::US, "d"
    )
    t = C0data::Table.new(b)
    t.record_count.should eq(1)
    String.new(t.name).should eq("t1")
  end

  it "stops at EOT" do
    b = buf(
      C0data::GS, "t1",
      C0data::RS, "x",
      C0data::EOT
    )
    t = C0data::Table.new(b)
    t.record_count.should eq(1)
    String.new(t.record(0).field(0)).should eq("x")
  end

  it "handles empty fields" do
    b = buf(
      C0data::GS, "t",
      C0data::RS, C0data::US, "val", C0data::US
    )
    t = C0data::Table.new(b)
    t.record(0).field_count.should eq(3)
    t.record(0).field(0).size.should eq(0)
    String.new(t.record(0).field(1)).should eq("val")
    t.record(0).field(2).size.should eq(0)
  end

  it "handles DLE-escaped bytes in fields" do
    b = buf(
      C0data::GS, "t",
      C0data::RS, "hello", C0data::DLE, C0data::US, "world"
    )
    t = C0data::Table.new(b)
    # DLE+US is escaped, so this is one field, not two
    t.record(0).field_count.should eq(1)
  end

  it "iterates records" do
    b = buf(
      C0data::GS, "t",
      C0data::RS, "a",
      C0data::RS, "b",
      C0data::RS, "c"
    )
    t = C0data::Table.new(b)
    names = [] of String
    t.each_record { |r| names << String.new(r.field(0)) }
    names.should eq(["a", "b", "c"])
  end
end
