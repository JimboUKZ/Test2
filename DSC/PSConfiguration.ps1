﻿configuration Configuration
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,
        [Parameter(Mandatory)]
        [String]$DCName,
        [Parameter(Mandatory)]
        [String]$DPMP1Name,
        [Parameter(Mandatory)]
        [String]$DPMP2Name,
        [Parameter(Mandatory)]
        [String]$Client1Name,
        [Parameter(Mandatory)]
        [String]$Client2Name,
        [Parameter(Mandatory)]
        [String]$PSName,
        [Parameter(Mandatory)]
        [String]$DNSIPAddress,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds
    )

    Import-DscResource -ModuleName TemplateHelpDSC
    
    $LogFolder = "TempLog"
    $CM = "CMCB"
    $LogPath = "c:\$LogFolder"
    $DName = $DomainName.Split(".")[0]
    $DCComputerAccount = "$DName\$DCName$"
    $DPMP1ComputerAccount = "$DName\$DPMP1Name$"
    $DPMP2ComputerAccount = "$DName\$DPMP2Name$"
    
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node LOCALHOST
    {
        LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        AddBuiltinPermission AddSQLPermission
        {
            Ensure = "Present"
        }

        InstallFeatureForSCCM InstallFeature
        {
            NAME = "PS"
            Role = "Site Server"
            DependsOn = "[AddBuiltinPermission]AddSQLPermission"
        }

        InstallADK ADKInstall
        {
            ADKPath = "C:\adksetup.exe"
            ADKWinPEPath = "c:\adksetupwinpe.exe"
            Ensure = "Present"
            DependsOn = "[InstallFeatureForSCCM]InstallFeature"
        }

        DownloadSCCM DownLoadSCCM
        {
            CM = $CM
            ExtPath = $LogPath
            Ensure = "Present"
            DependsOn = "[InstallADK]ADKInstall"
        }

        SetDNS DnsServerAddress
        {
            DNSIPAddress = $DNSIPAddress
            Ensure = "Present"
            DependsOn = "[DownloadSCCM]DownLoadSCCM"
        }

        WaitForDomainReady WaitForDomain
        {
            Ensure = "Present"
            DCName = $DCName
            WaitSeconds = 0
            DependsOn = "[SetDNS]DnsServerAddress"
        }

        JoinDomain JoinDomain
        {
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn = "[WaitForDomainReady]WaitForDomain"
        }
        
        File ShareFolder
        {            
            DestinationPath = $LogPath     
            Type = 'Directory'            
            Ensure = 'Present'
            DependsOn = "[JoinDomain]JoinDomain"
        }

        FileReadAccessShare DomainSMBShare
        {
            Name   = $LogFolder
            Path =  $LogPath
            Account = $DCComputerAccount
            DependsOn = "[File]ShareFolder"
        }
        
        OpenFirewallPortForSCCM OpenFirewall
        {
            Name = "PS"
            Role = "Site Server"
            DependsOn = "[JoinDomain]JoinDomain"
        }

        WaitForConfigurationFile DelegateControl
        {
            Role = "DC"
            MachineName = $DCName
            LogFolder = $LogFolder
            ReadNode = "DelegateControl"
            Ensure = "Present"
            DependsOn = "[OpenFirewallPortForSCCM]OpenFirewall"
        }

        ChangeSQLServicesAccount ChangeToLocalSystem
        {
            SQLInstanceName = "MSSQLSERVER"
            Ensure = "Present"
            DependsOn = "[WaitForConfigurationFile]DelegateControl"
        }

        FileReadAccessShare CMSourceSMBShare
        {
            Name   = $CM
            Path =  "c:\$CM"
            Account = $DCComputerAccount
            DependsOn = "[ChangeSQLServicesAccount]ChangeToLocalSystem"
        }

        RegisterTaskScheduler InstallAndUpdateSCCM1
        {
            TaskName = "ScriptWorkFlow"
            ScriptName = "ScriptWorkFlow.ps1"
            ScriptPath = $PSScriptRoot
            ScriptArgument = "$DomainName $CM $DName\$($Admincreds.UserName) $DPMP1Name $ClientName"
            Ensure = "Present"
            DependsOn = "[FileReadAccessShare]CMSourceSMBShare"
        }

        RegisterTaskScheduler InstallAndUpdateSCCM2
        {
            TaskName = "ScriptWorkFlow"
            ScriptName = "ScriptWorkFlow.ps1"
            ScriptPath = $PSScriptRoot
            ScriptArgument = "$DomainName $CM $DName\$($Admincreds.UserName) $DPMP2Name $ClientName"
            Ensure = "Present"
            DependsOn = "[FileReadAccessShare]CMSourceSMBShare"
        }
    }
}