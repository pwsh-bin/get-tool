# get-tool

### install

```powershell
irm "https://raw.githubusercontent.com/pwsh-bin/get-tool/main/install.ps1" | iex
```

### usage

```powershell
get-tool self-install                 - update get-tool to latest version
get-tool install java@openjdk-1.8     - install java openjdk version 1.8
get-tool install maven@3.1            - install maven version 3.1
get-tool list-supported               - list all supported tools
get-tool list-supported java          - list all supported java versions
get-tool list-installed               - list all installed tools
get-tool init                         - add tools to current path
get-tool setup                        - add init to current profile
```
