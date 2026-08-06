cask "dsbrain" do
  version "1.0.1"
  sha256 "5f011b8d71b75a1d3cc8bfbe1e5a6c46e334cabe1324392ff4e3e742a5636182"

  url "https://github.com/derkan/dsbrain/releases/download/v#{version}/DSBrain-#{version}-macos-arm64.zip"
  name "DSBrain"
  desc "Menu bar controller for local ds4-server"
  homepage "https://github.com/derkan/dsbrain"

  depends_on macos: :ventura
  depends_on arch: :arm64

  app "DSBrain.app"

  zap trash: [
    "~/Library/Application Support/DSBrain",
  ]
end
