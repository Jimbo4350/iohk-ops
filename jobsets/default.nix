{ nixopsPrsJSON ? ./simple-pr-dummy.json
, cardanoPrsJSON ? ./simple-pr-dummy.json
, daedalusPrsJSON ? ./simple-pr-dummy.json
, plutusPrsJSON ? ./simple-pr-dummy.json
, nixpkgs ? <nixpkgs>
, declInput ? {}
, handleCardanoPRs ? true
}:

# Followed by https://github.com/NixOS/hydra/pull/418/files

let
  nixopsPrs = builtins.fromJSON (builtins.readFile nixopsPrsJSON);
  cardanoPrs = builtins.fromJSON (builtins.readFile cardanoPrsJSON);
  daedalusPrs = builtins.fromJSON (builtins.readFile daedalusPrsJSON);
  plutusPrs = builtins.fromJSON (builtins.readFile plutusPrsJSON);

  iohkOpsURI = "https://github.com/input-output-hk/iohk-ops.git";
  mkFetchGithub = value: {
    inherit value;
    type = "git";
    emailresponsible = false;
  };
  nixpkgs-src = builtins.fromJSON (builtins.readFile ./../nixpkgs-src.json);
  pkgs = import nixpkgs {};

  defaultSettings = {
    enabled = 1;
    hidden = false;
    nixexprinput = "jobsets";
    keepnr = 5;
    schedulingshares = 42;
    checkinterval = 60;
    inputs = {
      nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgs-src.rev}";
      jobsets = mkFetchGithub "${iohkOpsURI} master";
    };
    enableemail = false;
    emailoverride = "";
  };

  # Adds an arg which disables optimization for cardano-sl builds
  withFasterBuild = jobset: jobset // {
    inputs = (jobset.inputs or { }) // {
      fasterBuild = { type = "boolean"; emailresponsible = false; value = "true"; };
    };
  };

  mkNixops = nixopsBranch: nixpkgsRev: {
    nixexprpath = "jobsets/cardano.nix";
    description = "IOHK-Ops";
    inputs = {
      nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgsRev}";
      jobsets = mkFetchGithub "${iohkOpsURI} ${nixopsBranch}";
      nixops = mkFetchGithub "https://github.com/NixOS/NixOps.git tags/v1.5";
    };
  };
  makeNixopsPR = num: info: {
    name = "iohk-ops-pr-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprpath = "jobsets/cardano.nix";
      inputs = {
        nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgs-src.rev}";
        jobsets = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
        nixops = mkFetchGithub "https://github.com/NixOS/NixOps.git tags/v1.5";
      };
    };
  };
  mkCardano = cardanoBranch: {
    nixexprpath = "release.nix";
    nixexprinput = "cardano";
    description = "Cardano SL";
    inputs = {
      cardano = mkFetchGithub "https://github.com/input-output-hk/cardano-sl.git ${cardanoBranch}";
    };
  };
  makeCardanoPR = num: info: {
    name = "cardano-sl-pr-${num}";
    value = defaultSettings // withFasterBuild {
      description = "PR ${num}: ${info.title}";
      nixexprinput = "cardano";
      nixexprpath = "release.nix";
      inputs = {
        cardano = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
      };
    };
  };
  mkDaedalus = daedalusBranch: {
    nixexprpath = "release.nix";
    nixexprinput = "daedalus";
    description = "Daedalus Wallet";
    inputs = {
      daedalus = mkFetchGithub "https://github.com/input-output-hk/daedalus.git ${daedalusBranch}";
    };
  };
  mkPlutus = plutusBranch: {
    nixexprpath = "release.nix";
    nixexprinput = "plutus";
    description = "Plutus Language";
    inputs = {
      plutus = mkFetchGithub "https://github.com/input-output-hk/plutus.git ${plutusBranch}";
    };
  };
  makeDaedalusPR = num: info: {
    name = "daedalus-pr-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprinput = "daedalus";
      nixexprpath = "release.nix";
      inputs = {
        daedalus = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
      };
    };
  };
  makePlutusPR = num: info: {
    name = "plutus-pr-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprinput = "plutus";
      nixexprpath = "release.nix";
      inputs = {
        plutus = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
      };
    };
  };
  PRExcludedLabels = import ./pr-excluded-labels.nix;
  exclusionFilter = pkgs.lib.filterAttrs (_: prInfo: builtins.length (builtins.filter (prLabel: (builtins.elem prLabel.name PRExcludedLabels))
                                                                                      (prInfo.labels or []))
                                                     == 0);
  nixopsPrJobsets   = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeNixopsPR   (exclusionFilter nixopsPrs));
  cardanoPrJobsets  = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeCardanoPR  (exclusionFilter cardanoPrs));
  daedalusPrJobsets = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeDaedalusPR (exclusionFilter daedalusPrs));
  plutusPrJobsets   = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makePlutusPR   (exclusionFilter plutusPrs));
  mainJobsets = with pkgs.lib; mapAttrs (name: settings: defaultSettings // settings) (rec {
    cardano-sl = mkCardano "develop";
    cardano-sl-master = mkCardano "master";
    cardano-sl-1-0 = mkCardano "release/1.0.x";
    cardano-sl-1-2 = mkCardano "release/1.2.0";
    cardano-sl-1-3 = mkCardano "release/1.3.1";
    cardano-sl-2-0 = mkCardano "release/2.0.0";

    # Provides cached build projects for PR builds with -O0
    no-opt-cardano-sl = withFasterBuild (mkCardano "develop");

    daedalus = mkDaedalus "develop";

    plutus = mkPlutus "master";

    iohk-ops = mkNixops "master" nixpkgs-src.rev;
    iohk-ops-bors-staging = mkNixops "bors-staging" nixpkgs-src.rev;
    iohk-ops-bors-trying = mkNixops "bors-trying" nixpkgs-src.rev;
  });
  jobsetsAttrs = daedalusPrJobsets // nixopsPrJobsets // plutusPrJobsets // (if handleCardanoPRs then cardanoPrJobsets else {}) // mainJobsets;
  jobsetJson = pkgs.writeText "spec.json" (builtins.toJSON jobsetsAttrs);
in {
  jobsets = with pkgs.lib; pkgs.runCommand "spec.json" {} ''
    cat <<EOF
    ${builtins.toJSON declInput}
    EOF
    cp ${jobsetJson} $out
  '';
}
