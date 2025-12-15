# PmcApplication.Tests.ps1 - Integration tests for core application components

BeforeAll {
    # Get script directory
    $script:consoleUIDir = Split-Path -Parent $PSScriptRoot
    
    # Load helper functions
    . "$script:consoleUIDir/helpers/TypeNormalization.ps1"
    
    # Load ServiceContainer
    . "$script:consoleUIDir/ServiceContainer.ps1"
    
    # Mock logging
    $global:PmcTuiLogFile = $null
    function global:Write-PmcTuiLog {
        param([string]$Message, [string]$Level = "INFO")
    }
    
    # Test data directory
    $script:testDataDir = "/tmp/pmc-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $script:testDataDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:testDataDir) {
        Remove-Item -Recurse -Force $script:testDataDir
    }
}

# === ServiceContainer Tests ===

Describe "ServiceContainer - Registration" {
    BeforeEach {
        $script:container = [ServiceContainer]::new()
    }

    It "Registers and resolves singleton service" {
        $script:counter = 0
        $script:container.Register('TestService', {
            $script:counter++
            return @{ id = $script:counter }
        }, $true)  # singleton
        
        $first = $script:container.Resolve('TestService')
        $second = $script:container.Resolve('TestService')
        
        $first | Should -Be $second
        $script:counter | Should -Be 1
    }

    It "Registers and resolves transient service" {
        $script:counter = 0
        $script:container.Register('TransientService', {
            $script:counter++
            return @{ id = $script:counter }
        }, $false)  # transient
        
        $first = $script:container.Resolve('TransientService')
        $second = $script:container.Resolve('TransientService')
        
        $first.id | Should -Not -Be $second.id
        $script:counter | Should -Be 2
    }

    It "Throws for unregistered service" {
        { $script:container.Resolve('NonExistent') } | Should -Throw
    }

    It "Checks registration status" {
        $script:container.Register('TestService', { @{} }, $true)
        
        $script:container.IsRegistered('TestService') | Should -Be $true
        $script:container.IsRegistered('NonExistent') | Should -Be $false
    }

    It "Passes container to factory function" {
        $script:container.Register('ServiceA', { 
            param($c)
            @{ name = 'A' }
        }, $true)
        
        $script:container.Register('ServiceB', { 
            param($c)
            $a = $c.Resolve('ServiceA')
            @{ name = 'B'; dependency = $a }
        }, $true)
        
        $b = $script:container.Resolve('ServiceB')
        $b.name | Should -Be 'B'
        $b.dependency.name | Should -Be 'A'
    }
}

Describe "ServiceContainer - Circular Dependency Detection" {
    BeforeEach {
        $script:container = [ServiceContainer]::new()
    }

    It "Detects direct circular dependency" {
        $script:container.Register('ServiceA', {
            param($c)
            $c.Resolve('ServiceA')  # Direct self-reference
        }, $true)
        
        { $script:container.Resolve('ServiceA') } | Should -Throw
    }

    It "Detects indirect circular dependency" {
        $script:container.Register('ServiceA', {
            param($c)
            $c.Resolve('ServiceB')
        }, $true)
        
        $script:container.Register('ServiceB', {
            param($c)
            $c.Resolve('ServiceA')  # Cycle back
        }, $true)
        
        { $script:container.Resolve('ServiceA') } | Should -Throw
    }
}

# === Helper Function Tests ===

Describe "ErrorHandler Functions" {
    BeforeAll {
        . "$script:consoleUIDir/helpers/ErrorHandler.ps1"
    }

    It "Invoke-SafeBlock returns result on success" {
        $result = Invoke-SafeBlock -ScriptBlock { 42 } -Context "Test"
        $result | Should -Be 42
    }

    It "Invoke-SafeBlock returns default on error" {
        $result = Invoke-SafeBlock -ScriptBlock { throw "Error" } -Context "Test" -DefaultValue "fallback"
        $result | Should -Be "fallback"
    }

    It "Test-Precondition returns true for valid condition" {
        $result = Test-Precondition -Condition $true -ErrorMessage "Test"
        $result | Should -Be $true
    }

    It "Test-Precondition returns false for invalid condition" {
        $result = Test-Precondition -Condition $false -ErrorMessage "Test"
        $result | Should -Be $false
    }
}

