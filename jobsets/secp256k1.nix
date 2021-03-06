{ stdenv
, autoconf
, automake
, libtool
, secp256k1Src
}:

stdenv.mkDerivation {
  name = "secp256k1";

  src = secp256k1Src;

  buildInputs = [ autoreconfHook libtool ];

  configureFlags = [ "--enable-module-recovery" "--enable-module-ecdh" "--enable-experimental" "--prefix" "$lib" ];

  doCheck = true;
  checkPhase = "./tests";

  outputs = [ "out" "lib" ];
}
