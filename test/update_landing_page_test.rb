# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

class UpdateLandingPageTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/update_landing_page.rb", __dir__)

  def fixture
    <<~HTML
      <a data-ume-download href="old.dmg">Download</a>
      <span data-ume-version>0.1.0</span>
              <!-- ume-changelog:start -->
              <h2 data-ume-release="0.1.0">0.1.0</h2>
              <!-- ume-changelog:end -->
    HTML
  end

  def run_update(path, version: "0.1.1", note_en: "Fixed <select> fields.", note_ja: "選択欄を修正しました。")
    Open3.capture3(
      "ruby", SCRIPT,
      "--file", path,
      "--version", version,
      "--download-url", "https://github.com/example/app/releases/download/v#{version}/App.dmg",
      "--note-en", note_en,
      "--note-ja", note_ja
    )
  end

  def test_updates_download_version_and_prepends_an_escaped_changelog_entry
    Dir.mktmpdir do |directory|
      path = File.join(directory, "app.html")
      File.write(path, fixture)
      _out, error, status = run_update(path)
      assert status.success?, error

      html = File.read(path)
      assert_includes html, "releases/download/v0.1.1/App.dmg"
      assert_includes html, "<span data-ume-version>0.1.1</span>"
      refute_includes html, "</span>0.1.1</span>"
      assert_includes html, 'data-ume-release="0.1.1"'
      assert_includes html, 'data-label-en="Fixed &lt;select&gt; fields."'
      refute_includes html, "<ul></ul>"
      assert_match(/<ul>\s*<li[^>]+>Fixed &lt;select&gt; fields\.<\/li>\s*<\/ul>/, html)
      assert_operator html.index('data-ume-release="0.1.1"'), :<, html.index('data-ume-release="0.1.0"')
    end
  end

  def test_is_idempotent_for_an_existing_version
    Dir.mktmpdir do |directory|
      path = File.join(directory, "app.html")
      File.write(path, fixture)
      _out, error, status = run_update(path)
      assert status.success?, error
      first_update = File.binread(path)
      _out, error, status = run_update(path)
      assert status.success?, error
      assert_equal first_update, File.binread(path)
      assert_equal 1, File.read(path).scan('data-ume-release="0.1.1"').length
    end
  end
end
