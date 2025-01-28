{
  stdenvNoCC,
  fetchFromGitHub,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  nodejs,
}:
stdenvNoCC.mkDerivation rec {
  pname = "bar-card";
  version = "3.2.0";

  src = fetchFromGitHub {
    owner = "patrickdag";
    repo = "bar-card";
    rev = "ad9b1e83f6cf75b699911ebc34a4782c707f254f";
    hash = "sha256-1dX6HErKfhMgu9YQATsUk9jPFbCRRoQLhYISM+evVQM=";
  };
  offlineCache = fetchYarnDeps {
    inherit src;
    hash = "sha256-f/kFCxIinW/9Po0pZM9V8i0ySqiGqz1rmEEFSvw1Gk4=";
  };
  nativeBuildInputs = [
    yarnConfigHook
    yarnBuildHook
    nodejs
  ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp dist/* $out

    runHook postInstall
  '';
}
