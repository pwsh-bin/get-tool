if (-not ${env:JAVA_GET_HOME}) {
  ${env:JAVA_GET_HOME} = "${HOME}\.java-get"
  [System.Environment]::SetEnvironmentVariable("JAVA_GET_HOME", ${env:JAVA_GET_HOME}, [System.EnvironmentVariableTarget]::User)
}

if (${env:PATH} -cnotlike "*${env:JAVA_GET_HOME}*") {
  ${env:PATH} = "${env:JAVA_GET_HOME};${env:PATH}"
  [System.Environment]::SetEnvironmentVariable("PATH", ${env:PATH}, [System.EnvironmentVariableTarget]::User)
}

if (-not (Test-Path -Path ${env:JAVA_GET_HOME} -PathType "Container")) {
  ${NO_OUTPUT} = (New-Item -Path ${env:JAVA_GET_HOME} -ItemType "Directory")
}

Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"
Invoke-RestMethod -OutFile "${env:JAVA_GET_HOME}/java-get.ps1" -Uri "https://raw.githubusercontent.com/pwsh-bin/java-get/main/java-get.ps1" -Method "Get"
Invoke-Expression -Command "java-get.ps1"
