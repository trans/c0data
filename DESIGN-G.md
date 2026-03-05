# Project: C0-Schema (The "Invisible" Data Protocol)
**Status:** Specification v1.0
**Goal:** High-performance, zero-copy, typed data serialization using ASCII C0 Control Codes.

---

## 1. The Control Character Map
We utilize the hierarchical nature of the C0 set to define data boundaries.

| Byte | Hex  | Abbr | Role | Logical Scope |
| :--- | :--- | :--- | :--- | :--- |
| `02` | 0x02 | **STX** | Start of Text | Packet Envelope Open |
| `03` | 0x03 | **ETX** | End of Text | Packet Envelope Close |
| `1C` | 0x1C | **FS** | File Separator | Database/Stream Level |
| `1D` | 0x1D | **GS** | Group Separator | Collection/Array Level |
| `1E` | 0x1E | **RS** | Record Separator | Object/Row Level |
| `1F` | 0x1F | **US** | Unit Separator | Field/Property Level |

---

## 2. Structural Specification

### 2.1 The "Typed" Packet
Every transmission must begin with `STX` followed immediately by a **Type ID Byte**. This removes the need for "key" strings (e.g., `"user_name":`).

**Format:**
`[STX] [TypeID] [Field1] [US] [Field2] [US] ... [ETX]`

### 2.2 Nested Collections
For arrays or nested objects, use `GS` to wrap the collection and `RS` to delimit items within it.

**Example (User with multiple Tags):**
`[STX][0x01]Alice[US][GS]Admin[RS]Editor[RS]User[GS][ETX]`
*Interpretation: User(Name: Alice, Tags: [Admin, Editor, User])*

---

## 3. Implementation Requirements (Zig / Rust / Crystal)

### 3.1 Zero-Copy Parsing
The agent should not "deserialize" into new strings. It must:
1.  Receive a pointer to a `[]const u8` buffer.
2.  Validate the `STX` and `TypeID`.
3.  Use SIMD-accelerated scanning (like `std.mem.splitScalar` in Zig) to find `US`, `RS`, and `GS` positions.
4.  Return a `Struct` containing **Slices** (pointers back into the original buffer).

### 3.2 Validation State Machine
Validation is performed by counting delimiters.
* **User Schema (Type 0x01):** Must contain exactly 2 `US` delimiters before `ETX`.
* **Error Handling:** If `ETX` is reached before the expected number of `US` units, the packet is malformed.



---

## 4. Competitive Advantages for the Coding Agent
* **No Escaping:** Unlike JSON, where a quote `"` in the data breaks the parser, C0 characters (0x00-0x1F) almost never appear in standard UTF-8 text strings. No `\"` escaping is required.
* **Hardware Alignment:** The parser should be written to take advantage of **Branch Prediction**. Since fields are positional, the CPU will learn the "shape" of the data after the first few packets.
* **SQLite Integration:** The design should include a helper to store these as `BLOB` and a custom SQL function `c0_extract(blob, index)` for ultra-fast indexing.

---

## 5. Sample Task for Agent
"Implement a Zig parser that takes a C0-encoded buffer representing a 'SensorReading' (Type 0x03). Fields: `timestamp` (i64 as string), `sensor_id` (string), `value` (f64 as string). Return a struct using slices. Bench it against a JSON parser using the same data."
