--building/construction mass removal/suspension tool

--[====[

gui/mass-remove
===============
Allows removal of buildings/constructions and suspend/unsuspend using
a box selection.

The following marking modes are available.

- Suspend (s): suspends the construction of a planned building/construction
- Unsuspend (p): resumes the construction of a planned building/construction
- Remove Construction (n): designates a construction (wall, floor, etc) for removal. Similar to the native Designate->Remove Construction menu in DF
- Unremove Construction (c): cancels removal of a construction (wall, floor, etc)
- Remove Building (x): designates a building (door, workshop, etc) for removal. Similar to the native Set Building Tasks/Prefs->Remove Building menu in DF
- Unremove Building (b): cancels removal of a building (door, workshop, etc)
- Remove All (a): designates both constructions and buildings for removal, and deletes planned buildings/constructions
- Unremove All (u): cancels removal designations for both constructions and buildings
]====]

local gui = require "gui"
local guidm = require "gui.dwarfmode"
local persistTable = require 'persist-table'
local utils = require 'utils'

MassRemoveUI = defclass(MassRemoveUI, guidm.MenuOverlay)

--used to iterate through actions with + and -
local actions={"suspend", "unsuspend", "remove_n", "unremove_n", "remove_x", "unremove_x", "remove_a", "unremove_a"}
local action_indexes=utils.invert(actions)

MassRemoveUI.ATTRS {
    action="remove_a",
    marking=false,
    mark=nil
}

--Helper functions.
local function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

--Helper to match a job of a particular type at tile (x,y,z) and run the callback function on the job.
local function iterateJobs(jobType, x, y, z, callback)
    local joblist = df.global.world.jobs.list.next

    while joblist do
        local job = joblist.item
        joblist = joblist.next

        if job.job_type == jobType and job.pos.x == x and job.pos.y == y and job.pos.z == z then
            callback(job)
        end
    end
end

--Sorts and returns the given arguments.
local function minToMax(...)
    local args={...}
    table.sort(args,function(a,b) return a < b end)
    return table.unpack(args)
end

local function paintMapTile(dc, vp, cursor, pos, ...)
    if not same_xyz(cursor, pos) then
        local stile = vp:tileToScreen(pos)
        if stile.z == 0 then
            dc:map(true):seek(stile.x,stile.y):char(...):map(false)
        end
    end
end

function MassRemoveUI:onAboutToShow(parent)
    gui.simulateInput(parent, df.interface_key.D_LOOK)
end

function MassRemoveUI:changeSuspendState(x, y, z, new_state)
    iterateJobs(df.job_type.ConstructBuilding, x, y, z, function(job) job.flags.suspend = new_state end)
end

function MassRemoveUI:suspend(x, y, z)
    self:changeSuspendState(x, y, z, true)
end

function MassRemoveUI:unsuspend(x, y, z)
    self:changeSuspendState(x, y, z, false)
end

function MassRemoveUI:removeConstruction(x, y, z)
    dfhack.constructions.designateRemove(x, y, z)
end

--Construction removals can either be marked as dig on the tile itself, or picked up as jobs. This function checks both.
function MassRemoveUI:unremoveConstruction(x, y, z)
    local tileFlags, occupancy = dfhack.maps.getTileFlags(x,y,z)
    tileFlags.dig = df.tile_dig_designation.No
    dfhack.maps.getTileBlock(x,y,z).flags.designated = true
end

function MassRemoveUI:removeBuilding(x, y, z)
    local building = dfhack.buildings.findAtTile(x, y, z)
    if building then
        dfhack.buildings.deconstruct(building)
    end
end

function MassRemoveUI:unremoveBuilding(x, y, z)
    local building = dfhack.buildings.findAtTile(x, y, z)
    if building then
        for _, job in ipairs(building.jobs) do
            if job.job_type == df.job_type.DestroyBuilding then
                dfhack.job.removeJob(job)
                break
            end
        end
    end
end

function MassRemoveUI:changeDesignation(x, y, z)
    if self.action == "suspend" then
        self:suspend(x, y, z)
    elseif self.action == "unsuspend" then
        self:unsuspend(x, y, z)
    elseif self.action == "remove_x" then
        self:removeBuilding(x, y, z)
    elseif self.action == "unremove_x" then
        self:unremoveBuilding(x, y, z)
    elseif self.action == "remove_n" then
        self:removeConstruction(x, y, z)
    elseif self.action == "unremove_n" then
        self:unremoveConstruction(x, y, z)
    elseif self.action == "remove_a" then
        self:removeBuilding(x, y, z)
        self:removeConstruction(x, y, z)
    elseif self.action == "unremove_a" then
        self:unremoveBuilding(x, y, z)
        self:unremoveConstruction(x, y, z)
    end
end

function MassRemoveUI:changeDesignations(x1, y1, z1, x2, y2, z2)
    local x_start, x_end = minToMax(x1, x2)
    local y_start, y_end = minToMax(y1, y2)
    local z_start, z_end = minToMax(z1, z2)
    for x=x_start, x_end do
        for y=y_start, y_end do
            for z=z_start, z_end do
                self:changeDesignation(x, y, z)
            end
        end
    end
end

function MassRemoveUI:getColor(action)
    if action == self.action then
        return COLOR_WHITE
    else
        return COLOR_GREY
    end
end

