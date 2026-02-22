require "test_helper"
require "fileutils"
require "rubygems/package"
require "zlib"

class TestDownload < ActiveSupport::TestCase
  def setup
    @exe_dir = Litestream::Commands::DEFAULT_DIR
    @platform = Litestream::Commands.platform
    @platform_dir = File.join(@exe_dir, @platform)
    @exe_path = File.join(@platform_dir, "litestream")
    # Clean up any previously downloaded binary for test isolation
    FileUtils.rm_rf(@platform_dir) if File.directory?(@platform_dir)
  end

  def teardown
    FileUtils.rm_rf(@platform_dir) if File.directory?(@platform_dir)
  end

  class TestDownloadUrl < TestDownload
    def test_download_url_returns_correct_url_for_current_platform
      url = Litestream::Commands.download_url
      version = Litestream::Upstream::VERSION
      filename = Litestream::Upstream::NATIVE_PLATFORMS[@platform]

      assert_equal "https://github.com/benbjohnson/litestream/releases/download/#{version}/#{filename}", url
    end

    def test_download_url_raises_for_unsupported_platform
      Litestream::Commands.stub :platform, "unsupported-platform" do
        assert_raises(Litestream::Commands::UnsupportedPlatformException) do
          Litestream::Commands.download_url
        end
      end
    end
  end

  class TestDownloadExecutable < TestDownload
    def test_download_creates_platform_directory
      # Stub the actual HTTP download to avoid network calls in tests
      fake_tar_gz = create_fake_tar_gz("litestream", "#!/bin/sh\necho fake")

      URI.stub :open, proc { |_url, &block| block.call(StringIO.new(fake_tar_gz)) } do
        Litestream::Commands.download
      end

      assert File.directory?(@platform_dir), "Expected #{@platform_dir} to be created"
    end

    def test_download_places_binary_in_correct_location
      fake_tar_gz = create_fake_tar_gz("litestream", "#!/bin/sh\necho fake")

      URI.stub :open, proc { |_url, &block| block.call(StringIO.new(fake_tar_gz)) } do
        result = Litestream::Commands.download
        assert_equal @exe_path, result
      end

      assert File.exist?(@exe_path), "Expected binary at #{@exe_path}"
    end

    def test_download_makes_binary_executable
      fake_tar_gz = create_fake_tar_gz("litestream", "#!/bin/sh\necho fake")

      URI.stub :open, proc { |_url, &block| block.call(StringIO.new(fake_tar_gz)) } do
        Litestream::Commands.download
      end

      assert File.executable?(@exe_path), "Expected #{@exe_path} to be executable"
    end

    def test_download_is_idempotent
      fake_tar_gz = create_fake_tar_gz("litestream", "#!/bin/sh\necho fake")

      URI.stub :open, proc { |_url, &block| block.call(StringIO.new(fake_tar_gz)) } do
        first_result = Litestream::Commands.download
        second_result = Litestream::Commands.download
        assert_equal first_result, second_result
      end

      assert File.exist?(@exe_path)
    end

    def test_download_raises_for_unsupported_platform
      Litestream::Commands.stub :platform, "unsupported-platform" do
        assert_raises(Litestream::Commands::UnsupportedPlatformException) do
          Litestream::Commands.download
        end
      end
    end

    private

    def create_fake_tar_gz(entry_name, content)
      tar_io = StringIO.new
      Gem::Package::TarWriter.new(tar_io) do |tar|
        tar.add_file_simple(entry_name, 0o755, content.bytesize) do |io|
          io.write(content)
        end
      end

      gz_io = StringIO.new
      gz = Zlib::GzipWriter.new(gz_io)
      gz.write(tar_io.string)
      gz.close
      gz_io.string
    end
  end
end
