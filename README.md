# java-get

### install

```powershell
irm "https://raw.githubusercontent.com/pwsh-bin/java-get/main/install.ps1" | iex
```

### usage

```powershell
java-get self-install                 - update java-get to latest version
java-get install java@openjdk-1.8     - install java openjdk version 1.8
java-get install maven@3.1            - install meven version 3.1
java-get list-supported               - list all supported binaries
java-get list-supported java          - list all supported java versions
java-get list-installed java          - list all installed java versions
java-get pick java@temurin-11         - pick installed java version
java-get pick ant@1.9                 - pick installed ant version
```
