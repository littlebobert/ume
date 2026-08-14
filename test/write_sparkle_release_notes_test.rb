# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

class WriteSparkleReleaseNotesTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/write_sparkle_release_notes.rb", __dir__)

  def run_write(directory, version: "0.1.12", note_en: "Fixed Add.", note_ja: "追加を修正しました。")
    Open3.capture3(
      "ruby", SCRIPT,
      "--dir", directory,
      "--version", version,
      "--note-en", note_en,
      "--note-ja", note_ja
    )
  end

  def test_writes_english_default_and_japanese_localized_files
    Dir.mktmpdir do |directory|
      _out, error, status = run_write(directory)
      assert status.success?, error
      assert_equal "# Ume 0.1.12\n\nFixed Add.\n", File.read(File.join(directory, "Ume-0.1.12-macOS.md"))
      assert_equal "# Ume 0.1.12\n\n追加を修正しました。\n", File.read(File.join(directory, "Ume-0.1.12-macOS.ja.md"))
    end
  end

  def test_omits_japanese_file_when_translation_is_blank
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "Ume-0.1.12-macOS.ja.md"), "stale")
      _out, error, status = run_write(directory, note_ja: "")
      assert status.success?, error
      assert File.exist?(File.join(directory, "Ume-0.1.12-macOS.md"))
      refute File.exist?(File.join(directory, "Ume-0.1.12-macOS.ja.md"))
    end
  end
end
