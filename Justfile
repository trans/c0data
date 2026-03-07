# C0DATA project tasks

# Build c0fmt CLI tool
build:
    crystal build src/c0fmt.cr -o bin/c0fmt --release

# Run all specs
test:
    crystal spec

# Generate all docs
docs: docs-tech docs-api

# Generate technical reference HTML from markdown
docs-tech:
    pandoc docs/tech/reference.md \
        -o docs/tech/index.html \
        --standalone \
        --toc \
        --toc-depth=3 \
        --metadata title="C0DATA Technical Reference"

# Generate Crystal API docs
docs-api:
    crystal doc -o docs/api

# Run tokenizer benchmark (default 10 MB)
bench-tokenizer size="10":
    crystal build bench/bench_tokenizer.cr -o bench/bench_tokenizer --release
    ./bench/bench_tokenizer {{size}}

# Run conversion benchmark (default 10000 rows)
bench-convert rows="10000":
    crystal build bench/bench_convert.cr -o bench/bench_convert --release
    ./bench/bench_convert {{rows}}

# Run all benchmarks
bench: bench-tokenizer bench-convert
