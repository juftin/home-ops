// $schema: "https://docs.renovatebot.com/renovate-global-schema.json"
// Runner configuration carried over from juftin/renovate; defaults are set in values.yaml.

const targetRepo = process.env.RENOVATE_REPOSITORY?.trim();
const currentRepo = process.env.GITHUB_REPOSITORY;
const owner = process.env.GITHUB_REPOSITORY_OWNER || currentRepo?.split("/")[0];
const preset =
  process.env.RENOVATE_CONFIG_PRESET || (currentRepo && `github>${currentRepo}`);

const commitStyle =
  process.env.RENOVATE_COMMIT_STYLE?.trim() ||
  (preset?.endsWith(":gitmoji") ? "gitmoji" : "conventional");
if (!["conventional", "gitmoji"].includes(commitStyle)) {
  throw new Error("RENOVATE_COMMIT_STYLE must be conventional or gitmoji");
}
// Apply style after the base preset, retaining managers, labels, and dashboards.
const stylePreset = currentRepo && `github>${currentRepo}:${commitStyle}`;
const presets = [
  ...new Set([
    ...(preset ? [preset] : ["config:recommended"]),
    ...(stylePreset ? [stylePreset] : []),
  ]),
];

module.exports = {
  platform: "github",
  onboarding: false,
  requireConfig: "optional",
  forkProcessing: "enabled",
  // Resolved with repository config so local settings and ignorePresets work.
  extends: presets,
  dependencyDashboard: true,
  dependencyDashboardTitle: "Renovate Dashboard 🤖",
  ignorePrAuthor: true,
  ...(process.env.GIT_AUTHOR ? { gitAuthor: process.env.GIT_AUTHOR } : {}),
  ...(targetRepo
    ? { repositories: [targetRepo] }
    : {
        autodiscover: true,
        autodiscoverFilter: owner ? [`${owner}/*`] : ["*/*"],
        autodiscoverTopics: ["renovate-enabled"],
      }),
  hostRules:
    process.env.RENOVATE_DOCKER_USERNAME && process.env.RENOVATE_DOCKER_PASSWORD
      ? [
          {
            matchHost: "docker.io",
            username: process.env.RENOVATE_DOCKER_USERNAME,
            password: process.env.RENOVATE_DOCKER_PASSWORD,
          },
        ]
      : [],
};
