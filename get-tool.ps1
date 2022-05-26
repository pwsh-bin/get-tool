Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

${DEBUG} = Test-Path -PathType "Container" -Path (Join-Path -Path ${PSScriptRoot} -ChildPath ".git")
${PS1_HOME} = Join-Path -Path ${HOME} -ChildPath ".get-tool"
${PS1_FILE} = Join-Path -Path ${PS1_HOME} -ChildPath "get-tool.ps1"
${STORE_PATH} = Join-Path -Path ${PS1_HOME} -ChildPath ".store"
${7ZIP} = Join-Path -Path ${ENV:PROGRAMFILES} -ChildPath "7-Zip" -AdditionalChildPath "7z.exe"
${TOOLS} = @(
  "java",
  "maven",
  "ant",
  "gradle",
  "python",
  "node",
  "ruby",
  "go",
  "pypy"
)
${VERSION} = "v0.2.1"
${HELP} = @"
Usage:
get-tool self-install                 - update get-tool to latest version
get-tool install java@openjdk-1.8     - install java openjdk version 1.8
get-tool install maven@3.1            - install maven version 3.1
get-tool list-supported               - list all supported tools
get-tool list-supported java          - list all supported java versions
get-tool list-installed               - list all installed tools
get-tool init                         - add tools to current path
get-tool setup                        - add init to current profile

${VERSION}
"@

if (${args}.Count -eq 0) {
  Write-Host ${HELP}
  return
}

function GetJDKS {
  param (
    ${Version}
  )
  ${uri} = "https://download.jetbrains.com/jdk/feed/v1/jdks.json"
  ${jdks} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${jdks} = Invoke-RestMethod -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  return (${jdks}.jdks | Where-Object -Property "listed" -eq $null | Select-Object -ExpandProperty "packages" | Where-Object -FilterScript { ($_.os -eq "windows") -and ($_.arch -eq "x86_64") -and ($_.install_folder_name -clike "${Version}*") })
}

function GetMaven {
  param (
    ${Version}
  )
  ${uri} = "https://dlcdn.apache.org/maven/maven-3/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri} -Body @{
      "C" = "N"
      "O" = "D"
      "F" = "0"
      "P" = "${Version}*"
    }
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" -Skip 1)
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${_version} = ${href}.SubString(0, ${href}.Length - 1)
    ${version} = [version]${_version}
    ${unpack_prefix_filter} = "apache-maven-${_version}"
    ${archive_file_name} = "apache-maven-${_version}-bin.zip"
    ${install_folder_name} = "maven-${_version}"
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${_version}/binaries/${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetAnt {
  param (
    ${Version}
  )
  ${uri} = "https://dlcdn.apache.org/ant/binaries/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri} -Body @{
      "C" = "N"
      "O" = "D"
      "F" = "0"
      "P" = "*-${Version}*-bin.zip"
    }
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" -Skip 1)
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${unpack_prefix_filter} = ${href}.SubString(0, ${href}.LastIndexOf("-"))
    ${install_folder_name} = ${unpack_prefix_filter}.SubString(${unpack_prefix_filter}.IndexOf("-") + 1)
    ${version} = [version]${install_folder_name}.SubString(${install_folder_name}.IndexOf("-") + 1)
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${href}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${href}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetGradle {
  param (
    ${Version}
  )
  ${uri} = "https://services.gradle.org/distributions/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" -Skip 1 | Where-Object -FilterScript { ($_ -cnotlike "*rc*") -and ($_ -cnotlike "*milestone*") -and ($_ -clike "*-${version}*-bin.zip") })
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${archive_file_name} = ${href}.SubString(${href}.LastIndexOf("/") + 1)
    ${install_folder_name} = ${archive_file_name}.SubString(0, ${archive_file_name}.LastIndexOf("-"))
    ${version} = [version]${install_folder_name}.SubString(${install_folder_name}.IndexOf("-") + 1)
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${install_folder_name}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetPython {
  param (
    ${Version}
  )
  ${uri} = "https://www.python.org/ftp/python/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" -Skip 1 | Where-Object -FilterScript { ($_ -clike "*.*.*") -and ($_ -cnotlike "*-*") -and ($_ -clike "${Version}*") })
  ${binaries} = @()
  ${minimumVersion} = [version]"3.5.0"
  foreach (${href} in ${hrefs}) {
    ${_version} = ${href}.SubString(0, ${href}.Length - 1)
    ${version} = [version]${_version}
    if (${version} -lt ${minimumVersion}) {
      continue
    }
    ${archive_file_name} = "python-${_version}-embed-amd64.zip"
    ${install_folder_name} = "python-${_version}"
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${href}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ""
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  ${result} = (${binaries} | Sort-Object -Property "version")
  # NOTE: check is last release is not a prerelease
  ${uri} = ${result}[-1].url
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] HEAD ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Head" -Uri ${uri}
  }
  catch {
    return ${result}[0..(${result}.Count - 2)]
  }
  return ${result}
}

