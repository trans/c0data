module C0data
  VERSION = "0.1.0"

  # Assigned C0 control codes
  SOH = 0x01_u8 # Header (field name declarations)
  STX = 0x02_u8 # Open nested sub-structure / reference scope
  ETX = 0x03_u8 # Close nested sub-structure / reference scope
  EOT = 0x04_u8 # End of document / message
  ENQ = 0x05_u8 # Reference (enquiry — look up named data)
  DLE = 0x10_u8 # Escape (next byte is literal)
  SUB = 0x1a_u8 # Substitution (old → new, C0-DIFF)
  FS  = 0x1c_u8 # File / Database separator
  GS  = 0x1d_u8 # Group / Table / Section separator
  RS  = 0x1e_u8 # Record / Row separator
  US  = 0x1f_u8 # Unit / Field separator

  # Set of assigned control code bytes for fast lookup
  ASSIGNED = StaticArray[
    false, true,  true,  true,  true,  true,  false, false, # 0x00-0x07
    false, false, false, false, false, false, false, false, # 0x08-0x0F
    true,  false, false, false, false, false, false, false, # 0x10-0x17
    false, false, true,  false, true,  true,  true,  true,  # 0x18-0x1F
  ]
end

require "./c0data/token"
require "./c0data/tokenizer"
require "./c0data/table"
require "./c0data/document"
require "./c0data/builder"
require "./c0data/pretty"
require "./c0data/diff"
