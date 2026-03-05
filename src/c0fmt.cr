require "option_parser"
require "./c0data"
require "./c0data/csv"

command = "pretty"
output_file : String? = nil
group_name : String? = nil
input_file : String? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: c0fmt [command] [options] [file]"

  parser.on("-o FILE", "--output=FILE", "Write to file (default: stdout)") { |f| output_file = f }
  parser.on("-g NAME", "--group=NAME", "Group name for csv-import (default: filename stem)") { |n| group_name = n }
  parser.on("-h", "--help", "Show help") do
    puts parser
    exit
  end

  parser.unknown_args do |args, _|
    args.each do |arg|
      case arg
      when "pretty", "compact", "csv-import", "csv-export", "json-import", "json-export", "yaml-import", "yaml-export", "validate"
        command = arg
      else
        input_file = arg
      end
    end
  end
end

# Read input from file or stdin.
input = if file = input_file
           File.read(file)
         else
           STDIN.gets_to_end
         end

# Resolve group name for csv-import.
gname : String = group_name || input_file.try { |f| File.basename(f, File.extname(f)) } || "data"

# Auto-detect: if command is "pretty" and input contains control pictures,
# it's already pretty — switch to compact. And vice versa.
def pretty_input?(input : String) : Bool
  input.each_char do |c|
    return true if c.ord >= 0x2400 && c.ord <= 0x241F
  end
  false
end

# Execute command.
result = case command
         when "pretty"
           buf = if pretty_input?(input)
                   # Already pretty, parse to compact first then re-format
                   C0data::Pretty.parse(input)
                 else
                   input.to_slice
                 end
           C0data::Pretty.format(buf)
         when "compact"
           buf = if pretty_input?(input)
                   C0data::Pretty.parse(input)
                 else
                   input.to_slice
                 end
           String.new(buf)
         when "csv-import"
           buf = C0data::CSV.from_csv(input, group_name: gname)
           String.new(buf)
         when "json-import"
           buf = C0data::JSON.from_json(input, group_name: gname)
           String.new(buf)
         when "yaml-import"
           buf = C0data::JSON.from_yaml(input, group_name: gname)
           String.new(buf)
         when "csv-export"
           buf = if pretty_input?(input)
                   C0data::Pretty.parse(input)
                 else
                   input.to_slice
                 end
           C0data::CSV.to_csv(buf)
         when "json-export"
           buf = if pretty_input?(input)
                   C0data::Pretty.parse(input)
                 else
                   input.to_slice
                 end
           C0data::JSON.to_json(buf)
         when "yaml-export"
           buf = if pretty_input?(input)
                   C0data::Pretty.parse(input)
                 else
                   input.to_slice
                 end
           C0data::JSON.to_yaml(buf)
         when "validate"
           buf = if pretty_input?(input)
                   C0data::Pretty.parse(input)
                 else
                   input.to_slice
                 end
           begin
             C0data::Tokenizer.new(buf).each { }
             STDERR.puts "valid"
             exit 0
           rescue ex : C0data::Error
             STDERR.puts "invalid: #{ex.message}"
             exit 1
           end
         else
           STDERR.puts "Unknown command: #{command}"
           exit 1
         end

# Write output.
if file = output_file
  File.write(file, result)
else
  print result
end
