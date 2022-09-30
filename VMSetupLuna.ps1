<#
 .DESCRIPTION
    Setup and configure Luna Client
 .NOTES
    AUTHOR Jonas Henriksson
 .LINK
    https://github.com/J0N7E
#>

[cmdletbinding(SupportsShouldProcess=$true)]

Param
(
    # VM name
    [String]$VMName,
    # Computer name
    [String]$ComputerName,
    # Force
    [Switch]$Force,

    # Serializable parameters
    $Session,
    $Credential,

    [String]$LunaClientPath = '.\LunaHSMClient.exe',

    [Parameter(ParameterSetName='LunaSh', Mandatory=$true)]
    <#----#>$LunaSh, #Serializable

    [Parameter(ParameterSetName='Plink', Mandatory=$true)]
    [String]$Fingerprint,

    [Parameter(ParameterSetName='Pscp')]
    [Switch]$PscpCertificateFromHsm,

    [Parameter(ParameterSetName='Pscp')]
    [Switch]$PscpCertificateToHsm,

    [Parameter(ParameterSetName='LunaSh', Mandatory=$true)]
    [Parameter(ParameterSetName='Plink', Mandatory=$true)]
    [Parameter(ParameterSetName='Pscp', Mandatory=$true)]
    [String]$HsmHostname,

    [Parameter(ParameterSetName='LunaSh', Mandatory=$true)]
    [Parameter(ParameterSetName='Plink', Mandatory=$true)]
    [Parameter(ParameterSetName='Pscp', Mandatory=$true)]
    <#----#>$HsmCredential, #Serializable

    [Parameter(ParameterSetName='LunaSh')]
    [String]$Timeout = '500',

    [Parameter(ParameterSetName='KspCmd', Mandatory=$true)]
    [String]$KspCmd,

    [Parameter(ParameterSetName='KspUtil', Mandatory=$true)]
    [String]$KspUtil,

    [Parameter(ParameterSetName='Vtl', Mandatory=$true)]
    [String]$Vtl,

    [Parameter(ParameterSetName='LunaCm', Mandatory=$true)]
    <#----#>$LunaCm, #Serializable

    [Parameter(ParameterSetName='Cmu', Mandatory=$true)]
    [String]$Cmu,

    [Parameter(ParameterSetName='PedServer', Mandatory=$true)]
    [ValidateSet('Start', 'Show', 'Stop')]
    [String]$PedServer
)