function GetNode {
  param (
    ${Version}
  )
  ${uri} = "https://nodejs.org/dist/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" -Skip 1 | Where-Object -FilterScript { ($_ -clike "v*.*.*") -and ($_ -cnotlike "*-*") -and ($_ -clike "v${Version}*") })
  ${binaries} = @()
  ${minimumVersion} = [version]"4.5.0"
  foreach (${href} in ${hrefs}) {
    ${_version} = ${href}.SubString(1, ${href}.Length - 2)
    ${version} = [version]${_version}
    if (${version} -lt ${minimumVersion}) {
      continue
    }
    ${unpack_prefix_filter} = "node-v${_version}-win-x64"
    ${archive_file_name} = "${unpack_prefix_filter}.zip"
    ${install_folder_name} = "node-${_version}"
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${href}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetRuby {
  param (
    ${Version}
  )
  ${uri} = "https://rubyinstaller.org/downloads/archives/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" | Where-Object -FilterScript { ($_ -clike "*-x64.7z") -and ($_ -clike "*-${Version}*") })
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${archive_file_name} = ${href}.SubString(${href}.LastIndexOf("/") + 1)
    ${unpack_prefix_filter} = ${archive_file_name}.SubString(0, ${archive_file_name}.Length - 3) # NOTE: drop '.7z'
    ${temp} = ${archive_file_name}.SubString(${archive_file_name}.IndexOf("-") + 1)
    ${_version} = (${temp}.SubString(0, ${temp}.Length - 7) -creplace '-', '.')  # NOTE: drop '-x64.7z'
    ${version} = [version]${_version}
    ${install_folder_name} = "ruby-${_version}"
    ${binaries} += [pscustomobject]@{
      "url"                  = ${href}
      "package_type"         = "7z"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetGo {
  param (
    ${Version}
  )
  ${uri} = "https://go.dev/dl/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" | Where-Object -FilterScript { ($_ -clike "*.windows-amd64.zip") -and ($_ -cnotlike "*rc*") -and ($_ -cnotlike "*beta*") -and ($_ -clike "/dl/go${Version}*") })
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${archive_file_name} = ${href}.SubString(${href}.LastIndexOf("/") + 1)
    ${temp} = ${archive_file_name}.SubString(2) # NOTE: drop 'go'
    ${_version} = ${temp}.SubString(0, ${temp}.Length - 18) # NOTE: drop '.windows-amd64.zip'
    ${version} = [version]${_version}
    ${install_folder_name} = "go-${_version}"
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = "go"
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetPyPy {
  param (
    ${Version}
  )
  ${uri} = "https://downloads.python.org/pypy/"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = Invoke-WebRequest -Method "Get" -Uri ${uri}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" | Where-Object -FilterScript { ($_ -clike "*-win64.zip") -and ($_ -cnotlike "*rc*") -and ($_ -cnotlike "*beta*") -and (($_ -creplace "v", "") -clike "pypy${Version}*") })
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${unpack_prefix_filter} = ${href}.SubString(0, ${href}.Length - 4) # NOTE: drop '.zip'
    ${temp} = ${unpack_prefix_filter}.SubString(4) # NOTE: drop 'pypy'
    ${temp} = ${temp}.SubString(0, ${temp}.Length - 6) # NOTE: drop '-win64'
    ${index} = ${temp}.IndexOf("-")
    ${_version_python} = ${temp}.SubString(0, ${index})
    ${_version_pypy} = ${temp}.SubString(${index} + 2)
    ${version_python} = [version]${_version_python}
    ${version_pypy} = [version]${_version_pypy}
    ${install_folder_name} = "pypy-${_version_python}-${_version_pypy}"
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${href}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${href}
      "install_folder_name"  = ${install_folder_name}
      "version_python"       = ${version_python}
      "version_pypy"         = ${version_pypy}
    }
  }
  return (${binaries} | Sort-Object -Property ("version_python", "version_pypy"))
}

