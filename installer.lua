function getToFile(url, filename)
    local f = io.open(filename, "w")
    local conn = http.get(url)
    f:write(conn.readAll())
    f:close()
    conn:close()
end
 
function main()
    -- TODO: parse page and extract scripts?
    getToFile(
        "https://raw.githubusercontent.com/modelflat/mc-lua/master/kkona.lua",
        "kkona.lua"
    )
    getToFile(
        "https://raw.githubusercontent.com/modelflat/mc-lua/master/reactor.lua",
        "reactor.lua"
    )
end
 
main()
