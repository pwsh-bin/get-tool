Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

${VERSION} = "v0.1.0"
${HELP} = @"
Usage:
java-get self-install                 - update java-get to latest version
java-get install java@openjdk-1.8     - install java openjdk version 1.8
java-get install maven@3.1            - install meven version 3.1
java-get list-supported               - list all supported binaries
java-get list-supported java          - list all supported java versions
java-get list-installed java          - list all installed java versions
java-get pick java@temurin-11         - pick installed java version
java-get pick ant@1.9                 - pick installed ant version

${VERSION}
"@

if (${args}.count -eq 0) {
  Write-Host ${HELP}
  return
}

${TEMP_PATH} = "${env:JAVA_GET_HOME}\.temp"
if (-not (Test-Path -Path ${TEMP_PATH} -PathType "Container")) {
  ${NO_OUTPUT} = (New-Item -Path ${TEMP_PATH} -ItemType "Directory")
}

${JDKS_PATH} = "${HOME}\.jdks"
if (-not (Test-Path -Path ${JDKS_PATH} -PathType "Container")) {
  ${NO_OUTPUT} = (New-Item -Path ${JDKS_PATH} -ItemType "Directory")
}

${JAVA_TOOLS_PATH} = "${HOME}\.java-tools"
if (-not (Test-Path -Path ${JAVA_TOOLS_PATH} -PathType "Container")) {
  ${NO_OUTPUT} = (New-Item -Path ${JAVA_TOOLS_PATH} -ItemType "Directory")
}

${BINARIES} = @(
  "java",
  "maven",
  "ant",
  "gradle"
)

function UpdatePath {
  param (
    ${Binary}
  )
  ${path} = "${env:JAVA_GET_HOME}\${Binary}\bin"
  if (${env:PATH} -cnotlike "*${path}*") {
    ${env:PATH} = "${path};${env:PATH}"
    [System.Environment]::SetEnvironmentVariable("PATH", ${env:PATH}, [System.EnvironmentVariableTarget]::User)
  }
}

function GetJDKS {
  ${uri} = "https://download.jetbrains.com/jdk/feed/v1/jdks.json"
  return ((Invoke-RestMethod -Method "Get" -Uri ${uri}).jdks |
    Where-Object -Property "listed" -eq $null |
    Select-Object -ExpandProperty "packages" |
    Where-Object -FilterScript { ($_.os -eq "windows") -and ($_.arch -eq "x86_64") } |
    Sort-Object -Property "install_folder_name")
}

function GetMavenBinaries {
  param (
    ${Version}
  )
  ${prefix} = "apache-maven"
  ${postfix} = "bin.zip"
  ${path} = "maven/maven-3"
  ${subpath} = "/binaries/"
  ${uri} = "https://dlcdn.apache.org/${path}"
  ${hrefs} = ((Invoke-WebRequest -Method "Get" -Uri ${uri} -Body @{
        "C" = "N"
        "O" = "D"
        "F" = "0"
        "P" = "${Version}*"
      }).Links |
    Select-Object -ExpandProperty "href" -Skip 1)
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${version} = (${href} -creplace "/", "")
    ${install_folder_name} = "${prefix}-${version}"
    ${archive_file_name} = "${install_folder_name}-${postfix}"
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}/${version}${subpath}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${install_folder_name}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
    }
  }
  return ${binaries}
}

function GetApacheBinaries {
  param (
    ${Path},
    ${Version}
  )
  ${prefix} = "*-"
  ${postfix} = "*-bin.zip"
  ${uri} = "https://dlcdn.apache.org/${Path}/binaries"
  ${hrefs} = ((Invoke-WebRequest -Method "Get" -Uri ${uri} -Body @{
        "C" = "N"
        "O" = "D"
        "F" = "0"
        "P" = "${prefix}${Version}${postfix}"
      }).Links |
    Select-Object -ExpandProperty "href" -Skip 1)
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${name} = ${href}.SubString(0, ${href}.Length - ${postfix}.Length + 1)
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}/${href}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${name}
      "archive_file_name"    = ${href}
      "install_folder_name"  = ${name}
    }
  }
  return ${binaries}
}

function GetGradleBinaries {
  param (
    ${Version}
  )
  ${prefix} = "*-"
  ${postfix} = "*-bin.zip"
  ${uri} = "https://services.gradle.org/distributions"
  ${hrefs} = ((Invoke-WebRequest -Method "Get" -Uri ${uri}).Links |
    Select-Object -ExpandProperty "href" -Skip 1 |
    Where-Object -FilterScript { ($_ -cnotlike "*rc*") -and ($_ -cnotlike "*milestone*") -and ($_ -clike "${prefix}${version}${postfix}") } |
    Sort-Object -Descending)
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${archive_file_name} = (${href} -csplit "/")[-1]
    ${install_folder_name} = ${archive_file_name}.SubString(0, ${archive_file_name}.Length - ${postfix}.Length + 1)
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}/${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${install_folder_name}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
    }
  }
  return ${binaries}
}

