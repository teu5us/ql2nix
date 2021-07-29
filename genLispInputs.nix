{ pkgs
, system-name
, system-path
, dependencies ? []
, quicklisp-packages ? []
, dists ? []
, local-systems ? {} }:

distfile:
  
with pkgs;

let
  ls = local-systems // lib.attrsets.optionalAttrs
    (builtins.pathExists (toString system-path + "/" + system-name + ".asd"))
    builtins.listToAttrs [ (lib.attrsets.nameValuePair system-name system-path) ];
  local-system-paths-raw = lib.attrsets.attrValues ls;
in

assert lib.lists.all builtins.isPath local-system-paths-raw;

let
  ql2nix-src = lib.cleanSource ./ql2nix;
  local-system-names = lib.attrsets.attrNames ls;
  local-system-paths = lib.lists.map toString local-system-paths-raw;
  concatStringList = lst: lib.concatMapStringsSep " " (x: ''"'' + x + ''"'') lst;
  load-dirs = writeScript "load-dirs.lisp" ''
    (defun fix-dirname (str)
      (let ((slash? (equal #\/ (aref (reverse str) 0))))
        (pathname
          (if slash?
              str
              (concatenate 'string str "/")))))

    (dolist (dir (list ${concatStringList local-system-paths}))
      (pushnew (fix-dirname dir) asdf:*central-registry*))
  '';
  build = writeScript "build.lisp" ''
    ;; Setup quicklisp
    (load "quicklisp.lisp")
    (quicklisp-quickstart:install)

    ;; Load local systems
    (load "${load-dirs}")

    ;; Load ql2nix from source
    (load "${ql2nix-src}/main.lisp")

    (dolist (dist '(${concatStringList dists}))
      (ql-dist:install-dist dist :prompt nil))

    (dolist (dir '(${concatStringList local-system-paths}))
      (pushnew (fix-dirname dir) ql:*local-project-directories*))

    ;; Generate dependency definitions
    (ql2nix:main `("--nixlisp-lib"
                   ${concatStringList (lib.lists.unique
                     (quicklisp-packages ++ local-system-names))}))

    (quit)
  '';
  generate-dist = writeScriptBin "generate-dist" ''
    set -e
    # Remember output directory
    out=$(pwd)/

    [ ! -d "$out" ] && mkdir -p "$out"

    # Create temporary home directory to work in
    tmp=$(mktemp -d --suffix=.boot.ql2nix)
    trap "rm -rf $tmp" EXIT
    cd $tmp
    HOME=$(pwd)

    # Install Quicklisp and run ql2nix
    curl -O https://beta.quicklisp.org/quicklisp.lisp
    bash -x $(which common-lisp.sh) --load ${build}

    # Copy generated files into output directory
    echo "Copying generated files"
    cp --no-preserve=mode --remove-destination -v -f qlDist.nix $out/
  '';
  lisp = writeScriptBin "lisp" ''
    #!${bash}/bin/bash
    common-lisp.sh --load ${load-dirs}
  '';
  mkNixlispBundle = import ./ql2nix/mkNixlispBundle.nix pkgs;
  bundle = mkNixlispBundle dependencies distfile;
  # Derivation defining an environment for use with nix-shell.
in with pkgs; [ bundle ] ++ dependencies ++ [ curl lispPackages.clwrapper generate-dist lisp ]
