require "../src/c0"

# Generates a C0DATA document equivalent to YAM's benchmark YAML.
#
# YAML version:
#   metadata:
#     name: benchmark-data
#     version: 1.2.0
#     generated: true
#   entries:
#     - id: 0
#       name: "item-0"
#       value: 0.00
#       tags: [alpha, beta, gamma]
#       nested:
#         x: 0
#         y: 0
#         label: 'entry #0'
#
# C0DATA equivalent:
#   [FS]benchmark
#   [GS]metadata
#   [SOH]key[US]value
#   [RS]name[US]benchmark-data
#   [RS]version[US]1.2.0
#   [RS]generated[US]true
#   [GS]entries
#   [SOH]id[US]name[US]value[US]tags[US]x[US]y[US]label
#   [RS]0[US]item-0[US]0.00[US]alpha,beta,gamma[US]0[US]0[US]entry #0
#   ...
#
def generate_c0data(target_size : Int32) : Bytes
  io = IO::Memory.new(target_size + 4096)

  # File header
  io.write_byte(C0::FS)
  io << "benchmark"

  # Metadata group (key-value style)
  io.write_byte(C0::GS)
  io << "metadata"
  io.write_byte(C0::SOH)
  io << "key"
  io.write_byte(C0::US)
  io << "value"
  io.write_byte(C0::RS)
  io << "name"
  io.write_byte(C0::US)
  io << "benchmark-data"
  io.write_byte(C0::RS)
  io << "version"
  io.write_byte(C0::US)
  io << "1.2.0"
  io.write_byte(C0::RS)
  io << "generated"
  io.write_byte(C0::US)
  io << "true"

  # Entries group (tabular style)
  io.write_byte(C0::GS)
  io << "entries"
  io.write_byte(C0::SOH)
  io << "id"
  io.write_byte(C0::US)
  io << "name"
  io.write_byte(C0::US)
  io << "value"
  io.write_byte(C0::US)
  io << "tags"
  io.write_byte(C0::US)
  io << "x"
  io.write_byte(C0::US)
  io << "y"
  io.write_byte(C0::US)
  io << "label"

  item = 0
  while io.size < target_size
    io.write_byte(C0::RS)
    io << item
    io.write_byte(C0::US)
    io << "item-"
    io << item
    io.write_byte(C0::US)
    io << (item &* 17 % 1000)
    io << "."
    io << (item &* 31 % 100).to_s.rjust(2, '0')
    io.write_byte(C0::US)
    io << "alpha,beta,gamma"
    io.write_byte(C0::US)
    io << (item &* 7 % 500)
    io.write_byte(C0::US)
    io << (item &* 13 % 500)
    io.write_byte(C0::US)
    io << "entry #"
    io << item
    item += 1
  end

  io.write_byte(C0::EOT)
  io.to_slice
end

def bench_c0data(buf : Bytes) : {Float64, Int32}
  t0 = Time.instant
  count = 0

  tokenizer = C0::Tokenizer.new(buf)
  tokenizer.each do |_token|
    count += 1
  end

  {(Time.instant - t0).total_seconds, count}
end

# ── Main ──────────────────────────────────────────────────

target_mb = (ARGV[0]? || "10").to_i.clamp(1, 100)
target_size = target_mb * 1024 * 1024

puts
puts "c0data tokenizer benchmark"
puts "═══════════════════════════════════════════════════════════"
puts

print "  Generating #{target_mb} MB C0DATA document..."
buf = generate_c0data(target_size)
size_mb = buf.size / (1024.0 * 1024.0)
puts " done"
puts "  Generated: #{"%.2f" % size_mb} MB (#{buf.size} bytes)"
puts

# warmup
bench_c0data(buf)

# benchmark: 5 iterations
iterations = 5
total = 0.0
best = Float64::MAX

printf "  %-10s  %-12s  %-12s  %-10s\n", "Run", "Time (ms)", "MB/s", "Tokens"
puts "  ──────────────────────────────────────────────────"

iterations.times do |i|
  elapsed, tokens = bench_c0data(buf)
  mbps = size_mb / elapsed
  total += elapsed
  best = elapsed if elapsed < best

  printf "  %-10d  %-12.2f  %-12.1f  %-10d\n", i + 1, elapsed * 1000, mbps, tokens
end

avg = total / iterations
avg_mbps = size_mb / avg
best_mbps = size_mb / best

puts "  ──────────────────────────────────────────────────"
printf "  avg         %-12.2f  %-12.1f\n", avg * 1000, avg_mbps
printf "  best        %-12.2f  %-12.1f\n", best * 1000, best_mbps

puts
puts "  Note: YAM scanner typically achieves ~420 MB/s on equivalent data."
puts "  YAM is a C library; this is Crystal. Compare accordingly."
puts
