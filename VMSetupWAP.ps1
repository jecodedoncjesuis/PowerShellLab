<#
 .DESCRIPTION
    Setup Web Application Proxy (WAP)
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
    $ADFSTrustCredential,

    # Default generic lazy pswd
    $CertFilePassword = (ConvertTo-SecureString -String 'e72d4D6wYweyLS4sIAuKOif5TUlJjEpB' -AsPlainText -Force),

    [String]$ADFSPfxFile,
    [String]$ADFSFederationServiceName,

    [Switch]$EnrollLetsEncryptCertificates
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
        @{ Name = 'Session';                                      },
        @{ Name = 'Credential';             Type = [PSCredential] },
        @{ Name = 'ADFSTrustCredential';    Type = [PSCredential] },
        @{ Name = 'CertFilePassword';       Type = [SecureString] }
    )

    #########
    # Invoke
    #########

    Invoke-Command -ScriptBlock `
    {
        try
        {
            . $PSScriptRoot\s_Begin.ps1
        }
        catch [Exception]
        {
            throw "$_ $( $_.ScriptStackTrace)"
        }

    } -NoNewScope

    ######################
    # Get parent ca files
    ######################

    if ($ADFSPfxFile)
    {
        # Get file content
        $ADFSPfxFile = Get-Content -Path (Get-Item -Path $PSScriptRoot\$ADFSPfxFile -ErrorAction Stop).FullName -Raw
    }

    ################################
    # Default ADFS trust credential
    ################################

    if (-not $ADFSTrustCredential -and $Credential)
    {
        $ADFSTrustCredential = $Credential
    }

    # ███╗   ███╗ █████╗ ██╗███╗   ██╗
    # ████╗ ████║██╔══██╗██║████╗  ██║
    # ██╔████╔██║███████║██║██╔██╗ ██║
    # ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
    # ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
    # ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

    $MainScriptBlock =
    {
        ##############
        # Check admin
        ##############

        if ( -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        {
            throw "Must be administrator to setup Webserver."
        }

        ###############
        # Check domain
        ###############

        $PartOfDomain = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty PartOfDomain

        # Check for part of domain
        if ($PartOfDomain)
        {
            $DomainName = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Domain

            if (-not $ADFSFederationServiceName)
            {
                $ADFSFederationServiceName = "adfs.$DomainName"
            }
        }
        elseif (-not $ADFSFederationServiceName)
        {
            throw "Can't find domain, please use -ADFSFederationServiceName and specify FQDN."
        }
        else
        {
            $DomainName = $ADFSFederationServiceName.Substring($ADFSFederationServiceName.IndexOf('.') + 1)
        }

        # ██████╗ ██████╗ ███████╗██████╗ ███████╗ ██████╗
        # ██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔════╝██╔═══██╗
        # ██████╔╝██████╔╝█████╗  ██████╔╝█████╗  ██║   ██║
        # ██╔═══╝ ██╔══██╗██╔══╝  ██╔══██╗██╔══╝  ██║▄▄ ██║
        # ██║     ██║  ██║███████╗██║  ██║███████╗╚██████╔╝
        # ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝ ╚══▀▀═╝

        ###############
        # Lets Encrypt
        # Acme
        ###############

        if ($EnrollLetsEncryptCertificates)
        {
            #########
            # Prereq
            #########

            # Check package provider
            if(-not (Get-PackageProvider | Where-Object { $_.Name -eq 'NuGet' }) -and
              (ShouldProcess @WhatIfSplat -Message "Installing NuGet package provider." @VerboseSplat))
            {
                # Install package provider
                Install-PackageProvider -Name NuGet -Force -ErrorAction Stop -Confirm:$false > $null
            }

            # Check module
            if(-not (Get-InstalledModule | Where-Object { $_.Name -eq 'Posh-ACME' }) -and
              (ShouldProcess @WhatIfSplat -Message "Installing Posh-ACME module." @VerboseSplat))
            {
                # Install module
                Install-Module -Name Posh-ACME -Force -ErrorAction Stop -Confirm:$false > $null
            }

            # Check server
            if(-not (Get-PAServer | Where-Object { $_.location -eq 'https://acme-v02.api.letsencrypt.org/directory' }) -and
              (ShouldProcess @WhatIfSplat -Message "Setting production server." @VerboseSplat))
            {
                # Set server
                Set-PAServer -DirectoryUrl 'https://acme-v02.api.letsencrypt.org/directory' > $null
            }

            # Check account
            if(-not (Get-PAAccount | Where-Object { $_.contact -eq "mailto:admin@$DomainName" }) -and
              (ShouldProcess @WhatIfSplat -Message "Adding account admin@$DomainName." @VerboseSplat))
            {
                # Adding account
                New-PAAccount -AcceptTOS -Contact "admin@$DomainName" > $null
            }

            ###############
            # Certificates
            ###############

            $Certificates =
            @(
                @("*.$DomainName")
            )

            ##########
            # Request
            ##########

            foreach ($Cert in $Certificates)
            {
                $PACertificate = Get-PACertificate -List | Where-Object { @(Compare-Object $_.AllSANs $Cert -SyncWindow 0).Length -eq 0 }

                # Check order status
                if(-not $PACertificate)
                {
                    $PACertificate = New-PACertificate -Domain $Cert -AcceptTOS -DNSSleep 20

                }
                if($PACertificate.NotAfter -le (get-date).AddDays(14).ToShortDateString())
                {
                    # Remove old cert
                    Remove-Item -Path "Cert:\LocalMachine\My\$($PACertificate.Thumbprint)" -DeleteKey -ErrorAction SilentlyContinue

                    if ($Cert.GetType().Name -eq 'object[]')
                    {
                        $MainDomain = $Cert[0]
                    }
                    else
                    {
                        $MainDomain = $Cert
                    }

                    $PACertificate = Submit-Renewal -MainDomain $MainDomain -NoSkipManualDns
                }

                $PACertificate | Install-PACertificate -StoreLocation LocalMachine -StoreName My -NotExportable
            }
        }

        ##################
        # Get certificate
        ##################

        $ADFSCertificate = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {
            $_.DnsNameList.Contains("adfs.$DomainName") -and
            $_.DnsNameList.Contains("certauth.adfs.$DomainName") -and
            $_.DnsNameList.Contains("enterpriseregistration.$DomainName") -and
            (
                $_.Extensions['2.5.29.37'].EnhancedKeyUsages.FriendlyName.Contains('Server Authentication')
            )
        }

        #####################
        # Import certificate
        #####################

        if (-not $ADFSCertificate)
        {
            if (-not $ADFSPfxFile)
            {
                throw "Can't find ADFS certificate, please use -ADFSPfxFile to submit certificate."
            }
            elseif (ShouldProcess @WhatIfSplat -Message "Importing ADFS certificate from PFX." @VerboseSplat)
            {
                # Save pfx
                Set-Content -Value $ADFSPfxFile -Path "$env:TEMP\ADFSCertificate.pfx" -Force

                try
                {
                    # FIX
                    # make function
                    $Pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection;
                    $Pfx.Import("$env:TEMP\ADFSCertificate.pfx", [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertFilePassword)), 'PersistKeySet,MachineKeySet');

                    foreach ($Cert in $Pfx) {

                        # CA Version
                        if ($Cert.Extensions['1.3.6.1.4.1.311.21.1'])
                        {
                            # Authority Key Identifier
                            if ($Cert.Extensions['2.5.29.35'])
                            {
                                $Store = 'CA'
                            }
                            else
                            {
                                $Store = 'Root'
                            }
                        }
                        else
                        {
                            $Store = 'My'
                            $ADFSCertificate = $Cert
                        }

                        $X509Store = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $Store,'LocalMachine'
                        $X509Store.Open('MaxAllowed')
                        $X509Store.Add($Cert)
                        $X509Store.Close > $null
                    }
                }
                catch [Exception]
                {
                    throw $_.Exception
                }
                finally
                {
                    # Cleanup
                    Remove-Item -Path "$env:TEMP\ADFSCertificate.pfx"
                }
            }
        }

        ###########
        # Firewall
        ###########

        # Check if Windows Remote Management - Compatibility Mode (HTTP-In) firewall rule is enabled
        if ((Get-NetFirewallRule -Name WINRM-HTTP-Compat-In-TCP).Enabled -eq 'False' -and
            (ShouldProcess @WhatIfSplat -Message "Enabling WINRM-HTTP-Compat-In-TCP firewall rule." @VerboseSplat))
        {
            Enable-NetFirewallRule -Name WINRM-HTTP-Compat-In-TCP > $null
        }

        ##################
        # Disable TLS 1.3
        ##################

        $TLSRegistrySettings =
        @(
            @{ Name = 'DisabledByDefault';  Value = '1';  PropertyType = 'DWord';  Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client' },
            @{ Name = 'Enabled';            Value = '0';  PropertyType = 'DWord';  Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client' }
        )

        Set-Registry -Settings $TLSRegistrySettings

        ########
        # Hosts
        ########

        <#
        $Hosts =
        @(
            "192.168.0.150 adfs.$DomainName"
            "192.168.0.200 pki.$DomainName"
        )

        $HostsFile = Get-Item -Path 'C:\Windows\System32\drivers\etc\hosts'
        $HostsContent = $HostsFile | Get-Content

        # Add to hosts file
        foreach ($Item in $Hosts)
        {
            if ($HostsContent -notcontains $Item -and
              ((ShouldProcess @WhatIfSplat -Message "Adding `"$Item`" to hosts." @VerboseSplat)))
            {
                $HostsFile | Add-Content -Value $Item
            }
        }
        #>

        # ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗
        # ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║
        # ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║
        # ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║
        # ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
        # ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝

        # Check if WAP is installed
        if (((Get-WindowsFeature -Name Web-Application-Proxy).InstallState -ne 'Installed') -and
             (ShouldProcess @WhatIfSplat -Message "Installing Web-Application-Proxy." @VerboseSplat))
        {
            Install-WindowsFeature -Name Web-Application-Proxy -IncludeManagementTools > $null
        }

        #  ██████╗ ██████╗ ███╗   ██╗███████╗██╗ ██████╗ ██╗   ██╗██████╗ ███████╗
        # ██╔════╝██╔═══██╗████╗  ██║██╔════╝██║██╔════╝ ██║   ██║██╔══██╗██╔════╝
        # ██║     ██║   ██║██╔██╗ ██║█████╗  ██║██║  ███╗██║   ██║██████╔╝█████╗
        # ██║     ██║   ██║██║╚██╗██║██╔══╝  ██║██║   ██║██║   ██║██╔══██╗██╔══╝
        # ╚██████╗╚██████╔╝██║ ╚████║██║     ██║╚██████╔╝╚██████╔╝██║  ██║███████╗
        #  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

        # Setup WAP parameters
        $WAPParams =
        @{
            FederationServiceName = $ADFSFederationServiceName
            CertificateThumbprint = $ADFSCertificate.Thumbprint
            FederationServiceTrustCredential = $ADFSTrustCredential
            #TlsClientPort = 443
        }

        # Check if WAP is configured
        try
        {
            Get-WebApplicationProxyApplication > $null
        }
        catch
        {
            # WAP not configured
            if (ShouldProcess @WhatIfSplat -Message "Configuring WAP." @VerboseSplat)
            {
                try
                {
                    Install-WebApplicationProxy @WAPParams -ErrorAction Stop > $null

                    $Reboot = $true
                }
                catch [Exception]
                {
                    throw $_
                }
            }
        }

        # ██████╗  ██████╗ ███████╗████████╗
        # ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝
        # ██████╔╝██║   ██║███████╗   ██║
        # ██╔═══╝ ██║   ██║╚════██║   ██║
        # ██║     ╚██████╔╝███████║   ██║
        # ╚═╝      ╚═════╝ ╚══════╝   ╚═╝

        $WAPApplications =
        @(
            @{ Name = "test.$DomainName";    Url = "http://test.$DomainName"; Auth = 'PassThrough'; }
        )

        $WildcardCertificate = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {
            $_.DnsNameList.Contains("*.$DomainName") -and
            (
                $_.Extensions['2.5.29.37'].EnhancedKeyUsages.FriendlyName.Contains('Server Authentication')
            )
        }

        foreach ($App in $WAPApplications)
        {
            # Initialize
            $CertificateSplat = @{}

            # Check if certificate is needed
            if ($App.Url -match 'https')
            {
                if (-not $WildcardCertificate)
                {
                    Write-Warning -Message "No certificate found for '$($App.Url)'."
                    continue
                }

                $CertificateSplat +=
                @{
                    ExternalCertificateThumbprint = $WildcardCertificate.Thumbprint
                }
            }

            # Check WAP application
            $WapApp = Get-WebApplicationProxyApplication | Where-Object { $_.Name -eq $App.Name }

            # Add new
            if (-not $WapApp -and
                (ShouldProcess @WhatIfSplat -Message "Adding $($App.Name)" @VerboseSplat))
            {
                Add-WebApplicationProxyApplication @CertificateSplat -Name $App.Name -ExternalPreauthentication $App.Auth -ExternalUrl $App.Url -BackendServerUrl $App.Url
            }
            # Update certificate
            elseif (($WapApp.ExternalCertificateThumbprint -and $WapApp.ExternalCertificateThumbprint -ne $WildcardCertificate.Thumbprint) -and
                    (ShouldProcess @WhatIfSplat -Message "Updating $($App.Name) certificate." @VerboseSplat))
            {
                Set-WebApplicationProxyApplication @CertificateSplat -Id $WapApp.Id
            }
        }

        # Check if restart
        if ($Reboot -and
            (ShouldProcess @WhatIfSplat -Message "Restarting `"$ENV:ComputerName`"." @VerboseSplat))
        {
            Restart-Computer -Force
        }
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

    # Initialize
    $InvokeSplat = @{}

    # Setup remote
    if ($Session -and $Session.State -eq 'Opened')
    {
        # Load functions
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_TryCatch.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_ShouldProcess.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_CheckContinue.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_CopyDifferentItem.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_SetRegistry.ps1

        # Get parameters
        Invoke-Command -Session $Session -ScriptBlock `
        {
            # Common
            $VerboseSplat = $Using:VerboseSplat
            $WhatIfSplat  = $Using:WhatIfSplat
            $Force        = $Using:Force

            $ADFSTrustCredential = $Using:ADFSTrustCredential
            $CertFilePassword = $Using:CertFilePassword
            $ADFSPfxFile = $Using:ADFSPfxFile
            $ADFSFederationServiceName = $Using:ADFSFederationServiceName

            $EnrollLetsEncryptCertificates = $Using:EnrollLetsEncryptCertificates
        }

        # Set remote splat
        $InvokeSplat.Add('Session', $Session)
    }
    else # Setup locally
    {
        Check-Continue -Message "Invoke locally?"

        # Load functions
        Invoke-Command -ScriptBlock `
        {
            try
            {
                . $PSScriptRoot\f_TryCatch.ps1
                . $PSScriptRoot\f_ShouldProcess.ps1
                . $PSScriptRoot\f_CheckContinue.ps1
                . $PSScriptRoot\f_CopyDifferentItem.ps1
                . $PSScriptRoot\f_SetRegistry.ps1
            }
            catch [Exception]
            {
                throw $_
            }

        } -NoNewScope

        # Set local splat
        $InvokeSplat.Add('NoNewScope', $true)
    }

    # Invoke
    try
    {
        # Run main
        Invoke-Command @InvokeSplat -ScriptBlock $MainScriptBlock -ErrorAction Stop
    }
    catch [Exception]
    {
        throw "$_ $( $_.ScriptStackTrace)"
    }
}

End
{
}

# SIG # Begin signature block
# MIIekQYJKoZIhvcNAQcCoIIegjCCHn4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUxN8ERQu1VLOmgUjhi/tzUfbb
# N3ugghgSMIIFBzCCAu+gAwIBAgIQJTSMe3EEUZZAAWO1zNUfWTANBgkqhkiG9w0B
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUUXE/zYL7
# dxe3oyzYd3kKDg4DeM0wDQYJKoZIhvcNAQEBBQAEggIAoKLQ8Ht48kwec7jL7xNP
# sFDufSE3p5f3bSNxAVimQJKw5VlLHnfpSQvaYW6cBZr8hcIPVxYm3ZhtbpPHtvAD
# itA+WiRP4e72KmIAeGN1DGd6Z0rWImxxXetT+1ZVVe1rcjzuO1BQ5fjoQDzMYwTY
# /BjTf/QtPlVKuL4Ln1ACsKmWVLi74NdbX+g6sKRXgFtMgDXyejlh2VeBfVGFSYKO
# gQuNKbnJ9SDQjI3Ebx72xPbyIQOAvC0UZ78cYLPeaA4hcxDPJ/vsEA5GO6hcwClC
# 2A75fHC7fKCgluMDZ+wD+55AeXkb+ERw92uxQfjsUtraU8LSXVTLEyAMw6JWw8XR
# APDkJBxcOH/XLLguViY2REE3s+Emn9PgVzjJvV7hLEM8xI400qsGfzRh2RDmRKJb
# hoJQEuRbagJu9lPeqPg/nTxwoMYOt5amyBE6JI2hlkcpY1SqJys10jKxUuiFxqiD
# vtwjUSHh7AolXEpHaYLIqirEm9cMi0JSZGFfZgpxYDdYdn2qT2sgpiGQ0WwI54D5
# xNww8ScRBO4MGb06gnJ1iurUAlZjSm4IkSPPTjfbHO+1Dr8Tmp/Pq3jv8NEFGcOx
# Bf+xDV+/zwMrboDS1DQ3vGfsxmEuaxKBGVSgbDaBJffUlZDJahnwjDQI32bElNP4
# LMDjXl7ww2S7wcEsStKQqRuhggMgMIIDHAYJKoZIhvcNAQkGMYIDDTCCAwkCAQEw
# dzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNV
# BAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1w
# aW5nIENBAhAMTWlyS5T6PCpKPSkHgD1aMA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZI
# hvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjMwMTEyMTQwMDAy
# WjAvBgkqhkiG9w0BCQQxIgQgZaG+g0rLsyVWNnrrowNoQg0v+tK3qhoWdswiozLb
# 1PAwDQYJKoZIhvcNAQEBBQAEggIABZMkImoZNKOfvX/LdHpLO+Q/w07GxCLZqMAK
# xdvy1wXNCvl8ODPybSDYuPf56vnIr3EpvbnbXWHQiSK3UtQKkhEb7ILE+WbfQeDA
# sAbYKixWWC/ZxA3YJeZSKmnMHlOuWR/n52XinI/QzD8OQxBbYFiMsWN/OKnbtsPU
# EEVS3xWCw75o1L5kW/LdaxHgfeuMgXPgfCqo3zkPOkbv3wC6evHfFV0Utmhyt/xP
# YegM9WyFkwJTwZUP8tlLLGbaVwJ/SjDvE7lVDFD+htnGoDR5BZTIDk2JSDWYv2yC
# RZSQuj8MJ/C8ewf6ummzRWnMK/4ORaAMBxQQ/5sBvIr7qwF2ddbHN1cYnfTfPf08
# ItpaB67cWhtnwu01dMbdI9j4Cy85UCHMCnIhCZjlJ5CO19Ahw4W866wPnUHm0oqO
# EHgyjeQnNGd1t9NevXi+sV1RNvFoxgrQeBRO4a+LU8Zz8r/pvBbmixXD3mWlpHR6
# b9tM1WSdroM2iLKFHQ/qolTHA8gV++nQpRV5hVhb9byqmrZ06JTqIBUpwQtjQUhe
# Pagc/w8btk7xdYrMPZcQI6p7o5oiiirJ/F58KcJrF/AHU3NCLRzxvzsjUuPm7N4T
# yZ7O5NXlbhRwhetAlYWv+sGNvQXguaJXx8pfW+JRXCe2jgNHYkbAmSKUAF3vXcGA
# AgTqoQ8=
# SIG # End signature block
