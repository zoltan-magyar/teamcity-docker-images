# The list of required arguments
# ARG jreWindowsComponent
# ARG jdkWindowsComponent
# ARG nanoserverImage
# ARG powershellImage

# Id teamcity-minimal-agent
# Tag ${tag}
# Platform ${windowsPlatform}
# Repo ${repo}
# Weight 1

## ${agentCommentHeader}

# Based on ${powershellImage} 1
# Install ${powerShellComponentName}
FROM ${powershellImage} AS base

SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install [${jreWindowsComponentName}](${jreWindowsComponent})
ARG jreWindowsComponent

RUN [Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls' ; \
    Invoke-WebRequest $Env:jreWindowsComponent -OutFile jre.zip; \
    Expand-Archive jre.zip -DestinationPath $Env:ProgramFiles\Java ; \
    Get-ChildItem $Env:ProgramFiles\Java | Rename-Item -NewName "OpenJDK" ; \
    Remove-Item -Force jre.zip

# Install [${jdkWindowsComponentName}](${jdkWindowsComponent})
ARG jdkWindowsComponent

RUN [Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls' ; \
    Invoke-WebRequest $Env:jdkWindowsComponent -OutFile jdk.zip; \
    Expand-Archive jdk.zip -DestinationPath $Env:Temp\JDK ; \
    Get-ChildItem $Env:Temp\JDK | Rename-Item -NewName "OpenJDK" ; \
    ('jar.exe', 'jcmd.exe', 'jconsole.exe', 'jmap.exe', 'jstack.exe', 'jps.exe') | foreach { \
         Copy-Item $Env:Temp\JDK\OpenJDK\bin\$_ $Env:ProgramFiles\Java\OpenJDK\bin\ \
    } ; \
    Remove-Item -Force -Recurse $Env:Temp\JDK ; \
    Remove-Item -Force jdk.zip

# Prepare build agent distribution
COPY TeamCity/buildAgent C:/BuildAgent
COPY run-agent.ps1 /BuildAgent/run-agent.ps1

ARG nanoserverImage

# Based on ${nanoserverImage} 1
FROM ${nanoserverImage}

COPY --from=base ["C:/Program Files/Java/OpenJDK", "C:/Program Files/Java/OpenJDK"]

ENV JRE_HOME="C:\Program Files\Java\OpenJDK" \
    CONFIG_FILE="C:\BuildAgent\conf\buildAgent.properties"

COPY --from=base /BuildAgent /BuildAgent

VOLUME C:/BuildAgent/conf
VOLUME C:/BuildAgent/plugins
VOLUME C:/BuildAgent/work
VOLUME C:/BuildAgent/temp
VOLUME C:/BuildAgent/tools
VOLUME C:/BuildAgent/logs

ENV LOCALAPPDATA="C:\Users\ContainerUser\AppData\Local" \
    # set a fixed location for the Module analysis cache
    PSModuleAnalysisCachePath="C:\Users\ContainerUser\AppData\Local\Microsoft\Windows\PowerShell\docker\ModuleAnalysisCache"

# intialize powershell module cache
RUN pwsh -NoLogo -NoProfile -Command " \
    $stopTime = (get-date).AddMinutes(15); \
    $ErrorActionPreference = 'Stop' ; \
    $ProgressPreference = 'SilentlyContinue' ; \
    while(!(Test-Path -Path $env:PSModuleAnalysisCachePath)) {  \
        Write-Host "'Waiting for $env:PSModuleAnalysisCachePath'" ; \
        if((get-date) -gt $stopTime) { throw 'timout expired'} \
        Start-Sleep -Seconds 6 ; \
    }"

CMD pwsh ./BuildAgent/run-agent.ps1