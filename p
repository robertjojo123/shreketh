local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")

if not modem then
    error("No wired modem found! Ensure a wired modem is attached.", 0)
end
if not monitor then
    error("Attach a monitor!", 0)
end

rednet.open(peripheral.getName(modem))

local quadrant = tonumber(os.getComputerLabel():match("%d"))
if quadrant == nil then
    error("Label computer as 'comp0', 'comp1', 'comp2', or 'comp3'", 0)
end

local fps = 5
local frameInterval = 1 / fps  -- 0.2 seconds per frame
local globalStartTime = nil
local preloadedFrame = nil
local partNumber = 1  -- Track current video part

-- **Define a split function (Fix for nil error)**
local function split(inputstr, sep)
    if inputstr == nil then return {} end  -- Prevent calling split on nil
    sep = sep or "%s"
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

-- **Base URL for video files**
local baseURL = "https://raw.githubusercontent.com/robertjojo123/shreketh/refs/heads/main/vid_"

-- **Function to download a video file**
local function downloadVideo(part)
    local fileURL = baseURL .. part .. "_c" .. quadrant .. ".nfv"
    local localPath = "/vid_" .. part .. "_c" .. quadrant .. ".nfv"

    print("Downloading:", fileURL)
    local response = http.get(fileURL)
    if response then
        local file = fs.open(localPath, "w")
        file.write(response.readAll())
        file.close()
        response.close()
        return localPath
    else
        print("Failed to download:", fileURL)
        return nil
    end
end

-- **Fast rendering function using term.blit()**
local function drawFast(frameData)
    term.redirect(monitor)
    local width, height = monitor.getSize()

    for y = 1, height do
        if frameData[y] then
            term.setCursorPos(1, y)
            term.blit(frameData[y], frameData[y], frameData[y])  -- Text, FG, BG same for smooth rendering
        end
    end
    term.redirect(term.native())
end

-- **Preloads the next frame but does NOT display it yet**
local function preloadFrame(frameIndex)
    local videoFile = "/vid_" .. partNumber .. "_c" .. quadrant .. ".nfv"
    
    if not fs.exists(videoFile) then
        videoFile = downloadVideo(partNumber)
        if not videoFile then return end
    end

    -- **Read the file safely**
    local file = fs.open(videoFile, "r")
    if not file then
        print("Error: Could not open", videoFile)
        return
    end

    local videoData = file.readAll()
    file.close()

    -- **Ensure videoData is not nil before calling split()**
    if videoData then
        local videoLines = split(videoData, "\n")
        table.remove(videoLines, 1)  -- Remove resolution header
        preloadedFrame = videoLines[frameIndex]
    else
        print("Error: videoData is nil for", videoFile)
    end
end

-- **Preloads the first frame of the next video part**
local function preloadNextPart()
    local nextPart = partNumber + 1
    local videoFile = "/vid_" .. nextPart .. "_c" .. quadrant .. ".nfv"

    if not fs.exists(videoFile) then
        videoFile = downloadVideo(nextPart)
        if not videoFile then return end
    end

    local file = fs.open(videoFile, "r")
    if not file then
        print("Error: Could not open", videoFile)
        return
    end

    local videoData = file.readAll()
    file.close()

    if videoData then
        local videoLines = split(videoData, "\n")
        table.remove(videoLines, 1)  
        preloadedFrame = videoLines[1]
    else
        print("Error: videoData is nil for", videoFile)
    end
end

-- **Wait for synchronization from the scheduler**
print("Waiting for sync...")
while true do
    local sender, msg = rednet.receive()
    if msg.type == "sync" then
        globalStartTime = msg.time
        break
    end
end

print("Synchronized! Starting playback...")
os.sleep((globalStartTime - os.epoch("utc")) / 1000)

-- **Main loop for frame playback**
while true do
    local sender, msg = rednet.receive()
    if msg.type == "frame" then
        -- **Instantly render preloaded frame**
        if preloadedFrame then
            drawFast(preloadedFrame)
        end

        -- **Immediately begin preloading the next frame**
        preloadFrame(msg.index)

        -- **Switch to next video part if needed**
        if (msg.index % 6) == 0 then
            partNumber = partNumber + 1
            print("Finished part", partNumber - 1, "downloading next part...")
            preloadNextPart()
        end
    end
end