function Unpack {
  param (
    ${Binary},
    ${Arguments},
    ${Objects},
    ${Path}
  )
  if (${Objects}.count -eq 0) {
    Write-Host "[ERROR] Unsupported version argument."
    return
  }
  ${object} = ${Objects}[0]
  ${uri} = ${object}.url
  ${package_type} = ${object}.package_type
  ${unpack_prefix_filter} = ${object}.unpack_prefix_filter
  ${archive_file_name} = ${object}.archive_file_name
  ${install_folder_name} = ${object}.install_folder_name
  ${filepath} = "${TEMP_PATH}\${archive_file_name}"
  try {
    Invoke-RestMethod -Method "Get" -Uri ${uri} -OutFile ${filepath}
  }
  catch {
    Write-Host $_
    return
  }
  switch (${package_type}) {
    "zip" {
      Expand-Archive -Force -Path ${filepath} -DestinationPath ${TEMP_PATH}
      Remove-Item -Force -Path ${filepath}
      break
    }
    "targz" {
      ${command} = "tar --extract --lzma --file ${filepath} --directory ${TEMP_PATH}"
      Invoke-Expression -Command ${command}
      break
    }
    default {
      Write-Host "[ERROR] Unsupported file extension."
      return
    }
  }
  ${from} = "${TEMP_PATH}\${unpack_prefix_filter}"
  ${to} = "${Path}\${install_folder_name}"
  ${command} = "${to}\bin\${Binary} ${Arguments}"
  if (Test-Path -Path ${to} -PathType "Container") {
    Remove-Item -Force -Recurse -Path ${to}
  }
  Move-Item -Force -Path ${from} -Destination ${to}
  Invoke-Expression -Command ${command}
}

function Pick {
  param (
    ${Binary},
    ${Path},
    ${Objects}
  )
  if (${Objects}.count -eq 0) {
    Write-Host "[ERROR] Unsupported version argument."
    return $null
  }
  ${picked} = ${object}[0].Name
  ${source_path} = "${Path}\${picked}"
  ${link_path} = "${env:JAVA_GET_HOME}\${Binary}"
  ${NO_OUTPUT} = (New-Item -Force -ItemType "SymbolicLink" -Path ${link_path} -Target ${source_path})
  return ${picked}
}

function ListSupported {
  param (
    ${Objects}
  )
  Write-Host ((${Objects} |
      Select-Object -ExpandProperty "install_folder_name") -join "`n")
}

function ListInstalledJavaTool {
  param (
    ${Pattern}
  )
  Write-Host ((Get-ChildItem -Path ${JAVA_TOOLS_PATH} -Filter ${Pattern} -Directory -Name) -join "`n")
}

