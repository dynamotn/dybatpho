# dybatpho
![Bash Script](https://img.shields.io/badge/bash_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
[![Coverage Status](https://coveralls.io/repos/github/dynamotn/dybatpho/badge.svg)](https://coveralls.io/github/dynamotn/dybatpho)
[![CI](https://github.com/dynamotn/dybatpho/actions/workflows/ci.yaml/badge.svg)](https://github.com/dynamotn/dybatpho/actions/workflows/ci.yaml)
[![Latest release](https://img.shields.io/github/release/dynamotn/dybatpho.svg)](https://github.com/dynamotn/dybatpho/releases/latest)

The place to store **frequently used functions** that are used in pipelines, scripts for multiple repositories and help you to **write efficient Bash script**.

## What does `dybatpho` mean?
`dybatpho` is a portmanteau of `đi bát phố`. `đi` is related to my nickname (Dynamo). `đi bát phố` means wandering on the street, an idiom in Vietnamese with `bát` with almost similar pronunciation with `bash`, `phố` is `street` that have many stores. I want this library will be used as a street on the Internet, which have some special stores to give you some surprise presents in your codes.

## Usage
1. Add `dybatpho` into your project in the way that best fits your workflow

The only requirement is that you **pin the version of `dybatpho`** that you use. This is important so that changes to `dybatpho` do not have the power to break all projects that use `dybatpho`. Your project can then test updates to `dybatpho` and roll forward periodically.
- Add as a submodule: it's an easy way to integrate `dybatpho` and automatically use a single SHA until manually updated. Submodules add a pointer from a mount point in your repo to the external repo (`dybatpho`), and require workflow changes to ensure that pointer is referenced during clone, checkout and some other operations.
```sh
git submodule add --depth 1 https://github.com/dynamotn/dybatpho.git <path>

# To update
git submodule update <path> --remote
```
- Add as a subtree: subtrees copy an external repo into a subdirectory of the host repo, no workflow changes are required. Subtrees naturally keep a single version of `dybatpho` until explicitly updated. Note that subtree merge commits do not rebase well ⚠️, so best to keep subtree updates in separate PRs from normal commits.
```sh
git subtree add --prefix <path> https://github.com/dynamotn/dybatpho.git main --squash

# To update
git subtree pull --prefix <path> https://github.com/dynamotn/dybatpho.git main --squash
```

- Clone `dybatpho` in your deployment process, `dybatpho` doesn't have to be within your repo, just needs to be somewhere where your scripts can source [init](init). This is where it's most important that you implement a mechanism to always use the same SHA, as a clone will track main branch by default, which is not an allowed use of `dybatpho`.
2. Source logics

Once you have `dybatpho` cloned in your project, you source by two ways:

- Source `dybatpho/init`: This ensures submodules are initialized. This makes it easy to source libraries from other scripts.
- Source `dybatpho/src/<library name>.sh` for any libraries you are interested in. But you need to check it carefully because some scripts are depended on another script.

> [!NOTE]
> You can see [example.sh](doc/example.sh) for example usages.
> Or you can see implementation in my [dotfiles](https://github.com/dynamotn/dotfiles) or my [custom font](https://github.com/dynamotn/Iosevka-Dynamo)

## Structure

```
 .
├──  doc # documentation of modules
│   ├──  *.md # module
│   └──  example.sh # example script for user can use as a reference
├──  src # source code of modules
│   └──  *.sh # module
├──  test # unit test folder
│   ├──  lib # library from bats
│   │   ├──  assert
│   │   ├──  core
│   │   └──  support
│   └──  *.bats # unit test for each module
├──  init # initial script, source it first
├──  doc.sh # generation documentation script
├──  modules # list of modules
└──  test.sh # unit test script
```
## Contents
- [string.sh](doc/string.md)
- [logging.sh](doc/logging.md)
- [helpers.sh](doc/helpers.md)
- [process.sh](doc/process.md)
- [network.sh](doc/network.md)
