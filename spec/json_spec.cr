require "./spec_helper"
require "../src/c0data/json"

describe C0data::JSON do
  describe ".to_json" do
    it "exports tabular group as array of objects" do
      buf = C0data::Builder.build do |b|
        b.group("users", headers: ["name", "amount"]) do
          b.record("Alice", "100")
          b.record("Bob", "200")
        end
      end

      result = ::JSON.parse(C0data::JSON.to_json(buf))
      result["users"].size.should eq(2)
      result["users"][0]["name"].as_s.should eq("Alice")
      result["users"][0]["amount"].as_s.should eq("100")
      result["users"][1]["name"].as_s.should eq("Bob")
    end

    it "exports key-value group as flat object" do
      buf = C0data::Builder.build do |b|
        b.group("database") do
          b.record("host", "localhost")
          b.record("port", "5432")
        end
      end

      result = ::JSON.parse(C0data::JSON.to_json(buf))
      result["database"]["host"].as_s.should eq("localhost")
      result["database"]["port"].as_s.should eq("5432")
    end

    it "exports multi-field records without headers as array of arrays" do
      buf = C0data::Builder.build do |b|
        b.group("data") do
          b.record("a", "b", "c")
          b.record("d", "e", "f")
        end
      end

      result = ::JSON.parse(C0data::JSON.to_json(buf))
      result["data"][0][0].as_s.should eq("a")
      result["data"][0][2].as_s.should eq("c")
      result["data"][1][1].as_s.should eq("e")
    end

    it "exports full document with multiple groups" do
      buf = C0data::Builder.build do |b|
        b.file("mydb") do
          b.group("users", headers: ["name"]) do
            b.record("Alice")
          end
          b.group("config") do
            b.record("host", "localhost")
          end
        end
      end

      result = ::JSON.parse(C0data::JSON.to_json(buf))
      result["mydb"]["users"][0]["name"].as_s.should eq("Alice")
      result["mydb"]["config"]["host"].as_s.should eq("localhost")
    end

    it "handles DLE-escaped field values" do
      buf = C0data::Builder.build do |b|
        b.group("data", headers: ["val"]) do
          b.record("hello\x1fworld") # US in value gets DLE-escaped by builder
        end
      end

      result = ::JSON.parse(C0data::JSON.to_json(buf))
      result["data"][0]["val"].as_s.should eq("hello\x1fworld")
    end

    it "handles empty group" do
      buf = C0data::Builder.build do |b|
        b.group("empty") {}
      end

      result = ::JSON.parse(C0data::JSON.to_json(buf))
      result["empty"].as_a.size.should eq(0)
    end
  end

  describe ".to_yaml" do
    it "exports tabular group as YAML" do
      buf = C0data::Builder.build do |b|
        b.group("users", headers: ["name", "amount"]) do
          b.record("Alice", "100")
          b.record("Bob", "200")
        end
      end

      result = ::YAML.parse(C0data::JSON.to_yaml(buf))
      result["users"][0]["name"].as_s.should eq("Alice")
      result["users"][0]["amount"].as_s.should eq("100")
      result["users"][1]["name"].as_s.should eq("Bob")
    end

    it "exports key-value group as YAML" do
      buf = C0data::Builder.build do |b|
        b.group("config") do
          b.record("host", "0.0.0.0")
          b.record("port", "8080")
        end
      end

      result = ::YAML.parse(C0data::JSON.to_yaml(buf))
      result["config"]["host"].as_s.should eq("0.0.0.0")
      result["config"]["port"].as_s.should eq("8080")
    end

    it "exports full document as YAML" do
      buf = C0data::Builder.build do |b|
        b.file("app") do
          b.group("settings") do
            b.record("debug", "true")
          end
        end
      end

      result = ::YAML.parse(C0data::JSON.to_yaml(buf))
      result["app"]["settings"]["debug"].as_s.should eq("true")
    end
  end
end
