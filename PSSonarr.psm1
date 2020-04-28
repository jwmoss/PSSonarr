function Set-SonarrConfig {
    [CmdletBinding()]
    param (
        [string]
        $URL,

        [string]
        $API
    )

    $script:configuration = @{
        URL = $URL
        API = $API
    }    

    $script:configuration["RootFolder"] = (Invoke-SonarrRestMethod -Method "GET" -Endpoint "/rootfolder").Path      
    $script:configuration["Profiles"] = Invoke-SonarrRestMethod -Method "GET" -Endpoint "/profile"      

}

function Invoke-SonarrRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet(
            "GET",
            "POST"
        )]
        [string]
        $Method,

        [string]
        $Endpoint,

        [string]
        $Command,

        [PSObject]
        $Body
    )
    
    begin {
        $InvokeRestMethodHash = @{
            URI     = $script:configuration.URL + $Endpoint
            Method  = $Method
            Headers = @{
                'X-Api-Key' = $script:configuration.API
            }
        }
    }
    
    process {
        if ($PSBoundParameters.ContainsKey('Command')) {
            $InvokeRestMethodHash["URI"] = $script:configuration.URL + $Endpoint + $Command
        }

        if ($PSBoundParameters.ContainsKey('Command') -and ($PSBoundParameters.ContainsKey('Body'))) {
            $InvokeRestMethodHash["URI"] = $script:configuration.URL + $Endpoint + $Command
            $InvokeRestMethodHash["Body"] = $Body
        }

        if ($PSBoundParameters.ContainsKey('Body')) {
            $InvokeRestMethodHash["Body"] = $Body
        }

        Invoke-RestMethod @InvokeRestMethodHash 
    }
    
    end {
        
    }
}

function Get-SonarrShow {
    [CmdletBinding()]
    param (
        [string]
        $ID
    )

    if ($PSBoundParameters.ContainsKey('ID')) {
        Invoke-SonarrRestMethod -Method "GET" -Endpoint "/series/$ID"
    }
    else {
        Invoke-SonarrRestMethod -Method "GET" -Endpoint "/series"
    }

}

function Find-SonarrShow {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet(
            "Name",
            "TMDB",
            "IMDB"
        )]
        [string]
        $SearchMethod,

        [string]
        $SearchValue
    )

    switch ($SearchMethod) {
        "Name" {  

            ## Add %20 to spaces in the name
            $value = [uri]::EscapeDataString($SearchValue)

            ## Search for movie using the name
            Invoke-SonarrRestMethod -Method 'GET' -Endpoint '/series/lookup' -Command "?term=$value"

        }
        "TMDB" {  

            ## Search for movie using TMDB ID
            Invoke-SonarrRestMethod -Method 'GET' -Endpoint '/series/lookup/tmdb' -Command "?tmdbId=$SearchValue"

        }
        "IMDB" {  

            ## Search for movie using TMDB ID
            Invoke-SonarrRestMethod -Method 'GET' -Endpoint '/series/lookup/imdb' -Command "?imdbId=$SearchValue"

        }
        Default { }
    }
}

function Get-SonarrProfile {
    [CmdletBinding()]
    param (
        
    )
    
    $script:configuration.Profiles

}

function Add-SonarrShow {
    [CmdletBinding()]
    param (
        [PSObject]
        $SearchResults,

        [string]
        $ProfileID,

        [switch]
        $Monitored,

        [switch]
        $SearchForMovie
    )

    $CoverImage = $SearchResults.Images | Where-Object { $_.CoverType -eq "Poster" }

    ## Add a show from non4K to 4K
    $params = @{
        title            = $SearchResults.title
        qualityProfileId = ProfileID
        titleSlug        = $SearchResults.titleslug  
        images           = @(
            @{
                covertype = $CoverImage.covertype
                url       = $CoverImage.url
            }
        )
        tvdbid           = $SearchResults.tvdbid
        profileId        = $ProfileID
        year             = $SearchResults.year
        rootfolderpath   = Get-SonarrRootFolder
        monitored        = $true
        addoptions       = @{
            "ignoreEpisodesWithFiles"= $false
            "ignoreEpisodesWithoutFiles" = $false
            "searchForMissingEpisodes" = $true
        }
    } | ConvertTo-Json

    Invoke-SonarrRestMethod -Method "POST" -Endpoint "/series" -Body $Params

}

