cask "dsbrain" do
  version "1.0.0"
  sha256 "bb7d0bbbc146140d823c12dc58b7fdaeacc0fd77dead18359091179535d868f3"

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
