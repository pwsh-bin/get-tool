Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

${DEBUG} = (Test-Path -PathType "Container" -Path (Join-Path -Path ${PSScriptRoot} -ChildPath ".git"))
${PS1_HOME} = (Join-Path -Path ${HOME} -ChildPath ".get-tool")
${PS1_FILE} = (Join-Path -Path ${PS1_HOME} -ChildPath "get-tool.ps1")
${GITHUB_PATH} = (Join-Path -Path ${PS1_HOME} -ChildPath ".github")
${STORE_PATH} = (Join-Path -Path ${PS1_HOME} -ChildPath ".store")
${7ZIP} = (Join-Path -Path ${ENV:PROGRAMFILES} -ChildPath (Join-Path -Path "7-Zip" -ChildPath "7z.exe"))
${PER_PAGE} = 1000
${VERSION} = "v0.3.3"
${HELP} = @"
Usage:
get-tool self-install                 - update get-tool to latest version
get-tool install java@openjdk-1.8     - install java openjdk version 1.8
get-tool install maven@3.1            - install maven version 3.1
get-tool list-supported java          - list all supported java versions
get-tool list-supported               - list all supported tools
get-tool list-installed               - list all installed tools
get-tool init                         - add tools to current path
get-tool setup                        - add init to current profile

${VERSION}
"@
${TOOLS} = @(
  "java",
  "maven",
  "ant",
  "gradle",
  "python",
  "node",
  "ruby",
  "go",
  "pypy",
  "cmake",
  "binaryen",
  "wasmedge",
  "wasmer",
  "poppler"
)

