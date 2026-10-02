{{flutter_js}}
{{flutter_build_config}}

const builds = window._flutter?.buildConfig?.builds ?? [];
const hasSkwasmBuild = builds.some((build) => build.renderer === "skwasm");

const config = {
  // Shows why candidates are skipped in the browser console.
  verboseBuildSelection: true,
};

if (hasSkwasmBuild) {
  config.renderer = "skwasm";
}

_flutter.loader.load({ config });
