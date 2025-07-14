# dybatpho

![Bash Script](https://img.shields.io/badge/bash_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
[![Coverage Status](https://coveralls.io/repos/github/dynamotn/dybatpho/badge.svg)](https://coveralls.io/github/dynamotn/dybatpho)
[![CI](https://github.com/dynamotn/dybatpho/actions/workflows/ci.yaml/badge.svg)](https://github.com/dynamotn/dybatpho/actions/workflows/ci.yaml)
[![Latest release](https://img.shields.io/github/release/dynamotn/dybatpho.svg)](https://github.com/dynamotn/dybatpho/releases/latest)

> **dybatpho** – A powerful collection of bash functions to help you build scripts efficiently, quickly, and maintainably!

---

## 🚀 Why choose **dybatpho**?

- **Save time:** A curated set of the most popular & useful functions for working with Bash scripts.
- **Easy integration:** Flexibly use as a submodule, subtree, or manual clone.
- **Battle-tested:** Used in many projects, personal dotfiles, and in real CI/CD workflows.
- **Extensible:** Easily add your own modules or customize to fit your needs.
- **Community-driven:** Always open to feedback, suggestions, and PRs from everyone.

## 📖 What is `dybatpho`?

`dybatpho` is a portmanteau of `đi bát phố` - meaning "to wander and explore", just like this repo helps you discover and use handy bash functions freely and flexibly.

# ⚡️ Quick Start

1. **Add `dybatpho` to your project** (pin the version if needed):

   - **Submodule:**

     ```sh
     git submodule add --depth 1 https://github.com/dynamotn/dybatpho.git <path>
     git submodule update <path> --remote
     ```

   - **Subtree:**

     ```sh
     git subtree add --prefix <path> https://github.com/dynamotn/dybatpho.git main --squash
     git subtree pull --prefix <path> https://github.com/dynamotn/dybatpho.git main --squash
     ```

   - **Manual clone** (for CI/CD, etc.):

     ```sh
     git clone https://github.com/dynamotn/dybatpho.git
     ```

2. **Source the logic you need:**

   ```sh
   # Source the initialization script
   . <path-to-dybatpho>/init.sh
   ```

   > See more [example scripts](example/) or real-world usage in [my dotfiles](https://github.com/dynamotn/dotfiles).

## 🗂 Directory Structure

```
.
├── doc/            # Module documentation
├── example/        # Example scripts for users
├── scripts/        # Helper scripts (test, doc generation, etc.)
├── src/            # Source code of modules
├── test/           # Unit tests
└── init.sh         # Initialization script, **must be sourced first**
```

## 📚 Contents & Featured Modules

- [array.sh](doc/array.md) – Array manipulation
- [string.sh](doc/string.md) – String operations
- [logging.sh](doc/logging.md) – Easy logging
- [helpers.sh](doc/helpers.md) – Miscellaneous utilities
- [process.sh](doc/process.md) – Process management
- [network.sh](doc/network.md) – Network utilities
- [file.sh](doc/file.md) – File operations
- [cli.sh](doc/cli.md) – CLI building support

## 🎯 Usage Example

```sh
# Using the log function
. dybatpho/init.sh
dybatpho::register_err_handler
dybatpho::info "Greetings from dybatpho!"
```

See more at [example/](example/).

## 💬 Contribution & Support

- Open an Issue or Pull Request if you'd like to suggest ideas, fix bugs, or contribute new modules!
- All feedback and contributions are welcome.

---

**Get started with dybatpho now to optimize your workflow and save time with your Bash scripts!**

<p align="center">
  <a href="https://github.com/dynamotn/dybatpho/stargazers">
    <img src="https://img.shields.io/github/stars/dynamotn/dybatpho?style=social" alt="Star dybatpho" />
  </a>
</p>
