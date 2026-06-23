{
  description = "Kakumazaka RTA";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-util.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-util,
    }:

    flake-util.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            android_sdk.accept_license = true;
            allowUnfree = true;
          };
        };
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "13.0";
          buildToolsVersions = [
            "36.0.0"
            "35.0.0"
          ];
          platformVersions = [
            "36"
            "35"
          ];
          includeEmulator = true;
          abiVersions = [
            "armeabi-v7a"
            "x86_64"
          ];
          includeSystemImages = true;
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          systemImageTypes = [
            "google_apis"
          ];
          includeCmake = true;
          cmakeVersions = [ "3.22.1" ];
        };
        androidSdk = androidComposition.androidsdk;
      in
      {
        devShells.default =
          with pkgs;
          mkShell {
            ANDROID_SDK = "${androidSdk}/libexec/android-sdk";
            ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
            ANDROID_NDK_ROOT = "${androidSdk}/libexec/android-sdk/ndk/28.2.13676358";
            JAVA_HOME = jdk17.home;
            buildInputs = [
              flutter
              androidSdk
              jdk17
            ];
          };
      }
    );
}
