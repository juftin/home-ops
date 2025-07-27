const path = require("path")
const fs = require("fs")

const tplFile = path.resolve(__dirname, ".github/release-notes.hbs")

module.exports = {
  branches: [
    "main",
  ],
  plugins: [
    [
      "semantic-release-gitmoji",
      {
        releaseNotes: {
          template: fs.readFileSync(tplFile, "utf-8"),
        }
      }
    ],
    "@semantic-release/github",
  ]
}