# NOTE: common
if (${args}.Count -eq 0) {
  Write-Host ${HELP}
  if ((${Env:Path} -split ";") -cnotcontains ${PS1_HOME}) {
    Write-Host @"
---------------------------------------------------------
The script are not found in the current PATH, please run:
> ${PS1_HOME} init
---------------------------------------------------------
"@
  }
  if (${PSVersionTable}.PSVersion.Major -lt 7) {
    Write-Host @"
-----------------------------------------------------------------
The PowerShell Core is preferable to use this script, please run:
> winget install Microsoft.PowerShell
-----------------------------------------------------------------
"@
  }
  if ((Get-ExecutionPolicy -Scope "LocalMachine") -ne "RemoteSigned") {
    Write-Host @"
-------------------------------------------------------------------------------
The RemoteSigned execution policy is preferable to use this script, please run:
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
-------------------------------------------------------------------------------
"@
  }
  exit
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
    ${jdks} = (Invoke-RestMethod -Method "Get" -Uri ${uri})
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
    ${response} = (Invoke-WebRequest -Method "Get" -Uri ${uri} -Body @{
        "C" = "N"
        "O" = "D"
        "F" = "0"
        "P" = "${Version}*"
      })
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${hrefs} = (${response}.Links | Where-Object -Property "href" -ne $null | Select-Object -ExpandProperty "href" -Skip 1)
  ${binaries} = @()
  foreach (${href} in ${hrefs}) {
    ${_version} = ${href}.SubString(0, ${href}.Length - 1) # NOTE: drop '/'
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${_version}/binaries/${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = "apache-maven-${_version}"
      "archive_file_name"    = "apache-maven-${_version}-bin.zip"
      "install_folder_name"  = "maven-${_version}"
      "version"              = [version]${_version}
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
    ${response} = (Invoke-WebRequest -Method "Get" -Uri ${uri} -Body @{
        "C" = "N"
        "O" = "D"
        "F" = "0"
        "P" = "*-${Version}*-bin.zip"
      })
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
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${href}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${href}
      "install_folder_name"  = ${install_folder_name}
      "version"              = [version]${install_folder_name}.SubString(${install_folder_name}.IndexOf("-") + 1)
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetGradle {
  param (
    ${Version}
  )
  ${uri} = "https://services.gradle.org/versions/all"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = (Invoke-RestMethod -Method "Get" -Uri ${uri})
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${objects} = (${response} | Where-Object -FilterScript { ($_.snapshot -eq $false) -and ($_.nightly -eq $false) -and ($_.rcFor -eq "") -and ($_.milestoneFor -eq "") -and ($_.version -cnotlike "*-*") -and ($_.version -clike "${Version}*") })
  ${binaries} = @()
  foreach (${object} in ${objects}) {
    ${archive_file_name} = ${object}.downloadUrl.SubString(${object}.downloadUrl.LastIndexOf("/") + 1)
    ${install_folder_name} = ${archive_file_name}.SubString(0, ${archive_file_name}.LastIndexOf("-"))
    ${binaries} += [pscustomobject]@{
      "url"                  = ${object}.downloadUrl
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${install_folder_name}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = ${install_folder_name}
      "version"              = [version]${object}.version
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
    ${response} = (Invoke-WebRequest -Method "Get" -Uri ${uri})
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
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${href}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ""
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = "python-${_version}"
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
    ${response} = (Invoke-WebRequest -Method "Head" -Uri ${uri})
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
  ${uri} = "https://nodejs.org/dist/index.json"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = (Invoke-RestMethod -Method "Get" -Uri ${uri})
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${objects} = (${response} | Where-Object -FilterScript { ($_.files -ccontains "win-x64-zip") -and ($_.version -clike "v${Version}*") })
  ${binaries} = @()
  foreach (${object} in ${objects}) {
    ${_version} = ${object}.version.SubString(1) # NOTE: drop 'v'
    ${unpack_prefix_filter} = "node-v${_version}-win-x64"
    ${archive_file_name} = "${unpack_prefix_filter}.zip"
    ${binaries} += [pscustomobject]@{
      "url"                  = "https://nodejs.org/dist/v${_version}/${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = "node-${_version}"
      "version"              = [version]${_version}
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
    ${response} = (Invoke-WebRequest -Method "Get" -Uri ${uri})
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
    ${_version} = (${temp}.SubString(0, ${temp}.Length - 7) -creplace "-", ".")  # NOTE: drop '-x64.7z'
    ${binaries} += [pscustomobject]@{
      "url"                  = ${href}
      "package_type"         = "7z"
      "unpack_prefix_filter" = ${unpack_prefix_filter}
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = "ruby-${_version}"
      "version"              = [version]${_version}
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
    ${response} = (Invoke-WebRequest -Method "Get" -Uri ${uri})
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
    ${binaries} += [pscustomobject]@{
      "url"                  = "${uri}${archive_file_name}"
      "package_type"         = "zip"
      "unpack_prefix_filter" = "go"
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = "go-${_version}"
      "version"              = [version]${_version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetPyPy {
  param (
    ${Version}
  )
  ${uri} = "https://downloads.python.org/pypy/versions.json"
  ${response} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${response} = (Invoke-RestMethod -Method "Get" -Uri ${uri})
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  ${python_version}, ${pypy_version} = (${Version} -csplit "-")
  ${objects} = (${response} | Where-Object -FilterScript { ($_.stable -eq $true) -and ($_.python_version -clike "${python_version}*") -and ($_.pypy_version -clike "${pypy_version}*") })
  ${binaries} = @()
  foreach (${object} in ${objects}) {
    ${temp} = (${object}.files | Where-Object -FilterScript { ($_.arch -eq "x64") -and ($_.platform -eq "win64") })
    if ($null -eq ${temp}) {
      continue
    }
    ${_version_python} = ${object}.python_version
    ${_version_pypy} = ${object}.pypy_version
    ${archive_file_name} = ${temp}.filename
    ${binaries} += [pscustomobject]@{
      "url"                  = ${temp}.download_url
      "package_type"         = "zip"
      "unpack_prefix_filter" = ${archive_file_name}.SubString(0, ${archive_file_name}.Length - 4) # NOTE: drop '.zip'
      "archive_file_name"    = ${archive_file_name}
      "install_folder_name"  = "pypy-${_version_python}-${_version_pypy}"
      "version_python"       = [version]${_version_python}
      "version_pypy"         = [version]${_version_pypy}
    }
  }
  return (${binaries} | Sort-Object -Property ("version_python", "version_pypy"))
}

# NOTE: common
function GetGitHubToken {
  if (Test-Path -PathType "Leaf" -Path ${GITHUB_PATH}) {
    return (Import-Clixml -Path ${GITHUB_PATH})
  }
  Write-Host @"
Generate GitHub API Token w/o expiration and public_repo scope: https://github.com/settings/tokens/new
Enter GitHub API Token:
"@
  ${token} = (Read-Host -AsSecureString)
  Export-Clixml -InputObject ${token} -Path ${GITHUB_PATH}
  return ${token}
}

# NOTE: common
function GetGitHubTagNamesFromReleases {
  param (
    ${RepositoryUri},
    ${Token},
    ${Pattern},
    ${Prerelease}
  )
  ${page} = 0
  ${uri} = "${RepositoryUri}/releases"
  while ($true) {
    ${page} += 1
    ${releases} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      # NOTE: compat
      ${headers} = @{
        "Authentication" = ("Bearer " + ${Token})
      }
      ${releases} = (Invoke-RestMethod -Method "Get" -Uri ${uri} -Headers ${headers} -Body @{
          "per_page" = ${PER_PAGE}
          "page"     = ${page}
        })
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    if (${releases}.Length -eq 0) {
      return $null
    }
    ${result} = (${releases} | Where-Object -FilterScript { ($_.prerelease -eq ${Prerelease}) -and ($_.tag_name -cmatch ${Pattern}) } | Select-Object -ExpandProperty "tag_name")
    if (${result}.Length -ne 0) {
      return ${result}
    }
  }
}

# NOTE: common
function GetGitHubTagNamesFromTags {
  param (
    ${RepositoryUri},
    ${Token},
    ${Pattern}
  )
  ${uri} = "${RepositoryUri}/tags"
  ${page} = 0
  while ($true) {
    ${page} += 1
    ${tags} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      # NOTE: compat
      ${headers} = @{
        "Authentication" = ("Bearer " + ${Token})
      }
      ${tags} = (Invoke-RestMethod -Method "Get" -Uri ${uri} -Headers ${headers} -Body @{
          "per_page" = ${PER_PAGE}
          "page"     = ${page}
        })
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    if (${tags}.Length -eq 0) {
      return $null
    }
    ${result} = (${tags} | Where-Object -Property "name" -cmatch ${Pattern} | Select-Object -ExpandProperty "name")
    if (${result}.Length -ne 0) {
      return ${result}
    }
  }
}

# NOTE: common
function GetGitHubTagNames {
  param (
    ${Repository},
    ${VersionPrefix},
    ${Version}
  )
  ${repository_uri} = "https://api.github.com/repos/${Repository}"
  ${token} = (GetGitHubToken)
  ${tag_names} = $null
  if ($null -eq ${Version}) {
    ${tag_names} = (GetGitHubTagNamesFromReleases -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}.*$" -Prerelease $false)
    if ($null -eq ${tag_names}) {
      ${tag_names} = (GetGitHubTagNamesFromReleases -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}.*$" -Prerelease $true)
      if ($null -eq ${tag_names}) {
        ${tag_names} = (GetGitHubTagNamesFromTags -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}[-TZ\.\d]*$")
      }
    }
  }
  else {
    ${tag_names} = (GetGitHubTagNamesFromTags -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}${Version}[-TZ\.\d]*$")
  }
  return ${tag_names}
}

function GetFromGitHub {
  param (
    ${Tool},
    ${Repository},
    ${VersionPrefix},
    ${UnpackPrefix},
    ${Uri},
    ${PackageType},
    ${Version}
  )
  ${tag_names} = (GetGitHubTagNames -Repository ${Repository} -VersionPrefix ${VersionPrefix} -Version ${Version})
  ${binaries} = @()
  foreach (${tag_name} in ${tag_names}) {
    ${_version} = (${tag_name} -creplace ${VersionPrefix}, "")
    ${version} = $null
    if (${_version}.Contains(".")) {
      if (${_version}.Contains("-")) {
        ${version} = [version](${_version} -creplace "-", ".")
      }
      else {
        ${version} = [version]${_version}
      }
    }
    else {
      ${version} = [convert]::ToInt32(${_version}, 10)
    }
    ${url} = (${Uri} -creplace "%version%", ${_version})
    ${binaries} += [pscustomobject]@{
      "url"                  = ${url}
      "package_type"         = ${PackageType}
      "unpack_prefix_filter" = (${UnpackPrefix} -creplace "%version%", ${_version})
      "archive_file_name"    = ${url}.SubString(${url}.LastIndexOf("/") + 1)
      "install_folder_name"  = "${Tool}-${_version}"
      "version"              = ${version}
    }
  }
  return (${binaries} | Sort-Object -Property "version")
}

function GetCMake {
  param (
    ${Version}
  )
  return (GetFromGitHub -Tool ${TOOLS}[9] -Repository "Kitware/CMake" -VersionPrefix "v" -UnpackPrefix "cmake-%version%-windows-x86_64" -Uri "https://github.com/Kitware/CMake/releases/download/v%version%/cmake-%version%-windows-x86_64.zip" -PackageType "zip" -Version ${Version})
}

function GetBinaryen {
  param (
    ${Version}
  )
  return (GetFromGitHub -Tool ${TOOLS}[10] -Repository "WebAssembly/binaryen" -VersionPrefix "version_" -UnpackPrefix "binaryen-version_%version%" -Uri "https://github.com/WebAssembly/binaryen/releases/download/version_%version%/binaryen-version_%version%-x86_64-windows.tar.gz" -PackageType "targz" -Version ${Version})
}

function GetWasmEdge {
  param (
    ${Version}
  )
  return (GetFromGitHub -Tool ${TOOLS}[11] -Repository "WasmEdge/WasmEdge" -VersionPrefix "" -UnpackPrefix "WasmEdge-%version%-Windows" -Uri "https://github.com/WasmEdge/WasmEdge/releases/download/%version%/WasmEdge-%version%-windows.zip" -PackageType "zip" -Version ${Version})
}

function GetWasmer {
  param (
    ${Version}
  )
  return (GetFromGitHub -Tool ${TOOLS}[12] -Repository "wasmerio/wasmer" -VersionPrefix "" -UnpackPrefix "" -Uri "https://github.com/wasmerio/wasmer/releases/download/%version%/wasmer-windows-amd64.tar.gz" -PackageType "targz" -Version ${Version})
}

function GetPoppler {
  param (
    ${Version}
  )
  return (GetFromGitHub -Tool ${TOOLS}[13] -Repository "oschwartz10612/poppler-windows" -VersionPrefix "v" -UnpackPrefix "poppler-*" -Uri "https://github.com/oschwartz10612/poppler-windows/releases/download/v%version%/Release-%version%.zip" -PackageType "zip" -Version ${Version})
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
    New-Item -Force -ItemType "Directory" -Path ${directory} | Out-Null
    switch (${package_type}) {
      "zip" {
        Expand-Archive -Force -Path ${outfile} -DestinationPath ${directory}
        break
      }
      "targz" {
        ${command} = "tar -x -f ${outfile} -C ${directory}"
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
      Remove-Item -Force -Path ${directory} | Out-Null
      Write-Host "[ERROR] Extraction failed."
      exit
    }
  }
  ${link} = (Join-Path -Path ${PS1_HOME} -ChildPath ${Tool})
  if (Test-Path -PathType "Container" -Path ${link}) {
    Remove-Item -Force -Path ${link}
  }
  ${target} = $null
  if (${unpack_prefix_filter}.Length -eq 0) {
    ${target} = ${directory}
  }
  else {
    ${child_paths} = (Get-ChildItem -Path ${directory} -Filter ${unpack_prefix_filter} -Directory -Name)
    ${child_path} = $null
    if (${child_paths} -is [string]) {
      ${child_path} = ${child_paths}
    }
    else {
      ${child_path} = ${child_paths}[0]
    }
    ${target} = (Join-Path -Path ${directory} -ChildPath ${child_path})
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
      ${command} = (Invoke-RestMethod -Method "Get" -Uri ${uri})
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
      ${TOOLS}[9] {
        ${objects} = (GetCMake -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "cmake.exe") -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[10] {
        ${objects} = (GetBinaryen -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "wasm2js.exe") -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[11] {
        ${objects} = (GetWasmEdge -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "wasmedge.exe") -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[12] {
        ${objects} = (GetWasmer -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path "bin" -ChildPath "wasmer.exe") -Arguments "--version" -Objects ${objects}
      }
      ${TOOLS}[13] {
        ${objects} = (GetPoppler -Version ${version})
        Install -Tool ${tool} -Executable (Join-Path -Path (Join-Path -Path "Library" -ChildPath "bin") -ChildPath "pdfinfo.exe") -Arguments "-v" -Objects ${objects}
      }
      default {
        Write-Host "[ERROR] Unsupported or missing tool argument."
      }
    }
  }
  { $_ -in "ls", "list-supported" } {
    ${tool}, ${version} = (${args}[1] -csplit "@")
    switch (${tool}) {
      ${TOOLS}[0] {
        ${objects} = (GetJDKS -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[1] {
        ${objects} = (GetMaven -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[2] {
        ${objects} = (GetAnt -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[3] {
        ${objects} = (GetGradle -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[4] {
        ${objects} = (GetPython -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[5] {
        ${objects} = (GetNode -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[6] {
        ${objects} = (GetRuby -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[7] {
        ${objects} = (GetGo -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[8] {
        ${objects} = (GetPyPy -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[9] {
        ${objects} = (GetCMake -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[10] {
        ${objects} = (GetBinaryen -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[11] {
        ${objects} = (GetWasmEdge -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[12] {
        ${objects} = (GetWasmer -Version ${version})
        ListSupported -Objects ${objects}
      }
      ${TOOLS}[13] {
        ${objects} = (GetPoppler -Version ${version})
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
    if ((${Env:Path} -split ";") -cnotcontains ${PS1_HOME}) {
      ${Env:Path} += ";${PS1_HOME}"
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[0] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[1] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[2] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[3] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[4]))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[5]))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[6] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[7] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath ${TOOLS}[8]))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[9] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[10] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[11] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[12] -ChildPath "bin")))
      ${Env:Path} += (";" + (Join-Path -Path ${PS1_HOME} -ChildPath (Join-Path -Path ${TOOLS}[13] -ChildPath (Join-Path -Path "Library" -ChildPath "bin"))))
    }
  }
  # NOTE: common
  { $_ -in "setup" } {
    New-Item -Force -ItemType "File" -Path ${PROFILE} | Out-Null
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