function Install {
  param (
    ${Tool},
    ${Executable},
    ${Arguments},
    ${Objects}
  )
  if (${Objects}.Count -eq 0) {
    Write-Host "[ERROR] Unsupported version argument."
    exit
  }
  ${object} = ${Objects}[-1]
  ${uri} = ${object}.url
  ${package_type} = ${object}.package_type
  ${unpack_prefix_filter} = ${object}.unpack_prefix_filter
  ${archive_file_name} = ${object}.archive_file_name
  ${install_folder_name} = ${object}.install_folder_name
  ${outfile} = (Join-Path -Path ${STORE_PATH} -ChildPath ${archive_file_name})
  ${directory} = (Join-Path -Path ${STORE_PATH} -ChildPath ${install_folder_name})
  ${link} = (Join-Path -Path ${PS1_HOME} -ChildPath ${Tool})
  ${target} = (Join-Path -Path ${directory} -ChildPath ${unpack_prefix_filter})
  if (-not (Test-Path -PathType "Container" -Path ${directory})) {
    New-Item -Force -ItemType "Directory" -Path ${STORE_PATH} | Out-Null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      Invoke-RestMethod -Method "Get" -Uri ${uri} -OutFile ${outfile}
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    switch (${package_type}) {
      "zip" {
        Expand-Archive -Force -Path ${outfile} -DestinationPath ${directory}
        break
      }
      "targz" {
        ${command} = "tar --extract --file ${outfile} --directory ${directory}"
        Invoke-Expression -Command ${command} | Out-Null
        break
      }
      "7z" {
        ${command} = "& '${7ZIP}' x -y -o${directory} ${outfile}"
        Invoke-Expression -Command ${command} | Out-Null
      }
      default {
        Write-Host "[ERROR] Unsupported file extension."
        exit
      }
    }
    Remove-Item -Force -Path ${outfile} | Out-Null
    if (-not (Test-Path -PathType "Container" -Path ${directory})) {
      Write-Host "[ERROR] Extraction failed."
      exit
    }
  }
  if (Test-Path -PathType "Container" -Path ${link}) {
    Remove-Item -Force -Path ${link}
  }
  New-Item -Force -ItemType "Junction" -Path ${link} -Target ${target} | Out-Null
  Invoke-Expression -Command ((Join-Path -Path ${link} -ChildPath ${Executable}) + " " + ${Arguments})
}

function ListSupported {
  param (
    ${Objects}
  )
  Write-Host ((${Objects} | Select-Object -ExpandProperty "install_folder_name") -join "`n")
}

