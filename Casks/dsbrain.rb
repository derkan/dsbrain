cask "dsbrain" do
  version "1.0.0"
  sha256 "7fbd662c29c4642f092ddd22214f2e2291c77cb09e9bf04701f98d744602b4d5"

  url "https://github.com/derkan/dsbrain/releases/download/v#{version}/DSBrain-#{version}-macos-arm64.zip"
  name "DSBrain"
  desc "Menu bar controller for local ds4-server"
  homepage "https://github.com/derkan/dsbrain"

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "DSBrain.app"

  zap trash: [
    "~/Library/Application Support/DSBrain",
  ]
end
