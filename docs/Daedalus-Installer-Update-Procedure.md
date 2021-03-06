# Daedalus Installer Update Procedure

After the installers are built in CI, they need to be copied to the
installer updates S3 bucket, and an update proposal needs to be
submitted to the cardano-sl network.

This is how wallet clients will self-update.

**21/08/2018 New!** There have recently been some changes and
improvements to these commands from [DEVOPS-868][].

## Intended Audience

This document is mainly intended for use by IOHK DevOps working from
the mainnet, staging mainnet, or testnet deployers.

It can also be used for testing the update system against a [developer
cluster](./Developer-clusters-HOWTO.md).

## Running the scripts

`ssh` into the deployer get a `nix-shell` in the `iohk-ops` checkout.

    cd mainnet
    nix-shell -A withAuxx

You can see the list of subcommands with:

    io update-proposal --help

Each `update-proposal` subcommand has its own usage information
accessible with the `--help` option.

| **Subcommand**      | **Synopsis**                                        |
| ------------------- | --------------------------------------------------- |
| init                | Create template config file and working directory.  |
| find-installers     | Download installer files from the Daedalus build.   |
| sign-installers     | Sign downloaded installer files with GPG.           |
| upload-s3           | Upload installer files to the S3 bucket.            |
| set-version-json    | Update the version info file in the the S3 bucket.  |
| submit              | Send update proposal transaction to the network.    |

The commands are run in order with manual checks between each step.

## Requirements

1. The keys for core nodes should be in the `keys` subdirectory.

2. You need to know the following things:

   * Daedalus revision to propose.
   * The `lastKnownBlockVersion`, according to the table below.
   * The `voterIndex`, according to the table below.
   * Signing key passphrase (optional).
   * IP address of a privileged relay (use `io info`).

## 1. Initialise params

    io -c NETWORK.yaml update-proposal init [DATE] --revision REVISION --block-version VER --voter-index N

Where *DATE* is a string which identifies the update proposal. By
default it will be today's date in `YYYY-MM-DD` format. The other
values should be set as required.

This command will create a template config file like
`update-proposals/mainnet-2018-04-03/params.yaml`.

The directory that the config file is created in is called the
*work dir*. It will contain logs, a node db, keys, installers, hashes,
and other information generated by the update proposal.

Open `params.yaml` in the work dir and double-check that it has
correct values. The contents will look similar to this:

    voterIndex: 2
    daedalusRevision: 32daff63e1fb1590cd7320e4253e61b2a47b0963
    lastKnownBlockVersion: '0.1.0'


## 2. Download installer files from CI

    io -c NETWORK.yaml update-proposal find-installers DATE

The *DATE* parameter is required to be specified and should be the
same as what was reported after running the `init` step.

This will locate the CI builds for the previously configured revision
and download their installer artifacts to the `installers`
subdirectory of the work dir. It will then use the `file` program to
check that they are actually installers for the correct platform, and
calculate their hashes using both `cardano-auxx` and `sha256sum`.

After it has finished, inspect the following values in `params.yaml`:

