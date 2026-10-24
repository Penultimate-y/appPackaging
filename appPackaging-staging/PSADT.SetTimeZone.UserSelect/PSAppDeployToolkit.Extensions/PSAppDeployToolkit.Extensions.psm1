<#

.SYNOPSIS
PSAppDeployToolkit.Extensions - Custom functions for Time Zone selection.

.DESCRIPTION
This module extends PSADT v4 with a custom timezone selection dialog showing all
available system timezones (global coverage).

#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1


##*===============================================
##* MARK: FUNCTION LISTINGS
##*===============================================

function Show-ADTTimeZoneSelection
{
    <#
    .SYNOPSIS
        Displays a dialog for users to select their timezone from all available system timezones.

    .DESCRIPTION
        Shows a WinForms dialog with dropdown selection of all Windows timezones, sorted by
        UTC offset. Runs in user context even when invoked from SYSTEM. Returns the selected
        Windows timezone ID.

    .PARAMETER DefaultTimeZone
        The timezone ID to pre-select in the dropdown. Defaults to current timezone.

    .OUTPUTS
        System.String
        Returns the selected Windows timezone ID (e.g., "Eastern Standard Time")

    .EXAMPLE
        $selectedTZ = Show-ADTTimeZoneSelection
        Set-TimeZone -Id $selectedTZ

    .EXAMPLE
        $selectedTZ = Show-ADTTimeZoneSelection -DefaultTimeZone "Pacific Standard Time"
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [System.String]$DefaultTimeZone = (Get-TimeZone).Id
    )

    begin
    {
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        Write-ADTLogEntry -Message "Preparing timezone selection dialog..."
    }

    process
    {
        try
        {
            try
            {
                # Define US timezones to feature at the top of the list
                $usTimeZoneIds = @(
                    'Eastern Standard Time'
                    'Central Standard Time'
                    'Mountain Standard Time'
                    'US Mountain Standard Time'
                    'Pacific Standard Time'
                    'Alaskan Standard Time'
                    'Hawaiian Standard Time'
                )

                # Build display formatter
                function Format-TZDisplay($tz) {
                    $offset = $tz.BaseUtcOffset
                    $sign = if ($offset -lt [TimeSpan]::Zero) { '-' } else { '+' }
                    $absOffset = if ($offset -lt [TimeSpan]::Zero) { $offset.Negate() } else { $offset }
                    $utcLabel = '(UTC{0}{1:D2}:{2:D2})' -f $sign, $absOffset.Hours, $absOffset.Minutes
                    $displayName = $tz.DisplayName -replace '^\(UTC[^\)]*\)\s*', ''
                    return "$utcLabel $displayName"
                }

                # Get all available system timezones
                $allSystemTZ = Get-TimeZone -ListAvailable

                # Build US section (featured at top)
                $usTZObjects = $allSystemTZ | Where-Object { $_.Id -in $usTimeZoneIds } |
                    Sort-Object BaseUtcOffset |
                    ForEach-Object { @{ Id = $_.Id; Display = Format-TZDisplay $_; Section = 'US' } }

                # Build global section (everything else, sorted by UTC offset)
                $globalTZObjects = $allSystemTZ | Where-Object { $_.Id -notin $usTimeZoneIds } |
                    Sort-Object BaseUtcOffset |
                    ForEach-Object { @{ Id = $_.Id; Display = Format-TZDisplay $_; Section = 'Global' } }

                # Combine: US first, separator, then global
                $separator = @{ Id = '---'; Display = '── All Timezones ──────────────────────────'; Section = 'Separator' }
                $allTimeZones = @($usTZObjects) + @($separator) + @($globalTZObjects)

                Write-ADTLogEntry -Message "Loaded $($usTZObjects.Count) US + $($globalTZObjects.Count) global timezone options"
                Write-ADTLogEntry -Message "Current timezone: $DefaultTimeZone"

                # Build the dropdown items text for Show-ADTInstallationPrompt
                # Format: "Display Text 1|Display Text 2|Display Text 3"
                $dropdownItems = ($allTimeZones | ForEach-Object { $_.Display }) -join '|'

                # Find the index of the current timezone for pre-selection
                # Searches US section first, then global section
                $defaultIndex = 0
                for ($i = 0; $i -lt $allTimeZones.Count; $i++)
                {
                    if ($allTimeZones[$i].Id -eq $DefaultTimeZone)
                    {
                        $defaultIndex = $i
                        Write-ADTLogEntry -Message "Pre-selecting index $defaultIndex for $DefaultTimeZone"
                        break
                    }
                }

                # Show the selection dialog
                $promptMessage = @"
Select your timezone from the list below.

This setting will configure your system clock for the correct time display and automatic daylight saving time adjustments.

Your current timezone: $DefaultTimeZone

Tip: The list is sorted by UTC offset. Use the dropdown to scroll or type to search.
"@

                Write-ADTLogEntry -Message "Displaying timezone selection dialog to user..."

                # PSADT v4 does not have native dropdown support in Show-ADTInstallationPrompt
                # We must use Windows Forms to create a custom dropdown dialog
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing

                # Create the form
                $form = New-Object System.Windows.Forms.Form
                $form.Text = 'Time Zone Configuration'
                $form.Size = New-Object System.Drawing.Size(600, 350)
                $form.StartPosition = 'CenterScreen'
                $form.FormBorderStyle = 'FixedDialog'
                $form.MaximizeBox = $false
                $form.MinimizeBox = $false
                $form.TopMost = $true
                $form.Icon = [System.Drawing.SystemIcons]::Information

                # Add message label
                $label = New-Object System.Windows.Forms.Label
                $label.Location = New-Object System.Drawing.Point(10, 10)
                $label.Size = New-Object System.Drawing.Size(560, 140)
                $label.Text = $promptMessage
                $form.Controls.Add($label)

                # Add ComboBox for timezone selection
                $comboBox = New-Object System.Windows.Forms.ComboBox
                $comboBox.Location = New-Object System.Drawing.Point(10, 160)
                $comboBox.Size = New-Object System.Drawing.Size(560, 25)
                $comboBox.DropDownStyle = 'DropDownList'

                # Populate the ComboBox with timezone display names
                foreach ($tz in $allTimeZones)
                {
                    [void]$comboBox.Items.Add($tz.Display)
                }

                # Set the default selected item
                $comboBox.SelectedIndex = $defaultIndex
                $form.Controls.Add($comboBox)

                # Add OK button
                $okButton = New-Object System.Windows.Forms.Button
                $okButton.Location = New-Object System.Drawing.Point(400, 270)
                $okButton.Size = New-Object System.Drawing.Size(75, 30)
                $okButton.Text = 'OK'
                $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.AcceptButton = $okButton
                $form.Controls.Add($okButton)

                # Add Cancel button
                $cancelButton = New-Object System.Windows.Forms.Button
                $cancelButton.Location = New-Object System.Drawing.Point(490, 270)
                $cancelButton.Size = New-Object System.Drawing.Size(75, 30)
                $cancelButton.Text = 'Cancel'
                $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                $form.CancelButton = $cancelButton
                $form.Controls.Add($cancelButton)

                # Show the form and get the result
                $result = $form.ShowDialog()

                if ($result -eq [System.Windows.Forms.DialogResult]::OK)
                {
                    $selectedIndex = $comboBox.SelectedIndex
                    $selectedItem = $allTimeZones[$selectedIndex]

                    # Don't allow the separator to be selected
                    if ($selectedItem.Id -eq '---')
                    {
                        Write-ADTLogEntry -Message "User selected separator row — treating as cancel" -Severity 2
                        $form.Dispose()
                        throw "Timezone selection was cancelled by user"
                    }

                    $selectedTimeZone = $selectedItem.Id
                    $selectedDisplay = $selectedItem.Display

                    Write-ADTLogEntry -Message "User selected: $selectedDisplay (ID: $selectedTimeZone)"

                    # Clean up
                    $form.Dispose()

                    return $selectedTimeZone
                }
                else
                {
                    Write-ADTLogEntry -Message "User cancelled timezone selection" -Severity 2
                    $form.Dispose()
                    throw "Timezone selection was cancelled by user"
                }
            }
            catch
            {
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}


##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported successfully." -ScriptSection Initialization