function Get-SonarrRootFolder {
    [CmdletBinding()]
    param (
        
    )

    $script:configuration.RootFolder
}

function Get-SonarrSystemStatus {
    [CmdletBinding()]
    param (
        
    )
    
    Invoke-SonarrRestMethod -Method "GET" -Endpoint "/system/status"
}

function Get-SonarrRecommendations {
    [CmdletBinding()]
    param (
        
    )
    
    Invoke-SonarrRestMethod -Method "GET" -Endpoint "/seriess/discover/recommendations"
}

function Sync-SonarrInstance {
    [CmdletBinding()]
    param (
        [PSObject]
        $Source,

        [PSObject]
        $Destination,

        [string]
        $DestinationProfileID,

        [int]
        $Max,

        [switch]
        $Monitored,

        [switch]
        $SearchForTV
    )

    ## Loop through each movie in the source library
    
    if (-not $PSBoundParameters.ContainsKey('Max')) {
        foreach ($tvshow in $Source) {
            Write-Verbose "Processing $($tvshow.Title)"
            ## If the movie in source library is not in the destination library, do stuff
            if ($tvshow.tmdbid -notin $Destination.tmdbid) {
                Write-Verbose "Adding $($tvshow.Title) to destination library"
                ## If you want to monitor and search for the movie
                if ($PSBoundParameters.ContainsKey('Monitored') -and ($PSBoundParameters.ContainsKey('SearchForMovie'))) {
                    Write-Verbose "Adding $($tvshow.Title) to Destination Library, searching and monitoring it."
                    Add-SonarrShow -SearchResults $tvshow -ProfileID $DestinationProfileID -Monitored -SearchForTV
                } 
                
                ## If you want to monitor the movie
                if ($PSBoundParameters.ContainsKey('Monitored')) {
                    Write-Verbose "Adding $($tvshow.Title) to Destination Library, and monitoring it."
                    Add-SonarrShow -SearchResults $tvshow -ProfileID $DestinationProfileID -Monitored
                }       
                
                ## If you want to search for the movie
                if ($PSBoundParameters.ContainsKey('SearchForMovie')) {
                    Write-Verbose "Adding $($tvshow.Title) to Destination Library, and searching for the movie."
                    Add-SonarrShow -SearchResults $tvshow -ProfileID $DestinationProfileID -SearchForTV
                }   
            }   
        }  
    }

    if ($PSBoundParameters.ContainsKey('Max')) {
        Write-Verbose -Message "Processing the first $Max"
        foreach ($tvshow in $Source[0..$Max]) {
            Write-Verbose "Processing $($tvshow.Title)"
            ## If the movie in source library is not in the destination library, do stuff
            if ($tvshow.tmdbid -notin $Destination.tmdbid) {
                Write-Verbose "Adding $($tvshow.Title) to destination library"
                ## If you want to monitor and search for the movie
                if ($PSBoundParameters.ContainsKey('Monitored') -and ($PSBoundParameters.ContainsKey('SearchForMovie'))) {
                    Write-Verbose "Adding $($tvshow.Title) to Destination Library, searching and monitoring it."
                    Add-SonarrShow -SearchResults $tvshow -ProfileID $DestinationProfileID -Monitored -SearchForTV
                } 
                
                ## If you want to monitor the movie
                if ($PSBoundParameters.ContainsKey('Monitored')) {
                    Write-Verbose "Adding $($movie.Title) to Destination Library, and monitoring it."
                    Add-SonarrShow -SearchResults $movie -ProfileID $DestinationProfileID -Monitored
                }       
                
                ## If you want to search for the movie
                if ($PSBoundParameters.ContainsKey('SearchForMovie')) {
                    Write-Verbose "Adding $($movie.Title) to Destination Library, and searching for the movie."
                    Add-SonarrShow -SearchResults $movie -ProfileID $DestinationProfileID -SearchForTV
                }   
            }   
        }
    }
}