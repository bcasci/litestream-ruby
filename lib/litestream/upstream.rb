module Litestream
  module Upstream
    VERSION = "v0.5.8"

    # rubygems platform name => upstream release filename
    NATIVE_PLATFORMS = {
      "aarch64-linux" => "litestream-#{VERSION.delete_prefix("v")}-linux-arm64.tar.gz",
      "arm64-darwin" => "litestream-#{VERSION.delete_prefix("v")}-darwin-arm64.tar.gz",
      "arm64-linux" => "litestream-#{VERSION.delete_prefix("v")}-linux-arm64.tar.gz",
      "x86_64-darwin" => "litestream-#{VERSION.delete_prefix("v")}-darwin-x86_64.tar.gz",
      "x86_64-linux" => "litestream-#{VERSION.delete_prefix("v")}-linux-x86_64.tar.gz"
    }
  end
end
