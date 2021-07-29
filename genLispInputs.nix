{ pkgs, dependencies ? [], quicklisp-packages ? [], dists ? [], trees ? [], dirs ? [] }:
distfile:
  
with pkgs;

let
  ql2nix-src = lib.cleanSource ./ql2nix;
  concatStringList = lst: lib.concatMapStringsSep " " (x: ''"'' + x + ''"'') lst;
  build = writeScript "build.lisp" ''
    ;; Setup quicklisp
    (load "quicklisp.lisp")
    (quicklisp-quickstart:install)

    ;; Load ql2nix from source
    (load "${ql2nix-src}/main.lisp")

    (dolist (dist '(${concatStringList dists}))
      (ql-dist:install-dist dist :prompt nil))

    ;; Generate dependency definitions
    (ql2nix:main (list "--nixlisp-lib" ${concatStringList quicklisp-packages}))
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
  load-trees = writeScript "load-trees" ''
    (defun fix-dirname (str)
      (let ((slash? (equal #\/ (aref (reverse str) 0))))
        (pathname
          (if slash?
              str
              (concatenate 'string str "/")))))

    (dolist (tree (list ${concatStringList trees}))
      (let* ((tree- (fix-dirname tree)))
        (dolist (dir (uiop:subdirectories tree-))
          (pushnew dir asdf:*central-registry*))))

    (dolist (dir (list ${concatStringList dirs}))
      (pushnew (fix-dirname dir) asdf:*central-registry*))
  '';
  lisp = writeScriptBin "lisp" ''
    #!${bash}/bin/bash
    common-lisp.sh --load ${load-trees}
  '';
  mkNixlispBundle = import ./ql2nix/mkNixlispBundle.nix pkgs;
  bundle = mkNixlispBundle dependencies distfile;
  # Derivation defining an environment for use with nix-shell.
in with pkgs; [ bundle ] ++ dependencies ++ [ curl lispPackages.clwrapper generate-dist lisp ]
