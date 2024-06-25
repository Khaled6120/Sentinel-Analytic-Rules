$jsonConversionDepth = 50

function ConvertHuntingQueryFromYamlToArm {
    param (
        # Parameter help description
        [Parameter(Mandatory)][string] $inputFilePath,
        [Parameter(Mandatory)][string] $outputFilePath
    )

    $file = Get-Item -Path $inputFilePath
    $yaml = $null

    if ($file.FullName -match "(\.yaml)$") {
        $rawData = Get-Content $inputFilePath
        $content = ''
        foreach ($line in $rawData) {
            $content = $content + "`n" + $line
        }

        try {
            $yaml = ConvertFrom-YAML $content
        }
        catch {
            Write-Host "Failed to deserialize $file $_" -ForegroundColor Red 
            break;
        }
    }
                            
    $basicJson = @"
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "workspace": {
            "type": "String"
        }
    },
    "resources":[]
}
"@

    $baseHuntingObject = ConvertFrom-Json $basicJson
    $huntingQueryObj = [PSCustomObject] @{
        type       = "Microsoft.OperationalInsights/workspaces/savedSearches";
        apiVersion = "2020-08-01";
        name       = "[concat(parameters('workspace'), '/$($file.BaseName.replace(' ', ''))')]";
        location   = "[resourceGroup().location]"; 
        properties = [PSCustomObject] @{
            eTag        = "*";
            displayName = $yaml.name;
            category    = "Hunting Queries";
            query       = $yaml.query;
            version     = 1;
            tags        = @()
        }
    }

    $huntingQueryDescription = ""
    if ($yaml.description) {
        $huntingQueryDescription = $yaml.description.substring(0, [math]::min($yaml.description.length - 3, 240))
        $descriptionObj = [PSCustomObject] @{
            name  = "description";
            value = $huntingQueryDescription
        }
        $huntingQueryObj.properties.tags += $descriptionObj
        $huntingQueryDescription = "$huntingQueryDescription "
    }

    $tacticsMapping = @{
        'reconnaissance'            = 'Reconnaissance';
        'resource_development'      = 'Resource Development';
        'initial_access'            = 'Initial Access';
        'execution'                 = 'Execution';
        'persistence'               = 'Persistence';
        'privilege_escalation'      = 'Privilege Escalation';
        'defense_evasion'           = 'Defense Evasion';
        'credential_access'         = 'Credential Access';
        'discovery'                 = 'Discovery';
        'collection'                = 'Collection';
        'command_and_control'       = 'Command And Control';
        'impact'                    = 'Impact';
        'lateral_movement'          = 'Lateral Movement';
        'evasion'                   = 'Evasion';
        'inhibit_response_function' = 'Inhibit Response Function';
        'impair_process_control'    = 'Impair Process Control'
    }

    if ($yaml.tactics -and $yaml.tactics.Count -gt 0) {
        $formattedTactics = $yaml.tactics | ForEach-Object {
            $tactic = $_.Trim().ToLower()
            if ($tacticsMapping.ContainsKey($tactic)) {
                $tacticsMapping[$tactic]
            } else {
                throw "Invalid tactic: $tactic"
            }
        } -join ","
       
        $tacticsObj = [PSCustomObject] @{
            name  = "tactics";
            value = $formattedTactics
        }
    
        $huntingQueryObj.properties.tags += $tacticsObj
    }

    if ($yaml.relevantTechniques -and $yaml.relevantTechniques.Count -gt 0) {
        $formattedTechniques = $yaml.relevantTechniques | ForEach-Object {
            if ($_ -match "^t\d{4}(\.\d+)?$") {
                "T" + ($_ -split '\.')[0].Substring(1)
            } else {
                $_
            }
        }

        $techniqueObj = [PSCustomObject] @{
            name  = "relevantTechniques";
            value = $formattedTechniques -join ","
        }

        if ($techniqueObj.value.ToString() -match ' ') {
            $techniqueObj.value = $techniqueObj.value -replace ' ', ''
        }

        $huntingQueryObj.properties.tags += $techniqueObj
    }

    $baseHuntingObject.resources = @()
    $baseHuntingObject.resources += $huntingQueryObj

    ConvertTo-Json $baseHuntingObject -EscapeHandling Default -Depth $jsonConversionDepth | Set-Content -Path $outputFilePath
}
