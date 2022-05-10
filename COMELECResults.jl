using HTTP, DataFrames, CSV, OrderedCollections, JSON

function getCandidates(races::Array)
    res=LittleDict()

    url="https://2022electionresults.comelec.gov.ph/data/contests/"

    for i in races
        r=HTTP.request("GET", url*string(i)*".json",["User-Agent"=>"Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"]; verbose=0)
        root=JSON.parse(String(r.body),dicttype=LittleDict)["bos"]
        for candidate in values(root)
            merge!(res,Dict(candidate["boc"]=>candidate["bon"]))
        end
    end

    return res
end


function main()

    final_df=DataFrame()
    candidate_ids=[]
    candidates=[]
    votes=[]
    precincts=[]
    barangays=[]
    citymuns=[]
    provinces=[]
    regions=[]
    failed=DataFrame(:Precinct=>[],:Barangay=>[],:CityMun=>[],:Province=>[],:Region=>[])

    races=[5587,5588,5589]
    #Get list of candidates
    CANDIDATELIST=getCandidates(races)

    useragent="User-Agent"=>"Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"

    
    r=HTTP.request("GET", "https://2022electionresults.comelec.gov.ph/data/regions/root.json",["User-Agent"=>"Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"]; verbose=0)
    root=JSON.parse(String(r.body),dicttype=LittleDict)["srs"]
    
    for region in values(root)
        regionname=region["rn"]#get name of region
        println("\n","------"*regionname*"-----\n")
    
        regionurl="https://2022electionresults.comelec.gov.ph/data/regions/"*region["url"]*".json"

        #println(regionname, " ", regionurl)

        #get provinces
        r2=HTTP.request("GET", regionurl,[useragent]; verbose=0)
        root2=JSON.parse(String(r2.body),dicttype=LittleDict)["srs"]
        for province in values(root2)
            provincename=province["rn"]
            println("  Getting Data for "*provincename*"...\n")

            provinceurl="https://2022electionresults.comelec.gov.ph/data/regions/"*province["url"]*".json"

            #get city/municipality
            r3=HTTP.request("GET", provinceurl,[useragent]; verbose=0)
            root3=JSON.parse(String(r3.body),dicttype=LittleDict)["srs"]


            for citymun in values(root3)
                citymunname=citymun["rn"]
                print("\u1b[1F")
                println(citymunname)
                print("\u1b[2K")
               

                citymunurl="https://2022electionresults.comelec.gov.ph/data/regions/"*citymun["url"]*".json"

                #Get barangays
                r4=HTTP.request("GET", citymunurl,[useragent]; verbose=0)
                root4=JSON.parse(String(r4.body),dicttype=LittleDict)["srs"]
        
                @sync begin
                    for barangay in values(root4)
                        @async begin
                            barangayname=barangay["rn"]
                            #println("\n","    "*"------"*barangayname*"-----\n")

                            barangayurl="https://2022electionresults.comelec.gov.ph/data/regions/"*barangay["url"]*".json"
                            
                            #get precincts
                            r5=HTTP.request("GET", barangayurl,[useragent]; verbose=0)
                            root5=JSON.parse(String(r5.body),dicttype=LittleDict)["pps"]
                            for precinct in values(root5[1]["vbs"])
                                precinctcode=precinct["pre"]
                                precincturl="https://2022electionresults.comelec.gov.ph/data/results/"*precinct["url"]*".json"
                                
                                try
                                #get candidate votes per precinct
                                    r6=HTTP.request("GET", precincturl,[useragent]; verbose=0)
                                    root6=JSON.parse(String(r6.body),dicttype=LittleDict)["rs"]
                                    for i in root6
                                        if i["cc"] == 5587||i["cc"] == 5588||i["cc"] == 5589
                                            #=println("Candidate: ",CANDIDATELIST[i["bo"]])
                                            println("Votes: ", i["v"])
                                            println("Percentage: ",i["per"])=#

                                            #push element into our arrays
                                            push!(candidate_ids,i["bo"])
                                            push!(candidates,CANDIDATELIST[i["bo"]])
                                            push!(votes,i["v"])
                                            push!(precincts,precinctcode)
                                            push!(barangays,barangayname)
                                            push!(citymuns,citymunname)
                                            push!(provinces,provincename)
                                            push!(regions,regionname)

                                            #=println("candidates: ", candidates, ",", "Votes: ",votes)
                                            println("precinct: ",precincts)
                                            println("Barangay: ",barangays)
                                            println("City/Municipality: ",citymuns)
                                            println("Region: ",regions)
                                            println("Province: ",provinces)
                                            println("\n")=#
                                        end
                                    end
                                catch
                                    #push!(failed,Dict("Precinct"=>precinctcode, "Barangay"=>barangayname,"CityMun"=>citymunname,"Province"=>provincename,"Region"=>regionname))
                                    push!(failed,[precinctcode,barangayname,citymunname,provincename,regionname])
                                end
                                

                                #=println("precinct: ",precinctcode)
                                println("URL: ", precincturl)
                                println("Region: ",regionname)
                                println("Province: ",provincename)
                                println("City/Municipality: ",citymunname)
                                println("Barangay: ",barangayname)
                                println("\n")=#
                            end 
                                              
                        end
                        #println(barangayname, " ", barangayurl)
                    end
                end
                
                #println(citymunname, " ", citymunurl)
            end            
            #sleep(1) #pause script for a bit to avoid the timeout
            #println("   ",provincename, " ", provinceurl)
        end
    end

    #Populate our results DataFrame
    final_df.Candidate_ID=candidate_ids
    final_df.Candidate=candidates
    final_df.Votes=votes
    final_df.Precinct=precincts
    final_df.Barangay=barangays
    final_df.CityMun=citymuns
    final_df.Province=provinces
    final_df.Region=regions

    #write to csv
    try
        println("Writing Failures to file...")
        CSV.write("COMELECResultsFailed.csv",failed)
    catch
        println("Failed to Write COMELECResultsFailed.csv")
    end
    
    regionlist=unique(final_df.Region)
    println("Writing Regional Results...")
    for r in regionlist
        try
            CSV.write(r*"Results"*".csv",final_df[final_df.Region.==r,:])
        catch
            println("Failed to write for ",r)
        end
    end

    println("Writing Overall Results...")
    try
        CSV.write("COMELECResults.csv",final_df)
    catch
        println("Failed to write overall results")
    end
    


    


    
    #=r6=HTTP.request("GET", "https://2022electionresults.comelec.gov.ph/data/results/202/202987.json",[useragent]; verbose=0)
    root6=JSON.parse(String(r6.body),dicttype=LittleDict)["rs"]
    for i in root6
        if i["cc"] == 5587||i["cc"] == 5588||i["cc"] == 5589
            println("Candidate: ",CANDIDATELIST[i["bo"]])
            println("Votes: ", i["v"])
            println("Percentage: ",i["per"])
        end
    end=#
    #=for precinct in values(root5[1]["vbs"])
        println(precinct["pre"])
        precinctcode=precinct["url"]
        precincturl="https://2022electionresults.comelec.gov.ph/data/results/"*precinct["url"]*".json"

        println(precinctcode, " ", precincturl)
    end=#
end

main()
#getCandidates()