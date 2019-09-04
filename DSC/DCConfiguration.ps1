configuration Configuration
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
    $LogPath = "c:\$LogFolder"
    $CM = "CMCB"
    $DName = $DomainName.Split(".")[0]
    $PSComputerAccount = "$DName\$PSName$"
    $DPMP1ComputerAccount = "$DName\$DPMP1Name$"
    $DPMP2ComputerAccount = "$DName\$DPMP2Name$"
    $Client1ComputerAccount = "$DName\$Client1Name$"
    $Client2ComputerAccount = "$DName\$Client2Name$"

    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node LOCALHOST
    {
        LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        SetCustomPagingFile PagingSettings
        {
            Drive       = 'C:'
            InitialSize = '8192'
            MaximumSize = '8192'
        }
        
        InstallFeatureForSCCM InstallFeature
        {
            Name = 'DC'
            Role = 'DC'
            DependsOn = "[SetCustomPagingFile]PagingSettings"
        }

        SetupDomain FirstDS
        {
            DomainFullName = $DomainName
            SafemodeAdministratorPassword = $DomainCreds
            DependsOn = "[InstallFeatureForSCCM]InstallFeature"
        }

        InstallCA InstallCA
        {
            HashAlgorithm = "SHA256"
            DependsOn = "[SetupDomain]FirstDS"
        }

        VerifyComputerJoinDomain WaitForPS
        {
            ComputerName = $PSName
            Ensure = "Present"
            DependsOn = "[InstallCA]InstallCA"
        }

        VerifyComputerJoinDomain WaitForDPMP
        {
            ComputerName = $DPMP1Name
            Ensure = "Present"
            DependsOn = "[InstallCA]InstallCA"
        }

        VerifyComputerJoinDomain WaitForDPMP
        {
            ComputerName = $DPMP2Name
            Ensure = "Present"
            DependsOn = "[InstallCA]InstallCA"
        }

        VerifyComputerJoinDomain WaitForClient
        {
            ComputerName = $Client1Name
            Ensure = "Present"
            DependsOn = "[InstallCA]InstallCA"
        }

        VerifyComputerJoinDomain WaitForClient
        {
            ComputerName = $Client2Name
            Ensure = "Present"
            DependsOn = "[InstallCA]InstallCA"
        }

        File ShareFolder
        {            
            DestinationPath = $LogPath     
            Type = 'Directory'            
            Ensure = 'Present'
            DependsOn = @("[VerifyComputerJoinDomain]WaitForPS","[VerifyComputerJoinDomain]WaitForDPMP","[VerifyComputerJoinDomain]WaitForClient")
        }

        FileReadAccessShare DomainSMBShare
        {
            Name   = $LogFolder
            Path =  $LogPath
            Account = $PSComputerAccount,$DPMPComputerAccount,$ClientComputerAccount
            DependsOn = "[File]ShareFolder"
        }

        WriteConfigurationFile WritePSJoinDomain
        {
            Role = "DC"
            LogPath = $LogPath
            WriteNode = "PSJoinDomain"
            Status = "Passed"
            Ensure = "Present"
            DependsOn = "[FileReadAccessShare]DomainSMBShare"
        }

        WriteConfigurationFile WriteDPMPJoinDomain
        {
            Role = "DC"
            LogPath = $LogPath
            WriteNode = "DPMPJoinDomain"
            Status = "Passed"
            Ensure = "Present"
            DependsOn = "[FileReadAccessShare]DomainSMBShare"
        }

        WriteConfigurationFile WriteClientJoinDomain
        {
            Role = "DC"
            LogPath = $LogPath
            WriteNode = "ClientJoinDomain"
            Status = "Passed"
            Ensure = "Present"
            DependsOn = "[FileReadAccessShare]DomainSMBShare"
        }

        DelegateControl AddPS
        {
            Machine = $PSName
            DomainFullName = $DomainName
            Ensure = "Present"
            DependsOn = "[WriteConfigurationFile]WritePSJoinDomain"
        }

        DelegateControl AddDPMP1
        {
            Machine = $DPMP1Name
            DomainFullName = $DomainName
            Ensure = "Present"
            DependsOn = "[WriteConfigurationFile]WriteDPMPJoinDomain"
        }

        DelegateControl AddDPMP2
        {
            Machine = $DPMP2Name
            DomainFullName = $DomainName
            Ensure = "Present"
            DependsOn = "[WriteConfigurationFile]WriteDPMPJoinDomain"
        }

        WriteConfigurationFile WriteDelegateControlfinished
        {
            Role = "DC"
            LogPath = $LogPath
            WriteNode = "DelegateControl"
            Status = "Passed"
            Ensure = "Present"
            DependsOn = @("[DelegateControl]AddPS","[DelegateControl]AddDPMP")
        }

        WaitForExtendSchemaFile WaitForExtendSchemaFile
        {
            MachineName = $PSName
            ExtFolder = $CM
            Ensure = "Present"
            DependsOn = "[WriteConfigurationFile]WriteDelegateControlfinished"
        }
    }
}