Describe "InlineEditorFields Functions" {
    BeforeAll {
        . "$script:consoleUIDir/helpers/InlineEditorFields.ps1"
    }

    It "ConvertTo-DateFromText parses relative +days" {
        $result = ConvertTo-DateFromText "+7"
        $expected = [DateTime]::Now.AddDays(7).Date
        $result.Date | Should -Be $expected
    }

    It "ConvertTo-DateFromText parses 'today'" {
        $result = ConvertTo-DateFromText "today"
        $result | Should -Be ([DateTime]::Today)
    }

    It "ConvertTo-DateFromText parses 'tomorrow'" {
        $result = ConvertTo-DateFromText "tomorrow"
        $result | Should -Be ([DateTime]::Today.AddDays(1))
    }

    It "ConvertTo-DateFromText parses YYYYMMDD" {
        $result = ConvertTo-DateFromText "20240115"
        $result | Should -Be ([DateTime]::new(2024, 1, 15))
    }

    It "ConvertTo-DateFromText returns null for invalid" {
        $result = ConvertTo-DateFromText "invalid"
        $result | Should -BeNull
    }

    It "ConvertTo-TagsFromText parses comma-separated" {
        $result = ConvertTo-TagsFromText "urgent, high-priority, bug"
        $result.Count | Should -Be 3
        $result | Should -Contain "urgent"
        $result | Should -Contain "high-priority"
        $result | Should -Contain "bug"
    }

    It "ConvertTo-TagsFromText filters invalid tags" {
        $result = ConvertTo-TagsFromText "valid, inv@lid, another_valid"
        $result.Count | Should -Be 2
        $result | Should -Not -Contain "inv@lid"
    }

    It "Format-NumberSlider creates visual slider" {
        $result = Format-NumberSlider -Value 5 -Min 0 -Max 10
        $result | Should -Match "^\[.*●.*\] 5$"
    }

    It "Format-TagsDisplay formats array" {
        $result = Format-TagsDisplay @("a", "b")
        $result | Should -Be "[a] [b]"
    }

    It "Format-TagsDisplay returns placeholder for empty" {
        $result = Format-TagsDisplay @()
        $result | Should -Be "(no tags)"
    }
}

Describe "TimeValidationHelper Functions" {
    BeforeAll {
        . "$script:consoleUIDir/helpers/TimeValidationHelper.ps1"
    }

    It "ConvertTo-TimeMinutes validates hours" {
        $result = ConvertTo-TimeMinutes @{ hours = '2.5' }
        $result.Valid | Should -Be $true
        $result.Minutes | Should -Be 150
    }

    It "ConvertTo-TimeMinutes rejects missing hours" {
        $result = ConvertTo-TimeMinutes @{ }
        $result.Valid | Should -Be $false
        $result.ErrorMessage | Should -Not -BeNullOrEmpty
    }

    It "ConvertTo-TimeMinutes rejects negative hours" {
        $result = ConvertTo-TimeMinutes @{ hours = '-1' }
        $result.Valid | Should -Be $false
    }

    It "ConvertTo-SafeDate returns today for empty" {
        $result = ConvertTo-SafeDate @{ }
        $result | Should -Be ([DateTime]::Today)
    }

    It "ConvertTo-SafeDate parses valid date" {
        $result = ConvertTo-SafeDate @{ date = '2024-01-15' }
        $result | Should -Be ([DateTime]::new(2024, 1, 15))
    }
}

Describe "ClosureHelper Functions" {
    BeforeAll {
        . "$script:consoleUIDir/helpers/ClosureHelper.ps1"
    }

    It "New-MethodCallback creates working callback" {
        $obj = @{ 
            value = 0
            Increment = { param($by); $this.value += $by }
        }
        # Add method capability
        $obj = [PSCustomObject]$obj
        Add-Member -InputObject $obj -MemberType ScriptMethod -Name "Add" -Value { param($x); $this.value += $x }
        
        $callback = New-MethodCallback -Target $obj -MethodName "Add"
        & $callback 5
        
        $obj.value | Should -Be 5
    }

    It "New-SafeClosure captures variables" {
        $capturedValue = "test-value"
        
        $closure = New-SafeClosure -ScriptBlock { 
            return $capturedValue 
        } -CaptureVariables @{
            capturedValue = $capturedValue
        }
        
        $result = & $closure
        $result | Should -Be "test-value"
    }

    It "New-FormatterCallback works with simple formatter" {
        $formatter = New-FormatterCallback -FormatBlock {
            param($row)
            return $row.name.ToUpper()
        }
        
        $result = & $formatter @{ name = "test" }
        $result | Should -Be "TEST"
    }
}