Begin
{
    # ██████╗ ███████╗ ██████╗ ██╗███╗   ██╗
    # ██╔══██╗██╔════╝██╔════╝ ██║████╗  ██║
    # ██████╔╝█████╗  ██║  ███╗██║██╔██╗ ██║
    # ██╔══██╗██╔══╝  ██║   ██║██║██║╚██╗██║
    # ██████╔╝███████╗╚██████╔╝██║██║ ╚████║
    # ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝

    ##############
    # Deserialize
    ##############

    $Serializable =
    @(
        @{ Name = 'Session';                                         },
        @{ Name = 'Credential';                Type = [PSCredential] },
        @{ Name = 'LunaSh';                    Type = [Array] },
        @{ Name = 'HsmCredential';             Type = [PSCredential] },
        @{ Name = 'LunaCm';                    Type = [Array] }
    )

    #########
    # Invoke
    #########

    Invoke-Command -ScriptBlock `
    {
        try
        {
            . $PSScriptRoot\s_Begin.ps1
            . $PSScriptRoot\f_ShouldProcess.ps1
            . $PSScriptRoot\f_CheckContinue.ps1
        }
        catch [Exception]
        {
            throw "$_ $( $_.ScriptStackTrace)"
        }

    } -NoNewScope

    #######################
    # Get ParameterSetName
    #######################

    $ParameterSetName = $PsCmdlet.ParameterSetName

    #######################
    # Get Luna Client file
    #######################

    if (Test-Path -Path "$PSScriptRoot$LunaClientPath")
    {
        $LunaFile = Get-Item -Path "$PSScriptRoot$LunaClientPath"

        $SessionSplat = @{}
        $ToSessionSplat = @{}

        if ($Session -and $Session.State -eq 'Opened')
        {
            $SessionSplat += @{ Session = $Session }
            $ToSessionSplat += @{ ToSession = $Session }

            $TestLunaFileBlock =
            {
               Get-Item -Path "$Using:TempDir\$($Using:LunaFile.Name)" -ErrorAction SilentlyContinue
            }
        }
        else
        {
            $TestLunaFileBlock =
            {
               Get-Item -Path "$TempDir\$($LunaFile.Name)" -ErrorAction SilentlyContinue
            }
        }

        if (-not (Invoke-Command @SessionSplat -ScriptBlock $TestLunaFileBlock))
        {
            Copy-Item @ToSessionSplat -Path $LunaFile.FullName -Destination $TempDir
        }
    }
    else
    {
        throw "Can't find $LunaClientPath."
    }

    # ███╗   ███╗ █████╗ ██╗███╗   ██╗
    # ████╗ ████║██╔══██╗██║████╗  ██║
    # ██╔████╔██║███████║██║██╔██╗ ██║
    # ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
    # ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
    # ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

    $MainScriptBlock =
    {
        # Initialize
        $Result = @{}

        ##############
        # Check admin
        ##############

        if ( -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        {
            throw "Must be administrator to setup Luna Client."
        }

        ############
        # Functions
        ############

        function SafeNet
        {
            param
            (
                [Parameter(ParameterSetName='LunaSh', Mandatory=$true)]
                [Switch]$LunaSh,

                [Parameter(ParameterSetName='Plink', Mandatory=$true)]
                [Switch]$Plink,

                [Parameter(ParameterSetName='Pscp', Mandatory=$true)]
                [Switch]$Pscp,

                [Parameter(ParameterSetName='LunaSh', Mandatory=$true)]
                [Parameter(ParameterSetName='Plink', Mandatory=$true)]
                [Parameter(ParameterSetName='Pscp', Mandatory=$true)]
                [String]$HsmHostname,

                [Parameter(ParameterSetName='LunaSh', Mandatory=$true)]
                [Parameter(ParameterSetName='Plink', Mandatory=$true)]
                [Parameter(ParameterSetName='Pscp', Mandatory=$true)]
                [PSCredential]$HsmCredential,

                [Parameter(ParameterSetName='LunaSh')]
                [String]$TimeOut = 500,

                [Parameter(ParameterSetName='KspCmd', Mandatory=$true)]
                [Switch]$KspCmd,

                [Parameter(ParameterSetName='KspUtil', Mandatory=$true)]
                [Switch]$KspUtil,

                [Parameter(ParameterSetName='Vtl', Mandatory=$true)]
                [Switch]$Vtl,

                [Parameter(ParameterSetName='LunaCm', Mandatory=$true)]
                [Switch]$LunaCm,

                [Parameter(ParameterSetName='Cmu', Mandatory=$true)]
                [Switch]$Cmu,

                [Parameter(ParameterSetName='PedServer', Mandatory=$true)]
                [Switch]$PedServer,

                [Array]$Command
            )

            begin
            {
                ##################
                # Configure paths
                ##################

                $LunaPath = 'C:\Program Files\SafeNet\LunaClient'
                $KspPath  = 'C:\Program Files\SafeNet\LunaClient\ksp'

                #######################
                # Get ParameterSetName
                #######################

                $ParameterSetName = $PsCmdlet.ParameterSetName

                ###############
                # Check params
                ###############

                if ($LunaSh.IsPresent)
                {
                    if(-not(Get-InstalledModule | Where-Object { $_.Name -match 'Posh-SSH' }))
                    {
                        throw "Please install Posh-SSH module from PSGallery to use SSH."
                    }
                }

                ###################
                # Set command file
                ###################

                if($LunaSh.IsPresent -or $LunaCm.IsPresent)
                {
                    Out-File -FilePath "$env:TEMP\safenet_cmd.txt" -InputObject $Command -Encoding Ascii
                }
                else
                {
                    Out-File -FilePath "$env:TEMP\safenet_cmd.txt" -InputObject ($Command -join ' ') -Encoding Ascii
                }

                # Remember working directory
                Push-Location
            }

            Process
            {
                #######
                # Main
                #######

                # Get commands
                $Commands = Get-Content -Path "$env:TEMP\safenet_cmd.txt" -Encoding Ascii

                if($ParameterSetName -eq 'LunaSh')
                {
                    ##########
                    # Session
                    ##########

                    $Session = Get-SSHSession | Where-Object { $_.Connected -eq $true -and $_.Host -eq $HsmHostname }

                    if(-not $Session)
                    {
                        $Session = New-SSHSession -ComputerName $HsmHostname -Credential $HsmCredential -AcceptKey -ConnectionTimeout $TimeOut
                    }

                    $Stream = New-SSHShellStream -SSHSession $Session

                    Start-Sleep -Milliseconds $TimeOut

                    # Discard banner
                    $Stream.Read() > $null

                    #########
                    # Invoke
                    #########

                    foreach($Cmd in $Commands)
                    {
                        $Stream.WriteLine($Cmd)

                        Start-Sleep -Milliseconds $TimeOut

                        $Stream.ReadLine() > $null # Discard writeline output

                        do
                        {
                            $StreamOutput = $Stream.Read()

                            if ($StreamOutput -notmatch '^\s*$')
                            {
                                Write-Host -Object $StreamOutput
                            }

                            if($StreamOutput -match '''Proceed''')
                            {
                                if ((Read-Host -Prompt 'Continue? [y/n]') -ne 'y')
                                {
                                    $Stream.WriteLine('quit')
                                }
                                else
                                {
                                    $Stream.WriteLine('proceed')
                                }

                                Start-Sleep -Milliseconds $TimeOut

                                $Stream.ReadLine() > $null # Discard writeline output
                            }
                        }
                        while ($StreamOutput -notmatch 'LunaSh:>')
                    }

                    ########
                    # Close
                    ########

                    $Stream.Close()
                }
                else
                {
                    switch($ParameterSetName)
                    {
                        { $_ -in @('KspCmd', 'KspUtil') }
                        {
                            $ProgPath = $KspPath
                        }

                        Default
                        {
                            $ProgPath = $LunaPath
                        }
                    }

                    # LunaCm command exception
                    if ($ParameterSetName -eq 'LunaCm')
                    {
                        $Commands = "-f $env:TEMP\safenet_cmd.txt"
                    }

                    # Cmu list command exception
                    if ($ParameterSetName -eq 'Cmu' -and $Commands.StartsWith('list'))
                    {
                        $Commands = "list '-display=handle,label,keyType,class,id'$($Commands -replace 'list', '')"
                    }

                    # Change working directory
                    Set-Location -Path $ProgPath

                    try
                    {
                        # Invoke
                        $Output = Invoke-Expression -Command ".\$ParameterSetName.exe $Commands"

                        # Output
                        foreach($Row in $Output)
                        {
                            Write-Host -Object $Row
                        }
                    }
                    catch [Exception]
                    {
                        Remove-Item -Path "$env:TEMP\safenet_cmd.txt" -Force -ErrorAction SilentlyContinue
                        Pop-Location

                        throw $_
                    }
                }
            }

            End
            {
                Remove-Item -Path "$env:TEMP\safenet_cmd.txt" -Force -ErrorAction SilentlyContinue
                Pop-Location
            }
        }

        ######################
        # Install Luna Client
        ######################

        # FIX

        if (-not (Test-Path -Path "C:\Program Files\SafeNet\LunaClient\lunacm.exe") -and
            (ShouldProcess @WhatIfSplat -Message "Installing LunaCm." @VerboseSplat))
        {
            Start-Process -WorkingDirectory $env:TEMP -FilePath $LunaFile.Name -ArgumentList "/install /quiet /norestart addlocal=NETWORK,CSP_KSP" -Verb RunAs
        }

        #########
        # Params
        #########

        $SafeNetSplat = @{}

        switch ($ParameterSetName)
        {
            { $_ -in @('LunaSh', 'Plink', 'Pscp') }
            {
                $SafeNetSplat +=
                @{
                    $ParameterSetName = $true
                    HsmHostname =  $HsmHostname
                    HsmCredential = $HsmCredential
                }

                if ($LunaSh)
                {
                    $SafeNetSplat +=
                    @{
                        Command = $LunaSh
                        Timeout = $Timeout
                    }
                }
                elseif ($Fingerprint)
                {
                    $SafeNetSplat += @{ Command = "-pw $([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HsmCredential.Password))) -hostkey `"$Fingerprint`" $($HsmCredential.UserName)@$($HsmHostname)" }
                }
                elseif ($PscpCertificateFromHsm.IsPresent)
                {
                    $SafeNetSplat += @{ Command = "-batch -pw $([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HsmCredential.Password))) `"$($HsmCredential.UserName)@$($HsmHostname):server.pem`" `"C:\Program Files\SafeNet\LunaClient\$HsmHostname.pem`"" }
                }
            }

            'PedServer'
            {
                $SafeNetSplat +=
                @{
                    PedServer = $true
                    Command = "mode $PedServer"
                }
            }

            Default
            {
                $SafeNetSplat +=
                @{
                    $ParameterSetName = $true
                    Command = Get-Variable -Name $ParameterSetName | Select-Object -ExpandProperty Value
                }
            }
        }

        #########
        # Invoke
        #########

        SafeNet @SafeNetSplat

        # ██████╗ ███████╗████████╗██╗   ██╗██████╗ ███╗   ██╗
        # ██╔══██╗██╔════╝╚══██╔══╝██║   ██║██╔══██╗████╗  ██║
        # ██████╔╝█████╗     ██║   ██║   ██║██████╔╝██╔██╗ ██║
        # ██╔══██╗██╔══╝     ██║   ██║   ██║██╔══██╗██║╚██╗██║
        # ██║  ██║███████╗   ██║   ╚██████╔╝██║  ██║██║ ╚████║
        # ╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝

        Write-Output -InputObject $Result
    }
}

