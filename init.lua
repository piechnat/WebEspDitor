gpio.mode(3, gpio.INPUT, gpio.PULLUP) -- FLASH BUTTON
if gpio.read(3) == 0 then return end  -- boot loop protection

print("Starting WebEspDitor...")

net.createServer():listen(80, function(socket)

  local htmlTmpl = {
    -- 1 --
[===[HTTP/1.0 200 OK
Content-Type: text/html; charset=UTF-8
Connection: close

<!DOCTYPE html><html><head><title>WebEspDitor</title><meta name="viewport" 
content="width=device-width"><link rel="icon" href="data:;base64,="><style>
a{text-decoration:none;color:navy}a:hover{text-decoration:underline}body{
line-height:1.5em;font-family:monospace}</style></head><body>
]===], 
    -- 2 --
[===[<p><a href="/">WebEspDitor</a> [ <a href="/reset">reset</a> ]</p>]===], 
    -- 3 --
[===[<form action="/save/<!FNAME>" method="post" enctype="text/plain">
<textarea name="s" spellcheck="false" style="position:absolute;width:100%;
height:100%;margin:0;border:0;padding:4px;resize:none;white-space:pre;
box-sizing:border-box">]===], 
    -- 4 --
[===[</textarea><input style="position:absolute;bottom:0;right:0" type="submit" 
value="Save"></form><style>body{margin:0;overflow:hidden}</style>]===], 
    -- 5 --
[===[<input id="name" type="text"><input type="button" value="create" 
onclick="location.href='/edit/'+document.getElementById('name').value">]===],
    -- 6 --
[===[<script>setTimeout(function(){location.href='/'},2000)</script>]===],
    -- 7 --
[===[<li><a href="/edit/<!FNAME>"><!FNAME></a> (<!FSIZE>, 
<a href="/delete/<!FNAME>" onclick="return confirm('Are you sure to delete'+
' file \'<!FNAME>\'?')">del</a>)</li>]===]
  }
  local rqst, rspn = { length = 0, totalLen = 0, fname = nil }, { }
  
  local function getLine(str, bgnPos)
    local line, endPos = "", str:find("\r\n", bgnPos, true)
    if endPos then 
      line = str:sub(bgnPos, endPos - 1)
      bgnPos = endPos + 2
    end
    return line, bgnPos
  end

  local function sendRspn(sck) -- send response table to client
    if #rspn > 0 then 
      sck:send(table.remove(rspn, 1), sendRspn) else sck:close() end
  end
  
  local function saveRqst(sck, data) -- save incoming content to file
    if #data > 0 then rqst[#rqst+1] = data end
    rqst.length = rqst.length + #data
    if rqst.length >= rqst.totalLen then -- last network frame
      data = nil
      rqst[1] = rqst[1]:sub(3) -- enctype text/plain:
      rqst[#rqst] = rqst[#rqst]:sub(1, -3) -- s=[data]CRLF
      local fd = file.open(rqst.fname, "w+")
      if fd then
        while #rqst > 0 do fd:write(table.remove(rqst, 1)) end
        fd:close()
      end
      collectgarbage("collect")
      sendRspn(sck) 
    end
  end
  
  socket:on("receive", function(sck, data)
    rspn[1] = htmlTmpl[1]
    local line, dataPos = getLine(data, 1) -- 1    2   3   4    5
    local parts = {}                       -- GET /cmd/prm HTTP/1.1
    for elm in line:gmatch("[^/ ]+") do parts[#parts+1] = elm end
    if #parts == 5 then parts[3] = parts[3]:gsub("[^a-zA-Z0-9_.-]", "") end
    if parts[1] == "POST" then
      repeat
        line, dataPos = getLine(data, dataPos)
        local len = line:match("Content%-Length: (%d+)")
        if len then rqst.totalLen = tonumber(len) end
      until #line == 0
    end
-- EDIT
    if parts[2] == "edit" and #parts == 5 then 
      local tmp = htmlTmpl[3]:gsub("<!FNAME>", parts[3], 1)
      rspn[#rspn+1] = tmp
      tmp = #rspn + 1
      local fd = file.open(parts[3], "r")
      if fd then
        while true do
          local chunk = fd:read(512)
          if chunk then rspn[#rspn+1] = chunk else break end
        end
        fd:close()
      end
      for i = tmp, #rspn do 
        rspn[i] = rspn[i]:gsub("&", "&amp;"):gsub("<", "&lt;") 
      end
      rspn[#rspn+1] = htmlTmpl[4]
    else
      rspn[#rspn+1] = htmlTmpl[2]
-- SAVE
      if parts[2] == "save" and #parts == 5 then 
        rqst.fname = parts[3]
        rspn[#rspn+1] = 
          '<p>File "'..parts[3]..'" has been saved.</p>'..htmlTmpl[6]
-- DELETE
      elseif parts[2] == "delete" and #parts == 5 then
        file.remove(parts[3])
        rspn[#rspn+1] = 
          '<p>File "'..parts[3]..'" has been deleted.</p>'..htmlTmpl[6]
-- RESET
      elseif parts[2] == "reset" then
        local timer = tmr.create()
        timer:register(500, tmr.ALARM_SINGLE, function() node.restart() end)
        timer:start()
        rspn[#rspn+1] = '<p>Waiting for device...</p>'..htmlTmpl[6]
-- INDEX
      else 
        local res = {'<ul>'}
        for n, s in pairs(file.list()) do 
          if not n:find("init.", 1, true) then
            res[#res+1] = htmlTmpl[7]:gsub("<!FNAME>", n):gsub("<!FSIZE>", s)
          end
        end
        res[#res+1] = '</ul>'
        rspn[#rspn+1] = table.concat(res)..htmlTmpl[5]
        local res = file.getcontents("init.out")
        if res then 
          rspn[#rspn+1] = '<p>Lua interpreter output:<pre>'..res..'</pre></p>' 
        end
      end
    end
    rspn[#rspn+1] = '</body></html>'
    socket, htmlTmpl, line, parts = nil
    collectgarbage("collect")
-- FILE UPLOAD
    if rqst.fname and rqst.totalLen > 0 then
      sck:on("receive", saveRqst)      
      saveRqst(sck, data:sub(dataPos)) 
-- NORMAL REQUEST          
    else sendRspn(sck) end
  end)
  
end)

print("Starting main...")

do
  local res, err
  file.remove("init.out")
  node.output(function(s)
    local fd = file.open("init.out", "a+")
    if fd then fd:write(s) fd:close() end
  end, 1)
  if file.exists("main.lc") then
    res, err = pcall(function() dofile("main.lc") end)
  else
    res, err = pcall(function() dofile("main.lua") end)
  end
  if not res then print(err) end
end
