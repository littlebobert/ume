#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "optparse"
require "uri"

options = {}
OptionParser.new do |parser|
  parser.on("--file PATH") { |value| options[:file] = value }
  # The changelog has its own page (umete.jp/changelog); without this option the
  # entry goes into --file, as it did when the changelog was on the landing page.
  parser.on("--changelog-file PATH") { |value| options[:changelog_file] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--download-url URL") { |value| options[:download_url] = value }
  parser.on("--note-en TEXT") { |value| options[:note_en] = value }
  parser.on("--note-ja TEXT") { |value| options[:note_ja] = value }
end.parse!

path = options.fetch(:file)
changelog_path = options.fetch(:changelog_file, path)
version = options.fetch(:version).to_s.sub(/\Av/, "")
download_url = options.fetch(:download_url)
note_en = options.fetch(:note_en, "").to_s.strip
note_ja = options.fetch(:note_ja, "").to_s.strip

abort "Version must use X.Y.Z format." unless version.match?(/\A\d+\.\d+\.\d+\z/)
uri = URI.parse(download_url)
abort "Download URL must use HTTPS." unless uri.is_a?(URI::HTTPS) && uri.host == "github.com"
abort "Release notes must be 1,000 characters or fewer." if [note_en, note_ja].any? { |note| note.length > 1_000 }

html = File.read(path, encoding: "UTF-8")
original = html.dup

download_count = 0
escaped_download_url = CGI.escapeHTML(download_url)
html.gsub!(/(<a\b[^>]*\bdata-ume-download\b[^>]*\bhref=")[^"]*(")/) do
  match = Regexp.last_match
  prefix = match[1].dup
  suffix = match[2].dup
  download_count += 1
  "#{prefix}#{escaped_download_url}#{suffix}"
end
abort "No data-ume-download links found in #{path}." if download_count.zero?

version_count = 0
html.gsub!(/(<span\b[^>]*\bdata-ume-version\b[^>]*>)[^<]*(<\/span>)/) do
  match = Regexp.last_match
  prefix = match[1].dup
  suffix = match[2].dup
  version_count += 1
  # The language switcher re-renders the span from its data-label-* attributes,
  # so the version must be updated there as well as in the text node.
  prefix.gsub!(/(data-label-(?:en|ja)=")([^"]*?)\d+\.\d+\.\d+([^"]*")/) { "#{$1}#{$2}#{version}#{$3}" }
  "#{prefix}#{version}#{suffix}"
end
warn "No data-ume-version element found in #{path}; skipping the version label." if version_count.zero?

changelog_html = changelog_path == path ? html : File.read(changelog_path, encoding: "UTF-8")
changelog_original = changelog_html.dup

start_marker = "        <!-- ume-changelog:start -->"
end_marker = "        <!-- ume-changelog:end -->"
abort "Missing Umete changelog markers in #{changelog_path}." unless changelog_html.include?(start_marker) && changelog_html.include?(end_marker)

escaped_version = CGI.escapeHTML(version)
unless note_en.empty? || changelog_html.include?("data-ume-release=\"#{escaped_version}\"")
  note_ja = note_en if note_ja.empty?
  escaped_note_en = CGI.escapeHTML(note_en)
  escaped_note_ja = CGI.escapeHTML(note_ja)
  today = Date.today
  date_en = today.strftime("%B %-d, %Y")
  date_ja = "#{today.year}年#{today.month}月#{today.day}日"
  entry = <<~HTML.chomp
        <h2 data-ume-release="#{escaped_version}">#{escaped_version}</h2>
        <span class="release-date" data-label-en="#{date_en}" data-label-ja="#{date_ja}">#{date_en}</span>
        <ul>
          <li data-label-en="#{escaped_note_en}" data-label-ja="#{escaped_note_ja}">#{escaped_note_en}</li>
        </ul>
  HTML
  changelog_html.sub!(start_marker, "#{start_marker}\n#{entry}")
end

if changelog_path != path && changelog_html != changelog_original
  File.write(changelog_path, changelog_html, encoding: "UTF-8")
  puts "Updated #{changelog_path} for Umete #{version}."
end

if html == original
  puts "Landing page is already current."
else
  File.write(path, html, encoding: "UTF-8")
  puts "Updated #{path} for Umete #{version}."
end
