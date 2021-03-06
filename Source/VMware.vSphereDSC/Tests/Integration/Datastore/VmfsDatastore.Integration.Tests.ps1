<#
Copyright (c) 2018 VMware, Inc.  All rights reserved

The BSD-2 license (the "License") set forth below applies to all parts of the Desired State Configuration Resources for VMware project.  You may not use this file except in compliance with the License.

BSD-2 License

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#>

Param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Server,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $User,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Password,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name
)

<#
.DESCRIPTION

Retrieves the canonical name of the Scsi logical unit that will contain the Vmfs Datastore used in the Integration Tests.
#>
function Invoke-TestSetup {
    $viServer = Connect-VIServer -Server $Server -User $User -Password $Password -ErrorAction Stop -Verbose:$false
    $vmHost = Get-VMHost -Server $viServer -Name $Name -ErrorAction Stop -Verbose:$false
    $datastoreSystem = Get-View -Server $viServer -Id $vmHost.ExtensionData.ConfigManager.DatastoreSystem -ErrorAction Stop -Verbose:$false
    $scsiLun = $datastoreSystem.QueryAvailableDisksForVmfs($null) | Select-Object -First 1

    if ($null -eq $scsiLun) {
        throw 'The Vmfs Datastore that is used in the Integration Tests requires one unused Scsi logical unit to be available.'
    }

    $script:scsiLunCanonicalName = $scsiLun.CanonicalName

    Disconnect-VIServer -Server $Server -Confirm:$false -ErrorAction Stop -Verbose:$false
}

Invoke-TestSetup

$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (ConvertTo-SecureString -String $Password -AsPlainText -Force)

$script:dscResourceName = 'VmfsDatastore'
$script:moduleFolderPath = (Get-Module -Name 'VMware.vSphereDSC' -ListAvailable).ModuleBase
$script:integrationTestsFolderPath = Join-Path -Path (Join-Path -Path $moduleFolderPath -ChildPath 'Tests') -ChildPath 'Integration'
$script:configurationFile = "$script:integrationTestsFolderPath\Configurations\$script:dscResourceName\$($script:dscResourceName)_Config.ps1"

$script:configurationData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
            Server = $Server
            Credential = $Credential
            VMHostName = $Name
            VmfsDatastoreResourceName = 'VmfsDatastore'
            DatastoreName = 'MyTestVmfsDatastore'
            ScsiLunCanonicalName = $script:scsiLunCanonicalName
            FileSystemVersion = '5'
            BlockSizeMB = 1
            StorageIOControlEnabled = $false
            DefaultCongestionThresholdMillisecond = 30
            MinCongestionThresholdMillisecond = 10
            MaxCongestionThresholdMillisecond = 100
        }
    )
}

$script:configCreateVmfsDatastore = "$($script:dscResourceName)_CreateVmfsDatastore_Config"
$script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond = "$($script:dscResourceName)_CreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond_Config"
$script:configModifyVmfsDatastore = "$($script:dscResourceName)_ModifyVmfsDatastore_Config"
$script:configRemoveVmfsDatastore = "$($script:dscResourceName)_RemoveVmfsDatastore_Config"

. $script:configurationFile -ErrorAction Stop

$script:mofFileCreateVmfsDatastorePath = "$script:integrationTestsFolderPath\$script:configCreateVmfsDatastore\"
$script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath = "$script:integrationTestsFolderPath\$script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond\"
$script:mofFileModifyVmfsDatastorePath = "$script:integrationTestsFolderPath\$script:configModifyVmfsDatastore\"
$script:mofFileRemoveVmfsDatastorePath = "$script:integrationTestsFolderPath\$script:configRemoveVmfsDatastore\"

