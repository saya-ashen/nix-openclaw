{
  nixpkgs,
  steipetePkgs ? { },
  system,
}:
let
  pkgs = import nixpkgs {
    inherit system;
  };
in
import ./nix/packages {
  inherit pkgs steipetePkgs;
}
