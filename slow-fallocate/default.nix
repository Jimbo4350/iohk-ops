with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "slow-fallocate";
  src = ./.;
  installPhase = ''
    mkdir -pv $out/lib/
    cp -vi libslow-fallocate.so $out/lib/
  '';
  meta.platforms = [ "x86_64-linux" ];
}