Process
{
    # ██████╗ ██████╗  ██████╗  ██████╗███████╗███████╗███████╗
    # ██╔══██╗██╔══██╗██╔═══██╗██╔════╝██╔════╝██╔════╝██╔════╝
    # ██████╔╝██████╔╝██║   ██║██║     █████╗  ███████╗███████╗
    # ██╔═══╝ ██╔══██╗██║   ██║██║     ██╔══╝  ╚════██║╚════██║
    # ██║     ██║  ██║╚██████╔╝╚██████╗███████╗███████║███████║
    # ╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝╚══════╝╚══════╝╚══════╝

    # Load functions
    Invoke-Command -ScriptBlock `
    {
        try
        {
            . $PSScriptRoot\f_TryCatch.ps1
            # f_ShouldProcess.ps1 loaded in Begin
            . $PSScriptRoot\f_CopyDifferentItem.ps1
            # f_CheckContinue.ps1 loaded in begin
        }
        catch [Exception]
        {
            throw $_
        }

    } -NoNewScope

    # Initialize
    $InvokeSplat = @{}

    # Setup remote
    if ($Session -and $Session.State -eq 'Opened')
    {
        # Load functions
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_TryCatch.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_ShouldProcess.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_CheckContinue.ps1

        # Get parameters
        Invoke-Command -Session $Session -ScriptBlock `
        {
            # Common
            $VerboseSplat           = $Using:VerboseSplat
            $WhatIfSplat            = $Using:WhatIfSplat
            $Force                  = $Using:Force
            $ParameterSetName       = $Using:ParameterSetName

            $LunaFile               = $Using:LunaFile

            $LunaSh                 = $Using:LunaSh
            $Fingerprint            = $Using:Fingerprint
            $PscpCertificateFromHsm = $Using:PscpCertificateFromHsm
            $HsmHostname            = $Using:HsmHostname
            $HsmCredential          = $Using:HsmCredential
            $Timeout                = $Using:Timeout

            $KspCmd                 = $Using:KspCmd
            $KspUtil                = $Using:KspUtil
            $Vtl                    = $Using:Vtl
            $LunaCm                 = $Using:LunaCm
            $Cmu                    = $Using:Cmu
            $PedServer              = $Using:PedServer
        }

        $InvokeSplat.Add('Session', $Session)
    }
    else # Locally
    {
        # Load functions
        Invoke-Command -ScriptBlock `
        {
            try
            {
            }
            catch [Exception]
            {
                throw $_
            }

        } -NoNewScope

        $InvokeSplat.Add('NoNewScope', $true)
    }

    # Invoke
    try
    {
        # Run main
        $Result = Invoke-Command @InvokeSplat -ScriptBlock $MainScriptBlock -ErrorAction Stop
    }
    catch [Exception]
    {
        throw "$_ $( $_.ScriptStackTrace)"
    }

    # ██████╗ ███████╗███████╗██╗   ██╗██╗  ████████╗
    # ██╔══██╗██╔════╝██╔════╝██║   ██║██║  ╚══██╔══╝
    # ██████╔╝█████╗  ███████╗██║   ██║██║     ██║
    # ██╔══██╗██╔══╝  ╚════██║██║   ██║██║     ██║
    # ██║  ██║███████╗███████║╚██████╔╝███████╗██║
    # ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝ ╚══════╝╚═╝

    if ($Result)
    {
        if ($Result.GetType().Name -eq 'Hashtable')
        {
            $ResultOutput = @{}

            foreach($item in $Result.GetEnumerator())
            {
                if ($item.Key.GetType().Name -eq 'String')
                {
                    $ResultOutput.Add($item.Key, $item.Value)
                }
                else
                {
                    # Save in temp
                    Set-Content -Path "$env:TEMP\$($item.Key.Name)" -Value $item.Value

                    if ($item.Key.Extension -eq '.crt' -or $item.Key.Extension -eq '.crl')
                    {
                        # Convert to base 64
                        TryCatch { certutil -f -encode "$env:TEMP\$($item.Key.Name)" "$env:TEMP\$($item.Key.Name)" } > $null
                    }

                    # Set original timestamps
                    Set-ItemProperty -Path "$env:TEMP\$($item.Key.Name)" -Name CreationTime -Value $item.Key.CreationTime
                    Set-ItemProperty -Path "$env:TEMP\$($item.Key.Name)" -Name LastWriteTime -Value $item.Key.LastWriteTime
                    Set-ItemProperty -Path "$env:TEMP\$($item.Key.Name)" -Name LastAccessTime -Value $item.Key.LastAccessTime

                    # Move to script root if different
                    Copy-DifferentItem -SourcePath "$env:TEMP\$($item.Key.Name)" -Delete -TargetPath "$PSScriptRoot\$($item.Key.Name)" @VerboseSplat
                }
            }

            Write-Output -InputObject $ResultOutput
        }
        else
        {
            Write-Warning -Message 'Unexpected result:'

            foreach($row in $Result)
            {
                Write-Host -Object $row
            }
        }
    }
}

End
{
    if ($Session)
    {
        $Session | Remove-PSSession
    }
}

# SIG # Begin signature block
# MIIekQYJKoZIhvcNAQcCoIIegjCCHn4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6Xcc817X8DfTU+tglDP2AR7P
# se2gghgSMIIFBzCCAu+gAwIBAgIQJTSMe3EEUZZAAWO1zNUfWTANBgkqhkiG9w0B
# AQsFADAQMQ4wDAYDVQQDDAVKME43RTAeFw0yMTA2MDcxMjUwMzZaFw0yMzA2MDcx
# MzAwMzNaMBAxDjAMBgNVBAMMBUowTjdFMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAzdFz3tD9N0VebymwxbB7s+YMLFKK9LlPcOyyFbAoRnYKVuF7Q6Zi
# fFMWIopnRRq/YtahEtmakyLP1AmOtesOSL0NRE5DQNFyyk6D02/HFhpM0Hbg9qKp
# v/e3DD36uqv6DmwVyk0Ui9TCYZQbMDhha/SvT+IS4PBDwd3RTG6VH70jG/7lawAh
# mAE7/gj3Bd5pi7jMnaPaRHskogbAH/vRGzW+oueG3XV9E5PWWeRqg1bTXoIhBG1R
# oSWCXEpcHekFVSnatE1FGwoZHTDYcqNnUOQFx1GugZE7pmrZsdLvo/1gUCSdMFvT
# oU+UeurZI9SlfhPd6a1jYT/BcgsZdghWUO2M8SCuQ/S/NuotAZ3kZI/3y3T5JQnN
# 9l9wMUaoIoEMxNK6BmsSFgEkiQeQeU6I0YT5qhDukAZDoEEEHKl17x0Q6vxmiFr0
# 451UPxWZ19nPLccS3i3/kEQjVXc89j2vXnIW1r5UHGUB4NUdktaQ25hxc6c+/Tsx
# 968S+McqxF9RmRMp4g0kAFhBHKj7WhUVt2Z/bULSyb72OF4BC54CCSt1Q4eElh0C
# 1AudkZgj9CQKFIyveTBFsi+i2g6D5cIpl5fyQQnqDh/j+hN5QuI8D7poLe3MPNA5
# r5W1c60B8ngrDsJd7XnJrX6GdJd2wIPh1RmzDlmoUxVXrgnFtgzeTUUCAwEAAaNd
# MFswDgYDVR0PAQH/BAQDAgWgMCoGA1UdJQQjMCEGCCsGAQUFBwMDBgkrBgEEAYI3
# UAEGCisGAQQBgjcKAwQwHQYDVR0OBBYEFEPCLoNYgwyQVHRrBSI9l0nSMwnLMA0G
# CSqGSIb3DQEBCwUAA4ICAQBiMW8cSS4L1OVu4cRiaPriaqQdUukgkcT8iWGWrAHL
# TFPzivIPI5+7qKwzIJbagOM3fJjG0e6tghaSCPfVU+sPWvXIKF3ro5XLUfJut6j5
# qUqoQt/zNuWpI12D1gs1NROWnJgqe1ddmvoAOn5pZyFqooC4SnD1fT7Srs+G8Hs7
# Qd2j/1XYAphZfLXoiOFs7uzkQLJbhmikhEJQKzKE4i8dcsoucNhe2lvNDftJqaGl
# oALzu04y1LcpgCDRbvjU0YDStZwKSEj9jvz89xpl5tMrgGWIK8ghjRzGf0iPhqb/
# xFOFcKP2k43X/wXWa9W7PlO+NhIlZmTM/W+wlgrRfgkawy2WLpO8Vop+tvVwLdyp
# 5n4UxRDXBhYd78Jfscb0fwpsU+DzONLrJEwXjdj3W+vdEZs7YIwAnsCGf8NznXWp
# N9D7OzqV0PT2Szkao5hEp3nS6dOedw/0uKAz+l5s7WJOTLtFjDhUk62g5vIZvVK2
# E9TWAuViPmUkVugnu4kV4c870i5YgRZz9l4ih5vL9XMoc4/6gohLtUgT4FD0xKXn
# bwtl/LczkzDO9vKLbx93ICmNJuzLj+K8S4AAo8q6PTgLZyGlozmTWRa3SmGVqTNE
# suZR41hGNpjtNtIIiwdZ4QuP8cj64TikUIoGVNbCZgcPDHrrz84ZjAFlm7H9SfTK
# 8jCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFowDQYJKoZIhvcNAQEMBQAw
# ZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBS
# b290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2jeu+RdSjwwIjBpM+zCpyUu
# ySE98orYWcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bGl20dq7J58soR0uRf1gU8
# Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBEEC7fgvMHhOZ0O21x4i0M
# G+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/NrDRAX7F6Zu53yEioZldX
# n1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A2raRmECQecN4x7axxLVq
# GDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8IUzUvK4bA3VdeGbZOjFE
# mjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfBaYh2mHY9WV1CdoeJl2l6
# SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaaRBkrfsCUtNJhbesz2cXf
# SwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZifvaAsPvoZKYz0YkH4b23
# 5kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXeeqxfjT/JvNNBERJb5RBQ
# 6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g/KEexcCPorF+CiaZ9eRp
# L5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0O
# BBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1R
# i6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEFBQcBAQRtMGswJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1UdIAQKMAgwBgYEVR0gADAN
# BgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22Ftf3v1cHvZqsoYcs7IVe
# qRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih9/Jy3iS8UgPITtAq3vot
# Vs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYDE3cnRNTnf+hZqPC/Lwum
# 6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c2PR3WlxUjG/voVA9/HYJ
# aISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88nq2x2zm8jLfR+cWojayL/
# ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5lDCCBq4wggSWoAMCAQIC
# EAc2N7ckVHzYR6z9KGYqXlswDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTIyMDMyMzAw
# MDAwMFoXDTM3MDMyMjIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQw
# OTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAMaGNQZJs8E9cklRVcclA8TykTepl1Gh1tKD0Z5Mom2gsMyD+Vr2
# EaFEFUJfpIjzaPp985yJC3+dH54PMx9QEwsmc5Zt+FeoAn39Q7SE2hHxc7Gz7iuA
# hIoiGN/r2j3EF3+rGSs+QtxnjupRPfDWVtTnKC3r07G1decfBmWNlCnT2exp39mQ
# h0YAe9tEQYncfGpXevA3eZ9drMvohGS0UvJ2R/dhgxndX7RUCyFobjchu0CsX7Le
# Sn3O9TkSZ+8OpWNs5KbFHc02DVzV5huowWR0QKfAcsW6Th+xtVhNef7Xj3OTrCw5
# 4qVI1vCwMROpVymWJy71h6aPTnYVVSZwmCZ/oBpHIEPjQ2OAe3VuJyWQmDo4EbP2
# 9p7mO1vsgd4iFNmCKseSv6De4z6ic/rnH1pslPJSlRErWHRAKKtzQ87fSqEcazjF
# KfPKqpZzQmiftkaznTqj1QPgv/CiPMpC3BhIfxQ0z9JMq++bPf4OuGQq+nUoJEHt
# Qr8FnGZJUlD0UfM2SU2LINIsVzV5K6jzRWC8I41Y99xh3pP+OcD5sjClTNfpmEpY
# PtMDiP6zj9NeS3YSUZPJjAw7W4oiqMEmCPkUEBIDfV8ju2TjY+Cm4T72wnSyPx4J
# duyrXUZ14mCjWAkBKAAOhFTuzuldyF4wEr1GnrXTdrnSDmuZDNIztM2xAgMBAAGj
# ggFdMIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBS6FtltTYUvcyl2
# mi91jGogj57IbzAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNV
# HQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBp
# MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUH
# MAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRS
# b290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EM
# AQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAfVmOwJO2b5ipRCIB
# fmbW2CFC4bAYLhBNE88wU86/GPvHUF3iSyn7cIoNqilp/GnBzx0H6T5gyNgL5Vxb
# 122H+oQgJTQxZ822EpZvxFBMYh0MCIKoFr2pVs8Vc40BIiXOlWk/R3f7cnQU1/+r
# T4osequFzUNf7WC2qk+RZp4snuCKrOX9jLxkJodskr2dfNBwCnzvqLx1T7pa96kQ
# sl3p/yhUifDVinF2ZdrM8HKjI/rAJ4JErpknG6skHibBt94q6/aesXmZgaNWhqsK
# RcnfxI2g55j7+6adcq/Ex8HBanHZxhOACcS2n82HhyS7T6NJuXdmkfFynOlLAlKn
# N36TU6w7HQhJD5TNOXrd/yVjmScsPT9rp/Fmw0HNT7ZAmyEhQNC3EyTN3B14OuSe
# reU0cZLXJmvkOHOrpgFPvT87eK1MrfvElXvtCl8zOYdBeHo46Zzh3SP9HSjTx/no
# 8Zhf+yvYfvJGnXUsHicsJttvFXseGYs2uJPU5vIXmVnKcPA3v5gA3yAWTyf7YGcW
# oWa63VXAOimGsJigK+2VQbc61RWYMbRiCQ8KvYHZE/6/pNHzV9m8BPqC3jLfBInw
# AM1dwvnQI38AC+R2AibZ8GV2QqYphwlHK+Z/GqSFD/yYlvZVVCsfgPrA8g4r5db7
# qS9EFUrnEw4d2zc4GqEr9u3WfPwwggbAMIIEqKADAgECAhAMTWlyS5T6PCpKPSkH
# gD1aMA0GCSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2
# IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMjIwOTIxMDAwMDAwWhcNMzMxMTIx
# MjM1OTU5WjBGMQswCQYDVQQGEwJVUzERMA8GA1UEChMIRGlnaUNlcnQxJDAiBgNV
# BAMTG0RpZ2lDZXJ0IFRpbWVzdGFtcCAyMDIyIC0gMjCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAM/spSY6xqnya7uNwQ2a26HoFIV0MxomrNAcVR4eNm28
# klUMYfSdCXc9FZYIL2tkpP0GgxbXkZI4HDEClvtysZc6Va8z7GGK6aYo25BjXL2J
# U+A6LYyHQq4mpOS7eHi5ehbhVsbAumRTuyoW51BIu4hpDIjG8b7gL307scpTjUCD
# HufLckkoHkyAHoVW54Xt8mG8qjoHffarbuVm3eJc9S/tjdRNlYRo44DLannR0hCR
# RinrPibytIzNTLlmyLuqUDgN5YyUXRlav/V7QG5vFqianJVHhoV5PgxeZowaCiS+
# nKrSnLb3T254xCg/oxwPUAY3ugjZNaa1Htp4WB056PhMkRCWfk3h3cKtpX74LRsf
# 7CtGGKMZ9jn39cFPcS6JAxGiS7uYv/pP5Hs27wZE5FX/NurlfDHn88JSxOYWe1p+
# pSVz28BqmSEtY+VZ9U0vkB8nt9KrFOU4ZodRCGv7U0M50GT6Vs/g9ArmFG1keLuY
# /ZTDcyHzL8IuINeBrNPxB9ThvdldS24xlCmL5kGkZZTAWOXlLimQprdhZPrZIGwY
# UWC6poEPCSVT8b876asHDmoHOWIZydaFfxPZjXnPYsXs4Xu5zGcTB5rBeO3GiMiw
# bjJ5xwtZg43G7vUsfHuOy2SJ8bHEuOdTXl9V0n0ZKVkDTvpd6kVzHIR+187i1Dp3
# AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgB
# hv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYDVR0OBBYE
# FGKK3tBh/I8xFO2XC809KpQU31KcMFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9j
# cmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZU
# aW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEy
# NTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAFWqKhrzRvN4
# Vzcw/HXjT9aFI/H8+ZU5myXm93KKmMN31GT8Ffs2wklRLHiIY1UJRjkA/GnUypsp
# +6M/wMkAmxMdsJiJ3HjyzXyFzVOdr2LiYWajFCpFh0qYQitQ/Bu1nggwCfrkLdcJ
# iXn5CeaIzn0buGqim8FTYAnoo7id160fHLjsmEHw9g6A++T/350Qp+sAul9Kjxo6
# UrTqvwlJFTU2WZoPVNKyG39+XgmtdlSKdG3K0gVnK3br/5iyJpU4GYhEFOUKWaJr
# 5yI+RCHSPxzAm+18SLLYkgyRTzxmlK9dAlPrnuKe5NMfhgFknADC6Vp0dQ094XmI
# vxwBl8kZI4DXNlpflhaxYwzGRkA7zl011Fk+Q5oYrsPJy8P7mxNfarXH4PMFw1nf
# J2Ir3kHJU7n/NBBn9iYymHv+XEKUgZSCnawKi8ZLFUrTmJBFYDOA4CPe+AOk9kVH
# 5c64A0JH6EE2cXet/aLol3ROLtoeHYxayB6a1cLwxiKoT5u92ByaUcQvmvZfpyeX
# upYuhVfAYOd4Vn9q78KVmksRAsiCnMkaBXy6cbVOepls9Oie1FqYyJ+/jbsYXEP1
# 0Cro4mLueATbvdH7WwqocH7wl4R44wgDXUcsY6glOJcB0j862uXl9uab3H4szP8X
# TE0AotjWAQ64i+7m4HJViSwnGWH2dwGMMYIF6TCCBeUCAQEwJDAQMQ4wDAYDVQQD
# DAVKME43RQIQJTSMe3EEUZZAAWO1zNUfWTAJBgUrDgMCGgUAoHgwGAYKKwYBBAGC
# NwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUTI/YoFqJ
# PnWnx/3kYPYdaGm1tZwwDQYJKoZIhvcNAQEBBQAEggIAaaqIdnHIoS8usfy4ECMv
# fEigO1b7MVNqay0LxuChg5yWc0zIbceaGSvORkQEqLQGSJ1xPZgcmiwZQ2dWaX9S
# dWlUp4qouD5aNAuv6cr/QFOokYKnMTwRSCY3Tj1UNnWsqcOpihJbcSbdTiX5wGRE
# Ko34yCfdqfRUPaiibxqEect/+tBsd2ZXScPkyPw4b1fwGoF0PsU05ItRlKedIJVM
# VskPH8WdCcIZDTerxGbl/DTLz/7GZEOGwyMsfvZjeMmrTYSHY46xSn3fMYik2kfN
# 5wwJQyzr6u9Pdq20g6pF9JizlKF79kEzFNLjP9LxcCVXsXc+DY2tKVds7ttrneWE
# tT75k1apwkMAtoPU65OAPvELPIM5iT60mYZ9HjufqTmsetzk9n9MKDYe16X5KrEI
# c7CbhsDYLgPPsARQOg03cE/4SU69b3E+pKv2bgWG0cn7x57CVjLk3pMik5+k5qXZ
# I99+gjuHKcX671czGkAZzHgQ26NRRHPbUN40IpBqfVbloGaRHDZuwMiRpOQtQ9av
# kk+631m3ib64bVdJHpN75HG64Atli8sv/FLatonse7YPyJhL/KZhlKNMf9uJjYWd
# q+OBk4N4iSG0DIE1Eg7K4V5C4dB++LvwsHiSdoM/XmjkDG9YbUyPLlEMMIjL8FCT
# AwvOwAgJ8hqrWwVy/cVVFROhggMgMIIDHAYJKoZIhvcNAQkGMYIDDTCCAwkCAQEw
# dzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNV
# BAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1w
# aW5nIENBAhAMTWlyS5T6PCpKPSkHgD1aMA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZI
# hvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjIwOTMwMTQwMDAw
# WjAvBgkqhkiG9w0BCQQxIgQgeBHV8I7VJZDPAn2A9foQ9lAnVtC8KJOWXTekKlBL
# VgwwDQYJKoZIhvcNAQEBBQAEggIAwZvPKhALbYzBSYSViNlfgbgVlHzjiLYnwRI7
# Kvg/fVc/pwjWcieyvhSopNTrfVL6Hcyzn0OSpCGH48I1iK2fdC20L7oXEKFBSV9O
# THtHXCJNy5UXBkILnOMdJRi8lwF22yC5bma8Bfm6wzYg4d14RJIIGgvtssn0rweW
# o3D4MoO58p1pOISpiTqYcQxTo0+b2PXpPX5hOZH+RpyDQ/IV+KAQqrSG2hG8vv5N
# evrQx2rgDize6TBAvvELrxshZENJPB04jfVMrlXLAdpc5qRbD3RdtHMeSu7JccuA
# TkwuSWNYvEnyuHia6zz6RMKSBjM3f/v7Ix/vAsPDgxGK9Mc35IvVz++zO2InkpsH
# CefKUBXqloiNvmhRTqfOpLO+/+VgJ9gC63pi+NfXNmGCUBYZHfVoTg5RU6pNyxsH
# TlVZO3oRBdEVpOrRyteHVJpARugplUH+8OKZIsItz8egVwBwGHJiSIXYVcCYJtpf
# nVQLa0hA0NJNc10QGwFtEUihFT4mmDzePdI7wzSKjjGMsPTgpe4iSfrKZJMIn8vh
# 6fKEbqBPHwOgaOHq//lf0U96wWnmmP8KB8kByYscuq5B/owRtozB3HHcKMcWBmZa
# c1YgwN1uWRQxEN+O+LDuvF2reZ9Jlhvp86uQDKCkw8DTtvB8/VAbEymInpf7hOIh
# J+4qYKY=
# SIG # End signature block