1. The `grApplicationVersion` value must be a value greater than all
   previous update proposals on the target cluster. This is recorded
   in [Daedalus Installer History](https://github.com/input-output-hk/internal-documentation/wiki/Daedalus-installer-history).

2. The `grApplicationVersion` found should match what you have set in
   `cardano-sl`.

3. The `ciResultBuildNumber` for all `ciResults` should be the correct
   build.
   
4. The `grCardanoCommit` value should match `cardano-sl-src.json` in
   the Daedalus tree.

5. The installer filenames should look normal, have the right network
   and versions, and correspond to the same build as was approved for
   release by QA (if updating mainnet installers).

6. The `installerHashes` and `installerSHA256` values should be
   present.

These values will also be summarised in the file `wiki.md` within the
work dir.

**Important**: If an update proposal is made with the wrong
`applicationVersion`, the update mechanism may fail and users will be
required to intervene by manually installing an update.

### When there is more than one build for the chosen revision

Sometimes there can be multiple builds corresponding to a given
Daedalus revision.

In this case, `find-installers` will list the builds and then exit
without downloading anything. You need to re-run the command with
`--buildkite-build-num` or `--appveyor-build-num` arguments added.


## 3. Sign installer files with GPG

This step requires a signing key available on the deployer host.

    io -c NETWORK.yaml update-proposal sign-installers -u signing.authority@iohk.io DATE

If the signing key is protected with a passphrase, you will be prompted to enter it.

This will place detached signatures in `.asc` files within the work
dir. These will be uploaded to S3 at the same time as the installer
files.


## 4. Upload installer files to the S3 update bucket

    io -c NETWORK.yaml update-proposal upload-s3 DATE

This will upload the hashed installers to S3, under their original
filename, as well as by their hash.

There will also be a file `daedalus-latest-version.json` added to the
work dir with download links and SHA-256 hashes.

*Hint*: The destination S3 bucket is configured with the
`installer-bucket` value in `NETWORK.yaml`. You can edit this for
debugging purposes.

### Troubleshooting

If you get an error like this: `AesonException "Error in $['mainnet_staging_short_epoch_wallet_win64']: key \"infra\" not present")`,
ensure that the `cardano-sl-auxx` that you are using matches that
cardano-sl version used by Daedalus.


## 5. Update version JSON

    io -c NETWORK.yaml update-proposal set-version-json DATE

This will drop the previously created `daedalus-latest-version.json`
into the S3 bucket. If done with the mainnet settings, it will have
the effect of immediately updating the download links on
[The Daedalus Wallet download page](https://daedaluswallet.io/#download).

## 6. Propose the update and vote in favor using majority stake

Find the IP address of a *privileged relay* with `io info`. This is
normally private info so don't leak it.

    io -c NETWORK.yaml update-proposal submit DATE --relay-ip 1.2.3.4 [--with-linux]

By default, installers will be proposed for Windows and macOS, but not
Linux. Use the `--with-linux` flag to include these installers in the
update proposal. While the Linux installer is in beta, it will not be
proposed on the mainnet blockchain.

This will generate a new node db, copy keys from the top-level `keys`
directory, then "rearrange" the copied keys.

It will then send a transaction to the given relay.

Note the proposal ID which is printed at the end of the output.

If the update proposal was successful, the ratified proposal will take
effect in _k_ slots time, where _k_ is the security parameter. On
mainnet/staging/testnet with _k=2160_ and 20 second slot duration,
this will be 12 hours.

## 7. Testing proposal acceptance

*Useful generic search:* [keywords](https://papertrailapp.com/groups/6487901/events?q=UpdateProposal%20OR%20UpdateVote%20OR%20Processing%20of%20proposal%20OR%20New%20vote%20OR%20Stakes%20of%20proposal%20OR%20Verifying%20stake%20for%20proposal%20OR%20Proposal%20is%20confirmed)

1. Search Papertrail for `We'll request data for key Tagged (UpdateProposal,[UpdateVote])` and confirm it references the first 8 chars of the proposal ID from the previous step.
2. Search Papertrail for `Processing of proposal csl-daedalus:` and confirm that
    1. the number following `:` matches the intended `applicationVersion`
    2. the correct `UpId:` is referenced
    3. the tags for the supported platforms are mentioned: `tags: [win64, macos64]`
    4. matching lines end with `is successful`

### Testing for proposal confirmation

12 hours after proposal acceptance, it should be confirmed.

Search papertrail for `Proposal 6e2f23c1 is confirmed` on a core node, using the first 8 characters of the proposal ID from the previous step.


## 8. Testing the update

Work in progress: [DEVOPS-651](https://iohk.myjetbrains.com/youtrack/issue/DEVOPS-651).

This is also covered in [how-to/test-update-system.md](https://github.com/input-output-hk/cardano-sl/blob/develop/docs/how-to/test-update-system.md#check-update-taken-by-wallet), section *Check update taken by wallet*.


## 9. Update the wiki

Copy the contents of `wiki.md` from the work dir and paste into
[Daedalus Installer History](https://github.com/input-output-hk/internal-documentation/wiki/Daedalus-installer-history).

Also update any other documentation which is missing or out of date.


## Block version table

The block version reflects the soft forks which have occurred on the
network. Use the following values depending on the network where the
update will be proposed.

| Network | `lastKnownBlockVersion` |
|:--------| -----------------------:|
| mainnet |                 `0.1.0` |
| staging |                 `0.1.0` |
| testnet |                 `0.0.0` |


## Voter index table

For whatever reason, the update proposal procedure requires a voter
index. This number is supposed to denote the person who submitted the
proposal.

| `voterIndex` | Person      |
| ------------:| ----------- |
|            1 | Domen       |
|            2 | Serge       |

**Note:** The `voterIndex` needs to be *≥ 0 and ≤ 2*, otherwise you
will receive the error `Prelude.!!: index too large`.


## See also

* [Cardano SL Updater](https://cardanodocs.com/technical/updater/)

* [Previously released versions](https://github.com/input-output-hk/internal-documentation/wiki/Daedalus-installer-history)

* [cardano-sl/how-to/test-update-system.md](https://github.com/input-output-hk/cardano-sl/blob/develop/docs/how-to/test-update-system.md#propose-update--vote-for-it)

[DEVOPS-656]: https://iohk.myjetbrains.com/youtrack/issue/DEVOPS-656
[DEVOPS-709]: https://iohk.myjetbrains.com/youtrack/issue/DEVOPS-709
[DEVOPS-710]: https://iohk.myjetbrains.com/youtrack/issue/DEVOPS-710
[DEVOPS-816]: https://iohk.myjetbrains.com/youtrack/issue/DEVOPS-816
[DEVOPS-868]: https://iohk.myjetbrains.com/youtrack/issue/DEVOPS-868

## Future automation

1. The `lastKnownBlockVersion` parameter should be investigated to
   determine whether it is really needed to be configured, or can be
   determined from the configuration.

2. When printing paths to *work dir*, show them as relative to the
   `iohk-ops` checkout, rather than as absolute paths.

3. Automatically make sure that the version of auxx and tools used
   corresponds to the `cardano-sl` version of Daedalus. Currently, the
   version used is that built by the nix-shell.

4. [DEVOPS-816][] Automated testing of update proposals.
