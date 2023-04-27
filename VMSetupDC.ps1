<#
 .DESCRIPTION
    Setup Domain Controller
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

    # Type of DC
    #[Parameter(Mandatory=$true)]
    [ValidateSet('ADDSForest')]
    [String]$DCType = 'ADDSForest',

    # Name of domain to setup
    [Parameter(Mandatory=$true)]
    [String]$DomainName,

    # Netbios name of domain to setup
    [Parameter(Mandatory=$true)]
    [String]$DomainNetbiosName,

    # Network Id
    [Parameter(Mandatory=$true)]
    [String]$DomainNetworkId,

    # Local admin password on domain controller
    [Parameter(Mandatory=$true)]
    $DomainLocalPassword,

    # DNS
    [String]$DNSReverseLookupZone,
    [TimeSpan]$DNSRefreshInterval,
    [TimeSpan]$DNSNoRefreshInterval,
    [TimeSpan]$DNSScavengingInterval,
    [Bool]$DNSScavengingState,

    # DHCP
    [String]$DHCPScope,
    [String]$DHCPScopeStartRange,
    [String]$DHCPScopeEndRange,
    [String]$DHCPScopeSubnetMask,
    [String]$DHCPScopeDefaultGateway,
    [Array]$DHCPScopeDNSServer,
    [String]$DHCPScopeLeaseDuration,

    # Path to gpos
    [String]$BaselinePath,
    [String]$GPOPath,
    [String]$TemplatePath,

    # Switches
    [ValidateSet($true, $false)]
    [String]$SecureTiering,

    [Switch]$BackupGpo,
    [Switch]$BackupTemplates,
    [Switch]$RemoveAuthenticatedUsersFromUserGpos
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
        @{ Name = 'DomainLocalPassword';    Type = [SecureString] },
        @{ Name = 'DHCPScopeDNSServer';     Type = [Array]        }
    )

    #########
    # Invoke
    #########

    Invoke-Command -ScriptBlock `
    {
        try
        {
            . $PSScriptRoot\s_Begin.ps1
            . $PSScriptRoot\f_CheckContinue.ps1
            . $PSScriptRoot\f_ShouldProcess.ps1
        }
        catch [Exception]
        {
            throw "$_ $( $_.ScriptStackTrace)"
        }

    } -NoNewScope

    #################
    # Define presets
    #################

    $Preset =
    @{
        ADDSForest =
        @{
            # DNS
            DNSReverseLookupZone = (($DomainNetworkId -split '\.')[-1..-3] -join '.') + '.in-addr.arpa'
            DNSRefreshInterval = '7.00:00:00'
            DNSNoRefreshInterval = '7.00:00:00'
            DNSScavengingInterval = '0.01:00:00'
            DNSScavengingState = $true

            # DHCP
            DHCPScope = "$DomainNetworkId.0"
            DHCPScopeStartRange = "$DomainNetworkId.154"
            DHCPScopeEndRange = "$DomainNetworkId.254"
            DHCPScopeSubnetMask = '255.255.255.0'
            DHCPScopeDefaultGateway = "$DomainNetworkId.1"
            DHCPScopeDNSServer = @("$DomainNetworkId.10")
            DHCPScopeLeaseDuration = '14.00:00:00'
        }
    }

    # Set preset values for missing parameters
    foreach ($Var in $MyInvocation.MyCommand.Parameters.Keys)
    {
        if ($Preset.Item($DCType).ContainsKey($Var) -and
            -not (Get-Variable -Name $Var).Value)
        {
            Set-Variable -Name $Var -Value $Preset.Item($DCType).Item($Var)
        }
    }

    #######
    # Copy
    #######

    $Paths = @()

    if ($BaselinePath)
    {
        $Paths += @{ Name = 'MSFT Baselines';         Source = $BaselinePath;  Destination = 'Baseline' }
    }

    if ($GpoPath)
    {
        $Paths += @{ Name = 'Group Policy Objects';   Source = $GpoPath;       Destination = 'Gpo' }
    }

    if ($TemplatePath)
    {
        $Paths += @{ Name = 'Certificate Templates';  Source = $TemplatePath;  Destination = 'Templates' }
    }

    if ($Paths.Count -ne 0)
    {
        # Initialize
        $SessionSplat = @{}
        $ToSessionSplat = @{}

        # Check session
        if ($Session -and $Session.State -eq 'Opened')
        {
            # Set session splats
            $SessionSplat.Add('Session', $Session)
            $ToSessionSplat.Add('ToSession', $Session)
        }

        $DCTemp = Invoke-Command @SessionSplat -ScriptBlock {

            if ($Host.Name -eq 'ServerRemoteHost')
            {
                $UsingPaths = $Using:Paths
            }
            else
            {
                $UsingPaths = $Paths
            }

            foreach ($Path in $UsingPaths)
            {
                if ($Path.Source -and (Test-Path -Path "$env:TEMP\$($Path.Destination)"))
                {
                    Remove-Item -Path "$env:TEMP\$($Path.Destination)" -Recurse -Force
                }
            }

            Write-Output -InputObject $env:TEMP
        }

        foreach ($Path in $Paths)
        {
            # Check if source exist
            if ($Path.Source -and (Test-Path -Path $Path.Source) -and
                (ShouldProcess @WhatIfSplat -Message "Copying `"$($Path.Name)`" to `"$DCTemp\$($Path.Destination)`"." @VerboseSplat))
            {
                Copy-Item @ToSessionSplat -Path $Path.Source -Destination "$DCTemp\$($Path.Destination)" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
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
        $UpdatedObjects = @{}

        # Get base DN
        $BaseDN = Get-BaseDn -DomainName $DomainName

        # Set friendly netbios name
        $DomainPrefix = $DomainNetbiosName.Substring(0, 1).ToUpper() + $DomainNetbiosName.Substring(1)

        ############
        # Fucntions
        ############

        function ConvertTo-CanonicalName
        {
            param
            (
                [Parameter(Mandatory=$true)]
                [ValidateNotNullOrEmpty()]
                [string]$DistinguishedName
            )

            $CN = [string]::Empty
            $DC = [string]::Empty

            foreach ($item in ($DistinguishedName.split(',')))
            {
                if ($item -match 'DC=')
                {
                    $DC += $item.Replace('DC=', '') + '.'
                }
                else
                {
                    $CN = '/' + $item.Substring(3) + $CN
                }
            }

            Write-Output -InputObject ($DC.Trim('.') + $CN)
        }

        # ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗
        # ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║
        # ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║
        # ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║
        # ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
        # ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝

        # Check if RSAT-ADCS-Mgmt is installed
        if (((Get-WindowsFeature -Name RSAT-ADCS-Mgmt).InstallState -notmatch 'Install') -and
            (ShouldProcess @WhatIfSplat -Message "Installing RSAT-ADCS-Mgmt feature." @VerboseSplat))
        {
            Install-WindowsFeature -Name RSAT-ADCS-Mgmt > $null
        }

        # Check if DHCP windows feature is installed
        if (((Get-WindowsFeature -Name DHCP).InstallState -notmatch 'Install') -and
            (ShouldProcess @WhatIfSplat -Message "Installing DHCP Windows feature." @VerboseSplat))
        {
            Install-WindowsFeature -Name DHCP -IncludeManagementTools > $null
        }

        # Check if ADDS feature is installed
        if (((Get-WindowsFeature -Name AD-Domain-Services).InstallState -notmatch 'Install') -and
            (ShouldProcess @WhatIfSplat -Message "Installing AD-Domain-Services feature." @VerboseSplat))
        {
            Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools > $null
        }

        # Check if ADDS is installed
        if (-not (Test-Path -Path "$env:SystemRoot\SYSVOL" -ErrorAction SilentlyContinue) -and
           (ShouldProcess @WhatIfSplat -Message "Installing ADDS forest." @VerboseSplat))
        {
            Install-ADDSForest -DomainName $DomainName `
                               -DomainNetbiosName $DomainNetbiosName `
                               -SafeModeAdministratorPassword $DomainLocalPassword `
                               -NoRebootOnCompletion `
                               -Force > $null

            # Set result
            $Result.Add('WaitingForReboot', $true)

            # Output result
            Write-Output -InputObject $Result

            # Restart message
            Write-Warning -Message "Rebooting `"$ENV:ComputerName`", rerun this script to continue setup..."

            # Restart
            Restart-Computer -Force

            return
        }
        else
        {
            # ██████╗ ███╗   ██╗███████╗
            # ██╔══██╗████╗  ██║██╔════╝
            # ██║  ██║██╔██╗ ██║███████╗
            # ██║  ██║██║╚██╗██║╚════██║
            # ██████╔╝██║ ╚████║███████║
            # ╚═════╝ ╚═╝  ╚═══╝╚══════╝

            # Check if DNS server is installed and running
            if ((Get-Service -Name DNS -ErrorAction SilentlyContinue) -and (Get-Service -Name DNS).Status -eq 'Running')
            {
                #########
                # Server
                #########

                # Checking DNS server scavenging state
                if (((Get-DnsServerScavenging).ScavengingState -ne $DNSScavengingState) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server scavenging state to $DNSScavengingState." @VerboseSplat))
                {
                    Set-DnsServerScavenging -ScavengingState $DNSScavengingState -ApplyOnAllZones
                }

                # Checking DNS server refresh interval
                if (((Get-DnsServerScavenging).RefreshInterval -ne $DNSRefreshInterval) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server refresh interval to $DNSRefreshInterval." @VerboseSplat))
                {
                    Set-DnsServerScavenging -RefreshInterval $DNSRefreshInterval -ApplyOnAllZones
                }

                # Checking DNS server no refresh interval
                if (((Get-DnsServerScavenging).NoRefreshInterval -ne $DNSNoRefreshInterval) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server no refresh interval to $DNSNoRefreshInterval." @VerboseSplat))
                {
                    Set-DnsServerScavenging -NoRefreshInterval $DNSNoRefreshInterval -ApplyOnAllZones
                }

                # Checking DNS server scavenging interval
                if (((Get-DnsServerScavenging).ScavengingInterval -ne $DNSScavengingInterval) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server scavenging interval to $DNSScavengingInterval." @VerboseSplat))
                {
                    Set-DnsServerScavenging -ScavengingInterval $DNSScavengingInterval -ApplyOnAllZones
                }

                ##########
                # Reverse
                ##########

                # Checking reverse lookup zone
                if (-not (Get-DnsServerZone -Name $DNSReverseLookupZone -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Adding DNS server reverse lookup zone `"$DNSReverseLookupZone`"." @VerboseSplat))
                {
                    Add-DnsServerPrimaryZone -Name $DNSReverseLookupZone -ReplicationScope Domain -DynamicUpdate Secure
                }

                ######
                # CAA
                ######

                # FIX
                # Check if "\# Length" is needed
                # Array of allowed CAs
                # Replace = Clone and add : https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverresourcerecord?view=win10-ps

                # Get CAA record
                $CAA = Get-DnsServerResourceRecord -ZoneName $DomainName -Name $DomainName -Type 257

                # RData with flag = 0, tag length = 5, tag = issue and value = $DomainName
                # See https://tools.ietf.org/html/rfc6844#section-5
                $RData = "00056973737565$($DomainName.ToCharArray().ToInt32($null).ForEach({ '{0:X}' -f $_ }) -join '')"

                # Checking CAA record
                if ((-not $CAA -or $CAA.RecordData.Data -ne $RData) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting `"$RData`" to CAA record." @VerboseSplat))
                {
                    Add-DnsServerResourceRecord -ZoneName $DomainName -Name $DomainName -Type 257 -RecordData $RData
                }

                ##########
                # Records
                ##########

                # Initialize
                $Server = @{}

                # Define server records to get
                $ServerNames = @('ADFS', 'AS', 'WAP', 'curity')

                foreach ($Name in $ServerNames)
                {
                    # Get dns record
                    $ServerHostName = Get-DnsServerResourceRecord -ZoneName $DomainName -RRType A | Where-Object { $_.HostName -like "*$Name*" -and $_.Timestamp -notlike $null } | Select-Object -ExpandProperty HostName -First 1

                    if ($ServerHostName)
                    {
                        $Server.Add($Name, $ServerHostName)
                    }
                }

                # Initialize
                $DnsRecords = @()

                # Check if AS server exist
                if ($Server.AS)
                {
                    $DnsRecords += @{ Name = 'pki';                     Type = 'CNAME';  Data = "$($Server.AS).$DomainName." }
                }

                # Check if ADFS server exist
                if ($Server.ADFS)
                {
                    $DnsRecords += @{ Name = 'adfs';                    Type = 'A';      Data = "$DomainNetworkId.150" }
                    $DnsRecords += @{ Name = 'certauth.adfs';           Type = 'A';      Data = "$DomainNetworkId.150" }
                    $DnsRecords += @{ Name = 'enterpriseregistration';  Type = 'A';      Data = "$DomainNetworkId.150" }
                }

                # Check if WAP server exist
                if ($Server.WAP)
                {
                    $DnsRecords += @{ Name = 'wap';                     Type = 'A';      Data = "$DomainNetworkId.100" }
                }

                # Check if UBU server exist
                if ($Server.curity)
                {
                    $DnsRecords += @{ Name = 'curity';                  Type = 'CNAME';  Data = "$($Server.AS).$DomainName." }
                }

                foreach($Rec in $DnsRecords)
                {
                    $ResourceRecord = Get-DnsServerResourceRecord -ZoneName $DomainName -Name $Rec.Name -RRType $Rec.Type -ErrorAction SilentlyContinue

                    switch($Rec.Type)
                    {
                        'A'
                        {
                            $RecordType = @{ A = $true; IPv4Address = $Rec.Data; }
                            $RecordData = $ResourceRecord.RecordData.IPv4Address
                        }
                        'CNAME'
                        {
                            $RecordType = @{ CName = $true; HostNameAlias = $Rec.Data; }
                            $RecordData = $ResourceRecord.RecordData.HostnameAlias
                        }
                    }

                    if ($RecordData -ne $Rec.Data -and
                        (ShouldProcess @WhatIfSplat -Message "Adding $($Rec.Type) `"$($Rec.Name)`" -> `"$($Rec.Data)`"." @VerboseSplat))
                    {
                        Add-DnsServerResourceRecord -ZoneName $DomainName -Name $Rec.Name @RecordType
                    }
                }
            }

            # ██████╗ ██╗  ██╗ ██████╗██████╗
            # ██╔══██╗██║  ██║██╔════╝██╔══██╗
            # ██║  ██║███████║██║     ██████╔╝
            # ██║  ██║██╔══██║██║     ██╔═══╝
            # ██████╔╝██║  ██║╚██████╗██║
            # ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝

            # Check if DHCP server is installed and running
            if ((Get-Service -Name DHCPServer).Status -eq 'Running')
            {
                # Authorize DHCP server
                if ((Get-DhcpServerSetting).IsAuthorized -eq $false -and
                    (ShouldProcess @WhatIfSplat -Message "Authorizing DHCP server." @VerboseSplat))
                {
                    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
                }

                # Set conflict detection attempts
                if ((Get-DhcpServerSetting).ConflictDetectionAttempts -ne 1 -and
                    (ShouldProcess @WhatIfSplat -Message "Setting DHCP server conflict detection attempts to 1." @VerboseSplat))
                {
                    Set-DhcpServerSetting -ConflictDetectionAttempts 1
                }

                # Dynamically update DNS
                if ((Get-DhcpServerv4DnsSetting).DynamicUpdates -ne 'Always' -and
                    (ShouldProcess @WhatIfSplat -Message "Enable DHCP always dynamically update DNS records." @VerboseSplat))
                {
                    Set-DhcpServerv4DnsSetting -DynamicUpdates Always
                }

                # Dynamically update DNS for older clients
                if ((Get-DhcpServerv4DnsSetting).UpdateDnsRRForOlderClients -ne $true -and
                    (ShouldProcess @WhatIfSplat -Message "Enable DHCP dynamically update DNS records for older clients." @VerboseSplat))
                {
                    Set-DhcpServerv4DnsSetting -UpdateDnsRRForOlderClients $true
                }

                # Scope
                if (-not (Get-DhcpServerv4Scope -ScopeId $DHCPScope -ErrorAction SilentlyContinue) -and
                    (ShouldProcess @WhatIfSplat -Message "Adding DHCP scope $DHCPScope ($DHCPScopeStartRange-$DHCPScopeEndRange/$DHCPScopeSubnetMask) with duration $DHCPScopeLeaseDuration" @VerboseSplat))
                {
                    Add-DhcpServerv4Scope -Name $DHCPScope -StartRange $DHCPScopeStartRange -EndRange $DHCPScopeEndRange -SubnetMask $DHCPScopeSubnetMask -LeaseDuration $DHCPScopeLeaseDuration
                }

                # Range
                if (((((Get-DhcpServerv4Scope).StartRange -ne $DHCPScopeStartRange) -or
                       (Get-DhcpServerv4Scope).EndRange -ne $DHCPScopeEndRange)) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope range $DHCPScopeStartRange-$DHCPScopeEndRange" @VerboseSplat))
                {
                    Set-DhcpServerv4Scope -ScopeID $DHCPScope -StartRange $DHCPScopeStartRange -EndRange $DHCPScopeEndRange
                }

                # SubnetMask
                if (((Get-DhcpServerv4Scope).SubnetMask -ne $DHCPScopeSubnetMask) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope subnet mask to $DHCPScopeSubnetMask" @VerboseSplat))
                {
                    Set-DhcpServerv4Scope -ScopeID $DHCPScope -SubnetMask $DHCPScopeSubnetMask
                }

                # Lease duration
                if (((Get-DhcpServerv4Scope).LeaseDuration -ne $DHCPScopeLeaseDuration) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope lease duration to $DHCPScopeLeaseDuration" @VerboseSplat))
                {
                    Set-DhcpServerv4Scope -ScopeID $DHCPScope -LeaseDuration $DHCPScopeLeaseDuration
                }

                # DNS domain
                if (-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 15 -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope DNS Domain to $env:USERDNSDOMAIN" @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeID $DHCPScope -DNSDomain $env:USERDNSDOMAIN
                }

                # DNS server
                if ((-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 6 -ErrorAction SilentlyContinue) -or
                    @(Compare-Object -ReferenceObject $DHCPScopeDNSServer -DifferenceObject (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 6).Value -SyncWindow 0).Length -ne 0) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope DNS to $DHCPScopeDNSServer" @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeID $DHCPScope -DNSServer $DHCPScopeDNSServer
                }

                # Gateway
                if (-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 3 -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope router to $DHCPScopeDefaultGateway" @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeID $DHCPScope -Router $DHCPScopeDefaultGateway
                }

                # Disable netbios
                if (-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 1 -VendorClass 'Microsoft Windows 2000 Options' -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope option to disable netbios." @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeId $DHCPScope -VendorClass 'Microsoft Windows 2000 Options' -OptionId 1 -Value 2
                }

                ###############
                # Reservations
                ###############

                $DhcpReservations =
                @(
                    @{ Name = "WAP";    IPAddress = "$DomainNetworkId.100"; }
                    @{ Name = "ADFS";   IPAddress = "$DomainNetworkId.150"; }
                    @{ Name = "AS";     IPAddress = "$DomainNetworkId.200"; }
                    @{ Name = "curity"; IPAddress = "$DomainNetworkId.250"; }
                )

                foreach($Reservation in $DhcpReservations)
                {
                    # Set reservation name
                    $ReservationName = "$($Server.Item($Reservation.Name)).$DomainName"

                    # Get clientId from dhcp active leases
                    $ClientId = (Get-DhcpServerv4Lease -ScopeID $DHCPScope | Where-Object { $_.HostName -eq $ReservationName -and $_.AddressState -eq 'Active' } | Sort-Object -Property LeaseExpiryTime | Select-Object -Last 1).ClientId

                    # Check if client id exist
                    if ($ClientId)
                    {
                        $CurrentReservation = Get-DhcpServerv4Reservation -ScopeId $DHCPScope | Where-Object { $_.Name -eq $ReservationName -and $_.IPAddress -eq $Reservation.IPAddress }

                        if ($CurrentReservation)
                        {
                            if ($CurrentReservation.ClientId -ne $ClientId -and
                               (ShouldProcess @WhatIfSplat -Message "Updating DHCP reservation `"$($ReservationName)`" `"$($Reservation.IPAddress)`" to ($ClientID)." @VerboseSplat))
                            {
                                Set-DhcpServerv4Reservation -Name $ReservationName -IPAddress $Reservation.IPAddress -ClientId $ClientID

                                $UpdatedObjects.Add($Server.Item($Reservation.Name), $true)
                            }
                        }
                        elseif (ShouldProcess @WhatIfSplat -Message "Adding DHCP reservation `"$($ReservationName)`" `"$($Reservation.IPAddress)`" for ($ClientId)." @VerboseSplat)
                        {
                            Add-DhcpServerv4Reservation -ScopeId $DHCPScope -Name $ReservationName -IPAddress $Reservation.IPAddress -ClientId $ClientID

                            $UpdatedObjects.Add($Server.Item($Reservation.Name), $true)
                        }
                    }
                }
            }

            # ██╗    ██╗██╗███╗   ██╗██╗   ██╗███████╗██████╗
            # ██║    ██║██║████╗  ██║██║   ██║██╔════╝██╔══██╗
            # ██║ █╗ ██║██║██╔██╗ ██║██║   ██║█████╗  ██████╔╝
            # ██║███╗██║██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██╔══██╗
            # ╚███╔███╔╝██║██║ ╚████║ ╚████╔╝ ███████╗██║  ██║
            #  ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝

            $WinBuilds =
            [ordered]@{
               # Build
                '20348' = # Windows Server 2022
                @{
                    Version = '21H2'
                    Server = 'Windows Server 2022 21H2'
                    Baseline =
                    @(
                        'MSFT Windows Server 2022 - Domain Security'
                        'MSFT Windows Server 2022 - Defender Antivirus'
                        'MSFT Internet Explorer 11 21H2 (Windows Server 2022) - Computer'
                    )
                    UserBaseline =
                    @(
                        'MSFT Internet Explorer 11 21H2 (Windows Server 2022) - User'
                    )
                    ServerBaseline =
                    @(
                        'MSFT Windows Server 2022 - Member Server'
                    )
                    DCBaseline =
                    @(
                        'MSFT Windows Server 2022 - Domain Controller'
                    )
                }
                '22000' = # Windows 11
                @{
                    Version = '21H2'
                    Workstation = 'Windows 11 21H2'
                    Baseline =
                    @(
                        'MSFT Windows 11 - Domain Security'
                        'MSFT Windows 11 - Defender Antivirus'
                        'MSFT Internet Explorer 11 21H2 - Computer'
                    )
                    UserBaseline =
                    @(
                        'MSFT Internet Explorer 11 21H2 - User'
                        'MSFT Windows 11 - User'
                    )
                    ComputerBaseline =
                    @(
                        'MSFT Windows 11 - Computer'
                    )
                }
                '22621' = # Windows 11
                @{
                    Version = '22H2'
                    Workstation = 'Windows 11 22H2'

                    # FIX
                    # Add baselines
                }
            }

            #  ██████╗ ██╗   ██╗
            # ██╔═══██╗██║   ██║
            # ██║   ██║██║   ██║
            # ██║   ██║██║   ██║
            # ╚██████╔╝╚██████╔╝
            #  ╚═════╝  ╚═════╝

            $RedirUsr = 'Redirect Users'
            $RedirCmp = 'Redirect Computers'

            $OrganizationalUnits =
            @(
                @{ Name = $DomainName;                                                            Path = "$BaseDN"; }
                @{ Name = $RedirUsr;                                               Path = "OU=$DomainName,$BaseDN"; }
                @{ Name = $RedirCmp;                                               Path = "OU=$DomainName,$BaseDN"; }
            )

            ###########
            # Tier 0-2
            ###########

            foreach($Tier in @(0,1,2))
            {
                $OrganizationalUnits += @{ Name = "Tier $Tier";                                            Path = "OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{  Name = 'Administrators';                         Path = "OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{  Name = 'Groups';                                 Path = "OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{   Name = 'Access Control';              Path = "OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{   Name = 'Computers';                   Path = "OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{   Name = 'Local Administrators';        Path = "OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{   Name = 'Remote Desktop Access';       Path = "OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{   Name = 'Security Roles';              Path = "OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{  Name = 'Users';                                  Path = "OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
                $OrganizationalUnits += @{  Name = 'Computers';                              Path = "OU=Tier $Tier,OU=$DomainName,$BaseDN"; }
            }

            #########
            # Tier 0
            #########

            $OrganizationalUnits += @{ Name = 'Certificate Authority Templates';   Path = "OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"; }
            $OrganizationalUnits += @{ Name = 'Group Managed Service Accounts';    Path = "OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"; }
            $OrganizationalUnits += @{ Name = 'Service Accounts';                            Path = "OU=Tier 0,OU=$DomainName,$BaseDN"; }

            # Server builds
            foreach ($Build in $WinBuilds.GetEnumerator())
            {
                if ($Build.Value.Server)
                {
                    $ServerName = $Build.Value.Server

                    $OrganizationalUnits += @{ Name = $ServerName;                                Path = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"; }
                    $OrganizationalUnits += @{ Name = 'Certificate Authorities';   Path = "OU=$ServerName,OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"; }
                    $OrganizationalUnits += @{ Name = 'Federation Services';       Path = "OU=$ServerName,OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"; }
                    $OrganizationalUnits += @{ Name = 'Web Servers';               Path = "OU=$ServerName,OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"; }
                }
            }

            #########
            # Tier 1
            #########

            $OrganizationalUnits += @{ Name = 'Group Managed Service Accounts';    Path = "OU=Groups,OU=Tier 1,OU=$DomainName,$BaseDN"; }
            $OrganizationalUnits += @{ Name = 'Service Accounts';                            Path = "OU=Tier 1,OU=$DomainName,$BaseDN"; }

            # Server builds
            foreach ($Build in $WinBuilds.GetEnumerator())
            {
                if ($Build.Value.Server)
                {
                    $ServerName = $Build.Value.Server

                    $OrganizationalUnits += @{ Name = $ServerName;                                Path = "OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN"; }
                    $OrganizationalUnits += @{ Name = 'Application Servers';       Path = "OU=$ServerName,OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN"; }
                    $OrganizationalUnits += @{ Name = 'Web Application Proxy';     Path = "OU=$ServerName,OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN"; }
                    $OrganizationalUnits += @{ Name = 'Web Servers';               Path = "OU=$ServerName,OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN"; }
                }
            }

            #########
            # Tier 2
            #########

            # Workstation builds
            foreach ($Build in $WinBuilds.GetEnumerator())
            {
                if ($Build.Value.Workstation)
                {
                    $OrganizationalUnits += @{ Name = $Build.Value.Workstation;    Path = "OU=Computers,OU=Tier 2,OU=$DomainName,$BaseDN"; }
                }
            }

            # Build ou
            foreach($Ou in $OrganizationalUnits)
            {
                # Check if OU exist
                if (-not (Get-ADOrganizationalUnit -SearchBase $Ou.Path -Filter "Name -like '$($Ou.Name)'" -SearchScope OneLevel -ErrorAction SilentlyContinue) -and
                    (ShouldProcess @WhatIfSplat -Message "Creating OU=$($Ou.Name)" @VerboseSplat))
                {
                    # Create OU
                    New-ADOrganizationalUnit -Name $Ou.Name -Path $Ou.Path

                    if ($Ou.Path -eq "OU=$DomainName,$BaseDN")
                    {
                        if ($Ou.Name -eq $RedirCmp)
                        {
                            Write-Verbose -Message "Redirecting Computers to OU=$($Ou.Name),$($Ou.Path)" @VerboseSplat
                            redircmp "OU=$($Ou.Name),$($Ou.Path)" > $null
                        }

                        if ($Ou.Name -eq $RedirUsr)
                        {
                            Write-Verbose -Message "Redirecting Users to OU=$($Ou.Name),$($Ou.Path)" @VerboseSplat
                            redirusr "OU=$($Ou.Name),$($Ou.Path)" > $null
                        }
                    }
                }
            }

            # ██╗   ██╗███████╗███████╗██████╗ ███████╗
            # ██║   ██║██╔════╝██╔════╝██╔══██╗██╔════╝
            # ██║   ██║███████╗█████╗  ██████╔╝███████╗
            # ██║   ██║╚════██║██╔══╝  ██╔══██╗╚════██║
            # ╚██████╔╝███████║███████╗██║  ██║███████║
            #  ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝

            $Users =
            @(
                # Domain administrator
                @{
                    Name = 'Admin'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @('Domain Admins', 'Protected Users')
                }

                # Administrators
                @{
                    Name = 'Tier0Admin'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }
                @{
                    Name = 'Tier1Admin'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }
                @{
                    Name = 'Tier2Admin'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }

                # Service accounts
                @{
                    Name = 'AzADDSConnector'
                    Password = 'PHptNlPKHxL0K355QsXIJulLDqjAhmfABbsWZoHqc0nnOd6p'
                    AccountNotDelegated = $false
                    MemberOf = @()
                }

                # Join domain account
                @{
                    Name = 'JoinDomain'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }

                # Users
                @{
                    Name = 'Alice'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }
                @{
                    Name = 'Bob'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }
                @{
                    Name = 'Eve'
                    Password = 'P455w0rd'
                    AccountNotDelegated = $true
                    MemberOf = @()
                }
            )

            # Setup users
            foreach ($User in $Users)
            {
                if (-not (Get-ADUser -Filter "Name -eq '$($User.Name)'" -SearchBase "$BaseDN" -SearchScope Subtree -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Creating user `"$($User.Name)`"." @VerboseSplat))
                {
                    New-ADUser -Name $User.Name -DisplayName $User.Name -SamAccountName $User.Name -UserPrincipalName "$($User.Name)@$DomainName" -EmailAddress "$($User.Name)@$DomainName" -AccountPassword (ConvertTo-SecureString -String $User.Password -AsPlainText -Force) -ChangePasswordAtLogon $false -PasswordNeverExpires $true -Enabled $true -AccountNotDelegated $User.AccountNotDelegated

                    if ($User.MemberOf)
                    {
                        Add-ADPrincipalGroupMembership -Identity $User.Name -MemberOf $User.MemberOf
                    }
                }
            }

            # FIX Set sensitive and cannot be delegated

            # ███╗   ███╗ ██████╗ ██╗   ██╗███████╗
            # ████╗ ████║██╔═══██╗██║   ██║██╔════╝
            # ██╔████╔██║██║   ██║██║   ██║█████╗
            # ██║╚██╔╝██║██║   ██║╚██╗ ██╔╝██╔══╝
            # ██║ ╚═╝ ██║╚██████╔╝ ╚████╔╝ ███████╗
            # ╚═╝     ╚═╝ ╚═════╝   ╚═══╝  ╚══════╝

            $MoveObjects =
            @(
                # Domain controllers
                @{
                    Filter = "Name -like 'DC*' -and ObjectCategory -eq 'Computer'"
                    TargetPath = "OU=Domain Controllers,$BaseDN"
                }

                # Domain Admin
                @{
                    Filter = "Name -like 'Admin' -and ObjectCategory -eq 'Person'"
                    TargetPath = "CN=Users,$BaseDN"
                }

                # Join domain account
                @{
                    Filter = "Name -like 'JoinDomain' -and ObjectCategory -eq 'Person'"
                    TargetPath = "CN=Users,$BaseDN"
                }

                #########
                # Tier 0
                #########

                # Admin
                @{
                    Filter = "Name -like 'Tier0Admin' -and ObjectCategory -eq 'Person'"
                    TargetPath = "OU=Administrators,OU=Tier 0,OU=$DomainName,$BaseDN"
                }

                # Computers
                @{
                    Filter = "Name -like 'CA*' -and ObjectCategory -eq 'Computer'"
                    TargetPath = "OU=Certificate Authorities,%ServerPath%,OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                }

                @{
                    Filter = "Name -like 'ADFS*' -and ObjectCategory -eq 'Computer'"
                    TargetPath = "OU=Federation Services,%ServerPath%,OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                }

                @{
                    Filter = "Name -like 'AS*' -and ObjectCategory -eq 'Computer'"
                    TargetPath = "OU=Web Servers,%ServerPath%,OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                }

                # Service accounts
                @{
                    Filter = "Name -like 'Az*' -and ObjectCategory -eq 'Person'"
                    TargetPath = "OU=Service Accounts,OU=Tier 0,OU=$DomainName,$BaseDN"
                }

                @{
                    Filter = "Name -like 'Svc*' -and ObjectCategory -eq 'Person'"
                    TargetPath = "OU=Service Accounts,OU=Tier 0,OU=$DomainName,$BaseDN"
                }

                #########
                # Tier 1
                #########

                # Admin
                @{
                    Filter = "Name -like 'Tier1Admin' -and ObjectCategory -eq 'Person'"
                    TargetPath = "OU=Administrators,OU=Tier 1,OU=$DomainName,$BaseDN"
                }

                # Computers
                @{
                    Filter = "Name -like 'WAP*' -and ObjectCategory -eq 'Computer'"
                    TargetPath = "OU=Web Application Proxy,%ServerPath%,OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN"
                }

                #########
                # Tier 2
                #########

                # Admin
                @{
                    Filter = "Name -like 'Tier2Admin' -and ObjectCategory -eq 'Person'"
                    TargetPath = "OU=Administrators,OU=Tier 2,OU=$DomainName,$BaseDN"
                }

                # Computers
                @{
                    Filter = "Name -like 'WIN*' -and ObjectCategory -eq 'Computer'"
                    TargetPath = "%WorkstationPath%,OU=Computers,OU=Tier 2,OU=$DomainName,$BaseDN"
                }

                # Users
                @{
                    Filter = "(Name -eq 'Alice' -or Name -eq 'Bob' -or Name -eq 'Eve') -and ObjectCategory -eq 'Person'"
                    TargetPath = "OU=Users,OU=Tier 2,OU=$DomainName,$BaseDN"
                }
            )

            # Move objects
            foreach ($Obj in $MoveObjects)
            {
                # Set targetpath
                $TargetPath = $Obj.TargetPath

                # Get object
                $ADObjects = Get-ADObject -Filter $Obj.Filter -SearchBase "OU=$DomainName,$BaseDN" -SearchScope Subtree -Properties cn

                # Itterate if multiple
                foreach ($CurrentObj in $ADObjects)
                {
                    # Check if computer
                    if ($CurrentObj.ObjectClass -eq 'Computer')
                    {
                        # Get computer build
                        $Build = $CurrentObj | Get-ADComputer -Property OperatingSystemVersion | Select-Object -ExpandProperty OperatingSystemVersion | Where-Object {
                            $_ -match "\((\d+)\)"
                        } | ForEach-Object { $Matches[1] }

                        if (-not $Build)
                        {
                            Write-Warning -Message "Did'nt find build for $($CurrentObj.Name), skiping move."
                            continue
                        }

                        # Set targetpath with server version
                        if ($Obj.TargetPath -match '%ServerPath%')
                        {
                            if(-not $WinBuilds.Item($Build).Server)
                            {
                                Write-Warning -Message "Missing winver server entry for build $Build, skiping move."
                                continue
                            }

                            $TargetPath = $Obj.TargetPath.Replace('%ServerPath%', "OU=$($WinBuilds.Item($Build).Server)")
                        }

                        # Set targetpath with windows version
                        if ($Obj.TargetPath -match '%WorkstationPath%')
                        {
                            if(-not $WinBuilds.Item($Build).Workstation)
                            {
                                Write-Warning -Message "Missing winver workstation entry for build $Build, skiping move."
                                continue
                            }

                            $TargetPath = $Obj.TargetPath.Replace('%WorkstationPath%', "OU=$($WinBuilds.Item($Build).Workstation)")
                        }
                    }

                    # Check if object is in targetpath
                    if ($CurrentObj -and $CurrentObj.DistinguishedName -notlike "*$TargetPath" -and
                       (ShouldProcess @WhatIfSplat -Message "Moving object `"$($CurrentObj.Name)`" to `"$TargetPath`"." @VerboseSplat))
                    {
                        # Move object
                        $CurrentObj | Move-ADObject -TargetPath $TargetPath
                    }
                }
            }

            #  ██████╗ ██████╗  ██████╗ ██╗   ██╗██████╗ ███████╗
            # ██╔════╝ ██╔══██╗██╔═══██╗██║   ██║██╔══██╗██╔════╝
            # ██║  ███╗██████╔╝██║   ██║██║   ██║██████╔╝███████╗
            # ██║   ██║██╔══██╗██║   ██║██║   ██║██╔═══╝ ╚════██║
            # ╚██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║     ███████║
            #  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚══════╝

            ##########
            # Kds Key
            ##########

            if (-not (Get-KdsRootKey) -and
                (ShouldProcess @WhatIfSplat -Message "Adding KDS root key." @VerboseSplat))
            {
                # DC computer object must not be moved from OU=Domain Controllers
                Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) > $null
            }

            ################
            # Global Groups
            ################

            # Initialize
            $DomainGroups = @()

            # Name              : Name & display name
            # Path              : OU location
            # Filter            : Filter to get members
            # SearchBase        : Where to look for members
            # SearchScope       : Base/OneLevel/Subtree to look for members
            # MemberOf          : Member of these groups

            #########
            # Tier 0
            #########

            # Administrators
            foreach($Tier in @(0, 1, 2))
            {
                # Administrators
                $DomainGroups +=
                @{
                    Name                = "Tier $Tier - Administrators"
                    Scope               = 'Global'
                    Path                = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like '*' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "OU=Administrators,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                    MemberOf          = @('Protected Users')
                }
            }

            #############
            # Tier 0 + 1
            #############

            # Servers, server by build
            foreach($Tier in @(0, 1))
            {
                $DomainGroups +=
                @{
                    Name                = "Tier $Tier - Computers"
                    Scope               = 'Global'
                    Path                = "OU=Computers,OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like '*' -and ObjectCategory -eq 'Computer' -and OperatingSystem -like '*Server*'"
                            SearchBase  = "OU=Computers,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }

                # Server by build
                foreach ($Build in $WinBuilds.GetEnumerator())
                {
                    if ($Build.Value.Server)
                    {
                        $DomainGroups +=
                        @{
                            Name                = "Tier $Tier - $($Build.Value.Server)"
                            Scope               = 'Global'
                            Path                = "OU=Computers,OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                            Members             =
                            @(
                                @{
                                    Filter      = "Name -like '*' -and ObjectCategory -eq 'Computer' -and OperatingSystem -like '*Server*' -and OperatingSystemVersion -like '*$($Build.Key)*'"
                                    SearchBase  = "OU=Computers,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                                    SearchScope = 'Subtree'
                                }
                            )
                        }
                    }
                }
            }

            #################
            # Tier 0 + 1 + 2
            #################

            # Users
            foreach($Tier in @(0, 1, 2))
            {
                $DomainGroups +=
                @{
                    Name                = "Tier $Tier - Users"
                    Scope               = 'Global'
                    Path                = "OU=Security Roles,OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like '*' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "OU=Users,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            }

            # Local admins, rdp access
            foreach($Tier in @(0, 1, 2))
            {
                foreach($Computer in (Get-ADObject -Filter "Name -like '*' -and ObjectCategory -eq 'Computer'" -SearchBase "OU=Computers,OU=Tier $Tier,OU=$DomainName,$BaseDN" -SearchScope Subtree ))
                {

                    $DomainGroups +=
                    @{
                        Name              = "Tier $Tier - Local Admin - $($Computer.Name)"
                        Scope             = 'Global'
                        Path              = "OU=Local Administrators,OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                        MemberOf          = @('Protected Users')
                    }

                    $DomainGroups +=
                    @{
                        Name                = "Tier $Tier - Rdp Access - $($Computer.Name)"
                        Scope               = 'Global'
                        Path                = "OU=Remote Desktop Access,OU=Groups,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                        Members             =
                        @(
                            @{
                                Filter      = "Name -like '*' -and ObjectCategory -eq 'Person'"
                                SearchBase  = "OU=Users,OU=Tier $Tier,OU=$DomainName,$BaseDN"
                                SearchScope = 'OneLevel'
                            }
                        )
                    }
                }
            }

            #########
            # Tier 2
            #########

            # Workstations
            $DomainGroups +=
            @{
                Name                = 'Tier 2 - Computers'
                Scope               = 'Global'
                Path                = "OU=Computers,OU=Groups,OU=Tier 2,OU=$DomainName,$BaseDN"
                Members             =
                @(
                    @{
                        Filter      = "Name -like '*' -and ObjectCategory -eq 'Computer' -and OperatingSystem -notlike '*Server*'"
                        SearchBase  = "OU=Computers,OU=Tier 2,OU=$DomainName,$BaseDN"
                        SearchScope = 'Subtree'
                    }
                )
            }

            # Workstation by build
            foreach ($Build in $WinBuilds.GetEnumerator())
            {
                if ($Build.Value.Workstation)
                {
                    $DomainGroups +=
                    @{
                        Name                = "Tier 2 - $($Build.Value.Workstation)"
                        Scope               = 'Global'
                        Path                = "OU=Computers,OU=Groups,OU=Tier 2,OU=$DomainName,$BaseDN"
                        Members             =
                        @(
                            @{
                                Filter      = "Name -like '*' -and ObjectCategory -eq 'Computer' -and OperatingSystem -notlike '*Server*' -and OperatingSystemVersion -like '*$($Build.Key)*'"
                                SearchBase  = "OU=Computers,OU=Tier 2,OU=$DomainName,$BaseDN"
                                SearchScope = 'Subtree'
                            }
                        )
                    }
                }
            }

            #######
            # GMSA
            #######

            $DomainGroups +=
            @(
                @{
                    Name                = 'Adfs'
                    Scope               = 'Global'
                    Path                = "OU=Group Managed Service Accounts,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'ADFS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                        @{
                            Filter      = "Name -like 'Tier0Admin' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "OU=Administrators,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Ndes'
                    Scope               = 'Global'
                    Path                = "OU=Group Managed Service Accounts,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'AS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }

                @{
                    Name                = 'AzADSyncSrv'
                    Scope               = 'Global'
                    Path                = "OU=Group Managed Service Accounts,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'AS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                        @{
                            Filter      = "Name -eq 'ASasdsdfasd' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            )

            ######################
            # Domain Local Groups
            ######################

            #########
            # Tier 0
            #########

            # Access Control
            $DomainGroups +=
            @(
                @{
                    Name                = 'Delegate Tier 0 Admin Rights'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'Tier 0 - Administrators' -and ObjectCategory -eq 'group'"
                            SearchBase  = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Delegate Tier 1 Admin Rights'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'Tier 1 - Administrators' -and ObjectCategory -eq 'group'"
                            SearchBase  = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Delegate Tier 2 Admin Rights'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'Tier 2 - Administrators' -and ObjectCategory -eq 'group'"
                            SearchBase  = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            )

            # Join domain
            $DomainGroups +=
            @(
                @{
                    Name                = 'Delegate Create Child Computer'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'JoinDomain' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "CN=Users,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            )

            # Pki
            $DomainGroups +=
            @(
                @{
                    Name                = 'Delegate Install Certificate Authority'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'Tier 0 - Administrators' -and ObjectCategory -eq 'Group'"
                            SearchBase  = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Delegate CRL Publishers'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'CA*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }
            )

            # Adfs
            $DomainGroups +=
            @(
                @{
                    Name                = 'Delegate Adfs Container Generic Read'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'Tier 0 - Administrators' -and ObjectCategory -eq 'Group'"
                            SearchBase  = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Delegate Adfs Dkm Container Permissions'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'ADFS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                        @{
                            Filter      = "Name -eq 'Tier 0 - Administrators' -and ObjectCategory -eq 'Group'"
                            SearchBase  = "OU=Security Roles,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            )

            # Adsync
            $DomainGroups +=
            @(
                @{
                    Name                = 'Delegate AdSync Basic Read Permissions'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'AzADDSConnector' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "OU=Service Accounts,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Delegate AdSync Password Hash Sync Permissions'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'AzADDSConnector' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "OU=Service Accounts,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Delegate AdSync msDS Consistency Guid Permissions'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Access Control,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'AzADDSConnector' -and ObjectCategory -eq 'Person'"
                            SearchBase  = "OU=Service Accounts,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            )

            # CA Templates
            $DomainGroups +=
            @(
                @{
                    Name                = 'Template ADFS Service Communication'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'ADFS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }

                @{
                    Name                = 'Template CEP Encryption'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'AS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }

                @{
                    Name                = 'Template NDES'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'MsaNdes' -and ObjectClass -eq 'msDS-GroupManagedServiceAccount'"
                            SearchBase  = "CN=Managed Service Accounts,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Template OCSP Response Signing'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'AS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }

                @{
                    Name                = 'Template SSL'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -like 'AS*' -and ObjectCategory -eq 'Computer'"
                            SearchBase  = "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN"
                            SearchScope = 'Subtree'
                        }
                    )
                }

                @{
                    Name                = 'Template WHFB Enrollment Agent'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'MsaAdfs' -and ObjectClass -eq 'msDS-GroupManagedServiceAccount'"
                            SearchBase  = "CN=Managed Service Accounts,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Template WHFB Authentication'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'MsaAdfs' -and ObjectClass -eq 'msDS-GroupManagedServiceAccount'"
                            SearchBase  = "CN=Managed Service Accounts,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }

                @{
                    Name                = 'Template WHFB Authentication'
                    Scope               = 'DomainLocal'
                    Path                = "OU=Certificate Authority Templates,OU=Groups,OU=Tier 0,OU=$DomainName,$BaseDN"
                    Members             =
                    @(
                        @{
                            Filter      = "Name -eq 'Domain Users' -and ObjectCategory -eq 'Group'"
                            SearchBase  = "CN=Users,$BaseDN"
                            SearchScope = 'OneLevel'
                        }
                    )
                }
            )

            ###############
            # Build groups
            ###############

            foreach($Group in $DomainGroups)
            {
                # Check if group managed service account
                $IsGmsa = ($Group.Path -match 'Group Managed Service Accounts')

                if ($IsGmsa)
                {
                    $GroupName = "Gmsa $($Group.Name)"
                }
                else
                {
                    $GroupName = $Group.Name
                }

                # Get group
                $ADGroup = Get-ADGroup -Filter "Name -eq '$GroupName'" -Properties Member

                # Check if group exist
                if (-not $ADGroup -and
                    (ShouldProcess @WhatIfSplat -Message "Creating `"$GroupName`" group." @VerboseSplat))
                {
                    $ADGroup = New-ADGroup -Name $GroupName -DisplayName $GroupName -Path $Group.Path -GroupScope $Group.Scope -GroupCategory Security -PassThru
                }

                if ($ADGroup)
                {
                    # Gmsa
                    if ($IsGmsa)
                    {
                        $Msa = Get-ADServiceAccount -Filter "Name -eq 'Msa$($Group.Name)'" -Properties PrincipalsAllowedToRetrieveManagedPassword

                        # Check if service account exist
                        if (-not $Msa -and
                            (ShouldProcess @WhatIfSplat -Message "Creating managed service account `"Msa$($Group.Name)`$`"." @VerboseSplat))
                        {
                            $Msa = New-ADServiceAccount -Name "Msa$($Group.Name)" -SamAccountName "Msa$($Group.Name)" -DNSHostName "Msa$($Group.Name).$DomainName" -PrincipalsAllowedToRetrieveManagedPassword "$($ADGroup.DistinguishedName)"
                        }

                        if($Msa -and $ADGroup.DistinguishedName -notin $Msa.PrincipalsAllowedToRetrieveManagedPassword -and
                           (ShouldProcess @WhatIfSplat -Message "Allow `"$GroupName`" to retrieve `"Msa$($Group.Name)`" password. " @VerboseSplat))
                        {
                            Set-ADServiceAccount -Identity $Msa.DistinguishedName -PrincipalsAllowedToRetrieveManagedPassword @($Msa.PrincipalsAllowedToRetrieveManagedPassword + $ADGroup.DistinguishedName)
                        }
                    }

                    # Check if group should be member of other groups
                    if ($Group.MemberOf)
                    {
                        # Itterate other groups
                        foreach($OtherName in $Group.MemberOf)
                        {
                            # Get other group
                            $OtherGroup = Get-ADGroup -Filter "Name -eq '$OtherName'" -Properties Member

                            # Check if member of other group
                            if (($OtherGroup -and -not $OtherGroup.Member.Where({ $_ -match $ADGroup.Name })) -and
                                (ShouldProcess @WhatIfSplat -Message "Adding `"$($ADGroup.Name)`" to `"$OtherName`"." @VerboseSplat))
                            {
                                # Add group to other group
                                Add-ADPrincipalGroupMembership -Identity $ADGroup.Name -MemberOf @("$OtherName")
                            }
                        }
                    }

                    # Check if group should have members
                    if ($Group.Members)
                    {
                        foreach ($Members in $Group.Members)
                        {
                            # Check if filter exist
                            if ($Members.Filter)
                            {
                                $GetObjectSplat = @{ 'Filter' = $Members.Filter }

                                if ($Members.SearchScope)
                                {
                                    $GetObjectSplat.Add('SearchScope', $Members.SearchScope)
                                }

                                if ($Members.SearchBase)
                                {
                                    $GetObjectSplat.Add('SearchBase', $Members.SearchBase)
                                }

                                # Get members
                                foreach($NewMember in (Get-ADObject @GetObjectSplat))
                                {
                                    # Check if member is part of group
                                    if ((-not $ADGroup.Member.Where({ $_ -match $NewMember.Name })) -and
                                        (ShouldProcess @WhatIfSplat -Message "Adding `"$($NewMember.Name)`" to `"$($ADGroup.Name)`"." @VerboseSplat))
                                    {
                                        # Add new member
                                        Add-ADPrincipalGroupMembership -Identity $NewMember.DistinguishedName -MemberOf @("$($ADGroup.Name)")

                                        # Remember computer objects added to group
                                        if ($NewMember.ObjectClass -eq 'Computer' -and -not $UpdatedObjects.ContainsKey($NewMember.Name))
                                        {
                                            $UpdatedObjects.Add($NewMember.Name, $true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            #  █████╗ ██████╗ ███████╗███████╗
            # ██╔══██╗██╔══██╗██╔════╝██╔════╝
            # ███████║██║  ██║█████╗  ███████╗
            # ██╔══██║██║  ██║██╔══╝  ╚════██║
            # ██║  ██║██████╔╝██║     ███████║
            # ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚══════╝

            $Principals =
            @(
                (Get-ADComputer -Filter "Name -like 'ADFS*'" -SearchBase "OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN" -SearchScope Subtree),
                (Get-ADUser -Filter "Name -eq 'tier0admin'" -SearchBase "OU=Administrators,OU=Tier 0,OU=$DomainName,$BaseDN" -SearchScope OneLevel)
            )

            # Setup service account
            foreach($Principal in $Principals)
            {
                if ($Principal)
                {
                    # Initialize
                    $PrincipalsAllowedToDelegateToAccount = @()
                    $PrincipalsAllowedToRetrieveManagedPassword = @()

                    # Get
                    $MsaAdfs = Get-ADServiceAccount -Identity 'MsaAdfs' -Properties PrincipalsAllowedToRetrieveManagedPassword, PrincipalsAllowedToDelegateToAccount

                    if ($MsaAdfs)
                    {
                        # Populate
                        if ($MsaAdfs.PrincipalsAllowedToDelegateToAccount)
                        {
                            $PrincipalsAllowedToDelegateToAccount += $MsaAdfs.PrincipalsAllowedToDelegateToAccount
                        }

                        if ($MsaAdfs.PrincipalsAllowedToRetrieveManagedPassword)
                        {
                            $PrincipalsAllowedToRetrieveManagedPassword += $MsaAdfs.PrincipalsAllowedToRetrieveManagedPassword
                        }

                        # Retrive password
                        if ($Principal.DistinguishedName -notin $MsaAdfs.PrincipalsAllowedToRetrieveManagedPassword -and
                            (ShouldProcess @WhatIfSplat -Message "Allow `"$($Principal.Name)`" to retrieve `"$($MsaAdfs.Name)`" password." @VerboseSplat))
                        {
                            Set-ADServiceAccount -Identity 'MsaAdfs' -PrincipalsAllowedToRetrieveManagedPassword @($PrincipalsAllowedToDelegateToAccount + $Principal.DistinguishedName)
                        }

                        # Delegate
                        if ($Principal.DistinguishedName -notin $MsaAdfs.PrincipalsAllowedToDelegateToAccount -and
                            (ShouldProcess @WhatIfSplat -Message "Allow `"$($Principal.Name)`" to delegate to `"$($MsaAdfs.Name)`"." @VerboseSplat))
                        {
                            Set-ADServiceAccount -Identity 'MsaAdfs' -PrincipalsAllowedToDelegateToAccount @($PrincipalsAllowedToRetrieveManagedPassword + $Principal.DistinguishedName)
                        }
                    }
                }
            }

            # Check spn
            if (((setspn -L MsaAdfs) -join '') -notmatch "host/adfs.$DomainName" -and
                (ShouldProcess @WhatIfSplat -Message "Setting SPN `"host/adfs.$DomainName`" for MsaAdfs." @VerboseSplat))
            {
                setspn -a host/adfs.$DomainName MsaAdfs > $null
            }


            # Check adfs container
            if (-not (Get-ADObject -Filter "Name -eq 'ADFS' -and ObjectCategory -eq 'Container'" -SearchBase "CN=Microsoft,CN=Program Data,$BaseDN" -SearchScope 'OneLevel') -and
                (ShouldProcess @WhatIfSplat -Message "Adding `"CN=ADFS,CN=Microsoft,CN=Program Data,$BaseDN`" container." @VerboseSplat))
            {
                New-ADObject -Name "ADFS" -Path "CN=Microsoft,CN=Program Data,$BaseDN" -Type Container
            }

            $AdfsDkmContainer = Get-ADObject -Filter "Name -like '*'" -SearchBase "CN=ADFS,CN=Microsoft,CN=Program Data,$BaseDN" -SearchScope OneLevel
            $AdfsDkmGuid = [Guid]::NewGuid().Guid

            # Check dkm container
            if (-not $AdfsDkmContainer -and
                (ShouldProcess @WhatIfSplat -Message "Adding `"CN=$AdfsDkmGuid,CN=ADFS`" container." @VerboseSplat))
            {
                $AdfsDkmContainer = New-ADObject -Name $AdfsDkmGuid -Path "CN=ADFS,CN=Microsoft,CN=Program Data,$BaseDN" -Type Container -PassThru
            }
            else
            {
                $AdfsDkmGuid = $AdfsDkmContainer.Name
            }

            $Result.Add('AdfsDkmGuid', $AdfsDkmGuid)

            # ██████╗ ███████╗██╗     ███████╗ ██████╗  █████╗ ████████╗███████╗
            # ██╔══██╗██╔════╝██║     ██╔════╝██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝
            # ██║  ██║█████╗  ██║     █████╗  ██║  ███╗███████║   ██║   █████╗
            # ██║  ██║██╔══╝  ██║     ██╔══╝  ██║   ██║██╔══██║   ██║   ██╔══╝
            # ██████╔╝███████╗███████╗███████╗╚██████╔╝██║  ██║   ██║   ███████╗
            # ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

            # Check if AD drive is mapped
            if (-not (Get-PSDrive -Name AD -ErrorAction SilentlyContinue))
            {
                Import-Module -Name ActiveDirectory
            }

            $AccessRight = @{}
            Get-ADObject -SearchBase "CN=Configuration,$BaseDN" -LDAPFilter "(&(objectClass=controlAccessRight)(rightsguid=*))" -Properties displayName, rightsGuid | ForEach-Object { $AccessRight.Add($_.displayName, [System.GUID] $_.rightsGuid) }

            $SchemaID = @{}
            Get-ADObject -SearchBase "CN=Schema,CN=Configuration,$BaseDN" -LDAPFilter "(schemaidguid=*)" -Properties lDAPDisplayName, schemaIDGUID | ForEach-Object { $SchemaID.Add($_.lDAPDisplayName, [System.GUID] $_.schemaIDGUID) }

            ########################
            # Create Child Computer
            ########################

            $CreateChildComputer =
            @(
                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = $SchemaID['attributeCertificateAttribute'];
                    InheritedObjectType   = $SchemaID['Computer'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = 'home\Delegate Create Child Computer';
                }

                @{
                    ActiveDirectoryRights = 'CreateChild';
                    InheritanceType       = 'All';
                    ObjectType            = $SchemaID['Computer'];
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = 'home\Delegate Create Child Computer';
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['Computer'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = 'home\Delegate Create Child Computer';
                }
            )

            Set-Ace -DistinguishedName "OU=$RedirCmp,OU=$DomainName,$BaseDN" -AceList $CreateChildComputer

            ################################
            # Install Certificate Authority
            ################################

            $InstallCertificateAuthority =
            @(
                @{
                    ActiveDirectoryRights = 'GenericAll';
                    InheritanceType       = 'All';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate Install Certificate Authority";
                }
            )

            Set-Ace -DistinguishedName "CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN" -AceList $InstallCertificateAuthority

            $AddToGroup =
            @(
                @{
                    ActiveDirectoryRights = 'ReadProperty, WriteProperty';
                    InheritanceType       = 'All';
                    ObjectType            = $SchemaID['member'];
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate Install Certificate Authority";
                }
            )

            # Set R/W on member object
            Set-Ace -DistinguishedName "CN=Cert Publishers,CN=Users,$BaseDN" -AceList $AddToGroup
            Set-Ace -DistinguishedName "CN=Pre-Windows 2000 Compatible Access,CN=Builtin,$BaseDN" -AceList $AddToGroup

            ##############################
            # Adfs Container Generic Read
            ##############################

            $AdfsContainerGenericRead =
            @(
                @{
                    ActiveDirectoryRights = 'GenericRead';
                    InheritanceType       = 'All';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate Adfs Container Generic Read";
                }
            )

            Set-Ace -DistinguishedName "CN=ADFS,CN=Microsoft,CN=Program Data,$BaseDN" -AceList $AdfsContainerGenericRead -Owner "$DomainNetbiosName\Delegate Adfs Container Generic Read"

            #################################
            # Adfs Dkm Container Permissions
            #################################

            $AdfsDkmContainerPermissions =
            @(
                @{
                    ActiveDirectoryRights = 'CreateChild, WriteProperty, DeleteTree, GenericRead, WriteDacl, WriteOwner';
                    InheritanceType       = 'All';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate Adfs Dkm Container Permissions";
                }
            )

            Set-Ace -DistinguishedName $AdfsDkmContainer.DistinguishedName -AceList $AdfsDkmContainerPermissions -Owner "$DomainNetbiosName\Delegate Adfs Dkm Container Permissions"

            ################################
            # AdSync Basic Read Permissions
            ################################

            $AdSyncBasicReadPermissions =
            @(
                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['contact'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['user'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['group'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['device'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['computer'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['inetOrgPerson'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritedObjectType   = $SchemaID['foreignSecurityPrincipal'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                }
            )

            Set-Ace -DistinguishedName "OU=Users,OU=Tier 2,OU=$DomainName,$BaseDN" -AceList $AdSyncBasicReadPermissions

            ########################################
            # AdSync Password Hash Sync Permissions
            ########################################

            $AdSyncPasswordHashSyncPermissions =
            @(
                @{
                    ActiveDirectoryRights = 'ExtendedRight';
                    InheritanceType       = 'None';
                    ObjectType            = $AccessRight['Replicating Directory Changes All'];
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Password Hash Sync Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ExtendedRight';
                    InheritanceType       = 'None';
                    ObjectType            = $AccessRight['Replicating Directory Changes'];
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Password Hash Sync Permissions";
                }
            )

            Set-Ace -DistinguishedName "OU=Users,OU=Tier 2,OU=$DomainName,$BaseDN" -AceList $AdSyncPasswordHashSyncPermissions

            ###########################################
            # AdSync MsDs Consistency Guid Permissions
            ###########################################

            $AdSyncMsDsConsistencyGuidPermissions =
            @(
                @{
                    ActiveDirectoryRights = 'ReadProperty, WriteProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = $SchemaID['mS-DS-ConsistencyGuid'];
                    InheritedObjectType   = $SchemaID['user'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync MsDs Consistency Guid Permissions";
                }

                @{
                    ActiveDirectoryRights = 'ReadProperty, WriteProperty';
                    InheritanceType       = 'Descendents';
                    ObjectType            = $SchemaID['mS-DS-ConsistencyGuid'];
                    InheritedObjectType   = $SchemaID['group'];
                    AccessControlType     = 'Allow';
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync MsDs Consistency Guid Permissions";
                }
            )

            Set-Ace -DistinguishedName "OU=Users,OU=Tier 2,OU=$DomainName,$BaseDN" -AceList $AdSyncMsDsConsistencyGuidPermissions
            Set-Ace -DistinguishedName "CN=AdminSDHolder,CN=System,$BaseDN" -AceList $AdSyncMsDsConsistencyGuidPermissions

            ############################
            # Remove Join Domain access
            ############################

            <#
            foreach ($Computer in (Get-ADComputer -Filter "Name -like '*'"))
            {
                $ComputerAcl = Get-Acl -Path "AD:$($Computer.DistinguishedName)"

                foreach ($AccessRule in $ComputerAcl.Access)
                {
                    if ($AccessRule.IdentityReference.Value -match 'JoinDomain' -and
                        ((ShouldProcess @WhatIfSplat -Message "Removing `"JoinDomain: $($AccessRule.ActiveDirectoryRights)`" from `"$($Computer.Name)`"." @VerboseSplat)))
                    {
                        $ComputerAcl.RemoveAccessRule($AccessRule) > $null
                    }
                }

                Set-Acl -Path "AD:$($Computer.DistinguishedName)" -AclObject $ComputerAcl
            }
            #>

            #  ██████╗ ██████╗  ██████╗
            # ██╔════╝ ██╔══██╗██╔═══██╗
            # ██║  ███╗██████╔╝██║   ██║
            # ██║   ██║██╔═══╝ ██║   ██║
            # ╚██████╔╝██║     ╚██████╔╝
            #  ╚═════╝ ╚═╝      ╚═════╝

            #########
            # Import
            #########

            #Initialize
            $GpoPaths = @()
            $GpoPaths += Get-Item -Path "$env:TEMP\Gpo" -ErrorAction SilentlyContinue
            $GPoPaths += Get-ChildItem -Path "$env:TEMP\Baseline" -Directory -ErrorAction SilentlyContinue

            # Itterate gpo paths
            foreach($GpoDir in $GpoPaths)
            {
                # Read gpos
                foreach($Gpo in (Get-ChildItem -Path "$($GpoDir.FullName)" -Directory))
                {
                    # Set gpreport filepath
                    $GpReportFile = "$($Gpo.FullName)\gpreport.xml"

                    # Get gpo name from xml
                    $GpReportName = (Select-Xml -Path $GpReportFile -XPath '/').Node.GPO.Name

                    if (-not $GpReportName.StartsWith('MSFT'))
                    {
                        if (-not $GpReportName.StartsWith($DomainPrefix))
                        {
                            $GpReportName = "$DomainPrefix - $($GpReportName.Remove(0, $GpReportName.IndexOf('-') + 2))"
                        }

                        # Set domain name in site to zone assignment list

                        if ($GpReportName -match 'Internet Explorer Site to Zone Assignment List')
                        {
                            ((Get-Content -Path $GpReportFile -Raw) -replace '%domain_wildcard%', "*.$DomainName") | Set-Content -Path $GpReportFile
                        }

                        # Set sids in GptTempl.inf

                        if ($GpReportName -match 'Restrict User Rights Assignment')
                        {
                            $GptTmplFile = "$($Gpo.FullName)\DomainSysvol\GPO\Machine\microsoft\windows nt\SecEdit\GptTmpl.inf"

                            $GptContent = Get-Content -Path $GptTmplFile -Raw
                            $GptContent = $GptContent -replace '%join_domain%', "*$((Get-ADUser -Identity 'JoinDomain').SID.Value)"
                            $GptContent = $GptContent -replace '%domain_admins%', "*$((Get-ADGroup -Identity 'Domain Admins').SID.Value)"
                            $GptContent = $GptContent -replace '%enterprise_admins%', "*$((Get-ADGroup -Identity 'Enterprise Admins').SID.Value)"
                            $GptContent = $GptContent -replace '%schema_admins%', "*$((Get-ADGroup -Identity 'Schema Admins').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_0_admins%', "*$((Get-ADGroup -Identity 'Tier 0 - Administrators').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_0_computers%', "*$((Get-ADGroup -Identity 'Tier 0 - Computers').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_0_users%', "*$((Get-ADGroup -Identity 'Tier 0 - Users').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_1_admins%', "*$((Get-ADGroup -Identity 'Tier 1 - Administrators').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_1_computers%', "*$((Get-ADGroup -Identity 'Tier 1 - Computers').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_1_users%', "*$((Get-ADGroup -Identity 'Tier 1 - Users').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_2_admins%', "*$((Get-ADGroup -Identity 'Tier 2 - Administrators').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_2_computers%', "*$((Get-ADGroup -Identity 'Tier 2 - Computers').SID.Value)"
                            $GptContent = $GptContent -replace '%tier_2_users%', "*$((Get-ADGroup -Identity 'Tier 2 - Users').SID.Value)"

                            Set-Content -Path $GptTmplFile -Value $GptContent
                        }
                    }

                    # Check if gpo exist
                    if (-not (Get-GPO -Name $GpReportName -ErrorAction SilentlyContinue) -and
                        (ShouldProcess @WhatIfSplat -Message "Importing $($Gpo.Name) `"$GpReportName`"." @VerboseSplat))
                    {
                        Import-GPO -Path "$($GpoDir.FullName)" -BackupId $Gpo.Name -TargetName $GpReportName -CreateIfNeeded > $null
                    }
                }

                Start-Sleep -Seconds 1
            }

            ###########
            # Policies
            ###########

            # Enforced if ending with +
            # Disabled if ending with -

            $SecurityPolicy =
            @(
                "$DomainPrefix - Computer - Sec - Enable Virtualization Based Security+"
                "$DomainPrefix - Computer - Sec - Enable LSA Protection & LSASS Audit+"
                "$DomainPrefix - Computer - Sec - Enable PowerShell Logging+"
                "$DomainPrefix - Computer - Sec - Enable SMB Encryption+"
                "$DomainPrefix - Computer - Sec - Require Client LDAP Signing+"
                "$DomainPrefix - Computer - Sec - Disable Net Session Enumeration+"
                "$DomainPrefix - Computer - Sec - Disable Telemetry+"
                "$DomainPrefix - Computer - Sec - Disable Netbios+"
                "$DomainPrefix - Computer - Sec - Disable LLMNR+"
                "$DomainPrefix - Computer - Sec - Disable WPAD+"
                "$DomainPrefix - Computer - Sec - Block Untrusted Fonts+"
            )

            ########
            # Links
            ########

            # Get DC build
            $DCBuild = [System.Environment]::OSVersion.Version.Build.ToString()

            $GPOLinks =
            @{
                #######
                # Root
                #######

                $BaseDN =
                @(
                    "$DomainPrefix - Domain - Force Group Policy+"
                    "$DomainPrefix - Domain - Client Kerberos Armoring+"
                    "$DomainPrefix - Domain - Certificate Services Client+"
                    "$DomainPrefix - Domain - Firewall Rules+"
                    "$DomainPrefix - Domain - Remote Desktop+"
                    "$DomainPrefix - Domain - User - Display Settings+"
                    'Default Domain Policy'
                )

                #####################
                # Domain controllers
                #####################

                "OU=Domain Controllers,$BaseDN" =
                @(
                    "$DomainPrefix - Domain Controller - Firewall - IPSec - Any - Request-"
                    "$DomainPrefix - Domain Controller - Restrict User Rights Assignment"
                    "$DomainPrefix - Domain Controller - KDC Kerberos Armoring+"
                    "$DomainPrefix - Domain Controller - Advanced Audit+"
                    "$DomainPrefix - Domain Controller - Time - PDC NTP+"
                ) +
                $SecurityPolicy +
                @(
                    "$DomainPrefix - Computer - Sec - Disable Spooler+"
                    "$DomainPrefix - Computer - Windows Update+"
                    "$DomainPrefix - Computer - Display Settings+"
                ) +
                $WinBuilds.Item($DCBuild).DCBaseline +
                $WinBuilds.Item($DCBuild).BaseLine +
                @(
                    'Default Domain Controllers Policy'
                )
            }

            ############
            # Computers
            # Tier 0-2
            ############

            foreach($Tier in @(0, 1, 2))
            {
                $ComputerPolicy =
                @(
                    "$DomainPrefix - Computer - Firewall - IPSec - Any - Require/Request-"
                )

                # Link tier gpos
                $ComputerPolicy +=
                @(
                    "$DomainPrefix - Computer - Tier $Tier - Local Users and Groups+"
                    "$DomainPrefix - Computer - Tier $Tier - Restrict User Rights Assignment"
                )

                # Link security policy
                $ComputerPolicy += $SecurityPolicy

                if ($Tier -eq 2)
                {
                    # Workstations
                    $ComputerPolicy += @("$DomainPrefix - Computer - Sec - Disable Spooler Client Connections+")
                }
                else
                {
                    # Servers
                    $ComputerPolicy +=  @("$DomainPrefix - Computer - Sec - Disable Spooler+")
                }

                $ComputerPolicy +=
                @(
                    "$DomainPrefix - Computer - Windows Update+"
                    "$DomainPrefix - Computer - Display Settings+"
                    "$DomainPrefix - Computer - Internet Explorer Site to Zone Assignment List+"
                )

                # Link computer policy
                $GPOLinks.Add("OU=Computers,OU=Tier $Tier,OU=$DomainName,$BaseDN", $ComputerPolicy)
            }

            ############
            # Computers
            # Tier 0
            ############

            foreach($Build in $WinBuilds.Values)
            {
                # Check if server build
                if ($Build.Server)
                {
                    # Link baseline & server baseline
                    $GPOLinks.Add("OU=$($Build.Server),OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN", $Build.Baseline + $Build.ServerBaseline)

                    # Certificate Authorities
                    $GPOLinks.Add("OU=Certificate Authorities,OU=$($Build.Server),OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN", @(

                            "$DomainPrefix - Computer - Certification Services - Auditing"
                        )
                    )

                    # Federation Services
                    $GPOLinks.Add("OU=Federation Services,OU=$($Build.Server),OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN", @(

                            "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Request-"
                            "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Request-"
                        )
                    )

                    # Web Servers
                    $GPOLinks.Add("OU=Web Servers,OU=$($Build.Server),OU=Computers,OU=Tier 0,OU=$DomainName,$BaseDN", @(

                            "$DomainPrefix - Computer - Web Server - User Rights Assignment"
                            "$DomainPrefix - Computer - Firewall - Web Server"
                            "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Request-"
                            "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Request-"
                        )
                    )
                }
            }

            ############
            # Computers
            # Tier 1
            ############

            foreach($Build in $WinBuilds.Values)
            {
                # Check if server build
                if ($Build.Server)
                {
                    # Linkd baseline & server baseline
                    $GPOLinks.Add("OU=$($Build.Server),OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN", $Build.Baseline + $Build.ServerBaseline)

                    # Web Application Proxy
                    $GPOLinks.Add("OU=Web Application Proxy,OU=$($Build.Server),OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN", @(

                            "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Disable Private and Public-"
                            "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Disable Private and Public-"
                        )
                    )

                    # Web Servers
                    $GPOLinks.Add("OU=Web Servers,OU=$($Build.Server),OU=Computers,OU=Tier 1,OU=$DomainName,$BaseDN", @(

                            "$DomainPrefix - Computer - Web Server - User Rights Assignment"
                            "$DomainPrefix - Computer - Firewall - Web Server"
                            "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Request-"
                            "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Request-"
                        )
                    )
                }
            }

            ############
            # Computers
            # Tier 2
            ############

            foreach($Build in $WinBuilds.Values)
            {
                # Check if workstation build
                if ($Build.Workstation)
                {
                    # Link baseline & computer baseline
                    $GPOLinks.Add("OU=$($Build.Workstation),OU=Computers,OU=Tier 2,OU=$DomainName,$BaseDN", (

                            $Build.Baseline +
                            $Build.ComputerBaseline
                        )
                    )
                }
            }

            ########
            # Users
            ########

            # Initialize
            $UserServerBaseline = @()
            $UserWorkstationBaseline = @()

            # Get baseline for all versions from winver
            foreach($Build in $WinBuilds.Values)
            {
                if ($Build.Server -and $Build.UserBaseline)
                {
                    $UserServerBaseline += $Build.UserBaseline
                }

                if ($Build.Workstation -and $Build.UserBaseline)
                {
                    $UserWorkstationBaseline += $Build.UserBaseline
                }
            }

            ###########
            # Users
            # Tier 0-2
            ###########

            foreach($Tier in @(0, 1, 2))
            {
                $UserPolicy =
                @(
                    # Empty
                )

                # Link administrators policy
                $GPOLinks.Add("OU=Administrators,OU=Tier $Tier,OU=$DomainName,$BaseDN", $UserPolicy)

                if ($Tier -eq 2)
                {
                    # Workstations
                    $UserPolicy +=
                    @(
                        "$DomainPrefix - User - Disable WPAD"
                        "$DomainPrefix - User - Disable WSH-"
                    )

                    $UserPolicy += $UserWorkstationBaseline
                }
                else
                {
                    # Servers
                    $UserPolicy +=  $UserServerBaseline
                }

                # Link users policy
                $GPOLinks.Add("OU=Users,OU=Tier $Tier,OU=$DomainName,$BaseDN", $UserPolicy)
            }

            ############
            # Link GPOs
            ############

            # Itterate targets
            foreach ($Target in $GPOLinks.Keys)
            {
                $Order = 1
                $TargetShort = $Target -match '((?:cn|ou|dc)=.*?,(?:cn|ou|dc)=.*?)(?:,|$)' | ForEach-Object { $Matches[1] }

                # Itterate GPOs
                foreach($GpoName in ($GPOLinks.Item($Target)))
                {
                    $LinkEnable = 'Yes'
                    $LinkEnableBool = $true
                    $LinkEnforce = 'No'
                    $LinkEnforceBool = $false

                    if ($GpoName -match 'Restrict User Rights Assignment')
                    {
                        $LinkEnable = 'No'
                        $LinkEnableBool = $false
                        $LinkEnforce = 'Yes'
                        $LinkEnforceBool = $true
                    }
                    elseif ($GpoName.EndsWith('-'))
                    {
                        $LinkEnable = 'No'
                        $LinkEnableBool = $false
                        $GpoName = $GpoName.TrimEnd('-')
                    }
                    elseif ($GpoName.EndsWith('+'))
                    {
                        $LinkEnforce = 'Yes'
                        $LinkEnforceBool = $true
                        $GpoName = $GpoName.TrimEnd('+')
                    }

                    # Get gpo report
                    [xml]$GpoXml = Get-GPOReport -Name $GpoName -ReportType Xml -ErrorAction SilentlyContinue

                    if ($GpoXml)
                    {
                        $TargetCN = ConvertTo-CanonicalName -DistinguishedName $Target

                        # Check link
                        if (-not ($TargetCN -in $GpoXml.GPO.LinksTo.SOMPath) -and
                            (ShouldProcess @WhatIfSplat -Message "Created `"$GpoName`" ($Order) -> `"$TargetShort`"" @VerboseSplat))
                        {
                            New-GPLink -Name $GpoName -Target $Target -Order $Order -LinkEnabled $LinkEnable -Enforced $LinkEnforce -ErrorAction Stop > $null
                        }
                        else
                        {
                            foreach ($Link in $GpoXml.GPO.LinksTo)
                            {
                                if ($SecureTiering -notlike $null -and
                                    $GpoName -match 'Restrict User Rights Assignment')
                                {
                                    switch ($SecureTiering)
                                    {
                                        $true
                                        {
                                            $LinkEnable = 'Yes'
                                            $LinkEnableBool = $true
                                        }
                                        $false
                                        {
                                            $LinkEnable = 'No'
                                            $LinkEnableBool = $false
                                        }
                                    }
                                }

                                if ($Link.Enabled -ne $LinkEnableBool -and
                                    ($SecureTiering -notlike $null -and
                                     $GpoName -match 'Restrict User Rights Assignment') -and
                                    (ShouldProcess @WhatIfSplat -Message "Set `"$GpoName`" ($Order) Enabled: $LinkEnable -> `"$TargetShort`"" @VerboseSplat))
                                {
                                    Set-GPLink -Name $GpoName -Target $Target -LinkEnabled $LinkEnable > $null
                                }

                                if ($Link.NoOverride -ne $LinkEnforceBool -and
                                    (ShouldProcess @WhatIfSplat -Message "Set `"$GpoName`" ($Order) Enforced: $LinkEnforce -> `"$TargetShort`"" @VerboseSplat))
                                {
                                    Set-GPLink -Name $GpoName -Target $Target -Enforced $LinkEnforce > $null
                                }

                                if ($Order -ne (Get-GPInheritance -Target $Target | Select-Object -ExpandProperty GpoLinks | Where-Object { $_.DisplayName -eq $GpoName } | Select-Object -ExpandProperty Order) -and
                                    (ShouldProcess @WhatIfSplat -Message "Set `"$GpoName`" ($Order) -> `"$TargetShort`" " @VerboseSplat))
                                {
                                    Set-GPLink -Name $GpoName -Target $Target -Order $Order > $null
                                }
                            }
                        }

                        $Order++;
                    }
                    else
                    {
                        Write-Warning -Message "Gpo not found, couldn't link `"$GpoName`" -> `"$TargetShort`""
                    }
                }
            }

            ##############
            # Permissions
            ##############

            # Set permissions on user policies
            foreach ($GpoName in (Get-GPInheritance -Target "OU=Users,OU=Tier 2,OU=$DomainName,$BaseDN").GpoLinks | Select-Object -ExpandProperty DisplayName)
            {
                $Build = ($WinBuilds.GetEnumerator() | Where-Object { $GpoName -in $_.Value.UserBaseline }).Key

                if ($Build)
                {
                    # Set groups
                    $GpoPermissionGroups = @('Domain Users')

                    # Add workstation
                    if ($WinBuilds.Item($Build).Workstation)
                    {
                        $GpoPermissionGroups += "Tier 2 - $($WinBuilds.Item($Build).Workstation)"
                    }

                    <# FIX

                    # Add server
                    if ($WinBuilds.Item($Build).Server -and $GpoName -match 'Internet Explorer')
                    {
                        $GpoPermissionGroups += $WinBuilds.Item($Build).Server
                    }
                    #>

                    # Itterate groups
                    foreach ($Group in $GpoPermissionGroups)
                    {
                        # Set permission
                        if ((Get-GPPermission -Name $GpoName -TargetName $Group -TargetType Group -ErrorAction SilentlyContinue ).Permission -ne 'GpoApply' -and
                            (ShouldProcess @WhatIfSplat -Message "Setting `"$Group`" GpoApply to `"$GpoName`" gpo." @VerboseSplat))
                        {
                            Set-GPPermission -Name $GpoName -TargetName $Group -TargetType Group -PermissionLevel GpoApply > $nul
                        }
                    }

                    if ($RemoveAuthenticatedUsersFromUserGpos.IsPresent)
                    {
                        # Remove authenticated user
                        if ((Get-GPPermission -Name $GpoName -TargetName 'Authenticated Users' -TargetType Group -ErrorAction SilentlyContinue) -and
                            (ShouldProcess @WhatIfSplat -Message "Removing `"Authenticated Users`" from `"$GpoName`" gpo." @VerboseSplat))
                        {
                            Set-GPPermission -Name $GpoName -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel None -Confirm:$false > $nul
                        }
                    }
                }
            }

            # ████████╗███████╗███╗   ███╗██████╗ ██╗      █████╗ ████████╗███████╗███████╗
            # ╚══██╔══╝██╔════╝████╗ ████║██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
            #    ██║   █████╗  ██╔████╔██║██████╔╝██║     ███████║   ██║   █████╗  ███████╗
            #    ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
            #    ██║   ███████╗██║ ╚═╝ ██║██║     ███████╗██║  ██║   ██║   ███████╗███████║
            #    ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

            # Set oid path
            $OidPath = "CN=OID,CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN"

            # Get msPKI-Cert-Template-OID
            $msPKICertTemplateOid = Get-ADObject -Identity $OidPath -Properties msPKI-Cert-Template-OID | Select-Object -ExpandProperty msPKI-Cert-Template-OID

            # Check if msPKI-Cert-Template-OID exist
            if (-not $msPKICertTemplateOid -and
                (ShouldProcess @WhatIfSplat -Message "Creating default certificate templates." @VerboseSplat))
            {
                # Install default templates
                TryCatch { certutil -InstallDefaultTemplates } > $null

                # Wait a bit
                Start-Sleep -Seconds 1

                # Reload msPKI-Cert-Template-OID
                $msPKICertTemplateOid = Get-ADObject -Identity $OidPath -Properties msPKI-Cert-Template-OID | Select-Object -ExpandProperty msPKI-Cert-Template-OID
            }

            # Check if templates exist
            if ($msPKICertTemplateOid -and (Test-Path -Path "$env:TEMP\Templates"))
            {
                # Define empty acl
                $EmptyAcl = New-Object -TypeName System.DirectoryServices.ActiveDirectorySecurity

                # https://docs.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.objectsecurity.setaccessruleprotection?view=dotnet-plat-ext-3.1
                $EmptyAcl.SetAccessRuleProtection($true, $false)

                # Set template path
                $CertificateTemplatesPath = "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN"

                # Read templates
                foreach ($TemplateFile in (Get-ChildItem -Path "$env:TEMP\Templates" -Filter '*_tmpl.json'))
                {
                    # Read template file and convert from json
                    $SourceTemplate = $TemplateFile | Get-Content | ConvertFrom-Json

                    # Add domain prefix to template name
                    $NewTemplateName = "$DomainPrefix$($SourceTemplate.Name)"

                    # https://github.com/GoateePFE/ADCSTemplate/blob/master/ADCSTemplate.psm1
                    if (-not (Get-ADObject -SearchBase $CertificateTemplatesPath -Filter "Name -eq '$NewTemplateName' -and objectClass -eq 'pKICertificateTemplate'") -and
                        (ShouldProcess @WhatIfSplat -Message "Creating template `"$NewTemplateName`"." @VerboseSplat))
                    {
                        # Generate new template oid and cn
                        do
                        {
                           $Part2 = Get-Random -Minimum 10000000 -Maximum 99999999
                           $NewOid = "$msPKICertTemplateOid.$(Get-Random -Minimum 10000000 -Maximum 99999999).$Part2"
                           $NewOidCn = "$Part2.$((1..32 | % { '{0:X}' -f (Get-Random -Max 16) }) -join '')"
                        }
                        while (

                            # Check if oid exist
                            Get-ADObject -SearchBase $OidPath -Filter "cn -eq '$NewOidCn' -and msPKI-Cert-Template-OID -eq '$NewOID'"
                        )

                        # Add domain prefix to template display name
                        $NewTemplateDisplayName = "$DomainPrefix $($SourceTemplate.DisplayName)"

                        # Oid attributes
                        $NewOidAttributes =
                        @{
                            'DisplayName' = $NewTemplateDisplayName
                            'msPKI-Cert-Template-OID' = $NewOid
                            'flags' = [System.Int32] '1'
                        }

                        # Create oid
                        New-ADObject -Name $NewOidCn -Path $OidPath -Type 'msPKI-Enterprise-OID' -OtherAttributes $NewOidAttributes

                        # Template attributes
                        $NewTemplateAttributes =
                        @{
                            'DisplayName' = $NewTemplateDisplayName
                            'msPKI-Cert-Template-OID' = $NewOid
                        }

                        # Import attributes
                        foreach ($Property in ($SourceTemplate | Get-Member -MemberType NoteProperty))
                        {
                            Switch ($Property.Name)
                            {
                                { $_ -in @('flags',
                                           'revision',
                                           'msPKI-Certificate-Name-Flag',
                                           'msPKI-Enrollment-Flag',
                                           'msPKI-Minimal-Key-Size',
                                           'msPKI-Private-Key-Flag',
                                           'msPKI-RA-Signature',
                                           'msPKI-Template-Minor-Revision',
                                           'msPKI-Template-Schema-Version',
                                           'pKIDefaultKeySpec',
                                           'pKIMaxIssuingDepth')}
                                {
                                    $NewTemplateAttributes.Add($_, [System.Int32]$SourceTemplate.$_)
                                    break
                                }

                                { $_ -in @('msPKI-Certificate-Application-Policy',
                                           'msPKI-RA-Application-Policies',
                                           'msPKI-Supersede-Templates',
                                           'pKICriticalExtensions',
                                           'pKIDefaultCSPs',
                                           'pKIExtendedKeyUsage')}
                                {
                                    $NewTemplateAttributes.Add($_, [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]$SourceTemplate.$_)
                                    break
                                }

                                { $_ -in @('pKIExpirationPeriod',
                                           'pKIKeyUsage',
                                           'pKIOverlapPeriod')}
                                {
                                    $NewTemplateAttributes.Add($_, [System.Byte[]]$SourceTemplate.$_)
                                    break
                                }

                                { $_ -in @('Name',
                                           'DisplayName')}
                                {
                                    break
                                }

                                default
                                {
                                    Write-Warning -Message "Missing handler for `"$($Property.Name)`"."
                                }
                            }
                        }

                        # Create template
                        $NewADObj = New-ADObject -Name $NewTemplateName -Path $CertificateTemplatesPath -Type 'pKICertificateTemplate' -OtherAttributes $NewTemplateAttributes -PassThru

                        # Empty acl
                        Set-Acl -AclObject $EmptyAcl -Path "AD:$($NewADObj.DistinguishedName)"
                    }
                }

                # Read acl files
                foreach ($AclFile in (Get-ChildItem -Path "$env:TEMP\Templates" -Filter '*_acl.json'))
                {
                    # Read acl file and convert from json
                    $SourceAcl = $AclFile | Get-Content | ConvertFrom-Json

                    foreach ($Ace in $SourceAcl)
                    {
                        Set-Ace -DistinguishedName "CN=$DomainPrefix$($AclFile.BaseName.Replace('_acl', '')),$CertificateTemplatesPath" -AceList ($Ace | Select-Object -Property AccessControlType, ActiveDirectoryRights, InheritanceType, @{ n = 'IdentityReference'; e = { $_.IdentityReference.Replace('%domain%', $DomainNetbiosName) }}, ObjectType, InheritedObjectType)
                    }
                }

                Start-Sleep -Seconds 1
                Remove-Item -Path "$($env:TEMP)\Templates" -Recurse -Force
            }

            #  █████╗ ██╗   ██╗████████╗██╗  ██╗███╗   ██╗    ██████╗  ██████╗ ██╗     ██╗ ██████╗██╗   ██╗
            # ██╔══██╗██║   ██║╚══██╔══╝██║  ██║████╗  ██║    ██╔══██╗██╔═══██╗██║     ██║██╔════╝╚██╗ ██╔╝
            # ███████║██║   ██║   ██║   ███████║██╔██╗ ██║    ██████╔╝██║   ██║██║     ██║██║      ╚████╔╝
            # ██╔══██║██║   ██║   ██║   ██╔══██║██║╚██╗██║    ██╔═══╝ ██║   ██║██║     ██║██║       ╚██╔╝
            # ██║  ██║╚██████╔╝   ██║   ██║  ██║██║ ╚████║    ██║     ╚██████╔╝███████╗██║╚██████╗   ██║
            # ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝    ╚═╝      ╚═════╝ ╚══════╝╚═╝ ╚═════╝   ╚═╝

            $AuthenticationTires =
            @(
                @{ Name = 'Domain Controller';  Liftime = 45; }
                @{ Name = 'Tier 0';             Liftime = 45; }
                @{ Name = 'Tier 1';             Liftime = 45; }
                @{ Name = 'Tier 2';             Liftime = 45; }
                @{ Name = 'Lockdown';           Liftime = 45; }
            )

            foreach ($Tier in $AuthenticationTires)
            {
                ##############
                # Get members
                ##############

                switch ($Tier.Name)
                {
                    'Domain Controller'
                    {
                        $Members   = @(Get-ADGroup -Identity "Domain Admins" -Properties Members | Select-Object -ExpandProperty Members)
                        $Condition = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID(DD)}))'
                    }

                    'Lockdown'
                    {
                        $Members   = @(Get-ADUser -Filter "Name -like '*'" -SearchScope 'OneLevel' -SearchBase "OU=Redirect Users,OU=$DomainName,$BaseDN" | Select-Object -ExpandProperty DistinguishedName)
                        $Condition = 'O:SYG:SYD:(XA;OICI;CR;;;WD;(@USER.ad://ext/AuthenticationSilo== "Lockdown"))'
                    }
                    default
                    {
                        $Members =
                        @(
                            @(Get-ADGroup -Identity "$($Tier.Name) - Administrators" -Properties Members | Select-Object -ExpandProperty Members) +
                            @(Get-ADGroup -Identity "$($Tier.Name) - Users" -Properties Members | Select-Object -ExpandProperty Members)
                        )
                        $Condition = "O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of_any {SID($(Get-ADGroup -Identity "$($Tier.Name) - Computers" | Select-Object -ExpandProperty SID | Select-Object -ExpandProperty Value))}))"
                    }
                }

                # Get policy
                $AuthPolicy = Get-ADAuthenticationPolicy -Filter "Name -eq '$($Tier.Name) Policy'"

                if ($SecureTiering -eq $true)
                {
                    ################
                    # Create Policy
                    ################

                    if (-not $AuthPolicy -and (ShouldProcess @WhatIfSplat -Message "Adding `"$($Tier.Name) Policy`"" @VerboseSplat))
                    {
                        $Splat =
                        @{
                            Name = "$($Tier.Name) Policy"
                            Enforce = $true
                            ProtectedFromAccidentalDeletion = $false
                            UserTGTLifetimeMins = $Tier.Liftime
                            UserAllowedToAuthenticateFrom = $Condition
                        }

                        $AuthPolicy = New-ADAuthenticationPolicy @Splat -PassThru
                    }

                    <#

                    ##############
                    # Create Silo
                    ##############

                    if (-not (Get-ADAuthenticationPolicySilo -Filter "Name -eq '$($Tier.Name) Silo'") -and
                        (ShouldProcess @WhatIfSplat -Message "Adding `"$($Tier.Name) Silo`"" @VerboseSplat))
                    {
                        $Splat =
                        @{
                            Name = "$($Tier.Name) Silo"
                            Enforce = $true
                            ProtectedFromAccidentalDeletion = $false
                            UserAuthenticationPolicy = "$($Tier.Name) Policy"
                            ServiceAuthenticationPolicy = "$($Tier.Name) Policy"
                            ComputerAuthenticationPolicy = "$($Tier.Name) Policy"
                        }

                        New-ADAuthenticationPolicySilo @Splat
                    }

                    #>
                }

                ################
                # Add to Policy
                ################

                if ($AuthPolicy)
                {
                    # Itterate all group members
                    foreach ($MemberDN in $Members)
                    {
                        # Get common name
                        $MemberCN = $($MemberDN -match 'CN=(.*?),' | ForEach-Object { $Matches[1] })

                        # Get assigned authentication policy
                        $AssignedPolicy = Get-ADObject -Identity $MemberDN -Properties msDS-AssignedAuthNPolicy | Select-Object -ExpandProperty msDS-AssignedAuthNPolicy

                        if (-not $AssignedPolicy -or $AssignedPolicy -notmatch $AuthPolicy.DistinguishedName -and
                            (ShouldProcess -Message "Adding `"$MemberCN`" to `"$($Tier.Name) Policy`"" @VerboseSplat))
                        {
                            Set-ADAccountAuthenticationPolicySilo -AuthenticationPolicy $AuthPolicy.DistinguishedName -Identity $MemberDN
                        }
                    }
                }

                <#

                #####################
                # Add/Assign to Silo
                #####################

                # Itterate all group members
                foreach ($Member in $Members)
                {
                    # Get common name
                    $MemberCN = $($Member -match 'CN=(.*?),' | ForEach-Object { $Matches[1] })

                    if ($Member -notin (Get-ADAuthenticationPolicySilo -Filter "Name -eq '$($Tier.Name) Silo'" | Select-Object -ExpandProperty Members) -and
                        (ShouldProcess -Message "Adding `"$MemberCN`" to `"$($Tier.Name) Silo`"" @VerboseSplat))
                    {
                        Grant-ADAuthenticationPolicySiloAccess -Identity "$($Tier.Name) Silo" -Account "$Member"
                    }

                    # Get assigned authentication policy silo
                    $AssignedPolicy = Get-ADObject -Identity $Member -Properties msDS-AssignedAuthNPolicySilo | Select-Object -ExpandProperty msDS-AssignedAuthNPolicySilo

                    if (-not $AssignedPolicy -or $AssignedPolicy -notmatch "CN=$($Tier.Name) Silo" -and
                        (ShouldProcess -Message "Assigning `"$MemberCN`" with `"$($Tier.Name) Silo`"" @VerboseSplat))
                    {
                        Set-ADAccountAuthenticationPolicySilo -AuthenticationPolicySilo "$($Tier.Name) Silo" -Identity $Member
                    }
                }

                #>

                if ($SecureTiering -eq $false)
                {
                    if ((Get-ADAuthenticationPolicySilo -Filter "Name -eq '$($Tier.Name) Silo'") -and
                        (ShouldProcess @WhatIfSplat -Message "Removing `"$($Tier.Name) Silo`"" @VerboseSplat))
                    {
                        Remove-ADAuthenticationPolicySilo -Identity "$($Tier.Name) Silo" -Confirm:$false
                    }

                    if ((Get-ADAuthenticationPolicy -Filter "Name -eq '$($Tier.Name) Policy'") -and
                        (ShouldProcess @WhatIfSplat -Message "Removing `"$($Tier.Name) Policy`"" @VerboseSplat))
                    {
                        Remove-ADAuthenticationPolicy -Identity "$($Tier.Name) Policy" -Confirm:$false
                    }
                }
            }

            # ██╗      █████╗ ██████╗ ███████╗
            # ██║     ██╔══██╗██╔══██╗██╔════╝
            # ██║     ███████║██████╔╝███████╗
            # ██║     ██╔══██║██╔═══╝ ╚════██║
            # ███████╗██║  ██║██║     ███████║
            # ╚══════╝╚═╝  ╚═╝╚═╝     ╚══════╝

            # Check msLAPS-Password
            if (-not (TryCatch { Get-ADComputer -Filter "Name -eq '$ENV:ComputerName'" -SearchBase "OU=Domain Controllers,$BaseDN" -SearchScope OneLevel -Properties 'msLAPS-Password' } -Boolean -ErrorAction SilentlyContinue) -and
                (ShouldProcess @WhatIfSplat -Message "Updating LAPS schema." @VerboseSplat))
            {
                # Update schema
                Update-LapsAdSchema -Confirm:$false

                # Set permission
                Set-LapsADComputerSelfPermission -Identity "OU=$DomainName,$BaseDN"
            }

            # ██████╗  ██████╗ ███████╗████████╗
            # ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝
            # ██████╔╝██║   ██║███████╗   ██║
            # ██╔═══╝ ██║   ██║╚════██║   ██║
            # ██║     ╚██████╔╝███████║   ██║
            # ╚═╝      ╚═════╝ ╚══════╝   ╚═╝

            # ms-DS-MachineAccountQuota
            if ((Get-ADObject -Identity "$BaseDN" -Properties 'ms-DS-MachineAccountQuota' | Select-Object -ExpandProperty 'ms-DS-MachineAccountQuota') -ne 0 -and
                (ShouldProcess @WhatIfSplat -Message "Setting ms-DS-MachineAccountQuota = 0" @VerboseSplat))
            {
                Set-ADObject -Identity $BaseDN -Replace @{ 'ms-DS-MachineAccountQuota' = 0 }
            }

            # Subnet
            if (-not (Get-ADReplicationSubnet -Filter "Name -eq '$DomainNetworkId.0/24'") -and
                (ShouldProcess @WhatIfSplat -Message "Adding subnet `"$DomainNetworkId.0/24`" to `"Default-First-Site-Name`"." @VerboseSplat))
            {
                New-ADReplicationSubnet -Name "$DomainNetworkId.0/24" -Site 'Default-First-Site-Name'
            }

            # Recycle bin
            if (-not (Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" | Select-Object -ExpandProperty EnabledScopes) -and
                (ShouldProcess @WhatIfSplat -Message "Enabling Recycle Bin Feature." @VerboseSplat))
            {
                Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $DomainName -Confirm:$false > $null
            }

            # Register schema mmc
            if (-not (Get-Item -Path "Registry::HKEY_CLASSES_ROOT\CLSID\{333FE3FB-0A9D-11D1-BB10-00C04FC9A3A3}\InprocServer32" -ErrorAction SilentlyContinue) -and
                (ShouldProcess @WhatIfSplat -Message "Registering schmmgmt.dll." @VerboseSplat))
            {
                regsvr32.exe /s schmmgmt.dll
            }

            ###############
            # Empty groups
            ###############

            $EmptyGroups =
            @(
                # FIX remove Authenticated Users
                #'Pre-Windows 2000 Compatible Access'
                'Schema Admins',
                'Enterprise Admins'
            )

            # Remove members
            foreach ($Group in $EmptyGroups)
            {
                foreach ($Member in (Get-ADGroupMember -Identity $Group))
                {
                    if ((ShouldProcess @WhatIfSplat -Message "Removing `"$($Member.Name)`" from `"$Group`"." @VerboseSplat))
                    {
                        Remove-ADPrincipalGroupMembership -Identity $Member.DistinguishedName -MemberOf $Group -Confirm:$false
                    }
                }
            }

            # ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗      ██████╗ ██████╗  ██████╗
            # ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ██╔════╝ ██╔══██╗██╔═══██╗
            # ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝    ██║  ███╗██████╔╝██║   ██║
            # ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝     ██║   ██║██╔═══╝ ██║   ██║
            # ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║         ╚██████╔╝██║     ╚██████╔╝
            # ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝          ╚═════╝ ╚═╝      ╚═════╝

            if ($BackupGpo.IsPresent -and
                (ShouldProcess @WhatIfSplat -Message "Backing up GPOs to `"$env:TEMP\GpoBackup`"" @VerboseSplat))
            {
                # Remove old directory
                Remove-Item -Recurse -Path "$env:TEMP\GpoBackup" -Force -ErrorAction SilentlyContinue

                # Create new directory
                New-Item -Path "$env:TEMP\GpoBackup" -ItemType Directory > $null

                # Export
                foreach($Gpo in (Get-GPO -All | Where-Object { $_.DisplayName.StartsWith($DomainPrefix) }))
                {
                    # Backup gpo
                    $Backup = Backup-GPO -Guid $Gpo.Id -Path "$env:TEMP\GpoBackup"

                    # Replace domain name in site to zone assignment list

                    if ($Backup.DisplayName -match 'Computer - Internet Explorer Site to Zone Assignment List')
                    {
                        # Get backup filepath
                        $GpReportFile = "$env:TEMP\GpoBackup\{$($Backup.Id)}\gpreport.xml"

                        # Replace domain wildcard with placeholder
                        ((Get-Content -Path $GpReportFile -Raw) -replace "\*\.$($DomainName -replace '\.', '\.')", '%domain_wildcard%') | Set-Content -Path $GpReportFile
                    }

                    # Replace sids in GptTempl.inf

                    if ($Backup.DisplayName -match 'Restrict User Rights Assignment')
                    {
                        $GptTmplFile = "$env:TEMP\GpoBackup\{$($Backup.Id)}\DomainSysvol\GPO\Machine\microsoft\windows nt\SecEdit\GptTmpl.inf"

                        $GptContent = Get-Content -Path $GptTmplFile -Raw
                        $GptContent = $GptContent -replace "\*$((Get-ADUser  -Identity 'JoinDomain').SID.Value)", '%join_domain%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Domain Admins').SID.Value)", '%domain_admins%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Enterprise Admins').SID.Value)", '%enterprise_admins%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Schema Admins').SID.Value)", '%schema_admins%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 0 - Administrators').SID.Value)", '%tier_0_admins%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 0 - Computers').SID.Value)", '%tier_0_computers%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 0 - Users').SID.Value)", '%tier_0_users%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 1 - Administrators').SID.Value)", '%tier_1_admins%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 1 - Computers').SID.Value)", '%tier_1_computers%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 1 - Users').SID.Value)", '%tier_1_users%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 2 - Administrators').SID.Value)", '%tier_2_admins%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 2 - Computers').SID.Value)", '%tier_2_computers%'
                        $GptContent = $GptContent -replace "\*$((Get-ADGroup -Identity 'Tier 2 - Users').SID.Value)", '%tier_2_users%'

                        Set-Content -Path $GptTmplFile -Value $GptContent
                    }
                }

                foreach($file in (Get-ChildItem -Recurse -Force -Path "$env:TEMP\GpoBackup"))
                {
                    if ($file.Attributes.ToString().Contains('Hidden'))
                    {
                        Set-ItemProperty -Path $file.FullName -Name Attributes -Value Normal
                    }
                }
            }

            # ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗     ████████╗███████╗███╗   ███╗██████╗ ██╗      █████╗ ████████╗███████╗███████╗
            # ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ╚══██╔══╝██╔════╝████╗ ████║██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
            # ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝       ██║   █████╗  ██╔████╔██║██████╔╝██║     ███████║   ██║   █████╗  ███████╗
            # ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝        ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
            # ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║            ██║   ███████╗██║ ╚═╝ ██║██║     ███████╗██║  ██║   ██║   ███████╗███████║
            # ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝            ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

            if ($BackupTemplates.IsPresent -and
                (ShouldProcess @WhatIfSplat -Message "Backing up certificate templates to `"$env:TEMP\TemplatesBackup`"" @VerboseSplat))
            {
                # Remove old directory
                Remove-Item -Path "$env:TEMP\TemplatesBackup" -Recurse -Force -ErrorAction SilentlyContinue

                # Create new directory
                New-Item -Path "$env:TEMP\TemplatesBackup" -ItemType Directory > $null

                # Export
                foreach($Template in (Get-ADObject -Filter "Name -like '$DomainPrefix*' -and objectClass -eq 'pKICertificateTemplate'" -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN" -SearchScope Subtree -Property *))
                {
                    # Remove domain prefix
                    $Name = $Template.Name.Replace($DomainPrefix, '')

                    # Export template to json files
                    $Template | Select-Object -Property @{ n = 'Name' ; e = { $Name }}, @{ n = 'DisplayName'; e = { $_.DisplayName.Replace("$DomainPrefix ", '') }}, flags, revision, *PKI*, @{ n = 'msPKI-Template-Minor-Revision' ; e = { 1 }} -ExcludeProperty 'msPKI-Template-Minor-Revision', 'msPKI-Cert-Template-OID' | ConvertTo-Json | Out-File -FilePath "$env:TEMP\TemplatesBackup\$($Name)_tmpl.json"

                    # Export acl to json files
                    # Note: Convert to/from csv for ToString on all enums
                    Get-Acl -Path "AD:$($Template.DistinguishedName)" | Select-Object -ExpandProperty Access | Select-Object -Property *, @{ n = 'IdentityReference'; e = { $_.IdentityReference.ToString().Replace($DomainNetbiosName, '%domain%') }} -ExcludeProperty 'IdentityReference' | ConvertTo-Csv | ConvertFrom-Csv | ConvertTo-Json | Out-File -FilePath "$env:TEMP\TemplatesBackup\$($Name)_acl.json"
                }
            }

            # ██████╗ ███████╗████████╗██╗   ██╗██████╗ ███╗   ██╗
            # ██╔══██╗██╔════╝╚══██╔══╝██║   ██║██╔══██╗████╗  ██║
            # ██████╔╝█████╗     ██║   ██║   ██║██████╔╝██╔██╗ ██║
            # ██╔══██╗██╔══╝     ██║   ██║   ██║██╔══██╗██║╚██╗██║
            # ██║  ██║███████╗   ██║   ╚██████╔╝██║  ██║██║ ╚████║
            # ╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝

            # Check size
            if ($UpdatedObjects.Count -gt 0)
            {
                $Result.Add('ComputersAddedToGroup', $UpdatedObjects)
            }

            Write-Output -InputObject $Result
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
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_ShouldProcess.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_TryCatch.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_GetBaseDN.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_SetAce.ps1

        # Get parameters
        Invoke-Command -Session $Session -ScriptBlock `
        {
            # Common
            $VerboseSplat = $Using:VerboseSplat
            $WhatIfSplat  = $Using:WhatIfSplat
            $Force        = $Using:Force

            # Mandatory parameters
            $DomainName = $Using:DomainName
            $DomainNetbiosName = $Using:DomainNetbiosName
            $DomainLocalPassword = $Using:DomainLocalPassword
            $DomainNetworkId = $Using:DomainNetworkId

            # DNS
            $DNSReverseLookupZone = $Using:DNSReverseLookupZone
            $DNSRefreshInterval = $Using:DNSRefreshInterval
            $DNSNoRefreshInterval = $Using:DNSNoRefreshInterval
            $DNSScavengingInterval = $Using:DNSScavengingInterval
            $DNSScavengingState = $Using:DNSScavengingState

            # DHCP
            $DHCPScope = $Using:DHCPScope
            $DHCPScopeStartRange = $Using:DHCPScopeStartRange
            $DHCPScopeEndRange = $Using:DHCPScopeEndRange
            $DHCPScopeSubnetMask = $Using:DHCPScopeSubnetMask
            $DHCPScopeDefaultGateway = $Using:DHCPScopeDefaultGateway
            $DHCPScopeDNSServer = $Using:DHCPScopeDNSServer
            $DHCPScopeLeaseDuration = $Using:DHCPScopeLeaseDuration

            # Switches
            $BackupGpo = $Using:BackupGpo
            $BackupTemplates = $Using:BackupTemplates
            $RemoveAuthenticatedUsersFromUserGpos = $Using:RemoveAuthenticatedUsersFromUserGpos
            $SecureTiering = $Using:SecureTiering
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
                # f_ShouldProcess.ps1 loaded in Begin
                . $PSScriptRoot\f_TryCatch.ps1
                . $PSScriptRoot\f_GetBaseDN.ps1
                . $PSScriptRoot\f_SetAce.ps1
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
}

# SIG # Begin signature block
# MIIekQYJKoZIhvcNAQcCoIIegjCCHn4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU7pc7ylIso9ib4OTeqYKfQIdK
# ZkWgghgSMIIFBzCCAu+gAwIBAgIQJTSMe3EEUZZAAWO1zNUfWTANBgkqhkiG9w0B
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU48P09l20
# 8fJoIGZ1uqLqGS0C++YwDQYJKoZIhvcNAQEBBQAEggIAyxXDMwHV0slicSH2Cchw
# GLDwmM2ObG7YxUs5kiS9NOWf3yj+cywrdbFh5vDJumPFZ+BeT6GRmAFBs3sU2Ny9
# qL6+wYe3ZhDsv5l/LsHwB2HfMyEoOibvOooky5dL6ruB569pNJB5JlTEijrNdfyr
# 1S/2sdTyVjYGL1YsGmUYeSghCokmsj2f18T3iIzHRHBG5ysY7T4O1oqyDci3pk/Q
# FsSw7lrF13wB4vS5VjgoP+qXQSQgJOC+vtUYZ+O4/dAYn4GMV0DCLN9Qng6hntNL
# xrNts+GuE5Dc2XudFxtTK5OhOJbGJhX8QSFJ4P0V2hbKred8prRFoZIHLZL8l1PR
# y2nWtlJtbYX5fh1Q4gw9gybi3RodJZE4fw0i21CefkmOiDk9FiTszw2IemnmZsgg
# VZeQKSVnGNAkC/aOoRK6PLWMG/VC8rmhBa2cZ7hlV+zRTzy2gC0Rg5KR2z/KY29T
# NIYUmDQJ6knujwSXzGRxjR9H0aexyz+2Y4IN5Y3ust+8E/gZ+425Jh8gJJ0QwDky
# DSI7b/mQ1pAQI6kL8rVrPW8ToLmeDiQE6mgaR4VjXdkcQqdDLp3QARScAOFo/tFL
# EJ6j61fgZl2Y7e/RX6ssQOkZPMDPIs7VsxJlVuDj/IvR6AX6yFNE41bDw7jX/tUn
# VIcr3ItnIJpvHiKv7nDszlChggMgMIIDHAYJKoZIhvcNAQkGMYIDDTCCAwkCAQEw
# dzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNV
# BAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1w
# aW5nIENBAhAMTWlyS5T6PCpKPSkHgD1aMA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZI
# hvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjMwNDI3MjEwMDAz
# WjAvBgkqhkiG9w0BCQQxIgQgQY3FILHDGUz+eA5UXEyaUfZPsL4PGmBBIa0NFGGr
# SwowDQYJKoZIhvcNAQEBBQAEggIAOpaGecILpI2DP1/O2hQjEBk7rdX+MNPRuC2E
# pDRLk/zzsCavQEneFfVP9TU4hGxD+RblLw1rTlvm0jXOgAjPsW7Mu1SJeBjMXF9f
# 2UUfkadi6bXIAJmo7Od1QkwjB5IALIqZOBkIahavtNb7WABy165GhCqMYPHHR1ag
# PYlv290z/t+DfLZ6a98+q45+LU3Q3QBUmHq4ckPguiABrb5cxPHxG81tnclMcRRY
# rbSDYYzR6k5QxOiyMmISQ2Segy9mQ5jqSO2YT/eP8s7aSGAy6mh+sgl3ONHDWmiT
# rfFByfcbr7X6hEtEDd+GapVxFXbqqB8F/5IbiMCR8XqKjWcePIXiDAjY1UmZLrHk
# pfeo0cVbsCAJ2RvoqsobreNoBDPv14/yLDWtH8BR8uxK2TXrruJalxSCwidgUR5x
# ruGAAj27G8PHp1i1iN/aX9UQRJWp/tFShz0JevkfHem3bQbbZFMfNLrd8HajtH/Z
# WB9gU9te0WsdiwIWgpv7Wg7jUN9ikjNIgDk3+w4v8NIvFCrCdLCTIM8ou6pCjH1e
# vNVpVz+DbHx5vbTi+2KRGY3rWzSFh5DS9ngA+nvU1IIp6debwpdRRIz2c1WaV23l
# HQMuxd78n+WjnL27WVucxgiDMXe8o0haHhKYgPdEmnn0lL55GgIyjX5mhoeY7iB4
# dChA6fM=
# SIG # End signature block
