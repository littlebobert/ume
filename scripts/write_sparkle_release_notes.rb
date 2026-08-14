#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

options = {}
OptionParser.new do |parser|
  parser.on("--dir PATH") { |value| options[:dir] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--note-en TEXT") { |value| options[:note_en] = value }
  parser.on("--note-ja TEXT") { |value| options[:note_ja] = value }
end.parse!

directory = options.fetch(:dir)
version = options.fetch(:version).to_s.sub(/\Av/, "")
note_en = options.fetch(:note_en, "").to_s.strip
note_ja = options.fetch(:note_ja, "").to_s.strip

abort "Version must use X.Y.Z format." unless version.match?(/\A\d+\.\d+\.\d+\z/)
abort "Notes directory is missing." unless File.directory?(directory)

def write_notes(path, version, body)
  File.write(path, "# Ume #{version}\n\n#{body}\n".sub(/\n+\z/, "\n"))
end

basename = File.join(directory, "Ume-#{version}-macOS")
write_notes("#{basename}.md", version, note_en)
if note_ja.empty?
  File.delete("#{basename}.ja.md") if File.exist?("#{basename}.ja.md")
else
  write_notes("#{basename}.ja.md", version, note_ja)
end
