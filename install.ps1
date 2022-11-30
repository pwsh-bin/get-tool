Set-Variable -Name 'ProgressPreference' -Value 'SilentlyContinue'
${PS1_HOME} = Join-Path -Path ${HOME} -ChildPath '.get-tool'
${PS1_FILE} = Join-Path -Path ${PS1_HOME} -ChildPath 'get-tool.ps1'
New-Item -Force -ItemType 'Directory' -Path ${PS1_HOME} | Out-Null
Invoke-RestMethod -Method 'Get' -Uri 'https://raw.githubusercontent.com/pwsh-bin/get-tool/main/get-tool.ps1' -OutFile ${PS1_FILE}
Invoke-Expression -Command ${PS1_FILE}