switch (${args}[0]) {
  { $_ -in "si", "self-install" } {
    ${uri} = "https://raw.githubusercontent.com/pwsh-bin/get-tool/main/install.ps1"
    ${command} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      ${command} = Invoke-RestMethod -Method "Get" -Uri ${uri}
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    Invoke-Expression -Command ${command}
  }
  { $_ -in "i", "install" } {
    ${tool}, ${version} = (${args}[1] -csplit "@")
    switch (${tool}) {
      ${TOOLS}[0] {
        if ($null -eq ${version}) {
          ${version} = "openjdk"
        }
        ${objects} = (GetJDKS -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "java.exe") -Arguments "-version" -Objects ${objects}
      }
      ${TOOLS}[1] {
        ${objects} = (GetMaven -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "mvn.cmd") -Arguments "-version" -Objects ${objects}
      }
      ${TOOLS}[2] {
        ${objects} = (GetAnt -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "ant.bat") -Arguments "-version" -Objects ${objects}
      }
      ${TOOLS}[3] {
        ${objects} = (GetGradle -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "gradle.bat") -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[4] {
        ${objects} = (GetPython -Version ${version})
        Install -Tool ${tool} -Executable "python.exe" -Arguments "--version" -Objects ${objects}
        ${link} = (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[8])
        if (Test-Path -PathType "Container" -Path ${link}) {
          Remove-Item -Force -Path ${link}
          Write-Host ("[DEBUG] Resolved conflict with " + ${TOOLS}[8])
        }
      }
      ${TOOLS}[5] {
        ${objects} = (GetNode -Version ${version})
        Install -Tool ${tool} -Executable "node.exe" -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[6] {
        ${objects} = (GetRuby -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "ruby.exe") -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[7] {
        ${objects} = (GetGo -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "go.exe") -Arguments "version" -Objects ${objects}
      }
      ${TOOLS}[8] {
        ${objects} = (GetPypy -Version ${version})
        Install -Tool ${tool} -Executable "pypy.exe" -Arguments "--version" -Objects ${objects}
        ${link} = (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[4])
        if (Test-Path -PathType "Container" -Path ${link}) {
          Remove-Item -Force -Path ${link}
          Write-Host ("[DEBUG] Resolved conflict with " + ${TOOLS}[4])
        }
      }
      default {
        Write-Host "[ERROR] Unsupported or missing tool argument."
      }
    }
  }
  { $_ -in "ls", "list-supported" } {
    ${tool} = ${args}[1]
    switch (${tool}) {
      ${TOOLS}[0] {
        ${objects} = (GetJDKS)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[1] {
        ${objects} = (GetMaven)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[2] {
        ${objects} = (GetAnt)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[3] {
        ${objects} = (GetGradle)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[4] {
        ${objects} = (GetPython)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[5] {
        ${objects} = (GetNode)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[6] {
        ${objects} = (GetRuby)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[7] {
        ${objects} = (GetGo)
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[8] {
        ${objects} = (GetPyPy)
        ListSupported -Objects ${objects}
      }
      default {
        Write-Host (${TOOLS} -join "`n")
      }
    }
  }
  { $_ -in "li", "list-installed" } {
    Write-Host ((Get-ChildItem -Path ${STORE_PATH} -Filter ${Pattern} -Directory -Name) -join "`n")
  }
  { $_ -in "init" } {
    if (${env:PATH} -split ";" -cnotcontains ${PS1_HOME}) {
      ${env:PATH} += ";${PS1_HOME}"
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[0] -AdditionalChildPath "bin"))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[1] -AdditionalChildPath "bin"))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[2] -AdditionalChildPath "bin"))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[3] -AdditionalChildPath "bin"))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[4]))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[5]))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[6] -AdditionalChildPath "bin"))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[7] -AdditionalChildPath "bin"))
      ${env:PATH} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[8]))
    }
  }
  { $_ -in "setup" } {
    ${value} = "& '${PS1_FILE}' init"
    if (((Get-Content -Path ${PROFILE}) -split "`n") -cnotcontains ${value}) {
      Add-Content -Path ${PROFILE} -Value ${value}
      if (${DEBUG}) {
        Write-Host "[DEBUG] ${PROFILE}"
      }
    }
  }
  default {
    Write-Host "[ERROR] Unsupported command argument."
  }
}
