# Canonical source for the Homebrew cask. Copy this file into the tap repo
# `greggoire/homebrew-tap` at `Casks/run-cockpit.rb` on each release, updating
# `version` and `sha256` from `scripts/release.sh` output.
#
# The app is unsigned/not notarized, so users must install with:
#   brew install --cask --no-quarantine greggoire/tap/run-cockpit
cask "run-cockpit" do
  version "1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/greggoire/run-cockpit/releases/download/v#{version}/RunCockpit.dmg"
  name "RunCockpit"
  desc "Native macOS dashboard for live Claude Code sessions"
  homepage "https://github.com/greggoire/run-cockpit"

  depends_on macos: ">= :sequoia" # macOS 15+

  app "RunCockpit.app"

  zap trash: [
    "~/Library/Application Support/RunCockpit",
  ]
end