Describe "$($script:dscResourceName)_Integration" {
    Context "When using configuration $script:configCreateVmfsDatastore" {
        BeforeAll {
            # Arrange
            & $script:configCreateVmfsDatastore `
                -OutputPath $script:mofFileCreateVmfsDatastorePath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParameters = @{
                Path = $script:mofFileCreateVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParameters
        }

        It 'Should apply the MOF without throwing' {
            # Arrange
            $startDscConfigurationParameters = @{
                Path = $script:mofFileCreateVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            { Start-DscConfiguration @startDscConfigurationParameters } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            # Arrange && Act && Assert
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration and all parameters should match' {
            # Arrange && Act
            $configuration = Get-DscConfiguration -Verbose -ErrorAction Stop | Where-Object -FilterScript { $_.ConfigurationName -eq $script:configCreateVmfsDatastore }

            # Assert
            $configuration.Server | Should -Be $script:configurationData.AllNodes.Server
            $configuration.VMHostName | Should -Be $script:configurationData.AllNodes.VMHostName
            $configuration.Name | Should -Be $script:configurationData.AllNodes.DatastoreName
            $configuration.Path | Should -Be $script:configurationData.AllNodes.ScsiLunCanonicalName
            $configuration.Ensure | Should -Be 'Present'
            $configuration.FileSystemVersion | Should -BeLike "$($script:configurationData.AllNodes.FileSystemVersion)*"
            $configuration.BlockSizeMB | Should -Be $script:configurationData.AllNodes.BlockSizeMB
            $configuration.StorageIOControlEnabled | Should -Be $script:configurationData.AllNodes.StorageIOControlEnabled
            $configuration.CongestionThresholdMillisecond | Should -Be $script:configurationData.AllNodes.DefaultCongestionThresholdMillisecond
        }

        It 'Should return $true when Test-DscConfiguration is run' {
            # Arrange
            $testDscConfigurationParameters = @{
                ReferenceConfiguration = "$script:mofFileCreateVmfsDatastorePath\$($script:configurationData.AllNodes.NodeName).mof"
                ComputerName = $script:configurationData.AllNodes.NodeName
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            (Test-DscConfiguration @testDscConfigurationParameters).InDesiredState | Should -Be $true
        }

        AfterAll {
            # Arrange
            & $script:configRemoveVmfsDatastore `
                -OutputPath $script:mofFileRemoveVmfsDatastorePath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParameters = @{
                Path = $script:mofFileRemoveVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParameters

            Remove-Item -Path $script:mofFileCreateVmfsDatastorePath -Recurse -Confirm:$false -ErrorAction Stop
            Remove-Item -Path $script:mofFileRemoveVmfsDatastorePath -Recurse -Confirm:$false -ErrorAction Stop
        }
    }

    Context "When using configuration $script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond" {
        BeforeAll {
            # Arrange
            & $script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond `
                -OutputPath $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParameters = @{
                Path = $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParameters
        }

        It 'Should apply the MOF without throwing' {
            # Arrange
            $startDscConfigurationParameters = @{
                Path = $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            { Start-DscConfiguration @startDscConfigurationParameters } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            # Arrange && Act && Assert
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration and all parameters should match' {
            # Arrange && Act
            $configuration = Get-DscConfiguration -Verbose -ErrorAction Stop | Where-Object -FilterScript { $_.ConfigurationName -eq $script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond }

            # Assert
            $configuration.Server | Should -Be $script:configurationData.AllNodes.Server
            $configuration.VMHostName | Should -Be $script:configurationData.AllNodes.VMHostName
            $configuration.Name | Should -Be $script:configurationData.AllNodes.DatastoreName
            $configuration.Path | Should -Be $script:configurationData.AllNodes.ScsiLunCanonicalName
            $configuration.Ensure | Should -Be 'Present'
            $configuration.FileSystemVersion | Should -BeLike "$($script:configurationData.AllNodes.FileSystemVersion)*"
            $configuration.BlockSizeMB | Should -Be $script:configurationData.AllNodes.BlockSizeMB
            $configuration.StorageIOControlEnabled | Should -BeTrue
            $configuration.CongestionThresholdMillisecond | Should -Be $script:configurationData.AllNodes.MaxCongestionThresholdMillisecond
        }

        It 'Should return $true when Test-DscConfiguration is run' {
            # Arrange
            $testDscConfigurationParameters = @{
                ReferenceConfiguration = "$script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath\$($script:configurationData.AllNodes.NodeName).mof"
                ComputerName = $script:configurationData.AllNodes.NodeName
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            (Test-DscConfiguration @testDscConfigurationParameters).InDesiredState | Should -Be $true
        }

        AfterAll {
            # Arrange
            & $script:configRemoveVmfsDatastore `
                -OutputPath $script:mofFileRemoveVmfsDatastorePath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParameters = @{
                Path = $script:mofFileRemoveVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParameters

            Remove-Item -Path $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath -Recurse -Confirm:$false -ErrorAction Stop
            Remove-Item -Path $script:mofFileRemoveVmfsDatastorePath -Recurse -Confirm:$false -ErrorAction Stop
        }
    }

    Context "When using configuration $script:configModifyVmfsDatastore" {
        BeforeAll {
            # Arrange
            & $script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond `
                -OutputPath $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            & $script:configModifyVmfsDatastore `
                -OutputPath $script:mofFileModifyVmfsDatastorePath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParametersCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond = @{
                Path = $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            $startDscConfigurationParametersModifyVmfsDatastore = @{
                Path = $script:mofFileModifyVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParametersCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond
            Start-DscConfiguration @startDscConfigurationParametersModifyVmfsDatastore
        }

        It 'Should apply the MOF without throwing' {
            # Arrange
            $startDscConfigurationParameters = @{
                Path = $script:mofFileModifyVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            { Start-DscConfiguration @startDscConfigurationParameters } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            # Arrange && Act && Assert
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration and all parameters should match' {
            # Arrange && Act
            $configuration = Get-DscConfiguration -Verbose -ErrorAction Stop | Where-Object -FilterScript { $_.ConfigurationName -eq $script:configModifyVmfsDatastore }

            # Assert
            $configuration.Server | Should -Be $script:configurationData.AllNodes.Server
            $configuration.VMHostName | Should -Be $script:configurationData.AllNodes.VMHostName
            $configuration.Name | Should -Be $script:configurationData.AllNodes.DatastoreName
            $configuration.Path | Should -Be $script:configurationData.AllNodes.ScsiLunCanonicalName
            $configuration.Ensure | Should -Be 'Present'
            $configuration.FileSystemVersion | Should -BeLike "$($script:configurationData.AllNodes.FileSystemVersion)*"
            $configuration.BlockSizeMB | Should -Be $script:configurationData.AllNodes.BlockSizeMB
            $configuration.StorageIOControlEnabled | Should -Be $script:configurationData.AllNodes.StorageIOControlEnabled
            $configuration.CongestionThresholdMillisecond | Should -Be $script:configurationData.AllNodes.MinCongestionThresholdMillisecond
        }

        It 'Should return $true when Test-DscConfiguration is run' {
            # Arrange
            $testDscConfigurationParameters = @{
                ReferenceConfiguration = "$script:mofFileModifyVmfsDatastorePath\$($script:configurationData.AllNodes.NodeName).mof"
                ComputerName = $script:configurationData.AllNodes.NodeName
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            (Test-DscConfiguration @testDscConfigurationParameters).InDesiredState | Should -Be $true
        }

        AfterAll {
            # Arrange
            & $script:configRemoveVmfsDatastore `
                -OutputPath $script:mofFileRemoveVmfsDatastorePath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParameters = @{
                Path = $script:mofFileRemoveVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParameters

            Remove-Item -Path $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath -Recurse -Confirm:$false -ErrorAction Stop
            Remove-Item -Path $script:mofFileModifyVmfsDatastorePath -Recurse -Confirm:$false -ErrorAction Stop
            Remove-Item -Path $script:mofFileRemoveVmfsDatastorePath -Recurse -Confirm:$false -ErrorAction Stop
        }
    }

    Context "When using configuration $script:configRemoveVmfsDatastore" {
        BeforeAll {
            # Arrange
            & $script:configCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond `
                -OutputPath $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            & $script:configRemoveVmfsDatastore `
                -OutputPath $script:mofFileRemoveVmfsDatastorePath `
                -ConfigurationData $script:configurationData `
                -ErrorAction Stop

            $startDscConfigurationParametersCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond = @{
                Path = $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            $startDscConfigurationParametersRemoveVmfsDatastore = @{
                Path = $script:mofFileRemoveVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act
            Start-DscConfiguration @startDscConfigurationParametersCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecond
            Start-DscConfiguration @startDscConfigurationParametersRemoveVmfsDatastore
        }

        It 'Should apply the MOF without throwing' {
            # Arrange
            $startDscConfigurationParameters = @{
                Path = $script:mofFileRemoveVmfsDatastorePath
                ComputerName = $script:configurationData.AllNodes.NodeName
                Wait = $true
                Force = $true
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            { Start-DscConfiguration @startDscConfigurationParameters } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            # Arrange && Act && Assert
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration and all parameters should match' {
            # Arrange && Act
            $configuration = Get-DscConfiguration -Verbose -ErrorAction Stop | Where-Object -FilterScript { $_.ConfigurationName -eq $script:configRemoveVmfsDatastore }

            # Assert
            $configuration.Server | Should -Be $script:configurationData.AllNodes.Server
            $configuration.VMHostName | Should -Be $script:configurationData.AllNodes.VMHostName
            $configuration.Name | Should -Be $script:configurationData.AllNodes.DatastoreName
            $configuration.Path | Should -Be $script:configurationData.AllNodes.ScsiLunCanonicalName
            $configuration.Ensure | Should -Be 'Absent'
            $configuration.FileSystemVersion | Should -Be $script:configurationData.AllNodes.FileSystemVersion
            $configuration.BlockSizeMB | Should -Be $script:configurationData.AllNodes.BlockSizeMB
            $configuration.StorageIOControlEnabled | Should -Be $script:configurationData.AllNodes.StorageIOControlEnabled
            $configuration.CongestionThresholdMillisecond | Should -Be $script:configurationData.AllNodes.DefaultCongestionThresholdMillisecond
        }

        It 'Should return $true when Test-DscConfiguration is run' {
            # Arrange
            $testDscConfigurationParameters = @{
                ReferenceConfiguration = "$script:mofFileRemoveVmfsDatastorePath\$($script:configurationData.AllNodes.NodeName).mof"
                ComputerName = $script:configurationData.AllNodes.NodeName
                Verbose = $true
                ErrorAction = 'Stop'
            }

            # Act && Assert
            (Test-DscConfiguration @testDscConfigurationParameters).InDesiredState | Should -Be $true
        }

        AfterAll {
            # Act
            Remove-Item -Path $script:mofFileCreateVmfsDatastoreAndModifyStorageIOControlEnabledAndCongestionThresholdMillisecondPath -Recurse -Confirm:$false -ErrorAction Stop
            Remove-Item -Path $script:mofFileRemoveVmfsDatastorePath -Recurse -Confirm:$false -ErrorAction Stop
        }
    }
}
