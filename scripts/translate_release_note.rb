#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

note_en = ENV.fetch("RELEASE_NOTE_EN", "").strip
note_ja = ENV.fetch("RELEASE_NOTE_JA", "").strip
abort "Release notes must be 1,000 characters or fewer." if [note_en, note_ja].any? { |note| note.length > 1_000 }

if note_en.empty?
  note_ja = ""
elsif note_ja.empty?
  api_key = ENV.fetch("CHANGELOG_OPENAI_API_KEY", "").strip
  abort "CHANGELOG_OPENAI_API_KEY is required when an English release note has no Japanese translation." if api_key.empty?
  model = ENV.fetch("CHANGELOG_OPENAI_MODEL", "gpt-5.6-sol").strip
  reasoning_effort = ENV.fetch("CHANGELOG_OPENAI_REASONING_EFFORT", "medium").strip
  abort "CHANGELOG_OPENAI_MODEL is empty." if model.empty?
  abort "CHANGELOG_OPENAI_REASONING_EFFORT is empty." if reasoning_effort.empty?

  uri = URI("https://api.openai.com/v1/responses")
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{api_key}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(
    model: model,
    reasoning: { effort: reasoning_effort },
    store: false,
    input: [
      {
        role: "system",
        content: [
          {
            type: "input_text",
            text: "Translate this software changelog note into concise, natural Japanese. Preserve product names and technical terms. Return only the Japanese translation, with no quotation marks or explanation."
          }
        ]
      },
      { role: "user", content: [{ type: "input_text", text: note_en }] }
    ]
  )

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 45) do |http|
    http.request(request)
  end
  abort "OpenAI translation failed (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)

  payload = JSON.parse(response.body)
  note_ja = payload.fetch("output", []).flat_map { |item| item.fetch("content", []) }
    .filter_map { |content| content["text"] }
    .join("\n")
    .strip
  abort "OpenAI returned an empty Japanese translation." if note_ja.empty?
  abort "Translated release note is too long." if note_ja.length > 1_000
end

output = ENV["GITHUB_OUTPUT"]
if output && !output.empty?
  delimiter = "UME_NOTE_#{Process.pid}"
  release_body = [note_en, note_ja].reject(&:empty?).join("\n\n")
  File.open(output, "a") do |file|
    file.puts("note_en<<#{delimiter}\n#{note_en}\n#{delimiter}")
    file.puts("note_ja<<#{delimiter}\n#{note_ja}\n#{delimiter}")
    file.puts("release_body<<#{delimiter}\n#{release_body}\n#{delimiter}")
  end
else
  puts JSON.generate(note_en: note_en, note_ja: note_ja)
end
