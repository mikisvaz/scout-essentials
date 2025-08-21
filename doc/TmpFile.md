# TmpFile

TmpFile provides small helpers to create and manage temporary files and directories used throughout the framework. It offers safe temporary-path generation, scoped helpers that create and remove temporary files/dirs automatically, and a persistence-path helper (tmp_for_file) used by caching/persistence code to build stable cache filenames.

Files: lib/scout/tmpfile.rb

---

## Key constants & configuration

- TmpFile.MAX_FILE_LENGTH = 150 — max length used by tmp_for_file before truncating and appending a digest.
- TmpFile.tmpdir — base temporary directory used by tmp utilities (defaults to user tmp under $HOME: `~/tmp/scout/tmpfiles`).
  - You can set: `TmpFile.tmpdir = "/some/dir"`.

Helpers:
- TmpFile.user_tmp(subdir = nil) — returns user-scoped base tmp dir (under $HOME/tmp/scout). If `subdir` provided it is appended.

---

## Filename helpers

- TmpFile.random_name(prefix = 'tmp-', max = 1_000_000_000)
  - Return a random name with the given prefix and a random integer (0..max).

- TmpFile.tmp_file(prefix = 'tmp-', max = 1_000_000_000, dir = nil)
  - Returns a path inside `dir` (defaults to `TmpFile.tmpdir`) composed of prefix + random number.
  - If `dir` is a Path it will be `.find`ed.

---

## Scoped helpers

These helpers create temporary files/directories, yield them to the caller, and delete them afterward (by default).

- TmpFile.with_file(content = nil, erase = true, options = {}) { |tmpfile| ... }
  - Create a temporary file path and optionally pre-populate it with `content`.
  - Parameters:
    - `content`:
      - If String: write content into file.
      - If IO/StringIO: read its contents and write into tmp file.
      - If nil: tmp file is created empty.
      - If `content` is a Hash, it is treated as options (content=nil).
    - `erase` (default true): remove the tmp file after the block completes.
    - `options` (Hash):
      - `:prefix` — filename prefix (default `'tmp-'`).
      - `:max` — random suffix max integer.
      - `:tmpdir` — directory to write the tmp file into.
      - `:extension` — append `.extension` to tmp file name.
  - Behavior:
    - Ensures tmpdir exists (Open.mkdir).
    - Handles IO content safely by reading readpartial until EOF.
    - Yields the tmp file path (string) to the block.
    - After the block returns, removes the tmp file when `erase` is true and file exists.
  - Examples:
    ```ruby
    TmpFile.with_file("Hello") do |file|
      puts File.read(file)  # => "Hello"
    end
    ```

- TmpFile.with_dir(erase = true, options = {}) { |tmpdir| ... }
  - Create a temporary directory (using tmp_file for a unique name), yield its path, and remove it after block if `erase` true.
  - `options[:prefix]` may change directory name prefix.
  - Example:
    ```ruby
    TmpFile.with_dir do |dir|
      # dir is a path to a temporary directory
    end
    ```

- TmpFile.in_dir(*args) { |dir| ... }
  - Convenience that creates a temporary directory and executes the block with the current working directory changed to that directory (uses `Misc.in_dir` internally).

---

## Persistence path helper

- TmpFile.tmp_for_file(file, tmp_options = {}, other_options = {})
  - Generates a stable temporary/persistent filename for a logical file name plus options. Used by persistence/caching logic to build consistent cache files per logical input and options.
  - Returns a Path (string extended with Path) under the chosen persistence directory.
  - Parameters:
    - `file` — logical filename or Path used to build the identifier.
    - `tmp_options` may include:
      - `:file` — return value override (internal)
      - `:prefix` — prefix for the identifier (default: based on file)
      - `:key` — optional key appended in identifier (`[...]`).
      - `:dir` — base directory for persistence (defaults to `TmpFile.tmpdir`).
    - `other_options` — additional options whose digest will be appended to the filename (used to make identifier unique for variations like filters).
    - Special handling:
      - Replaces path separators with `SLASH_REPLACE` (character `·`) to make a single filename.
      - Truncates long filenames (over MAX_FILE_LENGTH) and appends a short digest to avoid filesystem limits.
      - Appends a digest of `other_options` (unless empty) to ensure uniqueness when options differ.
  - Use cases:
    - Build cache file path for a content produced from input + parameters.
    - Example (simplified):
      ```ruby
      p = TmpFile.tmp_for_file("data.tsv", dir: Path.setup("var/cache"))
      ```

---

## Behavior / edge cases

- `with_file` and `with_dir` remove created resources after the block only if `erase` true and the file/dir exists.
- `with_file` supports passing options as the first argument (if `content` is a Hash).
- `with_file` writes IO content using `readpartial` in chunks (handles large IOs without loading entire contents into memory).
- `tmp_for_file` uses a safe character `SLASH_REPLACE` (`'·'`) for replaced `/` characters — results in single-file names representing nested logical paths.
- `tmp_for_file` truncates overly long identifiers and appends a digest of the remainder to keep the filename length reasonable.
- The helper returns a Path-like value when `persistence_dir` is a Path.

---

## Examples (from tests)

- Create a temporary file with content:
  ```ruby
  TmpFile.with_file("Hello World!") do |file|
    assert_equal "Hello World!", File.read(file)
  end
  ```

- Create a temporary file from an IO and consume into another temporary:
  ```ruby
  TmpFile.with_file("Hello") do |file1|
    Open.open(file1) do |io|
      TmpFile.with_file(io) do |file2|
        assert_equal "Hello", File.read(file2)
      end
    end
  end
  ```

- Temporary directory and change into it:
  ```ruby
  TmpFile.in_dir do |dir|
    # current working directory is dir inside the block
  end
  ```

- Build a persistent cache path for a logical filename + options:
  ```ruby
  cache_path = TmpFile.tmp_for_file("input.tsv", dir: Path.setup("var/cache"))
  ```

---

## Implementation notes

- TmpFile uses `Open` utilities to create directories and write files.
- `tmp_file` returns plain string paths; callers often wrap them in Path.setup when needed.
- Filenames are sanitized (spaces replaced with `_`) and slashes replaced with `·` for single-file representation of nested paths in `tmp_for_file`.
- The module is intentionally minimal but used pervasively by other framework components like Persist and Resource to generate stable temporary / cache paths.

Use TmpFile helpers when you need temporary files/dirs or stable cache filenames with predictable cleanup behavior.