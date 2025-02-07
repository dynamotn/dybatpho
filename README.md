# bash-lib
The place to store functions that are used in pipelines, scripts for multiple repositories.

## Usage
1. Add bash-lib into your project in the way that best fits your workflow
The only requirement is that you *pin the version of bash-lib* that you use. This is important so that changes to bash-lib do not have the power to break all projects that use bash-lib. Your project can then test updates to bash-lib and roll forward periodically.
- Add as a submodule: it's an easy way to integrate bash-lib and automatically use a single SHA until manually updated. Submodules add a pointer from a mount point in your repo to the external repo (bash-lib), and require workflow changes to ensure that pointer is referenced during clone, checkout and some other operations.
```sh
git submodule add --depth 1 https://github.com/dynamotn/bash-lib.git <path>

# To update
git submodule update <path> --remote
```
- Add as a subtree: subtrees copy an external repo into a subdirectory of the host repo, no workflow changes are required. Subtrees naturally keep a single version of bash-lib until explicitly updated. Note that subtree merge commits do not rebase well ⚠️, so best to keep subtree updates in separate PRs from normal commits.
```sh
git subtree add --prefix <path> https://github.com/dynamotn/bash-lib.git main --squash

# To update
git subtree pull --prefix <path> https://github.com/dynamotn/bash-lib.git main --squash
```

- Clone bash-lib in your deployment process, bash-lib doesn't have to be within your repo, just needs to be somewhere where your scripts can source [init.sh](init.sh). This is where it's most important that you implement a mechanism to always use the same SHA, as a clone will track main branch by default, which is not an allowed use of bash-lib.
2. Source logics
Once you have bash-lib cloned in your project, you source by two ways:

- Source `bash-lib/init.sh`: This ensures submodules are initialized. This makes it easy to source libraries from other scripts.
- Source `bash-lib/src/<library name].sh` for any libraries you are interested in.

## Structure
TODO: Explain structure

## Contents
|Library|Description|Functions|
|-------|-----------|---------|
