cask "ration" do
  version "1.2.1"
  sha256 :no_check # replaced by the release workflow with the real DMG digest

  url "https://github.com/mcpeixoto/ration/releases/download/v#{version}/Ration-#{version}.dmg"
  name "Ration"
  desc "Menu bar meter for Claude Code, Codex, and Cursor usage limits"
  homepage "https://github.com/mcpeixoto/ration"

  depends_on macos: ">= :sonoma"

  app "Ration.app"

  zap trash: [
    "~/Library/Preferences/com.mcpeixoto.Ration.plist",
  ]
end
