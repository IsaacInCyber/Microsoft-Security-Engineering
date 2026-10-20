
<#
.SYNOPSIS
    Microsoft Teams External Domain Removal and Audit

.DESCRIPTION
    Retrieves the Microsoft Teams external-domain allowlist,
    creates a backup, identifies CAB-approved domains for
    removal, validates the proposed changes, and removes
    the approved domains.

    After execution, the script retrieves the updated
    configuration and compares it against the expected
    allowlist to verify the change.

.PREREQUISITES
    - PowerShell 7 or later
    - MicrosoftTeams PowerShell module installed
    - Active Microsoft Teams PowerShell connection
    - Appropriate Teams administrative permissions
    - Teams configured to allow only specific external domains
    - Approved list of domains authorized for removal
    - Existing local folders for audit file output

.SETUP
    Install-Module MicrosoftTeams -Scope CurrentUser
    Import-Module MicrosoftTeams
    Connect-MicrosoftTeams

.EXECUTION
    ./Teams_external_domains_removal.ps1

.OUTPUTS
    Teams-Allowlist-Backup.txt
    Teams-Proposed-Removals.txt
    Teams-Updated-Allowlist.txt

.NOTES
    SECURITY WARNING:
    This script modifies live Microsoft Teams federation
    settings in the authenticated tenant.

    Verify the tenant, CAB approval, and proposed removal
    list before execution.

    Designed for administrator-supervised execution.
    Test in a non-production tenant before deployment.
#>


# Retrieving Microsoft Teams federation configuration & the current domains on the allowl list
try {
    $config = Get-CsTenantFederationConfiguration -ErrorAction Stop
}
catch {
   throw "Unable to retrieve Microsoft Teams federation configuration. Error details: $_"
}

$currentallowed_list = @(
    $config.AllowedDomains.AllowedDomain.Domain
)

# Creating an backup List & Saving Backup to disk & verify it.
$back_up_allowed_list = @($currentallowed_list)

try {
    $back_up_allowed_list | 
Downloads
    if( -not (Test-Path $HOME\Documents\Teams-Allowlist-Backup.txt)) {
   
    throw "Backup failed! The backup file was not created."
    }
}
catch {
    throw "Teams allowlist backup failed. Error details: $_"
}

# Verify that the backup matches the current allowlist
try {
    $objects = @{
        ReferenceObject  = @(Get-Content -Path "$HOME\Downloads\Teams-Allowlist-Backup.txt" -ErrorAction Stop)
        DifferenceObject = @($currentallowed_list)
    }

    $differences = @(Compare-Object @objects)

    if ($differences.Count -gt 0) {
        throw "Backup contents do not match the original allowlist."
    }
}
catch {
    throw "Teams allowlist verification failed. Error details: $_"
}

#part 2 

# Iterating through Approved domains for removal & Creating a dynamic list of the domains that will be removed.
$approved_for_removal = @(
    "silveroak-systems.example",
    "quantumridge.example",
    "velox-partners.example"
)

$DomainsToRemove = [System.Collections.Generic.List[string]]::new()

foreach ($domain in $currentallowed_list) {
    if ($domain -in $approved_for_removal) {
        $domainsToRemove.Add($domain)
    }
}

# Compare the domains to remove to the approved one

# Compare CAB-approved domains against proposed removals
$validation = @(
    Compare-Object -ReferenceObject $approved_for_removal -DifferenceObject $DomainsToRemove
)

if ($validation.Count -gt 0) {
    throw "Validation failed. The proposed removals do not match CAB approval."
}

Write-Output "Validation passed. All proposed removals match CAB approval."

# Outputting the domains that will be removed via txt file from the current live configs. 
$DomainsToRemove | Set-Content -Path "$HOME/Downloads/Teams-Proposed-Removals.txt" -ErrorAction Stop


# Part 3 — Updating Microsoft Teams federation configuration

# Remove CAB-approved domains
try {
    Set-CsTenantFederationConfiguration -AllowedDomainsAsAList @{Remove=$DomainsToRemove} -ErrorAction Stop
}
catch {
    throw "Teams domain removal failed. $_"
}

# Retrieve newly updated configuration
$newconfig = Get-CsTenantFederationConfiguration -ErrorAction Stop

$Updatedlist = @(
    $newconfig.AllowedDomains.AllowedDomain.Domain
)

# Save updated allowlist for auditing
$Updatedlist | Set-Content -Path "$HOME/Downloads/Teams-Updated-Allowlist.txt" -ErrorAction Stop

# Calculate what the updated list SHOULD contain
$Expectedlist = @(
    $currentallowed_list | Where-Object {
        $_ -notin $DomainsToRemove
    }
)

# Compare expected configuration with actual configuration
$validation = @(
    Compare-Object -ReferenceObject $Expectedlist -DifferenceObject $Updatedlist
)

if ($validation.Count -gt 0) {
    throw "Post-change verification failed. The allowlist does not match expectations."
}

Write-Output "Success. Only the approved domains were removed."
