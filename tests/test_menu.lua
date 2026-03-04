local menu = require("menu")
local tracks = require("tracks")

describe("menu", function()
    it("initializes with first track selected", function()
        menu.init()
        expect_eq(menu.selectedTrack, 1)
        expect_eq(menu.selectedButton, "track")
    end)

    it("selectNext moves to next track", function()
        menu.init()
        menu.selectNext()
        expect_eq(menu.selectedTrack, 2)
    end)

    it("selectNext wraps around past add card", function()
        menu.init()
        local displayCount = menu.getDisplayCount()
        for _ = 1, displayCount do
            menu.selectNext()
        end
        expect_eq(menu.selectedTrack, 1)
    end)

    it("selectPrev moves to previous track", function()
        menu.init()
        menu.selectedTrack = 3
        menu.selectPrev()
        expect_eq(menu.selectedTrack, 2)
    end)

    it("selectPrev wraps around to add card", function()
        menu.init()
        menu.selectPrev()
        expect_eq(menu.selectedTrack, menu.getDisplayCount())
    end)

    it("getDisplayCount includes add card", function()
        menu.init()
        expect_eq(menu.getDisplayCount(), tracks.count() + 1)
    end)

    it("isAddSelected returns true for last slot", function()
        menu.init()
        menu.selectedTrack = tracks.count() + 1
        expect_true(menu.isAddSelected())
    end)

    it("isAddSelected returns false for track slots", function()
        menu.init()
        menu.selectedTrack = 1
        expect_false(menu.isAddSelected())
    end)

    it("getSelectedTrack returns nil when add is selected", function()
        menu.init()
        menu.selectedTrack = tracks.count() + 1
        expect_eq(menu.getSelectedTrack(), nil)
    end)

    it("moveDown changes button to controls", function()
        menu.init()
        expect_eq(menu.selectedButton, "track")
        menu.moveDown()
        expect_eq(menu.selectedButton, "controls")
    end)

    it("moveUp changes button to track", function()
        menu.init()
        menu.selectedButton = "controls"
        menu.moveUp()
        expect_eq(menu.selectedButton, "track")
    end)

    it("getSelectedTrack returns correct track", function()
        menu.init()
        local selectedTrack = menu.getSelectedTrack()
        local firstTrack = tracks.getByIndex(1)
        expect_eq(selectedTrack.id, firstTrack.id)
        expect_eq(selectedTrack.name, firstTrack.name)
    end)

    it("getTrackList returns all tracks", function()
        menu.init()
        local list = menu.getTrackList()
        expect_eq(#list, tracks.count())
    end)

    it("selectNext does nothing when controls selected", function()
        menu.init()
        menu.selectedButton = "controls"
        menu.selectedTrack = 2
        menu.selectNext()
        expect_eq(menu.selectedTrack, 2) -- unchanged
    end)
end)