function MassRemoveUI:renderOverlay()
    local vp=self:getViewport()
    local dc = gui.Painter.new(self.df_layout.map)

    --show buildings/constructions marked for removal and planned buildings/constructions that are suspended
    if gui.blink_visible(500) then
        local joblist = df.global.world.jobs.list.next
        while joblist do
            local job = joblist.item
            joblist = joblist.next

            if job.job_type == df.job_type.ConstructBuilding and job.flags.suspend then
                paintMapTile(dc, vp, nil, job.pos, "s", COLOR_LIGHTRED)
            elseif job.job_type == df.job_type.RemoveConstruction then
                paintMapTile(dc, vp, nil, job.pos, "n", COLOR_LIGHTRED)
            end
        end

        for x=vp.x1, vp.x2 do
            for y=vp.y1, vp.y2 do
                local building = dfhack.buildings.findAtTile(x, y, vp.z)
                if building and dfhack.buildings.markedForRemoval(building) then
                    paintMapTile(dc, vp, nil, xyz2pos(x, y, vp.z), "x", COLOR_LIGHTRED)
                end
            end
        end
    end

    --show box selection
    if not gui.blink_visible(500) and self.marking then
        local x_start, x_end = minToMax(self.mark.x, df.global.cursor.x)
        local y_start, y_end = minToMax(self.mark.y, df.global.cursor.y)
        paintMapTile(dc, vp, nil, self.mark, "+", COLOR_LIGHTGREEN)
        for x=x_start, x_end do
            for y=y_start, y_end do
                local fg=COLOR_GREEN
                local bg=COLOR_BLACK
                local symbol="X"
                dc:pen(fg,bg)
                paintMapTile(dc, vp, nil, xyz2pos(x, y, df.global.cursor.z), symbol, fg)
            end
        end
    end

    --show initial position of box selection
    if self.mark and self.marking then
        local fg=COLOR_RED
        local bg=COLOR_BLACK
        local symbol="X"
        dc:pen(fg,bg)
        paintMapTile(dc, vp, nil, xyz2pos(self.mark.x, self.mark.y, self.mark.z), symbol, fg)
    end
end

function MassRemoveUI:onRenderBody(dc)
    self:renderOverlay()

    dc:clear():seek(1,1):pen(COLOR_WHITE):string("Mass Remove")
    dc:seek(1,3)

    dc:pen(COLOR_GREY)
    dc:string("Designate multiple buildings"):newline(1)
      :string("and constructions (built or"):newline(1)
      :string("planned) for mass removal."):newline(1)

    dc:seek(1,7)
    dc:pen(COLOR_WHITE)
    if self.marking then
        dc:string("Select the second corner.")
    else
        dc:string("Select the first corner.")
    end

    dc:seek(1,9)
    dc:pen(self:getColor("suspend")):key_string("CUSTOM_S", "Suspend"):newline(1)
    dc:pen(self:getColor("unsuspend")):key_string("CUSTOM_P", "Unsuspend"):newline():newline(1)
    dc:pen(self:getColor("remove_n")):key_string("CUSTOM_N", "Remove Construction"):newline(1)
    dc:pen(self:getColor("unremove_n")):key_string("CUSTOM_C", "Unremove Construction"):newline():newline(1)
    dc:pen(self:getColor("remove_x")):key_string("CUSTOM_X", "Remove Building"):newline(1)
    dc:pen(self:getColor("unremove_x")):key_string("CUSTOM_B", "Unremove Building"):newline():newline(1)
    dc:pen(self:getColor("remove_a")):key_string("CUSTOM_A", "Remove All"):newline(1)
    dc:pen(self:getColor("unremove_a")):key_string("CUSTOM_U", "Unremove All"):newline(1)

    dc:pen(COLOR_WHITE)
    if self.marking then
        dc:newline(1):key_string("LEAVESCREEN", "Cancel selection")
    else
        dc:newline(1):key_string("LEAVESCREEN", "Back")
    end
end

function MassRemoveUI:onInput(keys)
    if keys.CUSTOM_S then
        self.action = "suspend"
        return
    elseif keys.CUSTOM_P then
        self.action = "unsuspend"
        return
    elseif keys.CUSTOM_C then
        self.action = "unremove_n"
        return
    elseif keys.CUSTOM_B then
        self.action = "unremove_x"
        return
    elseif keys.CUSTOM_X then
        self.action = "remove_x"
        return
    elseif keys.CUSTOM_N then
        self.action = "remove_n"
        return
    elseif keys.CUSTOM_A then
        self.action = "remove_a"
        return
    elseif keys.CUSTOM_U then
        self.action = "unremove_a"
        return
    elseif keys.SECONDSCROLL_UP then
        self.action = actions[((action_indexes[self.action]-2) % #actions)+1]
        return
    elseif keys.SECONDSCROLL_DOWN then
        self.action = actions[(action_indexes[self.action] % #actions)+1]
        return
    end

    if keys.SELECT then
        if self.marking then
            self.marking = false
            self:changeDesignations(self.mark.x, self.mark.y, self.mark.z, df.global.cursor.x, df.global.cursor.y, df.global.cursor.z)
        else
            self.marking = true
            self.mark = copyall(df.global.cursor)
        end
    elseif keys.LEAVESCREEN and self.marking then
        self.marking = false
        return
    end

    if keys.LEAVESCREEN then
        self:dismiss()
    elseif self:propagateMoveKeys(keys) then
        return
    end
end

if not (dfhack.gui.getCurFocus():match("^dwarfmode/Default") or dfhack.gui.getCurFocus():match("^dwarfmode/Designate") or dfhack.gui.getCurFocus():match("^dwarfmode/LookAround"))then
    qerror("This screen requires the main dwarfmode view or the designation screen")
end

local list = MassRemoveUI{action=persistTable.GlobalTable.massRemoveAction, marking=false}
list:show()