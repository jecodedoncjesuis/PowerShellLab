<#
 .DESCRIPTION
    Setup network properties
 .NOTES
    AUTHOR Jonas Henriksson
 .LINK
    https://github.com/bomberclaad
#>

[cmdletbinding(SupportsShouldProcess=$true)]

Param
(
    # VM name
    [String]$VMName,
    # Computer name
    [String]$ComputerName,

    # Serializable parameters
    $Session,
    $Credential,

    # Interface alias
    [String]$InterfaceAlias = 'Ethernet',

    # IP Address, defaults to DHCP
    [String]$IPAddress = 'DHCP',

    # Prefix length
    [String]$PrefixLength = '24',

    # Default gateway
    [String]$DefaultGateway = 'DHCP',

    # DNS servers
    [Array]$DNSServerAddresses
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
        @{ Name = 'DNSServerAddresses';     Type = [Array]        }
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
            throw $_
        }

    } -NoNewScope

    # ███╗   ███╗ █████╗ ██╗███╗   ██╗
    # ████╗ ████║██╔══██╗██║████╗  ██║
    # ██╔████╔██║███████║██║██╔██╗ ██║
    # ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
    # ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
    # ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

    $MainScriptBlock =
    {
        ######################
        # Get Interface Index
        ######################

        try
        {
            $IfIndex = Get-NetAdapter -InterfaceAlias "$InterfaceAlias*" -ErrorAction Stop | Sort-Object -Property Name | Select-Object -First 1 -ExpandProperty InterfaceIndex
        }
        catch [Exception]
        {
            throw $_.Exception
        }

        ########################################
        # Get Win32_NetworkAdapterConfiguration
        ########################################

        $Win32NetAdapterConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex='$IfIndex'"

        ##################
        # Disable Netbios
        ##################

        if (($Win32NetAdapterConfig | Select-Object -ExpandProperty TcpipNetbiosOptions) -ne 2 -and
            (ShouldProcess @WhatIfSplat -Message "Disabling Netbios on if $IfIndex `"$InterfaceAlias`"." @VerboseSplat))
        {
            $Win32NetAdapterConfig.SetTcpipNetbios('2') > $null
        }

        ########################
        # Disable LMHost Lookup
        ########################

        if (($Win32NetAdapterConfig | Select-Object -ExpandProperty WINSEnableLMHostsLookup) -eq 'True' -and
            (ShouldProcess @WhatIfSplat -Message "Disabling LMHost lookup on if $IfIndex `"$InterfaceAlias`"." @VerboseSplat))
        {
            $Win32NetAdapterConfList = Get-WmiObject -List Win32_NetworkAdapterConfiguration
            $Win32NetAdapterConfList.EnableWINS($false,$false) > $null
        }

        ###################################
        # IP Address / DNS ServerAddresses
        ###################################

        if ($IPAddress -eq 'DHCP')
        {
            if ((Get-NetIPInterface -InterfaceIndex $IfIndex -AddressFamily IPv4).DHCP -ne 'Enabled' -and
                (ShouldProcess @WhatIfSplat -Message "Enabling DHCP on if $IfIndex `"$InterfaceAlias`"." @VerboseSplat))
            {
                # Remove all ip addresses on interface
                Remove-NetIPAddress -InterfaceIndex $IfIndex -Confirm:$false -ErrorAction SilentlyContinue

                # Set interface to "Obtain an IP address automatically"
                Set-NetIPInterface -InterfaceIndex $IfIndex -AddressFamily IPv4 -Dhcp Enabled
            }

            # Get current dns server addresses
            $CurrentDNSServerAddresses = Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses

            if ($CurrentDNSServerAddresses -and
               (ShouldProcess @WhatIfSplat -Message "Removing dns server adresses $CurrentDNSServerAddresses on if $IfIndex `"$InterfaceAlias`" ." @VerboseSplat))
            {
                # Set interface to "Obtain DNS server address automatically"
                Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ResetServerAddresses
            }
        }
        else
        {
            # Check if ip exist
            if (-not (Get-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $IPAddress }) -and
               (ShouldProcess @WhatIfSplat -Message "Adding IP address $IPAddress/$PrefixLength to if $IfIndex `"$InterfaceAlias`"." @VerboseSplat))
            {
                # Remove all ip addresses on interface
                Remove-NetIPAddress -InterfaceIndex $IfIndex -Confirm:$false -ErrorAction SilentlyContinue

                # Add new ip address
                New-NetIPAddress -InterfaceIndex $IfIndex -IPAddress $IPAddress -PrefixLength $PrefixLength > $null
            }

            # Check if parameter exists
            if (-not $DNSServerAddresses -and $DefaultGateway -ne 'DHCP')
            {
                # Set default dns server addresses
                $DNSServerAddresses = $DefaultGateway
            }

            # Get current dns server addresses
            $CurrentDNSServerAddresses = Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses

            # Check dns client server addresses
            if (@(Compare-Object -ReferenceObject $DNSServerAddresses -DifferenceObject @($CurrentDNSServerAddresses) -SyncWindow 0).Length -ne 0 -and
               (ShouldProcess @WhatIfSplat -Message "Setting DNS server adresses $DNSServerAddresses on if $IfIndex `"$InterfaceAlias`"." @VerboseSplat))
            {
                Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $DNSServerAddresses
            }
        }

        ##########
        # Gateway
        ##########

        $CurrentGateway = Get-NetRoute -InterfaceIndex $IfIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue

        if ($DefaultGateway -eq 'DHCP')
        {
            if ($CurrentGateway -and
                (ShouldProcess @WhatIfSplat -Message "Removing gateway $($CurrentGateway.NextHop) on if $IfIndex `"$InterfaceAlias`" ." @VerboseSplat))
            {
                    # Remove gateway
                    $CurrentGateway | Remove-NetRoute -Confirm:$false

            }
        }
        # Check if gateway exist
        elseif ($DefaultGateway -and $CurrentGateway.NextHop -ne $DefaultGateway -and
               (ShouldProcess @WhatIfSplat -Message "Adding gateway $DefaultGateway to if $IfIndex `"$InterfaceAlias`"." @VerboseSplat))
        {
            New-NetRoute -InterfaceIndex $IfIndex -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -NextHop $DefaultGateway > $null
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

    # Remote
    if ($Session)
    {
        # Load functions
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_TryCatch.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_ShouldProcess.ps1

        # Get parameters
        Invoke-Command -Session $Session -ScriptBlock `
        {
            # Get splat
            $VerboseSplat = $Using:VerboseSplat
            $WhatIfSplat  = $Using:WhatIfSplat
            $ComputerName = $Using:ComputerName

            $InterfaceAlias = $Using:InterfaceAlias
            $IPAddress = $Using:IPAddress
            $PrefixLength = $Using:PrefixLength
            $DefaultGateway = $Using:DefaultGateway
            $DNSServerAddresses = $Using:DNSServerAddresses
        }

        # Run main
        Invoke-Command -Session $Session -ScriptBlock $MainScriptBlock
    }
    else # Locally
    {
        if ((Read-Host "Invoke locally? [y/n]") -ne 'y')
        {
            break
        }

        # Load functions
        Invoke-Command -ScriptBlock `
        {
            try
            {
                . $PSScriptRoot\f_TryCatch.ps1
                . $PSScriptRoot\f_ShouldProcess.ps1
            }
            catch [Exception]
            {
                throw $_
            }

        } -NoNewScope

        # Run main
        Invoke-Command -ScriptBlock $MainScriptBlock -NoNewScope
    }
}

End
{
}

# SIG # Begin signature block
# MIIUrwYJKoZIhvcNAQcCoIIUoDCCFJwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUJO32aI8t6v/TJlRoErRUyyv8
# NACggg8yMIIE9zCCAt+gAwIBAgIQJoAlxDS3d7xJEXeERSQIkTANBgkqhkiG9w0B
# AQsFADAOMQwwCgYDVQQDDANiY2wwHhcNMjAwNDI5MTAxNzQyWhcNMjIwNDI5MTAy
# NzQyWjAOMQwwCgYDVQQDDANiY2wwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQCu0nvdXjc0a+1YJecl8W1I5ev5e9658C2wjHxS0EYdYv96MSRqzR10cY88
# tZNzCynt911KhzEzbiVoGnmFO7x+JlHXMaPtlHTQtu1LJwC3o2QLAew7cy9vsOvS
# vSLVv2DyZqBsy1O7H07z3z873CAsDk6VlhfiB6bnu/QQM27K7WkGK23AHGTbPCO9
# exgfooBKPC1nGr0qPrTdHpAysJKL4CneI9P+sQBNHhx5YalmhVHr0yNeJhW92X43
# WE4IfxNPwLNRMJgLF+SNHLxNByhsszTBgebdkPA4nLRJZn8c32BQQJ5k3QTUMrnk
# 3wTDCuHRAWIp/uWStbKIgVvuMF2DixkBJkXPP1OZjegu6ceMdJ13sl6HoDDFDrwx
# 93PfUoiK7UtffyObRt2DP4TbiD89BldjxwJR1hakJyVCxvOgbelHHM+kjmBi/VgX
# Iw7UDIKmxZrnHpBrB7I147k2lGUN4Q+Uphrjq8fUOM63d9Vb9iTRJZvR7RQrPuXq
# iWlyFKcSpqOS7apgEqOnKR6tV3w/q8SPx98FuhTLi4hZak8u3oIypo4eOHMC5zqc
# 3WxxHHHUbmn/624oJ/RVJ1/JY5EZhKNd+mKtP3LTly7gQr0GgmpIGXmzzvxosiAa
# yUxlSRAV9b3RwE6BoT1wneBAF7s/QaStx1HnOvmJ6mMQrmi0aQIDAQABo1EwTzAO
# BgNVHQ8BAf8EBAMCBaAwHgYDVR0lBBcwFQYIKwYBBQUHAwMGCSsGAQQBgjdQATAd
# BgNVHQ4EFgQUEOwHbWEJldZG1P09yIHEvoP0S2gwDQYJKoZIhvcNAQELBQADggIB
# AC3CGQIHlHpmA6kAHdagusuMfyzK3lRTXRZBqMB+lggqBPrkTFmbtP1R/z6tV3Kc
# bOpRg1OZMd6WJfD8xm88acLUQHvroyDKGMSDOsCQ8Mps45bL54H+8IKK8bwfPfh4
# O+ivHwyQIfj0A44L+Q6Bmb+I0wcg+wzbtMmDKcGzq/SNqhYUEzIDo9NbVyKk9s0C
# hlV3h+N9x2SZJvZR1MmFmSf8tVCgePXMAdwPDL7Fg7np+1lZIuKu1ezG7mL8ULBn
# 81SFUn6cuOTmHm/xqZrDq1urKbauXlnUr+TwpZP9tCuihwJxLaO9mcLnKiEf+2vc
# RQYLkxk5gyUXDkP4k85qvZjc7zBFj9Ptsd2c1SMakCz3EWP8b56iIgnKhyRUVDSm
# o2bNz7MiEjp3ccwV/pMr8ub7OSqHKPSjtWW0Ccw/5egs2mfnAyO1ERWdtrycqEnJ
# CgSBtUtsXUn3rAubGJo1Q5KuonpihDyxeMl8yuvpcoYQ6v1jPG3SAPbVcS5POkHt
# DjktB0iDzFZI5v4nSl8J8wgt9uNNL3cSAoJbMhx92BfyBXTfvhB4qo862a9b1yfZ
# S4rbeyBSt3694/xt2SPhN4Sw36JD99Z68VnX7dFqaruhpyPzjGNjU/ma1n7Qdrnp
# u5VPaG2W3eV3Ay67nBLvifkIP9Y1KTF5JS+wzJoYKvZ2MIIE/jCCA+agAwIBAgIQ
# DUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEwNjAwMDAwMFowSDELMAkGA1UEBhMC
# VVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBU
# aW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLm
# YYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQtSYQ/h3Ib5FrDJbnGlxI70Tlv5th
# zRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4bbx9+cdtCT2+anaH6Yq9+IRdHnbJ
# 5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOKfF1FLUuxUOZBOjdWhtyTI433UCXo
# ZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlKXAwxikqMiMX3MFr5FK8VX2xDSQn9
# JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYervnpbCiAvSwnJlaeNsvrWY4tOpXIc
# 7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0MA4GA1UdDwEB/wQEAwIHgDAMBgNV
# HRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMEEGA1UdIAQ6MDgwNgYJ
# YIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29t
# L0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLkYaWyoiWyyBc1bjAdBgNVHQ4EFgQU
# NkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0fBGowaDAyoDCgLoYsaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC10cy5jcmwwMqAwoC6GLGh0dHA6
# Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtdHMuY3JsMIGFBggrBgEF
# BQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBP
# BggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOC
# AQEASBzctemaI7znGucgDo5nRv1CclF0CiNHo6uS0iXEcFm+FKDlJ4GlTRQVGQd5
# 8NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4eTZ6J7fz51Kfk6ftQ55757TdQSKJ
# +4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2hF3MN9PNlOXBL85zWenvaDLw9MtAb
# y/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1FUL1LTI4gdr0YKK6tFL7XOBhJCVP
# st/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6Xt/Q/hOvB46NJofrOp79Wz7pZdmGJ
# X36ntI5nePk2mOHLKNpbh6aKLzCCBTEwggQZoAMCAQICEAqhJdbWMht+QeQF2jaX
# whUwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGln
# aUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTE2MDEwNzEyMDAwMFoXDTMxMDEw
# NzEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hB
# MiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBAL3QMu5LzY9/3am6gpnFOVQoV7YjSsQOB0UzURB90Pl9TWh+
# 57ag9I2ziOSXv2MhkJi/E7xX08PhfgjWahQAOPcuHjvuzKb2Mln+X2U/4Jvr40ZH
# BhpVfgsnfsCi9aDg3iI/Dv9+lfvzo7oiPhisEeTwmQNtO4V8CdPuXciaC1TjqAlx
# a+DPIhAPdc9xck4Krd9AOly3UeGheRTGTSQjMF287DxgaqwvB8z98OpH2YhQXv1m
# blZhJymJhFHmgudGUP2UKiyn5HU+upgPhH+fMRTWrdXyZMt7HgXQhBlyF/EXBu89
# zdZN7wZC/aJTKk+FHcQdPK/P2qwQ9d2srOlW/5MCAwEAAaOCAc4wggHKMB0GA1Ud
# DgQWBBT0tuEgHf4prtLkYaWyoiWyyBc1bjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAT
# BgNVHSUEDDAKBggrBgEFBQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCB
# gQYDVR0fBHoweDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0QXNzdXJlZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBQBgNVHSAESTBHMDgG
# CmCGSAGG/WwAAgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQu
# Y29tL0NQUzALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggEBAHGVEulRh1Zp
# ze/d2nyqY3qzeM8GN0CE70uEv8rPAwL9xafDDiBCLK938ysfDCFaKrcFNB1qrpn4
# J6JmvwmqYN92pDqTD/iy0dh8GWLoXoIlHsS6HHssIeLWWywUNUMEaLLbdQLgcseY
# 1jxk5R9IEBhfiThhTWJGJIdjjJFSLK8pieV4H9YLFKWA1xJHcLN11ZOFk362kmf7
# U2GJqPVrlsD0WGkNfMgBsbkodbeZY4UijGHKeZR+WfyMD+NvtQEmtmyl7odRIeRY
# YJu6DC0rbaLEfrvEJStHAgh8Sa4TtuF8QkIoxhhWz0E0tmZdtnR79VYzIi8iNrJL
# okqV2PWmjlIxggTnMIIE4wIBATAiMA4xDDAKBgNVBAMMA2JjbAIQJoAlxDS3d7xJ
# EXeERSQIkTAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUQaaeCfXFhEqz5/jt43ivkcBJF9gwDQYJ
# KoZIhvcNAQEBBQAEggIAETHYIIIwPoWrM7myOMFjWdRoK/LC+HYfHO0NP3XEr6Pr
# UohsYm8k8KCOsPNWPf3goAr5TdwIEDlTCnEnwgtzaA8ht9bSTHOWT9mgKR9qt2F1
# tYqTjlUFnsfve6NdaaYFZnKfW7gaWRmODfs+mAHUEH/u2VQOTO54esgXDc8987Ub
# YFr8XlBrMMhBnxRelqLcQjV5G1UzUhH2bGAnsDr2TDrEm6Hbux6f4uqIicr51idd
# wiICD9ZcMONyFU/28RtB7b4qBXlucXBLBhSRmMPCA+p7Vx2co1BiLNRiithvEzEY
# BP4qiOmxPTS8s7C0yIUjSo/UReI7wTAsIygevTa/Jv/mYC65oMcF9J+mfPoc+bUe
# KeTSdf15ipMogivDKc2Sthmv7mbtDJARFt6d77vHrBpCiSY4k0yOV0EbqVSe7f4g
# Jk/mBivfkxmXZhGGPisDECQX35z7EaQ1h1sLFlkd134cGIFGvr1b3LXGuadtljN/
# WLn6GVINUb5rQrdVdqGGJFeWgSUnb0SsmGEbUH1yUI9moMfpQM/d5KsWo2vsQN84
# IHC9JADoWS1m6CYNlOi8LLUNjpXf4ZTjPAJkatUVPThnIndQLg127b7RA/wT9fRu
# I6vN3t4FEm9orQEyP2VaEqGBnnM+H7WQpz4KOTbFZLu3fpuL2YqacBFzxvqfTQ+h
# ggIgMIICHAYJKoZIhvcNAQkGMYICDTCCAgkCAQEwgYYwcjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIFRpbWVzdGFtcGlu
# ZyBDQQIQDUJK4L46iP9gQCHOFADw3TAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkD
# MQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjEwMTIyMDEwMDA2WjAjBgkq
# hkiG9w0BCQQxFgQU66hYy9QmmE1fjVZw3KSyT/pSSK8wDQYJKoZIhvcNAQEBBQAE
# ggEAgt7xFfK5z/ROs3anIlKAdTSpQIM/CSY9XX2LhOf4mjPMBzC1dj0c62h18Ygl
# YbLWh9lLAa/8MIARcjEvWQAqFyI4awn+iRc/7GwGdvhVSZXSORlUnp08GVgheOLy
# OHWnhD/hAy7HIdkSWjv95MwztA+RnqbFB4Uilgutr1414R4YQpLd06jzEoKXAhUC
# kU0MJltXtq+9E7Tuf+xLKlSaDOS7MjfQHjT2oF6Nzm9p/ydxzSwt9foFssyddhtF
# SYRHRUanBp40Kc3Ww5JWPbinhKU6nQ6UgzTpvIuMx/0xmGxivk/GLPMnjxTcYZvf
# +ef8Q+LPVerHQBq0jDiY6FXM7Q==
# SIG # End signature block
