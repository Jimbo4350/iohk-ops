{ name, pkgs, ... }:

{
  imports = [
    ./auto-gc.nix
    ./nix_nsswitch.nix
    ./datadog.nix
    ./docker-builder.nix
  ];

  services.dd-agent.tags = ["group:buildkite-agents"];

  services.buildkite-agent = {
    enable = true;
    name   = name;
    openssh.privateKeyPath = "/run/keys/buildkite-ssh-private";
    openssh.publicKeyPath  = "/run/keys/buildkite-ssh-public";
    tokenPath              = "/run/keys/buildkite-token";
    meta-data              = "system=x86_64-linux";
    runtimePackages        = with pkgs; [
       bash gnutar gzip bzip2 xz
       git git-lfs
       nix
    ];
    hooks.environment = ''
      # Provide a minimal build environment
      export NIX_BUILD_SHELL="/run/current-system/sw/bin/bash"
      export PATH="/run/current-system/sw/bin:$PATH"
      export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"

      # load S3 credentials for artifact upload
      source /var/lib/buildkite-agent/hooks/aws-creds
    '';
    hooks.pre-command = ''
      # Clean out the state that gets messed up and makes builds fail.
      rm -rf ~/.cabal
    '';
    extraConfig = ''
      git-clean-flags="-ffdqx"
    '';
  };
  users.users.buildkite-agent.extraGroups = [
    "keys"
    "docker"
  ];

  deployment.keys = {
    aws-creds = {
      keyFile = ./. + "/../static/buildkite-hook";
      destDir = "/var/lib/buildkite-agent/hooks";
      user    = "buildkite-agent";
      permissions = "0770";
    };
    buildkite-ssh-private = {
      keyFile = ./. + "/../static/buildkite-ssh";
      user    = "buildkite-agent";
    };
    buildkite-ssh-public = {
      keyFile = ./. + "/../static/buildkite-ssh.pub";
      user    = "buildkite-agent";
    };
    buildkite-token = {
      keyFile = ./. + "/../static/buildkite_token";
      user    = "buildkite-agent";
    };
  };

  # Globally enable stack's nix integration so that stack builds have
  # the necessary dependencies available.
  environment.etc."stack/config.yaml".text = ''
    nix:
      enable: true
  '';
}