switch (${args}[0]) {
  { $_ -in "si", "self-install" } {
    Invoke-RestMethod -Method "Get" -Uri "https://raw.githubusercontent.com/pwsh-bin/java-get/main/install.ps1" |
    Invoke-Expression
    return
  }
  { $_ -in "i", "install" } {
    ${binary}, ${version} = (${args}[1] -csplit "@")
    switch (${binary}) {
      ${BINARIES}[0] {
        if ($null -eq ${version}) {
          ${version} = "openjdk"
        }
        ${objects} = (GetJDKS |
          Where-Object -Property "install_folder_name" -clike "${version}*")
        Unpack -Binary "java.exe" -Arguments "-version" -Objects ${objects} -Path ${JDKS_PATH}
        return
      }
      ${BINARIES}[1] {
        ${objects} = (GetMavenBinaries -Version ${version})
        Unpack -Binary "mvn.cmd" -Arguments "-version" -Objects ${objects} -Path ${JAVA_TOOLS_PATH}
        return
      }
      ${BINARIES}[2] {
        ${objects} = (GetApacheBinaries -Path "ant" -Version ${version})
        Unpack -Binary "ant.bat" -Arguments "-version" -Objects ${objects} -Path ${JAVA_TOOLS_PATH}
        return
      }
      ${BINARIES}[3] {
        ${objects} = (GetGradleBinaries  |
          Where-Object -Property "install_folder_name" -clike "*-${version}*")
        Unpack -Binary "gradle.bat" -Arguments "--version" -Objects ${objects} -Path ${JAVA_TOOLS_PATH}
        return
      }
      default {
        Write-Host "[ERROR] Unsupported binary argument."
        return
      }
    }
  }
  { $_ -in "ls", "list-supported" } {
    ${binary} = ${args}[1]
    switch (${binary}) {
      ${BINARIES}[0] {
        ${objects} = (GetJDKS)
        return (ListSupported -Objects ${objects})
      }
      ${BINARIES}[1] {
        ${objects} = (GetMavenBinaries)
        return (ListSupported -Objects ${objects})
      }
      ${BINARIES}[2] {
        ${objects} = (GetApacheBinaries -Path "ant")
        return (ListSupported -Objects ${objects})
      }
      ${BINARIES}[3] {
        ${objects} = (GetGradleBinaries)
        return (ListSupported -Objects ${objects})
      }
      default {
        Write-Host ((${BINARIES} |
            Sort-Object) -join "`n")
        return
      }
    }
    return
  }
  { $_ -in "li", "list-installed" } {
    ${binary} = ${args}[1]
    switch (${binary}) {
      ${BINARIES}[0] {
        return (Get-ChildItem -Path ${JDKS_PATH} -Directory -Name)
      }
      ${BINARIES}[1] {
        return (ListInstalledJavaTool -Pattern "apache-maven-*")
      }
      ${BINARIES}[2] {
        return (ListInstalledJavaTool -Pattern "apache-ant-*")
      }
      ${BINARIES}[3] {
        return (ListInstalledJavaTool -Pattern "gradle-*")
      }
      default {
        Write-Host "[ERROR] Unsupported binary argument."
        return
      }
    }
    return
  }
  { $_ -in "p", "pick" } {
    ${binary}, ${version} = ${args}[1] -csplit "@"
    switch (${binary}) {
      ${BINARIES}[0] {
        UpdatePath -Binary ${binary}
        ${objects} = (Get-ChildItem -Path ${JDKS_PATH} -Filter "${version}*" -Directory -Name)
        ${picked} = (Pick -Binary ${binary} -Path ${JDKS_PATH} -Objects ${objects})
        if ($null -ne ${picked}) {
          ${env:JAVA_HOME} = "${JDKS_PATH}\${picked}"
          [System.Environment]::SetEnvironmentVariable("JAVA_HOME", ${env:JAVA_HOME}, [System.EnvironmentVariableTarget]::User)
          Write-Host "[DEBUG] JAVA_HOME: ${env:JAVA_HOME}"
        }
        return
      }
      ${BINARIES}[1] {
        UpdatePath -Binary ${binary}
        ${objects} = (Get-ChildItem -Path ${JAVA_TOOLS_PATH} -Filter "apache-maven-${version}*" -Directory -Name)
        ${picked} = (Pick -Binary ${binary} -Path ${JAVA_TOOLS_PATH} -Objects ${objects})
        if ($null -ne ${picked}) {
          ${env:M2_HOME} = "${JAVA_TOOLS_PATH}\${picked}"
          [System.Environment]::SetEnvironmentVariable("M2_HOME", ${env:M2_HOME}, [System.EnvironmentVariableTarget]::User)
          Write-Host "[DEBUG] M2_HOME: ${env:M2_HOME}"
        }
        return
      }
      ${BINARIES}[2] {
        UpdatePath -Binary ${binary}
        ${objects} = (Get-ChildItem -Path ${JAVA_TOOLS_PATH} -Filter "apache-ant-${version}*" -Directory -Name)
        ${picked} = (Pick -Binary ${binary} -Path ${JAVA_TOOLS_PATH} -Objects ${objects})
        if ($null -ne ${picked}) {
          ${env:ANT_HOME} = "${JAVA_TOOLS_PATH}\${picked}"
          [System.Environment]::SetEnvironmentVariable("ANT_HOME", ${env:ANT_HOME}, [System.EnvironmentVariableTarget]::User)
          Write-Host "[DEBUG] ANT_HOME: ${env:ANT_HOME}"
        }
        return
      }
      ${BINARIES}[3] {
        UpdatePath -Binary ${binary}
        ${objects} = (Get-ChildItem -Path ${JAVA_TOOLS_PATH} -Filter "gradle-${version}*" -Directory -Name)
        ${picked} = (Pick -Binary ${binary} -Path ${JAVA_TOOLS_PATH} -Objects ${objects})
        if ($null -ne ${picked}) {
          ${env:GRADLE_HOME} = "${JAVA_TOOLS_PATH}\${picked}"
          [System.Environment]::SetEnvironmentVariable("GRADLE_HOME", ${env:GRADLE_HOME}, [System.EnvironmentVariableTarget]::User)
          Write-Host "[DEBUG] GRADLE_HOME: ${env:GRADLE_HOME}"
        }
        return
      }
      default {
        Write-Host "[ERROR] Unsupported binary argument."
        return
      }
    }
    return
  }
  default {
    Write-Host "[ERROR] Unsupported command argument."
    return
  }
}
