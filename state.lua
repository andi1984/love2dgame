-- Game state machine (pure logic, no Love2D dependency)

local state = {}

-- Possible states: "menu", "racing", "paused", "controls"
state.current = "menu"
state.previous = nil

function state.init()
    state.current = "menu"
    state.previous = nil
end

function state.set(newState)
    state.previous = state.current
    state.current = newState
end

function state.is(checkState)
    return state.current == checkState
end

function state.goBack()
    if state.previous then
        state.current = state.previous
        state.previous = nil
    end
end

return state
