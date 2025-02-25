local version = "@project-version@"
local versionObj = {}

for w in string.gmatch(version, "[0-9]*") do
    if w ~= "" then 
        table.insert(versionObj, w)
    end
end

if #versionObj == 0 then
    versionObj = {1, 1}
end

local wState = LibStub:NewLibrary("wState-" .. versionObj[1], versionObj[2])


if not wState then
   return	-- already loaded and no upgrade necessary
end


local machine = {}
machine.__index = machine

local NONE = "none"
local ASYNC = "async"

local function call_handler(handler, params)
  if handler then
    return handler(unpack(params))
  end
end

local function firstToUpper(str)
  return (str:gsub("^%l", string.upper))
end

local function create_transition(name)
  local can, to, from, params

  local function transition(self, ...)
    if self.asyncState == NONE then
      can, to = self:can(name)
      from = self.current
      params = { self.object, self.options.id, name, from, to, ...}

      if not can then return false end
      self.currentTransitioningEvent = name

      local beforeReturn = call_handler(self["onbefore" .. name], params)
      local leaveReturn = call_handler(self["onleave" .. from], params)

      if beforeReturn == false or leaveReturn == false then
        return false
      end

      self.asyncState = name .. "WaitingOnLeave"

      if leaveReturn ~= ASYNC then
        transition(self, ...)
      end
      
      return true
    elseif self.asyncState == name .. "WaitingOnLeave" then
      self.current = to
      local enterReturn = call_handler(self["onenter" .. to] or self.object["On" .. firstToUpper(to)] or self.object["OnEnterState" .. firstToUpper(to)] or self["on" .. to], params)

      self.asyncState = name .. "WaitingOnEnter"

      if enterReturn ~= ASYNC then
        transition(self, ...)
      end
      
      return true
    elseif self.asyncState == name .. "WaitingOnEnter" then
      call_handler(self["onafter" .. name] or self.object["On" .. firstToUpper(name)] or self.object["OnState" .. firstToUpper(name)]  or self["on" .. name], params)
      call_handler(self["onstatechange"] or self.object["OnStateChange"], params)
      self.asyncState = NONE
      self.currentTransitioningEvent = nil
      return true
    else
    	if string.find(self.asyncState, "WaitingOnLeave") or string.find(self.asyncState, "WaitingOnEnter") then
    		self.asyncState = NONE
    		transition(self, ...)
    		return true
    	end
    end

    self.currentTransitioningEvent = nil
    return false
  end

  return transition
end

local function add_to_map(map, event)
  if type(event.from) == 'string' then
    map[event.from] = event.to
  else
    for _, from in ipairs(event.from) do
      map[from] = event.to
    end
  end
end

function machine.create(object, options)
  assert(options.events)


  local fsm = {}
  setmetatable(fsm, machine)

  fsm.object = object
  fsm.options = options
  fsm.current = options.initial or 'none'
  fsm.asyncState = NONE
  fsm.events = {}

  for name, event in pairs(options.events or {}) do
    fsm[name] = fsm[name] or create_transition(name)
    fsm.events[name] = fsm.events[name] or { map = {} }
    add_to_map(fsm.events[name].map, event)
  end

  
  
  -- for name, callback in pairs(options.callbacks or {}) do
  --   fsm["on"..name] = callback
  -- end

  return fsm
end

function machine:is(state)
  return self.current == state
end

function machine:can(e)
  local event = self.events[e]
  local to = event and event.map[self.current] or event.map['*']
  return to ~= nil, to
end

function machine:cannot(e)
  return not self:can(e)
end

function machine:transition(event)
  if self.currentTransitioningEvent == event then
    return self[self.currentTransitioningEvent](self)
  end
end

function machine:cancelTransition(event)
  if self.currentTransitioningEvent == event then
    self.asyncState = NONE
    self.currentTransitioningEvent = nil
  end
end

machine.NONE = NONE
machine.ASYNC = ASYNC


wState = Mixin(wState, machine)