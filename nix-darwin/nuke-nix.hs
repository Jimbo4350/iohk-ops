#! /usr/bin/env nix-shell
#! nix-shell -i runhaskell
{-# LANGUAGE OverloadedStrings, LambdaCase #-}

-- Use this script to reset all/most of the nix and nix-darwin
-- changes. This is just for debugging the deployment script.
-- Run with sudo.

import Prelude hiding (FilePath)
import Turtle
import Data.Text (Text)
import Control.Monad (forM_)

main :: IO ()
main = sh $ do
  void $ proc "launchctl" ["unload", "/Library/LaunchDaemons/org.nixos.nix-daemon.plist"] empty

  forM_ (under "/etc" ["bashrc", "profile", "zshrc"]) $ \cfg ->
    ifExists (cfg <> ".backup-before-nix") $ \backup ->
      procs "mv" (files [backup, cfg]) empty

  let userConfigs = [ ".nix-channels"
                    , ".nix-defexpr"
                    , ".nix-profile"
                    , ".nixpkgs"
                    , ".config/nixpkgs"
                    ]
  let dead = [ "/etc/nix"
             , "/etc/bashrc.backup-before-nix-darwin"
             , "/nix"
             , "/var/lib/buildkite-agent"
             ] ++
             (under "/Library/LaunchDaemons"
               [ "org.nixos.nix-daemon.plist"
               , "org.nixos.activate-system.plist"
               , "org.nixos.buildkite-agent.plist"
               , "org.nixos.nix-gc.plist"
               ]) ++
             (under "/Users/admin" userConfigs) ++
             (under "/root" userConfigs)

  void $ proc "rm" ("-rf":files dead) empty

  let deadUsers = [ "buildkite-agent" ] ++ map (format ("nixbld" % d)) [1 .. 32]
      deadGroups = [ "buildkite-agent", "nixbld"]

  forM_ deadUsers $ \u -> proc "dscl" [".", "-delete", "/Users/" <> u] empty
  forM_ deadGroups $ \g -> proc "dscl" [".", "-delete", "/Groups/" <> g] empty

  echo "Log out and log in again to fix your environment"

ifExists :: MonadIO m => FilePath -> (FilePath -> m a) -> m ()
ifExists f a = testpath f >>= \case
  True -> void $ a f
  False -> pure ()

files :: [FilePath] -> [Text]
files = map (format fp)

under :: FilePath -> [FilePath] -> [FilePath]
under base fs = [base </> f | f <- fs]
