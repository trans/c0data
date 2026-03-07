require "../src/c0"
require "../src/c0/csv"
require "../src/c0/json"

def time_it(label : String, iterations : Int32 = 5, &block : -> Nil) : Nil
  # warmup
  block.call

  total = 0.0
  best = Float64::MAX

  iterations.times do
    t0 = Time.instant
    block.call
    elapsed = (Time.instant - t0).total_seconds
    total += elapsed
    best = elapsed if elapsed < best
  end

  avg = total / iterations
  printf "  %-36s  avg %8.2f ms   best %8.2f ms\n", label, avg * 1000, best * 1000
end

# ── Generate test data ──────────────────────────────────

rows = (ARGV[0]? || "10000").to_i.clamp(100, 1_000_000)

puts
puts "c0data conversion benchmark (#{rows} rows)"
puts "═══════════════════════════════════════════════════════════════════"
puts

# Build C0DATA compact buffer
c0buf = C0::Builder.build do |b|
  b.group("data", headers: ["id", "name", "value", "tags", "label"]) do
    rows.times do |i|
      b.record(i.to_s, "item-#{i}", "#{i * 17 % 1000}.#{(i * 31 % 100).to_s.rjust(2, '0')}", "alpha,beta,gamma", "entry ##{i}")
    end
  end
end

# Build all forms
pretty_str = C0::Pretty.format(c0buf)
csv_str = C0::CSV.to_csv(c0buf)
json_str = C0::JSON.to_json(c0buf)
yaml_str = C0::JSON.to_yaml(c0buf)

# Pre-parse pretty to compact for pretty-input benchmarks
pretty_buf = C0::Pretty.parse(pretty_str)

puts "  Sizes"
puts "  ──────────────────────────────────────────────────────────"
printf "  %-12s  %8d bytes  (baseline)\n", "Compact", c0buf.size
printf "  %-12s  %8d bytes  (+%d%%)\n", "Pretty", pretty_str.bytesize, ((pretty_str.bytesize - c0buf.size) * 100.0 / c0buf.size).round
printf "  %-12s  %8d bytes  (+%d%%)\n", "CSV", csv_str.bytesize, ((csv_str.bytesize - c0buf.size) * 100.0 / c0buf.size).round
printf "  %-12s  %8d bytes  (+%d%%)\n", "YAML", yaml_str.bytesize, ((yaml_str.bytesize - c0buf.size) * 100.0 / c0buf.size).round
printf "  %-12s  %8d bytes  (+%d%%)\n", "JSON", json_str.bytesize, ((json_str.bytesize - c0buf.size) * 100.0 / c0buf.size).round

puts
puts "  Export from compact (C0DATA →)"
puts "  ──────────────────────────────────────────────────────────"

time_it("compact → CSV") { C0::CSV.to_csv(c0buf) }
time_it("compact → JSON") { C0::JSON.to_json(c0buf) }
time_it("compact → YAML") { C0::JSON.to_yaml(c0buf) }
time_it("compact → pretty") { C0::Pretty.format(c0buf) }

puts
puts "  Export from pretty (pretty C0DATA →)"
puts "  ──────────────────────────────────────────────────────────"

time_it("pretty → compact → CSV") do
  buf = C0::Pretty.parse(pretty_str)
  C0::CSV.to_csv(buf)
end

time_it("pretty → compact → JSON") do
  buf = C0::Pretty.parse(pretty_str)
  C0::JSON.to_json(buf)
end

time_it("pretty → compact → YAML") do
  buf = C0::Pretty.parse(pretty_str)
  C0::JSON.to_yaml(buf)
end

puts
puts "  Import (→ C0DATA compact)"
puts "  ──────────────────────────────────────────────────────────"

time_it("CSV → compact") { C0::CSV.from_csv(csv_str, group_name: "data") }
time_it("JSON → compact") { C0::JSON.from_json(json_str) }
time_it("YAML → compact") { C0::JSON.from_yaml(yaml_str) }
time_it("pretty → compact") { C0::Pretty.parse(pretty_str) }

puts
puts "  Round-trips"
puts "  ──────────────────────────────────────────────────────────"

time_it("CSV → compact → CSV") do
  buf = C0::CSV.from_csv(csv_str, group_name: "data")
  C0::CSV.to_csv(buf)
end

time_it("JSON → compact → JSON") do
  buf = C0::JSON.from_json(json_str)
  C0::JSON.to_json(buf)
end

time_it("pretty → compact → pretty") do
  buf = C0::Pretty.parse(pretty_str)
  C0::Pretty.format(buf)
end

time_it("JSON → compact → pretty → CSV") do
  buf = C0::JSON.from_json(json_str)
  pretty = C0::Pretty.format(buf)
  buf2 = C0::Pretty.parse(pretty)
  C0::CSV.to_csv(buf2)
end

puts
puts "  Note: YAML throughput limited by Crystal's stdlib YAML builder."
puts
